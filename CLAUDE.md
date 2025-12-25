# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the app
swift build

# Run the app
swift run

# Clean build artifacts
swift package clean
```

## Architecture

BrainPhArt is a macOS SwiftUI application for audio recording with chunked storage and local Whisper transcription.

### Core Components

- **BrainPhArtApp.swift** - App entry point using SwiftUI App protocol
- **ContentView.swift** - Main UI with two-panel layout: HistoryPanel (left) showing past recordings, RecorderPanel (right) with record/stop button and waveform visualization
- **AudioRecorder.swift** - Handles microphone capture using AVAudioEngine, saves audio in 32-second chunks as WAV files to `~/brainphart/audio/{date}/`
- **DatabaseManager.swift** - SQLite wrapper (using SQLite.swift) storing sessions, chunks, and transcripts in `~/Library/Application Support/brainphart/database.db`
- **TranscriptionManager.swift** - Actor wrapping SwiftWhisper for local speech-to-text, resamples audio to 16kHz
- **TranscriptionWorker.swift** - Background actor polling DB for pending chunks, triggers transcription

### Data Flow

1. User presses RECORD → creates new session in DB → AudioRecorder starts AVAudioEngine tap
2. Audio samples accumulate in buffer → every 32 seconds, chunk is saved as WAV file and recorded in DB
3. User presses STOP → final chunk saved → session marked complete
4. TranscriptionWorker (running on app launch) polls for chunks with `transcription_status = 'pending'`
5. TranscriptionManager loads Whisper model, transcribes audio, saves transcript to DB
6. HistoryPanel loads sessions from DB and displays transcripts

### Database Schema

- **sessions** - Recording sessions (id, created_at, completed_at, status, chunk_count)
- **chunks** - Audio file references (id, session_id, chunk_num, file_path, duration_ms, created_at, transcription_status)
- **chunk_transcripts** - Text transcripts per chunk (id, session_id, chunk_number, transcript, created_at)

### File Locations

- Audio files: `~/brainphart/audio/{yyyy-MM-dd}/session_{uuid}_chunk_{n}.wav`
- Database: `~/Library/Application Support/brainphart/database.db`
- Whisper model: `~/brainphart/models/ggml-base.bin` (must be downloaded separately)
- Debug log: `~/brainphart/debug.log`

## Dependencies

- SQLite.swift 0.15.3+ for database operations
- SwiftWhisper (master branch) for local transcription
- Requires macOS 13+
- Uses Swift 6.1 concurrency features

## Concurrency Notes

- `AudioRecorder` uses `@unchecked Sendable` with a dedicated `bufferQueue` for thread-safe buffer access
- `TranscriptionManager` and `TranscriptionWorker` are actors for safe concurrent access
- `DatabaseManager` uses `nonisolated(unsafe)` for its shared singleton (SQL operations are synchronous)
