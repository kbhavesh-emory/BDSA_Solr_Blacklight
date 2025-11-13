from typing import Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse
import requests
import indexer

app = FastAPI(title="BDSA→Solr ETL (Folder-based)")

def _wrap(fn, *a, **kw):
    try:
        return fn(*a, **kw)
    except indexer.IndexerError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

@app.get("/health")
def health():
    return {"ok": True, "time": indexer.now_iso()}

@app.post("/reindex_folder")
def reindex_folder(folder_id: Optional[str] = Query(None, description="BDSA folderId to index"),
                   incremental: bool = Query(True, description="Skip unchanged items if True")):
    return _wrap(indexer.index_folder, folder_id=folder_id, incremental=incremental)

@app.post("/reindex_folder_force")
def reindex_folder_force(folder_id: Optional[str] = Query(None, description="BDSA folderId to index")):
    """Force full re-index, ignoring existing metadata (always reindex all items)"""
    return _wrap(indexer.index_folder, folder_id=folder_id, incremental=False)

@app.get("/thumb_url/{item_id}")
def thumb_url(item_id: str, w: int = 384, h: int = 384):
    return {"item_id": item_id, "thumbnail": indexer.thumbnail_url(item_id, w, h)}

@app.get("/image/{item_id}")
def get_image(item_id: str, w: int = 384, h: int = 384):
    """Proxy image from BDSA API with authentication"""
    url = indexer.thumbnail_url(item_id, w, h)
    try:
        resp = requests.get(url, timeout=30)
        resp.raise_for_status()
        return StreamingResponse(
            iter([resp.content]),
            media_type=resp.headers.get("content-type", "image/jpeg"),
            headers={"Cache-Control": "public, max-age=3600"}
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Failed to fetch image: {str(e)}")
