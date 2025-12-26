# Checkpoint 34: Terminal-First Pivot

**Date:** 2025-12-26 01:45 GMT  
**Sprint:** Week 2, Day 4  
**Project:** brainph.art - Architecture Pivot  
**Status:** Vision clarified, stack redefined

---

## What Changed

**From:** macOS GUI app with Monaco editor  
**To:** Terminal CLI tool (Vim + Rust + SQLite)

**Why:**
- Lightweight (runs on Raspberry Pi)
- Universal (Linux, macOS, works over SSH)
- No dependencies (Vim pre-installed)
- Rock-solid (no update hell)
- No GUI bloat (terminal-only)

---

## The Real User

**Avatar:**
- Person in mental health crisis
- ADHD, homeless, emergency accommodation
- Has: TV, Raspberry Pi ($35), USB mic ($10)
- Needs: Voice dump → organized content → published
- Budget: One-time hardware cost, zero recurring
- Skills: Can learn terminal basics (motivated)

**NOT:**
- Mac user with $9/month
- Professional writer
- Tech enthusiast with latest gear

**Core need:**
- 3am brain dump (voice, not typing)
- Never lose thoughts (crash-proof)
- Privacy guaranteed (local-first)
- Publish content (prove they're not broken)

---

## Stack Redefined

**Phase 1 (Current):**
- Platform: macOS
- Language: Swift
- UI: SwiftUI
- Status: Prototype complete

**Phase 2 (Rebuild):**
- Platform: Linux-first (Raspberry Pi)
- Language: Rust (single binary)
- UI: Terminal + Vim
- Database: SQLite (local)
- Transcription: Whisper.cpp

**Why Rust:**
- Cross-platform (Pi ARM, Linux x86, macOS)
- Single binary (no runtime)
- Fast compilation
- Memory safe
- Great CLI libraries

**Why Vim:**
- Pre-installed everywhere
- Lightweight (< 1MB)
- Modal editing (fast)
- Scriptable (card extraction)
- Never changes (stable)
- No dependencies

**Why Terminal:**
- SSH-able (remote access)
- Lightweight (runs on Pi Zero)
- No GUI overhead
- Universal interface
- Works in any environment

---

## User Journey (Real Problems)

### Scenario 1: Crisis Recording

**3am, can't sleep, racing thoughts:**
1. SSH into Raspberry Pi (or local terminal)
2. Run: `brainphart record`
3. Talk for 10 minutes (stream of consciousness)
4. Hit Ctrl+C or `brainphart stop`
5. Audio saved in 32-second chunks
6. App crashes? Chunks are safe
7. Go to sleep

**Next day:**
1. Run: `brainphart list`
2. See yesterday's recording
3. Run: `brainphart transcribe session-abc123`
4. Whisper processes (2-3 minutes on Pi 4)
5. Transcript saved

**What works:**
- Voice = natural during crisis
- Chunked saving = never lose audio
- Transcription happens later (when calm)

**What's missing:**
- Can't edit transcript yet (Phase 2)
- Can't publish anywhere (Phase 3)

---

### Scenario 2: Editing & Privacy

**Processing the brain dump:**
1. Run: `brainphart edit session-abc123`
2. Transcript opens in Vim
3. Privacy patterns highlighted:
   - Red background = SSN, credit card (danger)
   - Yellow background = Email, phone (caution)
4. Spell check enabled (`:set spell`)
5. User fixes obvious errors
6. Selects good idea (visual mode)
7. Runs: `:BrainphartCard`
8. Text saved as card in INBOX pile
9. Save & exit (`:wq`)
10. Version saved to database

**What we need:**
- Vim syntax file (privacy highlighting)
- Custom Vim command (card creation)
- Version control (edit history)

---

### Scenario 3: Card Organization

**Building content from ideas:**
1. Run: `brainphart cards list --pile INBOX`
2. ASCII table shows all cards
3. User sees 5 related ideas
4. Run: `brainphart cards move <id> SHAPING`
5. Repeat for related cards
6. Run: `brainphart cards show --pile SHAPING`
7. See grouped cards
8. Run: `brainphart cards merge <id1> <id2> --output draft.md`
9. Merged content opens in Vim
10. User writes connecting tissue
11. Blog post draft ready

**What we need:**
- Card storage (SQLite)
- Pile system (6 piles: INBOX/SHAPING/ACTIVE/SHIPPED/HOLD/KILL)
- ASCII Kanban view
- Card merging

---

## Technical Architecture

### CLI Structure

```bash
brainphart record                    # Start recording
brainphart stop                      # Stop and save
brainphart list                      # Show sessions
brainphart play <session-id>         # Play audio
brainphart edit <session-id>         # Open in Vim
brainphart transcribe <session-id>   # Force transcription
brainphart cards list                # Show all cards
brainphart cards move <id> SHAPING   # Change pile
brainphart publish <file> --github   # Publish to blog
```

### File Structure

```
~/brainphart/
├── audio/
│   └── YYYY-MM-DD/
│       └── session-{uuid}-chunk-{n}.wav
├── transcripts/
│   └── session-{uuid}.md
├── database.db
├── config.toml
└── models/
    └── ggml-base.bin  # Whisper model
```

### Database Schema

```sql
-- Sessions (recordings)
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    status TEXT NOT NULL
);

-- Chunks (audio files)
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    chunk_num INTEGER NOT NULL,
    file_path TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- Transcriptions
CREATE TABLE transcriptions (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    raw_text TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- Versions (edit history)
CREATE TABLE versions (
    id TEXT PRIMARY KEY,
    transcription_id TEXT NOT NULL,
    version_num INTEGER NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (transcription_id) REFERENCES transcriptions(id)
);

-- Cards (Pirsig system)
CREATE TABLE cards (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    source_session_id TEXT,
    pile TEXT NOT NULL DEFAULT 'INBOX',
    created_at INTEGER NOT NULL,
    tags TEXT,  -- JSON array
    FOREIGN KEY (source_session_id) REFERENCES sessions(id)
);
```

---

## Vim Integration

### Syntax Highlighting (Privacy)

**Custom Vim syntax file:** `~/.vim/syntax/brainphart.vim`

```vim
" Danger patterns (red background)
syntax match BrainphartDanger /\d\{3\}-\d\{2\}-\d\{4\}/  " SSN
syntax match BrainphartDanger /\d\{4}[\s-]\?\d\{4}[\s-]\?\d\{4}[\s-]\?\d\{4\}/  " Credit card

" Caution patterns (yellow background)
syntax match BrainphartCaution /\w\+@\w\+\.\w\+/  " Email
syntax match BrainphartCaution /(\d\{3\})\s*\d\{3\}-\d\{4\}/  " Phone

highlight BrainphartDanger ctermbg=red ctermfg=white
highlight BrainphartCaution ctermbg=yellow ctermfg=black
```

### Card Creation Command

**Add to `~/.vimrc`:**

```vim
command! -range BrainphartCard :<line1>,<line2>w !brainphart cards create --from-stdin
```

**User workflow:**
1. Select text (visual mode: `V`)
2. Run: `:BrainphartCard`
3. Text piped to CLI
4. Card saved to INBOX

---

## Key Decisions

### What We're Building

**Phase 2 (Editing):**
- Rust CLI binary (`brainphart`)
- Vim integration (syntax + commands)
- Privacy detection (regex patterns)
- Card extraction (select → save)
- Version control (edit history)

**Phase 3 (Publishing):**
- GitHub Pages integration
- Medium API
- Twitter thread generator
- Markdown templates

### What We're NOT Building

❌ GUI (explicitly avoiding)  
❌ Web app (no browser needed)  
❌ Mobile app (terminal only)  
❌ Cloud sync (local-first)  
❌ SaaS product (open source)  

---

## Problems We'll Face

### Technical Challenges

**Whisper on Raspberry Pi:**
- Problem: Slow transcription (5+ min on Pi Zero)
- Solution: Use tiny model, or Pi 4+ only
- Reality: Acceptable for use case (not real-time)

**Cross-platform audio:**
- Problem: ALSA vs PulseAudio
- Solution: Detect system, use appropriate
- Fallback: Manual config

**Vim setup:**
- Problem: Users need to install syntax file
- Solution: `brainphart setup vim` command
- Reality: One-time setup

### UX Challenges

**Terminal learning curve:**
- Problem: Non-technical users
- Reality: Motivated users (crisis survivors)
- Solution: Good docs, examples

**Vim learning curve:**
- Problem: Vim is hard
- Reality: Just need basic (`i`, `Esc`, `:wq`)
- Solution: Cheat sheet

**Privacy false positives:**
- Problem: Might flag non-sensitive content
- Solution: User can override
- Reality: Better safe than sorry

---

## Validation Questions

### What Works

✅ Terminal-first (lightweight, SSH-able)  
✅ Vim integration (pre-installed, fast)  
✅ Chunked saving (proven in Phase 1)  
✅ Privacy-first (local database)  
✅ Voice-to-text (Whisper is mature)  

### What Needs Testing

❓ Card system in terminal (ASCII Kanban usable?)  
❓ Publishing automation (OAuth in terminal?)  
❓ Raspberry Pi performance (transcription speed?)  
❓ Vim syntax highlighting (clear enough?)  

### What Might Be Wrong

⚠️ Terminal-only might limit users  
⚠️ Vim requirement might scare people  
⚠️ Publishing setup might be complex  

**Reality:** Start simple, iterate based on actual use.

---

## What Success Looks Like

**Someone in crisis:**
- Uses it daily (3am brain dumps)
- Never loses thoughts (crash-proof)
- Organizes ideas (cards system)
- Publishes content (blog posts)
- Feels proud (shared their story)

**Technical success:**
- Works reliably for years
- No dependency hell
- Maintainable solo
- Clean codebase
- Open source

---

## Next Decisions Needed

**1. Start Rust rewrite now?**
- Option A: Finish Swift Phase 1, then rewrite
- Option B: Start Rust now, port Phase 1 features

**2. Build editing or cards first?**
- Option A: Editing (immediate value)
- Option B: Cards (unique differentiator)

**3. Raspberry Pi target?**
- Option A: Pi 4+ only (faster transcription)
- Option B: Support Pi Zero (slower but works)

**4. GitHub integration?**
- Option A: Use `gh` CLI (simpler)
- Option B: Direct API (more control)

**5. TUI or pure CLI?**
- Option A: Pure CLI (simplest)
- Option B: TUI with `ratatui` (nicer UX)

---

## Files Status

**Created:**
- ✅ Artifact updated: brainphart-phase2-complete-spec (terminal-first)
- ✅ Checkpoint: Checkpoint 34 - Terminal-First Pivot.md

**Discovered:**
- Freewrite app (`/Users/kjd/Library/Containers/app.humansongs.freewrite/`)
- Validates: Timer-based sessions, stream of consciousness, AI reflection

**Location:**
- Checkpoint: `~/01-Projects/IAC-001-a-BrainPh-art-Audio-Recorder/docs/`

---

## Token Usage

**Session total:** ~125K / 190K (66% used)  
**Remaining:** 65K (34% of budget)

**Good for:**
- Technical deep-dive (~30K)
- Build planning (~20K)
- Architecture decisions (~15K)

---

**END OF CHECKPOINT 34**

Status: Vision pivoted to terminal-first  
Architecture: Rust + Vim + SQLite  
Target: Raspberry Pi (crisis survivors)  
Philosophy: No GUI, no dependencies, no bullshit

Next: Decide build order, start Rust rewrite or finish Swift?
