#!/usr/bin/env python3
import json, os, sys, urllib.request, urllib.error

SOLR_CORE_URL = os.environ.get("SOLR_CORE_URL", "http://localhost:8983/solr/bdsa")
SCHEMA_FILE   = os.environ.get("SOLR_SCHEMA_FILE", "./solr_schema_bootstrap.json")
ADVANCED_HANDLER = {
    "name": "/advanced",
    "class": "solr.SearchHandler",
    "defaults": {
        "wt": "json",
        "echoParams": "explicit",
        "rows": 10,
        "defType": "edismax",
        "q.op": "AND",
        "df": "text",
        "qf": "name metadata bad_imageno np_blockID np_caseID np_regionName np_stainID text"
    }
}

def req(path, payload=None):
    url = f"{SOLR_CORE_URL}{path}"
    headers = {}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    r = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.getcode(), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

def ensure_field_type(ft):
    name = ft["name"]
    code,_ = req(f"/schema/fieldtypes/{name}")
    if code != 200:
        code, body = req("/schema", {"add-field-type": ft})
        if code != 200: raise RuntimeError(f"add-field-type {name} failed: {body}")

def ensure_field(f):
    name = f["name"]
    code,_ = req(f"/schema/fields/{name}")
    if code != 200:
        code, body = req("/schema", {"add-field": f})
        if code != 200: raise RuntimeError(f"add-field {name} failed: {body}")

def ensure_copy(cf):
    src, dst = cf["source"], cf["dest"]
    code,_ = req(f"/schema/copyfields?source={src}&dest={dst}")
    if code != 200:
        code, body = req("/schema", {"add-copy-field": cf})
        if code != 200: raise RuntimeError(f"add-copy-field {src}->{dst} failed: {body}")

def ensure_request_handler(handler):
    name = handler["name"]
    code, body = req("/config/requestHandler")
    if code == 200:
        data = json.loads(body.decode("utf-8"))
        handlers = data.get("config", {}).get("requestHandler", [])
        if isinstance(handlers, dict):
            handler_iterable = handlers.values()
        else:
            handler_iterable = handlers
        if any(h.get("name") == name for h in handler_iterable):
            up_code, up_body = req("/config", {"update-requesthandler": handler})
            if up_code != 200:
                raise RuntimeError(f"update-requesthandler {name} failed: {up_body}")
            return
    code, body = req("/config", {"add-requesthandler": handler})
    if code != 200:
        text = body.decode("utf-8") if isinstance(body, (bytes, bytearray)) else str(body)
        if "already exists" in text:
            return
        raise RuntimeError(f"add-requesthandler {name} failed: {body}")

def main():
    with open(SCHEMA_FILE, "r", encoding="utf-8") as f:
        schema = json.load(f)
    for ft in schema.get("add-field-type", []): ensure_field_type(ft)
    for fd in schema.get("add-field", []): ensure_field(fd)
    for cf in schema.get("add-copy-field", []): ensure_copy(cf)
    ensure_request_handler(ADVANCED_HANDLER)
    print("✅ Solr schema ensured")

if __name__ == "__main__":
    main()
