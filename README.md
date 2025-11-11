# BDSA ↔ Solr ↔ Blacklight (with ETL + Mirador stub)

A ready-to-run starter that indexes your Brain Digital Slide Archive (DSA) items into Solr, serves a Blacklight faceted gallery with DSA thumbnails, and includes a small FastAPI ETL plus a Mirador/IIIF stub.

# BDSA ↔ Solr ↔ Blacklight Search Stack

A ready-to-run Docker-based stack that indexes Brain Digital Slide Archive (DSA) items into Apache Solr, serves a faceted image gallery via Blacklight, and exposes a FastAPI ETL service for metadata indexing.

## Features

- **Apache Solr 9** – Search engine with pre-configured `bdsa` collection and schema
- **FastAPI ETL Service** – Authenticates with Girder/DSA, fetches items, and indexes into Solr
- **Blacklight Rails Gallery** – Faceted search UI with DSA thumbnail previews
- **Docker Compose** – Single-command deployment of all services
- **IIIF/Mirador Support** – Minimal IIIF manifest endpoints for slide viewer integration

## 📋 Prerequisites

- [Docker](https://www.docker.com/) and Docker Compose
- A BDSA/Girder instance with API key
- Folder ID(s) or item IDs to index

## Quick Start

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

## Project Structure

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

## Configuration

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

## API Endpoints

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

## Common Tasks

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

## Troubleshooting

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

## Advanced Usage

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

## Development

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
 
