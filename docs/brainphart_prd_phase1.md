# BrainPhArt - Phase 1 Product Requirements
**For:** CC (Claude Code) - Implementation  
**From:** QA/Product Manager  
**Date:** 2025-12-25 19:35 UTC  
**Deadline:** 20:20 UTC (45 minutes)

---

## CURRENT UX STRUCTURE (DO NOT CHANGE)

```
┌─────────────────────────────────────────────────────────┐
│  [Settings] [Folder] [Help]                            │ ← Top Bar
├──────────────┬──────────────────────────────────────────┤
│              │                                          │
│   HISTORY    │            CANVAS                        │
│   (Left      │            (Right Panel)                 │
│    Panel)    │                                          │
│              │                                          │
│  - Recording │   [Transcript text here]                 │
│    Cards     │   [Editable]                             │
│              │                                          │
├──────────────┴──────────────────────────────────────────┤
│                    RECORDER MODULE                      │ ← Bottom
│   [●REC] [00:00] [■STOP] [Waveform] [Playback]        │
└─────────────────────────────────────────────────────────┘
```

**Existing panels (keep as-is):**
- Top bar with 3 buttons
- History panel (left)
- Canvas panel (right)

**What's missing:** RECORDER module at bottom (or dockable)

---

## PHASE 1.1: RECORDER MODULE (15 minutes)

### Requirements

**Module must be STANDALONE:**
- Can exist without history/canvas
- Has its own state management
- Communicates only via database
- No direct coupling to other modules

### UI Elements Required

```
┌────────────────────────────────────────────────────────┐
│  [●REC]  [00:00]  [■STOP]  [✖CANCEL]  ████████▌       │
│   ↑       ↑         ↑         ↑         ↑              │
│  Record  Timer     Stop     Cancel   Waveform          │
└────────────────────────────────────────────────────────┘
```

**Button States:**

**IDLE:**
- REC: Red, enabled
- STOP: Gray, disabled
- CANCEL: Hidden
- Timer: 00:00 (gray)
- Waveform: Flat (gray)

**RECORDING:**
- REC: Gray, disabled
- STOP: Red, enabled
- CANCEL: Red, enabled
- Timer: Counting (red) 00:01, 00:02, 00:03...
- Waveform: Animated (red)

**STOPPED:**
- REC: Red, enabled
- STOP: Gray, disabled
- CANCEL: Hidden
- Timer: Final time (green)
- Waveform: Flat (gray)

### Data Flow

```
User clicks REC
    ↓
Create session in database (status='recording')
    ↓
Start audio capture
    ↓
Timer updates every 1 second
    ↓
Waveform updates from audio level
    ↓
Every 32 seconds: Save chunk to database
    ↓
User clicks STOP
    ↓
Save final chunk
    ↓
Mark session complete (status='complete')
    ↓
Display final time for 3 seconds
    ↓
Reset to IDLE
```

**CANCEL flow:**
```
User clicks CANCEL
    ↓
Stop audio immediately
    ↓
Mark session cancelled (status='cancelled')
    ↓
Do NOT delete chunks (black box - keep everything)
    ↓
Reset to IDLE
```

### Acceptance Criteria

- [ ] REC button visible and clickable
- [ ] Timer starts counting at 00:01 when REC pressed
- [ ] Timer displays MM:SS format
- [ ] STOP button becomes active when recording
- [ ] CANCEL button visible during recording
- [ ] Waveform shows visual feedback (bars moving)
- [ ] Clicking STOP saves and shows final time
- [ ] Clicking CANCEL stops without error
- [ ] Module can be placed anywhere in UI
- [ ] No errors in console

**Time box:** 15 minutes

---

## PHASE 1.2: PLAYBACK CONTROLS (15 minutes)

### Requirements

**Playback must handle multi-chunk recordings:**
- Load ALL chunks for a session
- Play them sequentially OR stitch together
- Controls work regardless of chunk count

### UI Elements Required

