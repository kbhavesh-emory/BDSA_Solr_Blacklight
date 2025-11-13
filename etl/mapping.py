import os
from typing import Any, Dict, Optional

BDSA_BASE = os.getenv("BDSA_BASE", "http://bdsa.pathology.emory.edu:8080/api/v1").rstrip("/")
BDSA_API_KEY = os.getenv("BDSA_API_KEY", "")
ETL_PROXY_URL = os.getenv("ETL_PROXY_URL", "http://einstein.neurology.emory.edu")

def get_meta(item: Dict[str, Any]) -> Dict[str, Any]:
    return item.get("meta", {}) or {}

def transform_item(item: Dict[str, Any]) -> Dict[str, Any]:
    meta = get_meta(item)
    nps  = meta.get("npSchema") or {}  # expected dict like {blockID, caseID, regionName, stainID}

    name = item.get("name")
    unique_id = item.get("_id")  # Unique ID from BDSA API
    metadata = meta.get("Metadata")
    bad_imageno = meta.get("bad_imageno")
    block = str(nps.get("blockID")) if nps.get("blockID") else None
    case = nps.get("caseID")
    region = nps.get("regionName")
    stain = nps.get("stainID")

    # Build direct BDSA thumbnail URL with API key for browser access
    thumb_url = f"{BDSA_BASE}/item/{unique_id}/tiles/thumbnail?width=768&height=768&token={BDSA_API_KEY}"

    # Use filename as document identifier for deduplication
    # If same filename appears in different folders, only one instance will be indexed
    # The document ID ensures no duplicate filenames in the index
    doc_id = f"bdsa-{name.replace(' ', '_').replace('/', '_')}" if name else f"bdsa-{unique_id}"

    doc = {
        "id": doc_id,  # Document ID uses filename for deduplication
        "unique_id": unique_id,  # Store unique_id for tracking which BDSA item this came from
        "name": name,
        "thumbnail_url": thumb_url,

        # Requested fields
        "metadata": metadata,       # string
        "bad_imageno": bad_imageno, # string

        "np_blockID": block,
        "np_caseID": case,
        "np_regionName": region,
        "np_stainID": stain,

        "created": item.get("created"),
        "updated": item.get("updated"),
    }
    tokens = []
    for val in (name, metadata, bad_imageno, block, case, region, stain):
        if isinstance(val, (list, tuple)):
            tokens.extend(str(v) for v in val if v not in (None, ""))
        elif val not in (None, ""):
            tokens.append(str(val))
    if tokens:
        doc["text"] = " ".join(tokens)
    # strip Nones and keep hash field if present (added by indexer)
    return {k: v for k, v in doc.items() if v is not None}
