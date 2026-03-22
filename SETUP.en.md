# VNDB Local Site Docker Setup Guide

This document explains how to set up a local VNDB site on a fresh machine using the data provided in this project.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (with Docker Compose)
- Approximately 2 GB of free disk space (image + database)

## Project Structure

```
VNDBDocker/
├── vndb/                          # VNDB source code
├── vndb-db-2026-03-21.tar.zst     # Database dump (~175 MB)
├── vndb-tags-2026-03-21.json.gz   # Tag dump (for reference)
├── vndb-traits-2026-03-21.json.gz # Trait dump (for reference)
├── vndb-votes-2026-03-21.gz       # Votes dump (for reference)
├── docker-compose.yml             # Docker Compose configuration
├── init-vndb.sh                   # Automatic initialization script
├── README.md                      # Original VNDB dump format description
└── SETUP.md                       # This document (Chinese version)
```

## Quick Start

### 1. Build the Docker Image

```bash
docker compose build
```

The first build takes about 2–3 minutes. It installs Alpine Linux, PostgreSQL 17, Perl, and all dependencies.

### 2. Start the Container

```bash
docker compose up -d
```

On the first start, `init-vndb.sh` will automatically perform the following steps (approximately 10–20 minutes):

1. Create a development user inside the container
2. Compile and install the vndbid PostgreSQL extension
3. Install the zstd decompression tool
4. Compile frontend assets (JS, CSS, icons)
5. Initialize the `var/` directory and configuration files
6. Initialize the PostgreSQL database
7. Import the data dump (decompress tar.zst → create schema → import tables)
8. Rebuild caches (VN cache, vote statistics, tags, traits, search index)
9. Start the development server

You can monitor initialization progress with:

```bash
docker logs -f vndb
```

When you see the following message, the server is ready:

```
==========================================
  VNDB is ready at http://localhost:3000
  API: http://localhost:3000/api/kana
==========================================
```

### 3. Verify

Open your browser and visit http://localhost:3000, or test the API:

```bash
# Query statistics
curl http://localhost:3000/api/kana/stats

# Query a specific VN
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","v11"],"fields":"id,title"}'
# Returns: {"more":false,"results":[{"id":"v11","title":"Fate/stay night"}]}

# Query a character
curl -X POST http://localhost:3000/api/kana/character \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","c1"],"fields":"id,name"}'

# List the first 5 VNs
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["id",">=","v1"],"fields":"id,title","results":5,"sort":"id"}'
```

## Common Operations

### Stop the Container

```bash
docker compose down
```

### Restart (Data Preserved)

```bash
docker compose up -d
```

When restarting, data will not be re-imported. The server starts directly and only takes a few seconds.

### Enter the Container Shell

```bash
docker exec -ti vndb su -l devuser
```

### Access PostgreSQL

```bash
docker exec -ti vndb psql -U vndb
```

### Full Reset (Wipe All Data and Re-import)

```bash
docker compose down
rm -rf vndb/docker/pg17
docker compose up -d
```

## API Documentation

The API endpoint is located at `http://localhost:3000/api/kana` and works the same way as the official API.

- API documentation page: http://localhost:3000/api/kana
- All query endpoints use the `POST` method with a JSON body
- Supported endpoints: `/vn`, `/character`, `/release`, `/producer`, `/staff`, `/tag`, `/trait`, `/user`, `/ulist`, `/quote`
- Other endpoints: `GET /stats`, `GET /schema`

### Query Examples

```bash
# Query by ID
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","v2002"],"fields":"id,title,olang,image.url"}'

# Query with multiple filters
curl -X POST http://localhost:3000/api/kana/vn \
  -H "Content-Type: application/json" \
  -d '{"filters":["and",["olang","=","ja"],["id",">=","v1"]],"fields":"id,title","results":10,"sort":"id"}'

# Query a release
curl -X POST http://localhost:3000/api/kana/release \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","r1"],"fields":"id,title,released"}'

# Query a tag
curl -X POST http://localhost:3000/api/kana/tag \
  -H "Content-Type: application/json" \
  -d '{"filters":["id","=","g1"],"fields":"id,name"}'
```

## Known Limitations

| Item | Description |
|------|-------------|
| Images | VN covers, character images, and screenshots cannot be displayed because image files are not included in the database dump. |
| extlinks tables | `producers_extlinks`, `releases_extlinks`, `staff_extlinks`, `vn_extlinks` failed to import (schema column mismatch); external link data is unavailable. |
| ulist_labels | User list labels were not imported (the dump does not include the `private` column). |
| vn_length_votes | Game length votes were not imported. |
| Discussions / Edit history | The dump itself does not contain this data. |
| Web frontend | The homepage returns a 500 error due to a cookie domain issue. The API documentation page (`GET /api/kana`) requires `make prod` (which depends on pandoc) to work. The API endpoints themselves are unaffected. |

## Cache Rebuilding

After data import, several caches need to be rebuilt for the API's `released`, `languages`, `platforms`, `developers`, `tags`, and `search` filters to work properly. The initialization script handles this automatically, but if you need to rebuild manually:

```bash
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT update_vncache(NULL);'"
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT update_vnvotestats();'"
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT tag_vn_calc(NULL);'"
docker exec vndb sh -c "psql -U vndb vndb -c 'SELECT traits_chars_calc(NULL);'"
docker exec vndb sh -c "psql -U vndb vndb -f sql/rebuild-search-cache.sql"
```

Step-by-step breakdown:

| Command | Purpose | Duration |
|---------|---------|----------|
| `update_vncache(NULL)` | Recalculates VN `released`, `languages`, `platforms`, `developers` | ~1 minute |
| `update_vnvotestats()` | Recalculates ratings, vote counts, rankings | ~30 seconds |
| `tag_vn_calc(NULL)` | Rebuilds `tags_vn_direct` and `tags_vn_inherit` (tag inheritance) | ~2–5 minutes |
| `traits_chars_calc(NULL)` | Rebuilds character trait inheritance cache | ~1–2 minutes |
| `rebuild-search-cache.sql` | Rebuilds full-text search index (processed in batches to avoid table locks) | ~5–10 minutes |

To rebuild the cache for a single VN, pass the specific ID:

```bash
docker exec vndb sh -c "psql -U vndb vndb -c \"SELECT update_vncache('v92');\""
docker exec vndb sh -c "psql -U vndb vndb -c \"SELECT tag_vn_calc('v92');\""
```

## Updating the Data Dump

To use a newer data dump:

1. Download the latest `vndb-db-*.tar.zst` from https://dl.vndb.org/dump/
2. Place the file in the project root directory
3. Update the filename in `docker-compose.yml`:
   ```yaml
   - ./vndb-db-NEW-DATE.tar.zst:/dump/vndb-db.tar.zst:ro
   ```
4. Reset and rebuild:
   ```bash
   docker compose down
   rm -rf vndb/docker/pg17
   docker compose up -d
   ```

## Troubleshooting

### Container Exits Immediately After Starting

Check the logs:
```bash
docker logs vndb
```

Common cause: port 3000 is already in use. Change it to another port in `docker-compose.yml`:
```yaml
ports:
  - "3001:3000"
```

### Database Initialization Fails

Delete the PostgreSQL data directory and retry:
```bash
docker compose down
rm -rf vndb/docker/pg17
docker compose up -d
```

### View API Error Logs

```bash
docker exec vndb cat /vndb/docker/var/log/fu.log
docker exec vndb cat /vndb/docker/var/log/api.log
```