```
┌────────────────────────────────────────────────────────┐
│  ▶PLAY  ⏸PAUSE  ■STOP  [─────●────] 01:23/03:45       │
│   ↑      ↑       ↑      ↑            ↑                 │
│  Play   Pause   Stop  Scrubber   Current/Total         │
│                                                         │
│  ⏪ <<15s  ⏩ 15s>>  [0.5x] [1.0x] [1.5x] [2.0x]       │
│     ↑       ↑          ↑                                │
│   Back    Forward   Speed Controls                     │
└────────────────────────────────────────────────────────┘
```

**Button States:**

**READY (audio loaded):**
- PLAY: Blue, enabled
- PAUSE: Gray, disabled
- STOP: Gray, disabled
- Scrubber: At 0:00
- Speed: 1.0x selected

**PLAYING:**
- PLAY: Gray, disabled
- PAUSE: Blue, enabled
- STOP: Red, enabled
- Scrubber: Moving
- Time updates: 00:01, 00:02, 00:03...

**PAUSED:**
- PLAY: Blue, enabled (resume)
- PAUSE: Gray, disabled
- STOP: Red, enabled
- Scrubber: Stopped at current position
- Time: Frozen

### Data Flow

```
User selects recording from history
    ↓
Load all chunks for session from database
    ↓
Calculate total duration
    ↓
Display playback controls
    ↓
User clicks PLAY
    ↓
Play chunks sequentially (chunk_0, chunk_1, chunk_2...)
    ↓
Update scrubber position
    ↓
Update time display (current/total)
    ↓
User drags scrubber
    ↓
Calculate which chunk + offset
    ↓
Jump to that position
    ↓
Continue playing
```

**Speed control:**
```
User selects 1.5x
    ↓
Set AVAudioPlayer rate = 1.5
    ↓
Audio plays faster
    ↓
Time display adjusts
```

### Acceptance Criteria

- [ ] PLAY button starts playback
- [ ] Audio plays through ALL chunks (not just first 32s)
- [ ] PAUSE button freezes playback
- [ ] STOP button returns to start
- [ ] Scrubber draggable to any position
- [ ] Time shows current/total (e.g., 01:23/03:45)
- [ ] <<15s jumps back 15 seconds
- [ ] 15s>> jumps forward 15 seconds
- [ ] Speed buttons change playback rate (0.5x to 2.0x)
- [ ] Current speed highlighted
- [ ] Playback continues after scrubbing
- [ ] No gaps/clicks between chunks

**Time box:** 15 minutes

---

## PHASE 1.3: SETTINGS PANEL (15 minutes)

### Requirements

**Settings button (top bar) opens modal:**
- Microphone selection
- Audio level test
- Sample rate selection
- Save location display
- Model location display

### UI Elements Required

```
┌─────────────────────────────────────┐
│          SETTINGS                   │
├─────────────────────────────────────┤
│                                     │
│  INPUT DEVICE:                      │
│  [▼ Built-in Microphone        ]   │
│     - USB Microphone               │
│     - External Interface           │
│                                     │
│  TEST AUDIO:                        │
│  [Test] ████████░░ (75%)           │
│                                     │
│  QUALITY:                           │
│  ○ 16kHz (Whisper optimized)       │
│  ● 48kHz (High quality) ✓          │
│                                     │
│  LOCATIONS:                         │
│  Audio: ~/brainphart/audio/        │
│  Model: ~/brainphart/models/       │
│                                     │
│         [Save] [Cancel]             │
└─────────────────────────────────────┘
```

### Data Flow

```
User clicks Settings button (top bar)
    ↓
Open modal dialog
    ↓
List available microphones from system
    ↓
Show current selection
    ↓
User clicks Test button
    ↓
Capture 2 seconds of audio
    ↓
Show level meter
    ↓
Play back audio (confirm it works)
    ↓
User selects sample rate
    ↓
Update in memory (not saved yet)
    ↓
User clicks Save
    ↓
Store preferences in database
    ↓
Close modal
```

### Acceptance Criteria

- [ ] Settings button (gear icon) in top bar
- [ ] Clicking opens modal dialog
- [ ] Dropdown lists ALL available microphones
- [ ] Current selection is pre-selected
- [ ] Test button captures and plays back audio
- [ ] Level meter shows real-time audio level
- [ ] Sample rate selection available (16kHz/48kHz)
- [ ] Current selection indicated with checkmark
- [ ] Audio/Model locations displayed (read-only)
- [ ] Save button stores preferences
- [ ] Cancel button closes without saving
- [ ] Settings persist between app restarts
- [ ] Microphone change takes effect immediately

