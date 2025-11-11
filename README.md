# BDSA ↔ Solr ↔ Blacklight (with ETL + Mirador stub)

A ready-to-run starter that indexes your Brain Digital Slide Archive (DSA) items into Solr, serves a Blacklight faceted gallery with DSA thumbnails, and includes a small FastAPI ETL plus a Mirador/IIIF stub.

# BDSA ↔ Solr ↔ Blacklight Search Stack

A ready-to-run Docker-based stack that indexes Brain Digital Slide Archive (DSA) items into Apache Solr, serves a faceted image gallery via Blacklight, and exposes a FastAPI ETL service for metadata indexing.

## 🎯 Features

- **Apache Solr 9** – Search engine with pre-configured `bdsa` collection and schema
- **FastAPI ETL Service** – Authenticates with Girder/DSA, fetches items, and indexes into Solr
- **Blacklight Rails Gallery** – Faceted search UI with DSA thumbnail previews
- **Docker Compose** – Single-command deployment of all services
- **IIIF/Mirador Support** – Minimal IIIF manifest endpoints for slide viewer integration

## 📋 Prerequisites

- [Docker](https://www.docker.com/) and Docker Compose
- A BDSA/Girder instance with API key
- Folder ID(s) or item IDs to index

## 🚀 Quick Start

### 1. Clone and configure

```bash
cd /opt/bhavesh/dsa-search
# Edit etl/.env with your BDSA_API_KEY and BDSA_FOLDER_ID
```

### 2. Start all services

```bash
docker compose up -d --build
```

This brings up:
- **Solr** on port 8983
- **ETL API** on port 8081
- **Blacklight Gallery** on port 3001 (or 3000 internally)
- **Nginx** on port 80 (optional reverse proxy)

### 3. Index your data

```bash
# Full reindex (all items in BDSA_FOLDER_ID)
docker compose run --rm etl python -m etl.cli full

# Or via HTTP
curl -X POST http://localhost:8081/reindex_folder
```

### 4. Browse the gallery

Open your browser to **http://localhost:3001** (or your host URL)

## 📚 Project Structure

```
.
├── docker-compose.yml           # Service orchestration
├── solr/
│   ├── solr_schema_bootstrap.json  # Field definitions
│   └── apply_schema.py          # Bootstrap script
├── etl/
│   ├── app.py                   # FastAPI service
│   ├── indexer.py               # Indexing logic
│   ├── mapping.py               # DSA → Solr field mapping
│   ├── requirements.txt          # Python dependencies
│   ├── Dockerfile               # ETL container
│   └── .env                     # Configuration (API keys, URLs)
├── blacklight/
│   ├── Dockerfile               # Rails container
│   └── scripts/init_blacklight.sh  # Initialization
└── nginx.conf                   # (Optional) reverse proxy config
```

## ⚙️ Configuration

### ETL Service (`etl/.env`)

```bash
BDSA_BASE=http://bdsa.pathology.emory.edu:8080/api/v1
BDSA_API_KEY=your-girder-api-key-here
BDSA_FOLDER_ID=your-bdsa-folder-id
SOLR_UPDATE=http://solr:8983/solr/bdsa/update?commitWithin=5000
BATCH_SIZE=200
DEFAULT_SINCE=2000-01-01T00:00:00Z
```

### Mapped Fields (in Solr)

The ETL maps DSA item metadata to these Solr fields:

- `id` – Unique document ID (e.g., `bdsa-{item_id}`)
- `item_id` – Original DSA item ID
- `name` – Item/slide name
- `thumbnail_url` – Link to DSA thumbnail
- `np_blockID`, `np_caseID`, `np_regionName`, `np_stainID` – Neuropathology schema fields
- `metadata`, `bad_imageno` – Custom metadata
- `text` – Full-text search field
- `created`, `updated` – Timestamps

See `etl/mapping.py` to customize field extraction.

## 🔗 API Endpoints

### ETL Service

All endpoints available at `http://localhost:8081`

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Service heartbeat |
| `POST` | `/reindex_folder?folder_id=...` | Index all items in a folder |
| `GET` | `/thumb_url/{item_id}` | Get thumbnail URL for an item |
| `GET` | `/docs` | Swagger UI |
| `GET` | `/redoc` | ReDoc API documentation |

### Solr

Search via **http://localhost:8983/solr/bdsa/select**

```bash
# Example: search for "aBeta" stain
curl "http://localhost:8983/solr/bdsa/select?q=stain:aBeta&rows=10"

# Check total indexed documents
curl "http://localhost:8983/solr/bdsa/select?q=*:*&rows=0"
```

### Blacklight

- **Home** – http://localhost:3001/
- **Faceted search** – http://localhost:3001/?q=searchterm
- **Admin** – http://localhost:3001/admin

## 💡 Common Tasks

### Reindex a specific folder

```bash
docker compose run --rm etl \
  python -m etl.cli full --folder-id 67ddb0782fc8ce397c5ef7fb
```

### View ETL logs

```bash
docker compose logs -f etl
```

### Inspect Solr schema

```bash
curl "http://localhost:8983/solr/bdsa/schema/fields?wt=json" | jq .
```

### Clean and restart

```bash
docker compose down --volumes
docker compose up -d --build
```

### Verify indexing succeeded

```bash
# Check document count
curl "http://localhost:8983/solr/bdsa/select?q=*:*&rows=0" | jq .response.numFound

# Spot-check a facet
curl "http://localhost:8983/solr/bdsa/select?q=np_regionName:*&rows=5&facet=true&facet.field=np_stainID"
```

## 🔧 Troubleshooting

### "BDSA_FOLDER_ID is not set"

Set `BDSA_FOLDER_ID` in `etl/.env`, then rebuild:

```bash
docker compose build etl
docker compose restart etl
```

### Blacklight shows no results

1. Check ETL health: `curl http://localhost:8081/health`
2. Verify Solr has documents: `curl http://localhost:8983/solr/bdsa/select?q=*:*&rows=0`
3. Inspect ETL logs: `docker compose logs etl`

### Port already in use

Change the host port in `docker-compose.yml`:

```yaml
services:
  blacklight:
    ports:
      - "3002:3000"  # Use 3002 instead of 3001
```

Then restart: `docker compose up -d`

## 📖 Advanced Usage

### Add custom fields

1. Edit `etl/mapping.py` to extract new fields from DSA metadata
2. Update `solr/solr_schema_bootstrap.json` with field definitions
3. Rebuild and reindex:

```bash
docker compose build etl
docker compose down --volumes
docker compose up -d --build
```

### ACL-aware indexing

Store ACL metadata in Solr fields and enforce access control in Blacklight using [authorization policies](https://github.com/projectblacklight/blacklight/wiki/Authorization).

### IIIF Image API

Extend the manifest endpoints to proxy DSA tiles through an IIIF compliance layer (e.g., [Cantaloupe](https://cantaloupe-project.github.io/)).

## 📝 Development

### Run tests

```bash
docker compose exec etl python -m pytest
```

### Hot-reload ETL

After editing `etl/*.py`:

```bash
docker compose restart etl
```

### Shell into a container

```bash
docker compose exec etl bash
docker compose exec blacklight bash
docker compose exec solr bash
```

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## 📄 License

This project is provided as-is. Modify and distribute as needed for your use case.

## 🙋 Support

For issues, questions, or feature requests, please open an [Issue](https://github.com/your-org/dsa-search/issues) on GitHub.

---

**Built with** ❤️ **for digital pathology and neuroscience research**


## What’s inside
- **Solr 9** (`bdsa` collection) + schema bootstrap
- **ETL (FastAPI)** to sync DSA → Solr (full + incremental)
- **Blacklight (Rails)** pre-configured with facets and grid cards that use DSA thumbnails
- **Mirador stub** via simple IIIF manifest route

## Quick start

```bash
# 1) Bring everything up

docker compose up -d --build

# 2) Watch logs
docker compose logs -f solr
docker compose logs -f solr-schema-setup
docker compose logs -f etl
docker compose logs -f blacklight
```

### ETL service
- Built automatically when you run 

```bash

docker compose up -d --build`
uvicorn etl.app:app --host 0.0.0.0 --port 8081

 ```
- Health check: `GET http://localhost:8081/health` → `{"ok": true, ...}`.

- Root path is intentionally undefined; `http://localhost:8081/` returns `{"detail":"Not Found"}`.

- Interactive docs: Swagger UI at `http://localhost:8081/docs`, ReDoc at `http://localhost:8081/redoc`.

### Index data
Full reindex:
```bash
curl -X POST http://localhost:8081/reindex_full
```
Incremental since a timestamp:
```bash
curl -X POST "http://localhost:8081/sync_since?since=2025-01-01T00:00:00Z"
```

### Run indexing from the CLI
The ETL package now includes a helper you can execute directly (uses the same `.env` settings):

```bash
cd etl

# Index everything (large images only, unless you pass --include-small)
python -m etl.cli full

# Incremental sync since a timestamp
python -m etl.cli since 2025-01-01T00:00:00Z
```

Use `--folder-id <GirderFolderId>` to override `BDSA_FOLDER_ID`, or `--include-small` if you want to index non-largeImage items.

### Fetch metadata/annotations first, then index
If you want to pull the full Girder record (metadata + annotations + files + tile info) before indexing, use the new command:

```bash
python -m etl.cli girder 67ddb0782fc8ce397c5ef7fb --dump-json folder_67ddb0782fc8ce397c5ef7fb.json
```

You can pass either a *folder ID* or a single *item ID*; if you give it an item, only that record is fetched and indexed. The command:
1. Authenticate to Girder using `BDSA_API_KEY` (or exchange your API key for a token).
2. Fetch every item in the folder along with metadata, annotations, files, and tile info.
3. Optionally dump the raw JSON (`--dump-json`).
4. Map the records into the Solr schema and upsert them so Blacklight can search them.

If you omit the folder id, the command defaults to `BDSA_FOLDER_ID` from `.env`.

### Open the gallery
- Blacklight: http://localhost:3000
- Solr Admin: http://localhost:8983
- ETL health: http://localhost:8081/health

### Chat → filter mapping (example)
```bash
curl "http://localhost:8081/chat_query?q=show%20hni%20images"
# → use returned Solr params to fetch docs and render the grid
```

**ETL endpoints**
- `GET /health` – service heartbeat.
- `POST /reindex_full?only_large=true[&folder_id=BDSA_FOLDER_ID]` – reindex every item (toggle `only_large` to include small images; optionally scope to a single BDSA folder).
- `POST /sync_since?since=ISO8601&only_large=true[&folder_id=BDSA_FOLDER_ID]` – incremental sync based on `updated` timestamps (defaults to `DEFAULT_SINCE` from `.env`; accepts `folder_id` to limit the crawl).
- `GET /thumb_url/{item_id}` – convenience helper that returns the tile thumbnail URL for an item id.
- `GET /chat_query?q=...` – maps simple text intents to Solr filter queries.

## Configuration
- ETL env in `etl/.env` (defaults point to your BDSA host). Set `BDSA_FOLDER_ID` if you want to restrict indexing to a specific Girder folder.
- Blacklight uses `SOLR_URL` from compose to talk to Solr.
- DSA thumbnail URLs point to `http://bdsa.pathology.emory.edu:8080/api/v1/...`; change the host if needed.

## Notes
- The IIIF manifest is minimal and references DZI from DSA. For full IIIF Image API compliance, add a proxy translating DSA tiles.
- For ACL-aware indexing, filter items in ETL by audience or store ACL fields and enforce app-side.

## Next steps
- Extend `etl/mapping.py` to derive more fields (e.g., Aβ positivity, PPC metrics).
- Add NLP synonyms in `/chat_query` for richer intent→facet mapping.
- Style Blacklight index page for a tighter ISIC-like layout (in `app/views/catalog/_index_default.html.erb`).


indexin

If the ETL container is already running, hot-reload it
 (docker compose restart etl) so it picks up the refactor.

Kick off an indexing run with either:
API: curl -X POST http://localhost:8081/reindex_full
CLI: cd etl && python -m etl.cli full

do

https://statics.teams.cdn.office.net/evergreen-assets/safelinks/2/atp-safelinks.html

docker logs -f dsa-search-solr-1

cd /opt/bhavesh/dsa-search/etl
# largeImage items from the default Girder folder
python -m etl.cli full
# …or incremental
python -m etl.cli since 2025-01-01T00:00:00Z

https://statics.teams.cdn.office.net/evergreen-assets/safelinks/2/atp-safelinks.html


BDSA_API_KEY=El4DUuufS4TBqxljcjdT4ZaXL7T4uVl7PK9gNigsgAhc9AjBlk5J4CIYAkNSEvsv
docker compose run --rm etl env | grep BDSA_API_KEY

docker compose run --rm -e BDSA_API_KEY=El4DUuufS4TBqxljcjdT4ZaXL7T4uVl7PK9gNigsgAhc9AjBlk5J4CIYAkNSEvsv etl python cli.py full


docker compose run --rm etl env | grep BDSA_API_KEY
docker compose build etl
