import Foundation
import SQLite

final class DatabaseManager {
    nonisolated(unsafe) static let shared = DatabaseManager()

    private var db: Connection!

    private init() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/brainphart")

        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        let dbPath = path.appendingPathComponent("database.db").path

        do {
            db = try Connection(dbPath)
            try db.execute("PRAGMA foreign_keys = ON")
            print("✅ Database opened at: \(dbPath)")
            createTables()
        } catch {
            print("❌ Database error: \(error)")
        }
    }
    
    private func createTables() {
        let sessionsTable = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            completed_at INTEGER,
            status TEXT NOT NULL,
            chunk_count INTEGER DEFAULT 0
        )
        """
        
        let chunksTable = """
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            chunk_num INTEGER NOT NULL,
            file_path TEXT NOT NULL,
            duration_ms INTEGER,
            created_at INTEGER NOT NULL,
            transcription_status TEXT DEFAULT 'pending',
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        )
        """
        
        let transcriptsTable = """
        CREATE TABLE IF NOT EXISTS chunk_transcripts (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            chunk_number INTEGER NOT NULL,
            transcript TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        )
        """
        
        do {
            try db.execute(sessionsTable)
            try db.execute(chunksTable)
            try db.execute(transcriptsTable)

            // Add transcription_status column if it doesn't exist (migration)
            let alterTableSQL = "ALTER TABLE chunks ADD COLUMN transcription_status TEXT DEFAULT 'pending'"
            do {
                try db.execute(alterTableSQL)
                print("✅ Added transcription_status column")
            } catch {
                // Column likely already exists, ignore error
            }

            print("✅ Tables created")
        } catch {
            print("❌ Table creation error: \(error)")
        }
    }
    
    func createSession(id: String) {
        let sql = """
        INSERT INTO sessions (id, created_at, status, chunk_count)
        VALUES (?, ?, 'recording', 0)
        """
        
        let timestamp = Int(Date().timeIntervalSince1970)
        
        do {
            try db.run(sql, id, timestamp)
            print("✅ Session created: \(id)")
        } catch {
            print("❌ Failed to create session: \(error)")
        }
    }
    
    func completeSession(id: String) {
        let sql = """
        UPDATE sessions
        SET completed_at = ?, status = 'complete'
        WHERE id = ?
        """

        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, timestamp, id)
            print("✅ Session completed: \(id)")
        } catch {
            print("❌ Failed to complete session: \(error)")
        }
    }

    func cancelSession(id: String) {
        let sql = """
        UPDATE sessions
        SET completed_at = ?, status = 'cancelled'
        WHERE id = ?
        """

        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, timestamp, id)
            print("⚠️ Session cancelled: \(id)")
        } catch {
            print("❌ Failed to cancel session: \(error)")
        }
    }
    
    func createChunk(id: String, sessionId: String, chunkNumber: Int, filePath: String, durationMs: Int) {
        let sql = """
        INSERT INTO chunks (id, session_id, chunk_num, file_path, duration_ms, created_at, transcription_status)
        VALUES (?, ?, ?, ?, ?, ?, 'pending')
        """

        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, id, sessionId, chunkNumber, filePath, durationMs, timestamp)
        } catch {
            print("❌ Failed to create chunk: \(error)")
        }
    }
    
    func getAllSessions() -> [Recording] {
        let sql = "SELECT id, created_at, completed_at, status, chunk_count FROM sessions ORDER BY created_at DESC"
        
        var sessions: [Recording] = []
        
        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                let recording = Recording(
                    id: row[0] as? String ?? "",
                    createdAt: Int(row[1] as? Int64 ?? 0),
                    completedAt: (row[2] as? Int64).map { Int($0) },
                    status: row[3] as? String ?? "unknown",
                    chunkCount: Int(row[4] as? Int64 ?? 0)
                )
                sessions.append(recording)
            }
        } catch {
            print("❌ Failed to load sessions: \(error)")
        }
        
        return sessions
    }
    
    func saveTranscript(sessionId: String, chunkNumber: Int, transcript: String) {
        let sql = """
        INSERT OR REPLACE INTO chunk_transcripts 
        (id, session_id, chunk_number, transcript, created_at)
        VALUES (?, ?, ?, ?, ?)
        """
        
        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        
        do {
            try db.run(sql, id, sessionId, chunkNumber, transcript, timestamp)
            print("📝 Saved transcript for chunk \(chunkNumber)")
        } catch {
            print("❌ Failed to save transcript: \(error)")
        }
    }
    
    func getTranscript(sessionId: String) -> String {
        let sql = """
        SELECT transcript FROM chunk_transcripts 
        WHERE session_id = ? 
        ORDER BY chunk_number ASC
        """
        
        var transcripts: [String] = []
        
        do {
            let stmt = try db.prepare(sql, sessionId)
            for row in stmt {
                if let text = row[0] as? String {
                    transcripts.append(text)
                }
            }
        } catch {
            print("❌ Failed to load transcript: \(error)")
        }
        
        return transcripts.joined(separator: "\n\n")
    }

    func updateFullTranscript(sessionId: String, transcript: String) {
        // Delete existing transcripts for this session
        let deleteSql = "DELETE FROM chunk_transcripts WHERE session_id = ?"

        do {
            try db.run(deleteSql, sessionId)
        } catch {
            print("❌ Failed to delete old transcripts: \(error)")
        }

        // Insert new full transcript as chunk 0
        let insertSql = """
        INSERT INTO chunk_transcripts
        (id, session_id, chunk_number, transcript, created_at)
        VALUES (?, ?, 0, ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(insertSql, id, sessionId, transcript, timestamp)
            print("✅ Full transcript saved for session: \(sessionId)")
        } catch {
            print("❌ Failed to save full transcript: \(error)")
        }
    }

    func getPendingChunks() -> [(id: String, sessionId: String, filePath: String, chunkNumber: Int)] {
        let sql = """
        SELECT id, session_id, file_path, chunk_num
        FROM chunks
        WHERE transcription_status = 'pending'
        ORDER BY created_at ASC
        """

        var pendingChunks: [(id: String, sessionId: String, filePath: String, chunkNumber: Int)] = []

        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                let chunk = (
                    id: row[0] as? String ?? "",
                    sessionId: row[1] as? String ?? "",
                    filePath: row[2] as? String ?? "",
                    chunkNumber: Int(row[3] as? Int64 ?? 0)
                )
                pendingChunks.append(chunk)
            }
        } catch {
            print("❌ Failed to load pending chunks: \(error)")
        }

        return pendingChunks
    }

    func updateChunkTranscriptionStatus(chunkId: String, status: String) {
        let sql = """
        UPDATE chunks
        SET transcription_status = ?
        WHERE id = ?
        """

        do {
            try db.run(sql, status, chunkId)
        } catch {
            print("❌ Failed to update transcription status: \(error)")
        }
    }
}
