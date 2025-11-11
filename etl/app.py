from typing import Optional
from fastapi import FastAPI, HTTPException, Query
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
def reindex_folder(folder_id: Optional[str] = Query(None, description="BDSA folderId to index")):
    return _wrap(indexer.index_folder, folder_id=folder_id)

@app.get("/thumb_url/{item_id}")
def thumb_url(item_id: str, w: int = 384, h: int = 384):
    return {"item_id": item_id, "thumbnail": indexer.thumbnail_url(item_id, w, h)}
