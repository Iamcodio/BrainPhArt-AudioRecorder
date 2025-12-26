# BrainPhArt Technical Document v2

**Project**: BrainPhArt - Voice-to-Text with AI Review
**Status**: Development (Alpha)
**Date**: 2024-12-26
**For**: CDesk Research Instance

---

## 1. ACHIEVEMENTS SUMMARY

### 1.1 Core Features Working

| Feature | Status | Notes |
|---------|--------|-------|
| Audio Recording | ✅ WORKING | AVAudioEngine, 32-second chunks |
| Whisper Transcription | ✅ WORKING | Local whisper.cpp, no cloud |
| SQLite Database | ✅ WORKING | Sessions, chunks, transcripts, versions |
| History Panel | ✅ WORKING | Left sidebar with recording list |
| Split Diff View | ✅ WORKING | Original vs Suggested comparison |
| Manual Editing | ✅ WORKING | In diff view right pane |
| Green Highlighting | ✅ WORKING | Shows changes vs original |
| Version Control | ✅ WORKING | Non-destructive saves (RAW + CLEANUP) |
| AI Review (Ollama) | ✅ WORKING | Local LLM for suggestions |
| Main Window Focus | ✅ WORKING | Regular NSWindow, not floating panel |

### 1.2 Recent Fixes Applied

1. **Window Focus Issue** - Changed from `FloatingPanel` (NSPanel) to regular `NSWindow`
2. **Destructive Save** - Now saves versions, never overwrites
3. **Diff View** - Split pane with red/green highlighting
4. **Manual Editing** - DiffEditableTextView allows typing in right pane

---

## 2. CRITICAL BUG: TEXT NOT DISPLAYING

### 2.1 Problem Description

When switching to **EDIT tab** or enabling **Spell Check mode**, the text view appears blank/empty even though:
- The transcript exists in database
- The `@Binding var text: String` contains data
- Other views (read-only Text) show the transcript fine

### 2.2 Affected Components

```
┌─────────────────────────────────────────────────────────────┐
│                    BUG LOCATIONS                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. EDIT Tab                                                │
│     └── EditorModule.swift → EditTabView                    │
│         └── InlineSpellTextView (NSViewRepresentable)       │
│             └── SpellCheckTextView (NSTextView subclass)    │
│                                                             │
│  2. Spell Check Mode (DICTATE Tab)                          │
│     └── DictateModule.swift → SimpleSpellCheckEditor        │
│         └── NSTextView (plain)                              │
│                                                             │
│  BOTH use NSTextView wrapped in NSViewRepresentable         │
│  BOTH have the same symptom: text.string = "" on appear     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Suspected Root Cause

**NSViewRepresentable Lifecycle Issue**

```
SwiftUI View Appears
       │
       ▼
makeNSView() called ─────► textView.string = text ◄── text may be ""
       │                                               at this moment
       ▼
updateNSView() called ───► checks textView.string != text
       │                   BUT if both are "", no update happens
       ▼
Text binding updates later ───► SwiftUI doesn't call updateNSView
       │                        because it thinks view is current
       ▼
Result: BLANK TEXT VIEW
```

### 2.4 Code Path Analysis

**InlineSpellTextView.swift:46-51**
```swift
// Set initial text
textView.string = text  // <-- What if text is "" here?

