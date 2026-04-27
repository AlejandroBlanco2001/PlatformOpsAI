from google.adk.agents.llm_agent import Agent
from .prompt import INSTRUCTION

root_agent = Agent(
    model='gemini-2.5-flash',
    name='platform_sre',
    instruction=INSTRUCTION,
)
