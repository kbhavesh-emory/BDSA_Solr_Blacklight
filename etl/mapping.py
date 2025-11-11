import os
from typing import Any, Dict, Optional

BDSA_BASE = os.getenv("BDSA_BASE", "http://bdsa.pathology.emory.edu:8080/api/v1").rstrip("/")

def get_meta(item: Dict[str, Any]) -> Dict[str, Any]:
    return item.get("meta", {}) or {}

def transform_item(item: Dict[str, Any]) -> Dict[str, Any]:
    meta = get_meta(item)
    nps  = meta.get("npSchema") or {}  # expected dict like {blockID, caseID, regionName, stainID}

    name = item.get("name")
    metadata = meta.get("Metadata")
    bad_imageno = meta.get("bad_imageno")
    block = nps.get("blockID")
    case = nps.get("caseID")
    region = nps.get("regionName")
    stain = nps.get("stainID")

    thumb_url = f"{BDSA_BASE}/item/{item['_id']}/tiles/thumbnail?width=384&height=384"

    doc = {
        "id": f"bdsa-{item['_id']}",
        "item_id": item["_id"],
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
    # strip Nones
    return {k: v for k, v in doc.items() if v is not None}
