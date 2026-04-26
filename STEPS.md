## Seed the development database (runs inside Docker)

```bash
# First-time seed happens automatically on first startup (empty volume)
docker compose up -d development-database

# To re-seed from scratch, wipe the volume and start again
docker compose down -v && docker compose up -d development-database
```