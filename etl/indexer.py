import os, json, requests
from datetime import datetime, timezone
from typing import Dict, Any, Iterable, List, Optional

from mapping import transform_item

BDSA_BASE   = os.getenv("BDSA_BASE", "http://bdsa.pathology.emory.edu:8080/api/v1").rstrip("/")
BDSA_KEY    = os.getenv("BDSA_API_KEY", "")
BDSA_FOLDER = os.getenv("BDSA_FOLDER_ID")
SOLR_UPDATE = os.getenv("SOLR_UPDATE", "http://localhost:8983/solr/bdsa/update?commitWithin=5000")
BATCH_SIZE  = int(os.getenv("BATCH_SIZE", "200"))
DEFAULT_SINCE = os.getenv("DEFAULT_SINCE", "2000-01-01T00:00:00Z")

HEADERS = {"Girder-Token": BDSA_KEY} if BDSA_KEY else {}

class IndexerError(Exception): pass

def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def _get(url: str, params: Dict[str, Any]=None):
    r = requests.get(url, params=params or {}, headers=HEADERS, timeout=60)
    if not r.ok:
        raise IndexerError(f"GET {url} -> {r.status_code} {r.text}")
    return r.json()

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

def index_folder(folder_id: Optional[str]=None) -> Dict[str, Any]:
    fid = folder_id or BDSA_FOLDER
    if not fid:
        raise IndexerError("BDSA_FOLDER_ID is not set and folder_id not provided")
    count = 0
    batch: List[Dict[str, Any]] = []
    for item in iter_folder_items(fid):
        batch.append(transform_item(item))
        if len(batch) >= BATCH_SIZE:
            upsert_solr(batch); count += len(batch); batch.clear()
    if batch:
        upsert_solr(batch); count += len(batch)
    return {"indexed": count, "folder_id": fid}

def thumbnail_url(item_id: str, w: int=384, h: int=384) -> str:
    # http://bdsa.../api/v1/item/{id}/tiles/thumbnail
    base = BDSA_BASE
    return f"{base}/item/{item_id}/tiles/thumbnail?width={w}&height={h}"