// Apple's spell check runs automatically when enabled
return scrollView
```

**InlineSpellTextView.swift:61-70**
```swift
// Only update text if it changed externally
if textView.string != text && !context.coordinator.isEditing {
    let selectedRange = textView.selectedRange()
    textView.string = text  // <-- Never called if both are ""
    textView.setSelectedRange(selectedRange)
}
```

### 2.5 Potential Fixes to Research

1. **Force text sync in onAppear**
   - Add `.onAppear { }` modifier to force binding read

2. **Use @State instead of @Binding**
   - Copy text to local state, sync back on change

3. **Add ID modifier to force view recreation**
   - `.id(text.hashValue)` to recreate when text changes

4. **Delay text assignment**
   - Use `DispatchQueue.main.async` in makeNSView

5. **Check parent view hierarchy**
   - Is the binding being passed correctly from ContentView?

---

## 3. ARCHITECTURE OVERVIEW

### 3.1 App Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                      BrainPhArtApp.swift                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Main Entry Point                                        │   │
│  │  - Creates FloatingPanel (dictation pill)                │   │
│  │  - Creates NSWindow (main editor)                        │   │
│  │  - Manages WindowMode (micro/medium/full)                │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ContentView.swift                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Main View Coordinator                                   │   │
│  │  - TabView with DICTATE / EDIT / CARDS tabs              │   │
│  │  - Manages @State for recordings, selectedRecording      │   │
│  │  - Loads data from DatabaseManager                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  DictateModule   │ │  EditorModule    │ │  CardsModule     │
│  ─────────────── │ │  ─────────────── │ │  ─────────────── │
│  - Audio record  │ │  - Full editor   │ │  - Kanban cards  │
│  - History panel │ │  - Spell check   │ │  - (Future)      │
│  - Diff view     │ │  - Readability   │ │                  │
│  - AI Review     │ │                  │ │                  │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

### 3.2 Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   RECORD    │────▶│   WHISPER   │────▶│   SQLITE    │
│  32s chunks │     │  Transcribe │     │   Store     │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    SAVE     │◀────│    EDIT     │◀────│   DISPLAY   │
│  Version N  │     │  Diff/Spell │     │  History    │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 3.3 Key Files

| File | Purpose |
|------|---------|
| `BrainPhArtApp.swift` | App entry, window management |
| `ContentView.swift` | Tab coordination, state management |
| `DictateModule.swift` | DICTATE tab, recording, diff view |
| `EditorModule.swift` | EDIT tab, full editor |
| `TranscriptComparisonView.swift` | Split diff view with highlighting |
| `InlineSpellTextView.swift` | NSTextView wrapper with spell check |
| `DatabaseManager.swift` | SQLite operations |
| `AudioRecorder.swift` | AVAudioEngine recording |
| `TranscriptionManager.swift` | Whisper integration |
| `TranscriptionWorker.swift` | Background transcription processing |

---

## 4. USER FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER FLOW                                │
└─────────────────────────────────────────────────────────────────┘

     ┌──────────┐
     │  START   │
     └────┬─────┘
          │
          ▼
     ┌──────────┐       ┌──────────────────────────────────────┐
     │ DICTATE  │       │  User sees:                          │
     │   TAB    │       │  - History panel (left)              │
     └────┬─────┘       │  - Transcript view (center)          │
          │             │  - Record controls (bottom)          │
          │             └──────────────────────────────────────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
┌───────┐  ┌────────┐
│  REC  │  │ SELECT │
│ Button│  │Recording│
└───┬───┘  └────┬───┘
    │           │
    ▼           ▼
┌───────────┐  ┌────────────────┐
│ Recording │  │ View Transcript │
│ 32s chunks│  │ (read-only)     │
└─────┬─────┘  └────────┬───────┘
      │                 │
      ▼                 │
┌───────────┐           │
│ Whisper   │           │
│ Transcribe│           │
└─────┬─────┘           │
      │                 │
      ▼                 │
┌───────────┐           │
│ DB Save   │◀──────────┘
└─────┬─────┘
      │
      │     ┌─────────────────────────┐
      │     │  User clicks buttons:   │
      │     │                         │
      │     │  [Spell] → Toggle spell │──────┐
      │     │            check mode   │      │
      │     │                         │      ▼
      │     │  [AI Review] → Show     │  ┌──────────────┐
      │     │               diff view │  │ Spell Check  │
      │     └───────────┬─────────────┘  │ Mode         │
      │                 │                │ (BROKEN)     │
      │                 ▼                └──────────────┘
      │         ┌───────────────┐
      │         │  DIFF VIEW    │
      │         │ ┌───────┬────┐│
      │         │ │ORIG   │SUGG││
      │         │ │(red)  │(grn)│
      │         │ └───────┴────┘│
      │         │ [Suggest]     │
      │         │ [Save Changes]│
      │         └───────┬───────┘
      │                 │
      │                 ▼
      │         ┌───────────────┐
      │         │ Save Version  │
      │         │ RAW + CLEANUP │
      │         └───────────────┘
      │
      │
      ▼
┌───────────┐       ┌──────────────────────────────────────┐
│   EDIT    │       │  User sees:                          │
│   TAB     │       │  - Full editor (BROKEN - blank)      │
│ (BROKEN)  │       │  - Readability sidebar               │
└───────────┘       └──────────────────────────────────────┘
```

