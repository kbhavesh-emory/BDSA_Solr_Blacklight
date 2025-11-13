import os, json, requests
from datetime import datetime, timezone
from typing import Dict, Any, Iterable, List, Optional
import hashlib

from mapping import transform_item

BDSA_BASE   = os.getenv("BDSA_BASE", "http://bdsa.pathology.emory.edu:8080/api/v1").rstrip("/")
BDSA_KEY    = os.getenv("BDSA_API_KEY", "")
BDSA_FOLDER = os.getenv("BDSA_FOLDER_ID")
SOLR_UPDATE = os.getenv("SOLR_UPDATE", "http://solr:8983/solr/bdsa/update?commitWithin=5000")
SOLR_QUERY  = os.getenv("SOLR_QUERY", "http://solr:8983/solr/bdsa/select")
BATCH_SIZE  = int(os.getenv("BATCH_SIZE", "200"))
DEFAULT_SINCE = os.getenv("DEFAULT_SINCE", "2000-01-01T00:00:00Z")

HEADERS = {"Girder-Token": BDSA_KEY} if BDSA_KEY else {}

class IndexerError(Exception): pass

def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def compute_hash(doc: Dict[str, Any]) -> str:
    """Compute SHA256 hash of document (excluding id and timestamp)"""
    sortable = {k: v for k, v in sorted(doc.items()) 
                if k not in ('id', 'item_id', 'created', 'updated', '_hash')}
    doc_str = json.dumps(sortable, sort_keys=True, default=str)
    return hashlib.sha256(doc_str.encode()).hexdigest()

def _get(url: str, params: Dict[str, Any]=None):
    r = requests.get(url, params=params or {}, headers=HEADERS, timeout=60)
    if not r.ok:
        raise IndexerError(f"GET {url} -> {r.status_code} {r.text}")
    return r.json()

def get_solr_doc_by_name(name: str) -> Optional[Dict[str, Any]]:
    """Fetch existing Solr document by filename (primary deduplication key)"""
    try:
        # Escape special characters in name for Solr query
        escaped_name = name.replace('"', '\\"')
        query_url = f"{SOLR_QUERY}?q=name:\"{escaped_name}\"&rows=1&wt=json"
        resp = _get(query_url)
        docs = resp.get("response", {}).get("docs", [])
        return docs[0] if docs else None
    except Exception as e:
        # Log but don't fail
        print(f"⚠️  Could not fetch existing doc for name '{name}': {e}")
        return None

def iter_folder_items(folder_id: str) -> Iterable[Dict[str, Any]]:
    # Use the generic resource endpoint the way you showed in your example
    # /resource/{id}/items?type=folder&limit=...&offset=...&sort=_id&sortdir=1
    limit, offset = 200, 0
    while True:
        u = f"{BDSA_BASE.replace('/api/v1','')}/api/v1/resource/{folder_id}/items"
        payload = {"type":"folder", "limit":limit, "offset":offset, "sort":"_id", "sortdir":1}
        items = _get(u, payload)
        if not items: break
        for it in items: yield it
        offset += limit

def upsert_solr(docs: List[Dict[str, Any]]) -> None:
    if not docs: return
    r = requests.post(SOLR_UPDATE, json=docs, timeout=60)
    if not r.ok:
        raise IndexerError(f"Solr update failed: {r.status_code} {r.text}")

def index_folder(folder_id: Optional[str]=None, incremental: bool=True) -> Dict[str, Any]:
    """
    Index a folder from BDSA with smart incremental logic.
    
    Args:
        folder_id: BDSA folder ID to index (uses BDSA_FOLDER_ID from env if None)
        incremental: If True, skip items with unchanged metadata. If False, always reindex.
    
    Returns:
        Dict with statistics: {'indexed': count, 'skipped': count, 'updated': count, 'folder_id': id}
    """
    fid = folder_id or BDSA_FOLDER
    if not fid:
        raise IndexerError("BDSA_FOLDER_ID is not set and folder_id not provided")
    
    indexed = 0      # New documents
    skipped = 0      # Unchanged documents
    updated = 0      # Updated documents
    batch: List[Dict[str, Any]] = []
    
    print(f"📁 Indexing folder {fid} (incremental={incremental})")
    
    for item in iter_folder_items(fid):
        # Transform BDSA item to Solr document
        new_doc = transform_item(item)
        name = new_doc.get("name")
        unique_id = new_doc.get("unique_id")
        
        if not name or not unique_id:
            continue
        
        # Compute hash of new document (content-based)
        new_hash = compute_hash(new_doc)
        new_doc["_hash"] = new_hash
        
        if incremental:
            # Check if document with same FILENAME already exists (deduplicate by image name)
            # This prevents indexing same image name from different folders or different unique_ids
            old_doc = get_solr_doc_by_name(name)
            
            if old_doc:
                old_hash = old_doc.get("_hash")
                
                # If old_hash is missing, treat as "needs update" (first run with new hash logic)
                if old_hash and old_hash == new_hash:
                    # Same filename, same metadata hash → SKIP
                    skipped += 1
                    print(f"  ⏭️  Skipping {name} (already indexed with identical metadata)")
                    continue
                else:
                    # Same filename, different metadata hash → UPDATE
                    updated += 1
                    if not old_hash:
                        print(f"  🔄 Updating {name} (adding content hash)")
                    else:
                        print(f"  🔄 Updating {name} (metadata changed)")
            else:
                # New filename (not seen before)
                indexed += 1
                print(f"  ✨ New {name}")
        else:
            # Force reindex mode - always add
            indexed += 1
        
        batch.append(new_doc)
        
        if len(batch) >= BATCH_SIZE:
            upsert_solr(batch)
            batch.clear()
    
    # Flush remaining batch
    if batch:
        upsert_solr(batch)
    
    return {
        "indexed": indexed,
        "skipped": skipped, 
        "updated": updated,
        "total": indexed + updated + skipped,
        "folder_id": fid,
        "timestamp": now_iso()
    }

def thumbnail_url(item_id: str, w: int=384, h: int=384) -> str:
    # http://bdsa.../api/v1/item/{id}/tiles/thumbnail
    base = BDSA_BASE
    url = f"{base}/item/{item_id}/tiles/thumbnail?width={w}&height={h}"
    if BDSA_KEY:
        url += f"&token={BDSA_KEY}"
    return url
