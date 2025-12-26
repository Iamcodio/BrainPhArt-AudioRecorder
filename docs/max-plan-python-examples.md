# BrainPhArt + Claude Max Plan - Python Examples

All examples use **$0 API costs** (Max Plan credits)

---

## Example 1: Simple Test

```python
# test_max_plan.py
import anyio
from claude_agent_sdk import query, AssistantMessage, TextBlock

async def main():
    print("Testing Max Plan...")
    
    async for message in query(prompt="What is 2 + 2?"):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(f"Claude: {block.text}")

if __name__ == "__main__":
    anyio.run(main)
```

---

## Example 2: Transcript Cleanup

```python
# clean_transcript.py
import anyio
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock

async def clean_transcript(raw: str) -> str:
    options = ClaudeAgentOptions(
        system_prompt="""Clean transcripts:
        - Fix grammar
        - Remove filler words (um, uh, like)
        - Create paragraphs
        Return ONLY cleaned text.""",
        max_turns=1
    )
    
    result = ""
    async for msg in query(prompt=f"Clean:\n\n{raw}", options=options):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    result += block.text
    return result.strip()

async def main():
    raw = "um so we uh discussed Q4 you know"
    cleaned = await clean_transcript(raw)
    print(f"Raw:     {raw}")
    print(f"Cleaned: {cleaned}")

if __name__ == "__main__":
    anyio.run(main)
```

---

## Example 3: Auto-Categorization

```python
# categorize.py
import anyio
import json
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock

async def categorize(transcript: str) -> dict:
    options = ClaudeAgentOptions(
        system_prompt="""Categorize into:
        - Mental Health (therapy, recovery)
        - Business (meetings, strategy)
        - Personal (family, hobbies)
        - Financial (budgets, investments)
        - Creative (writing, ideas)
        
        Return JSON:
        {"domain": "Mental Health", "tags": ["recovery"], "confidence": 0.95}""",
        max_turns=1
    )
    
    result_text = ""
    async for msg in query(prompt=f"Categorize:\n\n{transcript[:500]}", options=options):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    result_text += block.text
    
    try:
        clean = result_text.strip()
        if clean.startswith("```json"):
            clean = clean.split("```json")[1].split("```")[0]
        return json.loads(clean.strip())
    except:
        return {"domain": "Personal", "tags": [], "confidence": 0.5}

async def main():
    sample = "Had therapy today. Discussed recovery patterns."
    result = await categorize(sample)
    print(f"Domain: {result['domain']}")
    print(f"Tags: {result['tags']}")

if __name__ == "__main__":
    anyio.run(main)
```

---

## Example 4: Batch Processing

```python
# batch_process.py
import anyio
from typing import List

async def process_batch(recording_ids: List[str]):
    """Process multiple recordings"""
    for rec_id in recording_ids:
        print(f"\nProcessing {rec_id}...")
        
        # Get raw transcript from DB
        raw = f"um this is {rec_id} you know"
        
        # Clean it
        cleaned = await clean_transcript(raw)
        print(f"  ✅ Cleaned: {len(cleaned)} chars")
        
        # Categorize it
        category = await categorize(cleaned)
        print(f"  ✅ Category: {category['domain']}")
        
        # Save to DB
        # save_to_database(rec_id, cleaned, category)

async def main():
    await process_batch(["rec_001", "rec_002", "rec_003"])
    print("\n✅ All processed using $0 Max Plan credits")

if __name__ == "__main__":
    anyio.run(main)
```

---

## Example 5: Voice Commands

```python
# voice_commands.py
import anyio
import json
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock

async def detect_command(transcript: str) -> dict:
    """Parse natural language commands"""
    options = ClaudeAgentOptions(
        system_prompt="""Parse commands:
        - save_as: Save recording type
        - tag: Add tags
        - create_task: Create action item
        
        Return JSON or null:
        {"command": "tag", "parameters": {"tags": ["extrophi"]}}""",
        max_turns=1
    )
    
    result_text = ""
    async for msg in query(prompt=f"Parse:\n\n{transcript}", options=options):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, TextBlock):
                    result_text += block.text
    
    try:
        clean = result_text.strip()
        if "null" in clean.lower():
            return None
        if clean.startswith("```"):
            clean = clean.split("```")[1].strip()
            if clean.startswith("json"):
                clean = clean[4:].strip()
        return json.loads(clean)
    except:
        return None

async def main():
    text = "Tag this recording with Extrophi and seanchai"
    cmd = await detect_command(text)
    if cmd:
        print(f"Command: {cmd['command']}")
        print(f"Parameters: {cmd['parameters']}")

if __name__ == "__main__":
    anyio.run(main)
```

---

## Complete Integration Example

```python
# brainphart_integration.py
import anyio
from claude_agent_sdk import query, ClaudeAgentOptions

class BrainPhArtProcessor:
    async def process_recording(self, recording_id: str):
        # 1. Get raw Whisper transcript from DB
        raw = self.get_from_db(recording_id)
        
        # 2. Clean with Claude (Max Plan - $0)
        cleaned = await self.clean(raw)
        
        # 3. Categorize (Max Plan - $0)
        category = await self.categorize(cleaned)
        
        # 4. Save to DB
        self.save_to_db(recording_id, cleaned, category)
        
        return {"cleaned": cleaned, "category": category}
    
    async def clean(self, text: str) -> str:
        options = ClaudeAgentOptions(
            system_prompt="Clean transcript...",
            max_turns=1
        )
        result = ""
        async for msg in query(prompt=f"Clean:\n{text}", options=options):
            # Extract text...
            pass
        return result
    
    async def categorize(self, text: str) -> dict:
        # Similar pattern...
        pass
    
    def get_from_db(self, rec_id: str) -> str:
        # Your SQLite query
        pass
    
    def save_to_db(self, rec_id: str, cleaned: str, category: dict):
        # Your SQLite update
        pass

# Usage
async def main():
    processor = BrainPhArtProcessor()
    result = await processor.process_recording("rec_001")
    print(f"Processed: {result}")

if __name__ == "__main__":
    anyio.run(main)
```

---

## Setup Commands

```bash
# Install
pip install claude-agent-sdk==0.1.18

# Authenticate
claude logout
claude login  # Use Max Plan

# Remove API key
unset ANTHROPIC_API_KEY

# Test
python test_max_plan.py
```

---

**All examples use $0 API costs (Max Plan credits)**