---

## 5. DATABASE SCHEMA

```sql
-- Recording sessions
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    created_at INTEGER,
    completed_at INTEGER,
    status TEXT,
    chunk_count INTEGER
);

-- Audio chunks (32-second files)
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    chunk_num INTEGER,
    file_path TEXT,
    duration_ms INTEGER,
    transcription_status TEXT
);

-- Transcripts per chunk
CREATE TABLE chunk_transcripts (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    chunk_number INTEGER,
    transcript TEXT,
    created_at INTEGER
);

-- Version history (non-destructive saves)
CREATE TABLE transcript_versions (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    version_num INTEGER,
    version_type TEXT,  -- 'raw', 'edited', 'cleanup'
    content TEXT,
    created_at INTEGER
);

-- Custom dictionary (for spell check)
CREATE TABLE custom_dictionary (
    id TEXT PRIMARY KEY,
    word TEXT UNIQUE,
    added_at INTEGER
);

-- Standard dictionary (~383k words)
CREATE TABLE dictionary_words (
    word TEXT PRIMARY KEY,
    frequency INTEGER
);
```

---

## 6. RESEARCH TASKS FOR CDESK

### Priority 1: Fix Text Display Bug

1. **Trace the binding flow**
   - From ContentView → DictateTabView → editedTranscript binding
   - From ContentView → EditTabView → text binding
   - Confirm binding has data when views appear

2. **Test NSViewRepresentable lifecycle**
   - Add print statements to makeNSView and updateNSView
   - Check when `text` binding has value vs when it's empty

3. **Compare with working view**
   - `DiffEditableTextView` in TranscriptComparisonView.swift WORKS
   - What's different about its implementation?

### Priority 2: Understand SwiftUI/AppKit Bridge

1. **Research NSViewRepresentable best practices**
   - Correct way to handle @Binding with NSTextView
   - When updateNSView is called vs when it's not

2. **Look for similar issues**
   - SwiftUI forums, Stack Overflow
   - Apple Developer documentation

### Priority 3: Alternative Approaches

1. **Could we use TextEditor (pure SwiftUI)?**
   - Does it support spell check?
   - Limitations?

2. **Could we use a different NSTextView wrapper pattern?**
   - Observable object instead of binding?
   - Combine publishers?

---

## 7. PIVOT LOG

### Custom Spell Check → Apple Spell Check

**Date**: 2024-12-26

**Previous Approach**:
- Built custom `SpellEngine` actor
- Imported SCOWL dictionary (~383k words) into SQLite
- Levenshtein distance for suggestions
- Manual async word checking

**Why Abandoned**:
- Async tasks weren't running reliably
- Debug output not visible
- Complex actor isolation issues
- Too many moving parts

**New Approach**:
- Use Apple's built-in `isContinuousSpellCheckingEnabled`
- Red wavy underlines automatic
- Right-click for suggestions
- BUT: Only works on editable NSTextView

**Status**: Apple spell check enabled but text not displaying (same bug)

---

## 8. FILE LOCATIONS

```
/Users/kjd/01-projects/IAC-001-a-BrainPh-art-Audio-Recorder/
├── Sources/BrainPhArt/
│   ├── BrainPhArtApp.swift          # App entry
│   ├── ContentView.swift            # Main coordinator
│   ├── DictateModule.swift          # DICTATE tab
│   ├── EditorModule.swift           # EDIT tab (BROKEN)
│   ├── TranscriptComparisonView.swift # Diff view (WORKING)
│   ├── InlineSpellTextView.swift    # Spell check editor (BROKEN)
│   ├── DatabaseManager.swift        # SQLite
│   ├── AudioRecorder.swift          # Recording
│   ├── TranscriptionManager.swift   # Whisper
│   ├── TranscriptionWorker.swift    # Background processing
│   └── SpellEngine.swift            # Custom spell (ABANDONED)
├── Package.swift
├── CLAUDE.md                        # Project instructions
└── collab.md                        # Previous collab notes
```

---

## 9. BUILD & RUN

```bash
# Build
swift build

# Run
.build/debug/BrainPhArt

# Kill running instances
pkill -f BrainPhArt
```

---

**END OF DOCUMENT**

*Next session: CDesk to research NSViewRepresentable binding issue*
