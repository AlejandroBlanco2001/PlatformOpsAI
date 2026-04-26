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

app = get_fast_api_app(
    agents_dir=AGENT_DIR,
    web=True,
)

if __name__ == "__main__":
    import uvicorn
    PORT = os.getenv("PORT", "8080")

    uvicorn.run(app, host="0.0.0.0", port=int(PORT))