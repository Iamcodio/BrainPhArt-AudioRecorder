# Checkpoint 33: Phase 2 Complete Feature Specification

**Date:** 2025-12-26 01:15 GMT  
**Sprint:** Week 2, Day 4  
**Project:** brainph.art - Phase 2 Vision  
**Status:** Feature catalog complete  
**Tokens Used:** 111,205 / 190,000 (58%)  
**Tokens Remaining:** 78,795 (42%)

---

## What We Created

**Complete feature specification for Phase 2:**
- 38 distinct features catalogued
- Full user journey mapped (crisis → published content)
- Tiered pricing model defined
- Technical architecture outlined
- Out-of-scope items identified

---

## Key Decisions Made

**Pirsig Card System = Kanban:**
- Six piles: INBOX → SHAPING → ACTIVE → SHIPPED (+ HOLD/KILL)
- Cards = atomic ideas extracted from transcripts
- Drag-and-drop workflow (Shape Up methodology)

**Four Editing Modes:**
1. TRANSCRIBE: Plain text (copy/paste ready)
2. CLEANUP: Spell check + dictionary
3. EDIT: Monaco + Vim + watercolor highlighting
4. POLISH: Grammar + Hemingway + readability

**Watercolor System (Five Colors):**
- 🔴 RED: Privacy danger (auto-flagged PII)
- 🟠 ORANGE: Privacy caution (user review)
- 🟡 YELLOW: Grammar/readability issues
- 🟢 GREEN: Verified safe content
- 🟣 PURPLE: Selected for card creation

**Right-Click Context Menu:**
- Create Card (text → INBOX pile)
- Add to Dictionary (spell check whitelist)
- Search Context (vector search similar ideas)
- Mark as Private/Public (toggle classification)

**Publishing Targets:**
- GitHub Pages (serverless blog)
- Medium (OAuth + auto-post)
- Twitter threads (auto-split 280 chars)
- LinkedIn (professional formatting)
- Newsletter (HTML export)
- Book manuscript (markdown)

---

## The Complete Pipeline

```
Voice Recording (3am crisis brain dump)
    ↓
Whisper Transcription (local, private)
    ↓
CLEANUP Mode (fix spelling, add to dictionary)
    ↓
PRIVACY Detection (flag PII, watercolor highlighting)
    ↓
EDIT Mode (Monaco + Vim, full writing environment)
    ↓
Card Creation (extract best ideas → Kanban INBOX)
    ↓
POLISH Mode (Hemingway analysis, readability scoring)
    ↓
Version Control (raw → cleaned → edited → polished → published)
    ↓
PUBLISH:
  - GitHub Pages (blog)
  - Medium (cross-post)
  - Twitter (thread)
  - LinkedIn (formatted)
  - Newsletter (HTML)
  - Book (markdown)
```

---

## Technical Stack Confirmed

**Frontend:**
- SwiftUI (macOS native UI)
- Monaco Editor (web view for editing)
- WebKit bridge (Swift ↔ JavaScript communication)

**Backend:**
- SQLite (local database - cards, versions, transcripts)
- Whisper.cpp (transcription engine)
- Hunspell (spell check, offline)
- textstat (Python service for Hemingway-style analysis)
- FastAPI (optional, for AI features later)

**Storage:**
- Audio: `~/brainphart/audio/YYYY-MM-DD/`
- Database: `~/brainphart/database.db`
- Models: `~/brainphart/models/`
- Backups: `~/brainphart/backups/`

**Publishing:**
- GitHub API (OAuth + repo push)
- Medium API (OAuth + post creation)
- Markdown templates (formatting engine)

---

## Database Schema Updates Required

**New tables needed:**

```sql
-- Cards (Pirsig system)
CREATE TABLE cards (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    source_transcript_id TEXT,
    pile TEXT DEFAULT 'INBOX',
    pile_position INTEGER,
    created_at INTEGER,
    tags TEXT,
    FOREIGN KEY (source_transcript_id) REFERENCES transcriptions(id)
);

-- Versions (version control)
CREATE TABLE versions (
    id TEXT PRIMARY KEY,
    transcription_id TEXT NOT NULL,
    version_type TEXT NOT NULL,  -- 'raw', 'cleaned', 'edited', 'polished', 'published'
    content TEXT NOT NULL,
    created_at INTEGER,
    notes TEXT,
    FOREIGN KEY (transcription_id) REFERENCES transcriptions(id)
);

-- Custom Dictionary (spell check)
CREATE TABLE dictionary (
    id TEXT PRIMARY KEY,
    word TEXT UNIQUE NOT NULL,
    added_at INTEGER,
    frequency INTEGER DEFAULT 1
);

-- Privacy Classifications (manual overrides)
CREATE TABLE privacy_overrides (
    id TEXT PRIMARY KEY,
    transcription_id TEXT NOT NULL,
    text_segment TEXT NOT NULL,
    classification TEXT NOT NULL,  -- 'private', 'public', 'review'
    created_at INTEGER,
    FOREIGN KEY (transcription_id) REFERENCES transcriptions(id)
);
```

---

## Tiered Pricing Model

**Tier 1: Basic (Free)**
- Voice recording + transcription
- Spell check + cleanup
- Markdown export
- Manual GitHub push

**Tier 2: Pro ($9/month)**
- Monaco editor + Vim mode
- Auto-publish (Medium, Twitter, LinkedIn)
- Code editing mode
- AI enhancement (LLM integration)
- Vector search (pgvector)

**Tier 3: Team ($29/month)**
- Collaborative editing
- Shared workspace (team cards)
- Real-time co-editing
- Admin permissions

