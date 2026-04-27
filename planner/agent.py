import os 
from google.adk.agents.llm_agent import Agent
from .prompt import INSTRUCTION
from google.adk.tools.mcp_tool import McpToolset, StdioConnectionParams
from mcp.client.stdio import StdioServerParameters


mcp_args: list[str] = ["a2db-mcp"]
def prepare_a2db_mcp_args():
    development_uri = os.getenv(
        "DEVELOPMENT_URI",
        "postgresql://platform-ai:platform-ai@development-database:5432/platform-ai"
    ).strip()

    development_uri = development_uri.strip()

    project = os.getenv("A2DB_PROJECT", "uninorte")
    env = os.getenv("A2DB_ENV", "development")
    db = os.getenv("A2DB_DB", "development")
    
    connection_name = f"{project}/{env}/{db}"

    return ["--register", connection_name, development_uri]

mcp = McpToolset(
    connection_params=StdioConnectionParams(
        server_params=StdioServerParameters(
            command="uv",
            args=["run", *prepare_a2db_mcp_args()],
        )
    )
)

root_agent = Agent(
    model='gemini-2.5-flash',
    name='platform_sre',
    instruction=INSTRUCTION,
    tools=[mcp],
)
