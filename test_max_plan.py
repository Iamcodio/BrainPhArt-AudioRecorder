# test_max_plan.py
import anyio
from claude_agent_sdk import query, AssistantMessage, TextBlock

async def main():
    print("Testing Max Plan...")

    async for message in query(prompt="What is 2 + 2? Reply with just the number."):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(f"Claude: {block.text}")

if __name__ == "__main__":
    anyio.run(main)