**Time box:** 15 minutes

---

## MODULE BOUNDARIES

### Recorder Module
**Responsibilities:**
- Record audio
- Display timer
- Display waveform
- Save chunks to database
- Handle cancel

**Does NOT:**
- Know about history panel
- Know about canvas panel
- Know about transcription
- Know about playback

**Interface:**
```
Input: User clicks REC/STOP/CANCEL
Output: Database entries (sessions, chunks)
```

### Playback Module
**Responsibilities:**
- Load chunks from database
- Play audio sequentially
- Handle scrubbing
- Handle speed control
- Display time/position

**Does NOT:**
- Know about recording
- Know about transcription
- Modify database (read-only)

**Interface:**
```
Input: Session ID from history click
Output: Audio playback to speakers
```

### Settings Module
**Responsibilities:**
- List audio devices
- Test audio
- Save preferences
- Display locations

**Does NOT:**
- Know about recording state
- Know about playback state
- Modify audio files

**Interface:**
```
Input: User opens settings
Output: Preferences saved to database
```

---

## TECHNICAL CONSTRAINTS

### Must Use:
- Existing database schema (sessions, chunks tables)
- Existing file structure (~/brainphart/audio/)
- Existing UX layout (2-panel + recorder)
- SwiftUI for all UI
- AVFoundation for audio

### Must NOT:
- Create new database tables (use existing)
- Change file locations
- Break existing history panel
- Break existing canvas panel
- Add dependencies

### Performance:
- Timer updates: 1 second interval (not faster)
- Waveform updates: 10 FPS max (not 60 FPS)
- Playback: Smooth, no gaps between chunks
- Scrubbing: <100ms response time

---

## TESTING PROTOCOL

### Phase 1.1 Test (Recorder):
1. Launch app
2. Click REC
3. Verify timer starts: 00:01, 00:02, 00:03
4. Verify waveform animates
5. Wait 35 seconds
6. Click STOP
7. Verify timer shows final time (00:35)
8. Check database: 2 chunks saved
9. Click REC again
10. Click CANCEL immediately
11. Verify recording stops
12. Check database: Session marked cancelled

### Phase 1.2 Test (Playback):
1. Select 2-minute recording from history
2. Click PLAY
3. Listen for full 2 minutes (not just 32 seconds)
4. Click PAUSE at 1:00
5. Verify time shows 01:00/02:00
6. Drag scrubber to 1:30
7. Click PLAY
8. Verify resumes from 1:30
9. Click 1.5x speed
10. Verify audio plays faster
11. Click <<15s
12. Verify jumps back 15 seconds
13. Click STOP
14. Verify returns to 00:00

### Phase 1.3 Test (Settings):
1. Click Settings (gear icon)
2. Verify modal opens
3. Change microphone to USB device
4. Click Test
5. Verify level meter moves
6. Verify playback works
7. Select 16kHz quality
8. Click Save
9. Close and reopen app
10. Open Settings again
11. Verify USB mic still selected
12. Verify 16kHz still selected

---

## DELIVERABLES

CC must provide for each phase:

1. **Code files** (committed to repo)
2. **Screenshot** of working feature
3. **Console output** showing no errors
4. **Test results** (pass/fail for each acceptance criteria)

---

## TIME ALLOCATION

- Phase 1.1: 15 minutes (Recorder)
- Phase 1.2: 15 minutes (Playback)
- Phase 1.3: 15 minutes (Settings)
- **Total: 45 minutes**
- **Deadline: 20:20 UTC**

---

## SUCCESS CRITERIA

**Phase 1 complete when:**
- User can record with visible timer
- User can play back full recording with controls
- User can configure microphone in settings
- All acceptance criteria pass
- No console errors
- App doesn't crash

---

**END OF PRD**

CC: Build Phase 1.1 first. Report when done. Do not proceed to 1.2 until 1.1 approved.