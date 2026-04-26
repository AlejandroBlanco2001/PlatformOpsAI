import os

from pathlib import Path
from google.adk.cli.fast_api import get_fast_api_app
from phoenix.otel import register

AGENT_DIR = str(Path(__file__).parent)

tracer_provider = register(
    project_name="default",
    auto_instrument=True,
    endpoint=os.getenv("PHOENIX_COLLECTOR_ENDPOINT"),
)


def build_database_uri():
    "Build the database URI"
    user = os.getenv('POSTGRES_USER')
    password = os.getenv('POSTGRES_PASSWORD')
    host = os.getenv('POSTGRES_HOST')
    port = os.getenv('POSTGRES_PORT')
    db = os.getenv('POSTGRES_DB')

    if not all([user, password, host, port, db]):
        raise ValueError("Missing environment variables")

    return f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{db}"


app = get_fast_api_app(agents_dir=AGENT_DIR, web=True, session_service_uri=build_database_uri())

if __name__ == "__main__":
    import uvicorn

    PORT = os.getenv("PORT", "8080")

    uvicorn.run(app, host="0.0.0.0", port=int(PORT))
