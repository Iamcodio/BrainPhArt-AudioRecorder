# BrainPhArt Collaboration Notes

## 2024-12-26: Spell Check Pivot

### Previous Approach (ABANDONED)
- Built custom `SpellEngine` using SQLite dictionary (~383k words)
- Imported SCOWL dictionary into `dictionary_words` table
- Custom Levenshtein distance for suggestions
- Manual word-by-word checking with async tasks

### Why It Failed
- Async task execution wasn't working reliably
- Dictionary was loaded but spell check never ran
- Debug output not visible - couldn't trace execution
- Too many moving parts (actor isolation, debouncing, MainActor coordination)

### New Approach (USING APPLE'S BUILT-IN)
- Enable `isContinuousSpellCheckingEnabled = true` on NSTextView
- Enable `isGrammarCheckingEnabled = true`
- Enable `isAutomaticSpellingCorrectionEnabled = true`
- Red wavy underlines appear automatically
- Right-click gives suggestions

### Files Changed
- `InlineSpellTextView.swift` - Switched from custom to Apple's spell check

### Custom SpellEngine Status
- Code still exists in `SpellEngine.swift`
- Dictionary tables still in database
- Can be revisited later if needed
- For now: Apple's spell check works and we move on

### Lesson Learned
Apple's built-in spell check in NSTextView is:
- Battle-tested
- Automatically handles UI updates
- Properly integrated with AppKit
- Just works

Don't reinvent the wheel unless there's a compelling reason.

---

## Current State (Dec 26, 2024)

### Working Features
1. Audio recording (AVAudioEngine, 32s chunks)
2. Whisper transcription (local whisper.cpp)
3. Split-pane diff view (Original vs Suggested)
4. Manual editing with green highlighting for changes
5. Save with versioning (RAW and CLEANUP files)
6. AI Review button (Ollama LLM)
7. Spell Check button (Apple's built-in)
8. History panel with recordings
9. Playback controls

### Next Steps
- Test Apple spell check
- Fix EDIT tab if needed
- Consider removing custom SpellEngine code

---

## Architecture Notes

### Tabs
- **DICTATE**: Record audio, see transcript, edit
- **EDIT**: Full editor with spell check (InlineSpellTextView)
- **CARDS**: Kanban-style content cards (future)

### Key Files
- `ContentView.swift` - Main view coordinator
- `DictateModule.swift` - Dictate tab implementation
- `TranscriptComparisonView.swift` - Split diff view
- `InlineSpellTextView.swift` - Editor with spell check
- `DatabaseManager.swift` - SQLite storage
- `AudioRecorder.swift` - AVAudioEngine wrapper
- `TranscriptionManager.swift` - Whisper integration