**Tier 4: Enterprise (Custom)**
- Self-hosted deployment
- White-label branding
- Custom integrations
- Priority support

---

## What Makes This Different (Market Position)

**vs Otter.ai:**
- Local-first (no cloud, privacy guaranteed)
- Version control (never lose edits)
- Publishing engine (not just transcription)

**vs Notion:**
- Voice-first (not typing-first)
- Crisis-optimized (ADHD-friendly)
- Kanban cards (Pirsig system)

**vs Medium:**
- Voice → blog (not typing)
- Multi-platform (one source, many outputs)
- Privacy detection (auto-flag sensitive content)

**vs Obsidian:**
- Voice input (not markdown typing)
- Publishing built-in (not just notes)
- ADHD workflow (chaos → creativity)

---

## Features by Build Complexity

**Easy (1-2 days each):**
- Spell check integration (Hunspell)
- Custom dictionary (SQLite)
- Privacy regex patterns (already have code)
- Version control (database + UI)
- Markdown export (templating)

**Medium (3-5 days each):**
- Monaco editor integration (WebKit bridge)
- Watercolor highlighting (Monaco decorations)
- Card creation workflow (UI + database)
- Kanban board (drag-and-drop)
- GitHub API publishing (OAuth + push)

**Hard (1-2 weeks each):**
- textstat Python service (HTTP server + integration)
- Hemingway-style analysis (grammar algorithm)
- Medium API publishing (OAuth + formatting)
- Twitter thread generator (smart splitting)
- Vector search (pgvector + embeddings)

**Very Hard (3-4 weeks each):**
- Collaborative editing (WebSockets + CRDT)
- Real-time co-editing (conflict resolution)
- AI enhancement layer (LLM integration)
- Self-hosted deployment (Docker + setup)

---

## Out of Scope (Not Building)

❌ Mobile app (macOS only)  
❌ Cloud storage (local-first always)  
❌ Video recording (audio only)  
❌ Speech synthesis (text → voice)  
❌ Translation (English only initially)  
❌ Calendar integration (not a scheduling app)  
❌ Task management (not a to-do app)  
❌ Email client (not a communication tool)  

---

## Next Steps (Shaping Phase)

**What we need to decide:**
1. **Which features first?** (appetite allocation)
2. **What's the MVP?** (ship or kill)
3. **What's Phase 2.1 vs 2.2?** (split into sub-phases)
4. **What validates the vision?** (proof of concept)

**Shaping questions:**
- Can we ship editing without publishing? (Yes)
- Can we ship cards without vector search? (Yes)
- Can we ship cleanup without polish? (Yes)
- Can we ship Monaco without Vim? (No - Vim mode is core value)

**Betting table decisions needed:**
- Appetite: 2 weeks? 4 weeks? 6 weeks?
- Scope: All 38 features? Or narrow to 10-15?
- Risk: What could kill this project?
- Value: What delivers most user benefit fastest?

---

## The User We're Building For

**"Crisis User" Profile:**
- ADHD/anxiety/depression
- 3am brain dumps (can't sleep, racing thoughts)
- Privacy-conscious (won't use cloud tools)
- Wants to publish (has ideas worth sharing)
- Chaos → creativity pipeline needed
- Can't commit to daily journaling
- Voice = natural input (typing feels forced)

**Their workflow:**
1. Crisis moment → open app → hit record → talk for 10 minutes
2. Next day → transcribe → fix spelling → extract 3 cards
3. Later → drag cards to SHAPING → form pitch
4. Weekend → write full post → publish to blog
5. Auto-generate Twitter thread → cross-post to Medium
6. Repeat weekly

**What they value:**
- Never lose audio (crash-proof)
- Never lose edits (version control)
- Privacy guaranteed (local-first)
- Multi-platform reach (one source, many outputs)
- ADHD-friendly (distraction-free mode)

---

## Artifact Created

**brainphart-phase2-complete-spec**
- Full feature catalog (38 features)
- User journey mapped
- Technical architecture
- Tiered pricing
- Out-of-scope items
- Database schema

**Location:** Artifacts panel (available for reference)

---

## Files Status

**Created:**
- ✅ Artifact: brainphart-phase2-complete-spec
- ✅ Checkpoint: Checkpoint 33 - Phase 2 Complete Feature Spec.md

**Location:**
- Artifact: In Claude chat (persistent)
- Checkpoint: `/Users/kjd/01-Projects/IAC-001-a-BrainPh-art-Audio-Recorder/docs/`

---

## Token Usage

**This session:**
- Spec creation: ~15,000 tokens
- Artifact save: ~10,000 tokens
- Checkpoint: ~2,000 tokens
- Total: ~27,000 tokens

**Remaining:** 78,795 tokens (42% of budget)

**Good for:**
- Shaping discussion (~20K tokens)
- Technical deep-dive (~30K tokens)
- Build planning (~20K tokens)

---

## What's Next

**Immediate:**
- Review feature catalog
- Decide appetite (2/4/6 weeks?)
- Narrow scope to MVP features
- Start shaping individual features

**This week:**
- Shape editing modes (CLEANUP/EDIT/POLISH)
- Shape card system (Kanban + database)
- Shape publishing pipeline (GitHub/Medium)
- Betting table decision (ship/kill/reshape)

**This sprint:**
- Build Phase 2.1 MVP (editing + cards)
- Validate with real usage
- Ship or pivot

---

**END OF CHECKPOINT 33**

Status: Feature spec complete  
Artifact: Saved  
Checkpoint: Saved  
Tokens: Managed (42% remaining)  
Next: Shaping discussion

Balls: Still out.  
Meat: Still on table.  
Veg: Still showing.

Ready to shape this motherfucker. 🔥
