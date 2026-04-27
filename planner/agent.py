import os 
from google.adk.agents.llm_agent import Agent
from .prompt import INSTRUCTION, INSTRUCTION_LLM_PROVIDER_ASSISTANT
from google.adk.tools.mcp_tool import McpToolset, StdioConnectionParams
from mcp.client.stdio import StdioServerParameters
from google.adk.skills import load_skill_from_dir
from google.adk.tools import skill_toolset
from pathlib import Path
from google.adk.planners import BuiltInPlanner
from google.genai import types
from google.adk.tools import google_search
from google.adk.tools import AgentTool

fin_ops_skill = load_skill_from_dir(
    Path(__file__).parent / "skills" / "finops-llm-analyst",
)

my_skill_toolset = skill_toolset.SkillToolset(
    skills=[fin_ops_skill],
)

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

    return ["a2db-mcp", "--register", connection_name, development_uri]

mcp = McpToolset(
    connection_params=StdioConnectionParams(
        server_params=StdioServerParameters(
            command="uv",
            args=["run", *prepare_a2db_mcp_args()],
        )
    )
)

llm_provider_assistant = Agent(
    model="gemini-2.5-flash",
    name="llm_provider_atssistant",
    instruction=INSTRUCTION_LLM_PROVIDER_ASSISTANT,
    tools=[google_search],
        planner=BuiltInPlanner(
        thinking_config=types.ThinkingConfig(
            include_thoughts=True,
            thinking_budget=1024,
        )
    ),
)

root_agent = Agent(
    model='gemini-2.5-flash',
    name='platform_sre',
    instruction=INSTRUCTION,
    tools=[mcp, my_skill_toolset, AgentTool(llm_provider_assistant)],
)
