# PlatformOpsAI

This project runs an SRE-style AI agent for a **multi-tenant LLM API platform**.

The agent is designed to answer operational questions like:
- Customer **usage/spend/budget utilization**
- Model **latency/performance** comparisons
- Customers near/over **budget limits**
- **Error** summaries (what’s failing, where, and how often)

It does this by querying a seeded **development Postgres database** (via the `a2db` MCP tool) and, when needed, delegating to a small “LLM provider assistant” that uses **web search** to recommend better models (pros/cons + cost/latency tradeoffs).

The service is exposed as a **FastAPI web app** (Google ADK), stores agent sessions/state in **Postgres**, and can optionally send OpenTelemetry traces to **Arize Phoenix** for debugging and observability.

## Prerequisites

Choose **one** of the following run options.

### Option A (recommended): Docker

Install:
- **Docker Desktop** (includes Docker Engine)
- **Docker Compose v2** (`docker compose ...`)

### Option B: Run locally (without Docker)

Install:
- **Python 3.12+** (project targets `>=3.12`)
- **uv** (Astral) for dependency management
- **PostgreSQL** (or any compatible Postgres instance you can reach)

## Environment variables

Create a local `.env` file from the example:

```bash
cp .env.example .env
```

Then edit `.env` and set at least:
- **`GOOGLE_API_KEY`**: your API key
- **Agent DB (required)**: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_HOST`, `POSTGRES_PORT`
- **Development DB (required)**: `DEVELOPMENT_URI` (and/or `DEVELOPMENT_POSTGRES_*`)

Notes:
- When running with Docker Compose, `POSTGRES_HOST` should be `agent-database` (the service name) and `POSTGRES_PORT` should be `5432`.
- The development DB is exposed to your laptop on **localhost:5433**, but other containers must still connect to it via `development-database:5432`.
- Phoenix is optional. If you don’t want tracing, you can leave `PHOENIX_COLLECTOR_ENDPOINT` unset (or remove the `phoenix` service from compose).

## Run (Docker)

From the repo root:

```bash
docker compose up --build
```

What you get:
- **Agent server**: `http://localhost:8080`
- **Phoenix UI** (tracing): `http://localhost:6006`

Stop everything:

```bash
docker compose down
```

### Seed / reset the development database (Docker)

The `development-database` service mounts `SQL/01_seed.sql` and seeds automatically on first start (empty volume).

```bash
docker compose up -d development-database
```

To re-seed from scratch:

```bash
docker compose down -v && docker compose up -d development-database
```

## Run (local Python)

1) Install dependencies:

```bash
uv sync
```

2) Ensure your environment variables are set (either via `.env` in your shell/session, or exporting them manually).

3) Start the server:

```bash
uv run uvicorn main:app --host 0.0.0.0 --port 8080
```

## Troubleshooting

- **Missing environment variables**
  - `main.py` will raise `ValueError("Missing environment variables")` if Postgres env vars are not set.
- **Port conflicts**
  - Update `PORT` in `.env`, or change the port mappings in `docker-compose.yml`.

