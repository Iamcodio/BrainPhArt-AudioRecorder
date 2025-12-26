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

        // Version control for transcripts - NEVER lose edits
        let versionsTable = """
        CREATE TABLE IF NOT EXISTS transcript_versions (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            version_num INTEGER NOT NULL,
            version_type TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        )
        """

        // Custom dictionary for spell check (user words)
        let dictionaryTable = """
        CREATE TABLE IF NOT EXISTS custom_dictionary (
            id TEXT PRIMARY KEY,
            word TEXT NOT NULL UNIQUE,
            added_at INTEGER NOT NULL
        )
        """

        // Standard dictionary (imported from SCOWL + tech glossaries)
        let dictionaryWordsTable = """
        CREATE TABLE IF NOT EXISTS dictionary_words (
            word TEXT PRIMARY KEY,
            frequency INTEGER DEFAULT 0
        )
        """

        // Privacy tags with auto-suggest status
        let privacyTagsTable = """
        CREATE TABLE IF NOT EXISTS privacy_tags (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            start_offset INTEGER NOT NULL,
            end_offset INTEGER NOT NULL,
            status TEXT DEFAULT 'unreviewed',
            tag_type TEXT DEFAULT 'auto',
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        )
        """

        // Privacy ignore patterns (user says "this is fine")
        let privacyIgnoreTable = """
        CREATE TABLE IF NOT EXISTS privacy_ignore_patterns (
            id TEXT PRIMARY KEY,
            pattern TEXT NOT NULL UNIQUE,
            reason TEXT,
            added_at INTEGER NOT NULL
        )
        """

        // Cards for brain dump workflow (6 piles: INBOX, SHAPING, ACTIVE, SHIPPED, HOLD, KILL)
        let cardsTable = """
        CREATE TABLE IF NOT EXISTS cards (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            content TEXT NOT NULL,
            source_type TEXT DEFAULT 'brain_dump',
            pile TEXT DEFAULT 'INBOX',
            pile_position INTEGER DEFAULT 0,
            category TEXT,
            tags TEXT,
            is_private BOOLEAN DEFAULT FALSE,
            created_at INTEGER NOT NULL,
            moved_at INTEGER,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        )
        """

        do {
            try db.execute(sessionsTable)
            try db.execute(chunksTable)
            try db.execute(transcriptsTable)
            try db.execute(versionsTable)
            try db.execute(dictionaryTable)
            try db.execute(dictionaryWordsTable)
            try db.execute(privacyTagsTable)
            try db.execute(privacyIgnoreTable)
            try db.execute(cardsTable)

            // Add transcription_status column if it doesn't exist (migration)
            let alterTableSQL = "ALTER TABLE chunks ADD COLUMN transcription_status TEXT DEFAULT 'pending'"
            do {
                try db.execute(alterTableSQL)
                print("✅ Added transcription_status column")
            } catch {
                // Column likely already exists, ignore error
            }

            // Add privacy_level column to sessions if it doesn't exist (migration)
            let alterSessionsSQL = "ALTER TABLE sessions ADD COLUMN privacy_level TEXT DEFAULT 'public'"
            do {
                try db.execute(alterSessionsSQL)
                print("✅ Added privacy_level column to sessions")
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
        let sql = "SELECT id, created_at, completed_at, status, chunk_count, privacy_level FROM sessions ORDER BY created_at DESC"

        var sessions: [Recording] = []

        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                let recording = Recording(
                    id: row[0] as? String ?? "",
                    createdAt: Int(row[1] as? Int64 ?? 0),
                    completedAt: (row[2] as? Int64).map { Int($0) },
                    status: row[3] as? String ?? "unknown",
                    chunkCount: Int(row[4] as? Int64 ?? 0),
                    privacyLevel: row[5] as? String ?? "public"
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
        // NEVER DELETE - save as new version instead
        saveVersion(sessionId: sessionId, content: transcript, versionType: "edited")

        // Also update chunk_transcripts for backward compatibility
        let deleteSql = "DELETE FROM chunk_transcripts WHERE session_id = ?"
        let insertSql = """
        INSERT INTO chunk_transcripts
        (id, session_id, chunk_number, transcript, created_at)
        VALUES (?, ?, 0, ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(deleteSql, sessionId)
            try db.run(insertSql, id, sessionId, transcript, timestamp)
            print("✅ Full transcript saved for session: \(sessionId)")
        } catch {
            print("❌ Failed to save full transcript: \(error)")
        }
    }

    // MARK: - Version Control (NEVER LOSE EDITS)

    func saveVersion(sessionId: String, content: String, versionType: String) {
        let nextVersion = getNextVersionNumber(sessionId: sessionId)

        let sql = """
        INSERT INTO transcript_versions
        (id, session_id, version_num, version_type, content, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, id, sessionId, nextVersion, versionType, content, timestamp)
            print("📝 Version \(nextVersion) saved (\(versionType)) for session: \(sessionId)")
        } catch {
            print("❌ Failed to save version: \(error)")
        }
    }

    func getNextVersionNumber(sessionId: String) -> Int {
        let sql = "SELECT MAX(version_num) FROM transcript_versions WHERE session_id = ?"

        do {
            for row in try db.prepare(sql, sessionId) {
                if let maxVersion = row[0] as? Int64 {
                    return Int(maxVersion) + 1
                }
            }
        } catch {
            print("❌ Failed to get version number: \(error)")
        }

        return 1  // First version
    }

    func getVersions(sessionId: String) -> [(versionNum: Int, versionType: String, content: String, createdAt: Int)] {
        let sql = """
        SELECT version_num, version_type, content, created_at
        FROM transcript_versions
        WHERE session_id = ?
        ORDER BY version_num DESC
        """

        var versions: [(versionNum: Int, versionType: String, content: String, createdAt: Int)] = []

        do {
            let stmt = try db.prepare(sql, sessionId)
            for row in stmt {
                let version = (
                    versionNum: Int(row[0] as? Int64 ?? 0),
                    versionType: row[1] as? String ?? "unknown",
                    content: row[2] as? String ?? "",
                    createdAt: Int(row[3] as? Int64 ?? 0)
                )
                versions.append(version)
            }
        } catch {
            print("❌ Failed to get versions: \(error)")
        }

        return versions
    }

    func getLatestVersion(sessionId: String) -> (versionNum: Int, content: String)? {
        let sql = """
        SELECT version_num, content
        FROM transcript_versions
        WHERE session_id = ?
        ORDER BY version_num DESC
        LIMIT 1
        """

        do {
            for row in try db.prepare(sql, sessionId) {
                return (
                    versionNum: Int(row[0] as? Int64 ?? 0),
                    content: row[1] as? String ?? ""
                )
            }
        } catch {
            print("❌ Failed to get latest version: \(error)")
        }

        return nil
    }

    func restoreVersion(sessionId: String, versionNum: Int) {
        // Get the version content
        let sql = "SELECT content FROM transcript_versions WHERE session_id = ? AND version_num = ?"

        do {
            for row in try db.prepare(sql, sessionId, versionNum) {
                if let content = row[0] as? String {
                    // Save as new version (type: restored)
                    saveVersion(sessionId: sessionId, content: content, versionType: "restored")
                    // Update current transcript
                    updateFullTranscriptWithoutVersion(sessionId: sessionId, transcript: content)
                    print("🔄 Restored version \(versionNum) for session: \(sessionId)")
                }
            }
        } catch {
            print("❌ Failed to restore version: \(error)")
        }
    }

    private func updateFullTranscriptWithoutVersion(sessionId: String, transcript: String) {
        let deleteSql = "DELETE FROM chunk_transcripts WHERE session_id = ?"
        let insertSql = """
        INSERT INTO chunk_transcripts
        (id, session_id, chunk_number, transcript, created_at)
        VALUES (?, ?, 0, ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(deleteSql, sessionId)
            try db.run(insertSql, id, sessionId, transcript, timestamp)
        } catch {
            print("❌ Failed to update transcript: \(error)")
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

    func getChunkPaths(sessionId: String) -> [URL] {
        let sql = """
        SELECT file_path FROM chunks
        WHERE session_id = ?
        ORDER BY chunk_num ASC
        """

        var paths: [URL] = []

        do {
            let stmt = try db.prepare(sql, sessionId)
            for row in stmt {
                if let filePath = row[0] as? String {
                    let url = URL(fileURLWithPath: filePath)
                    if FileManager.default.fileExists(atPath: filePath) {
                        paths.append(url)
                    }
                }
            }
        } catch {
            print("❌ Failed to get chunk paths: \(error)")
        }

        return paths
    }

    func deleteSession(id: String) {
        // Get chunk file paths first
        let chunkPaths = getChunkPaths(sessionId: id)

        // Delete audio files
        for path in chunkPaths {
            try? FileManager.default.removeItem(at: path)
        }

        // Delete from database
        let deleteTranscripts = "DELETE FROM chunk_transcripts WHERE session_id = ?"
        let deleteChunks = "DELETE FROM chunks WHERE session_id = ?"
        let deleteSession = "DELETE FROM sessions WHERE id = ?"

        do {
            try db.run(deleteTranscripts, id)
            try db.run(deleteChunks, id)
            try db.run(deleteSession, id)
            print("🗑️ Session deleted: \(id)")
        } catch {
            print("❌ Failed to delete session: \(error)")
        }
    }

    func resetTranscriptionStatus(sessionId: String) {
        let sql = """
        UPDATE chunks
        SET transcription_status = 'pending'
        WHERE session_id = ?
        """

        // Also delete existing transcripts
        let deleteTranscripts = "DELETE FROM chunk_transcripts WHERE session_id = ?"

        do {
            try db.run(sql, sessionId)
            try db.run(deleteTranscripts, sessionId)
            print("🔄 Transcription reset for session: \(sessionId)")
        } catch {
            print("❌ Failed to reset transcription: \(error)")
        }
    }

    func getTranscriptionProgress(sessionId: String) -> Double {
        let totalSql = "SELECT COUNT(*) FROM chunks WHERE session_id = ?"
        let completedSql = "SELECT COUNT(*) FROM chunks WHERE session_id = ? AND transcription_status = 'complete'"

        do {
            var total = 0
            var completed = 0

            for row in try db.prepare(totalSql, sessionId) {
                total = Int(row[0] as? Int64 ?? 0)
            }
            for row in try db.prepare(completedSql, sessionId) {
                completed = Int(row[0] as? Int64 ?? 0)
            }

            if total == 0 { return 0 }
            return Double(completed) / Double(total)
        } catch {
            return 0
        }
    }

    // MARK: - Privacy Tags

    func savePrivacyTag(sessionId: String, startOffset: Int, endOffset: Int, tagType: String) {
        let sql = """
        INSERT INTO privacy_tags
        (id, session_id, start_offset, end_offset, status, tag_type, created_at)
        VALUES (?, ?, ?, ?, 'unreviewed', ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, id, sessionId, startOffset, endOffset, tagType, timestamp)
            print("🔒 Privacy tag saved for session: \(sessionId)")
        } catch {
            print("❌ Failed to save privacy tag: \(error)")
        }
    }

    func updatePrivacyTagStatus(tagId: String, status: String) {
        let sql = """
        UPDATE privacy_tags
        SET status = ?
        WHERE id = ?
        """

        do {
            try db.run(sql, status, tagId)
            print("🔒 Privacy tag status updated to: \(status)")
        } catch {
            print("❌ Failed to update privacy tag status: \(error)")
        }
    }

    func getPrivacyTags(sessionId: String) -> [(id: String, startOffset: Int, endOffset: Int, status: String, tagType: String)] {
        let sql = """
        SELECT id, start_offset, end_offset, status, tag_type
        FROM privacy_tags
        WHERE session_id = ?
        ORDER BY start_offset ASC
        """

        var tags: [(id: String, startOffset: Int, endOffset: Int, status: String, tagType: String)] = []

        do {
            let stmt = try db.prepare(sql, sessionId)
            for row in stmt {
                let tag = (
                    id: row[0] as? String ?? "",
                    startOffset: Int(row[1] as? Int64 ?? 0),
                    endOffset: Int(row[2] as? Int64 ?? 0),
                    status: row[3] as? String ?? "unreviewed",
                    tagType: row[4] as? String ?? "auto"
                )
                tags.append(tag)
            }
        } catch {
            print("❌ Failed to get privacy tags: \(error)")
        }

        return tags
    }

    func getUnreviewedCount(sessionId: String) -> Int {
        let sql = "SELECT COUNT(*) FROM privacy_tags WHERE session_id = ? AND status = 'unreviewed'"

        do {
            for row in try db.prepare(sql, sessionId) {
                return Int(row[0] as? Int64 ?? 0)
            }
        } catch {
            print("❌ Failed to get unreviewed count: \(error)")
        }

        return 0
    }

    func canPublish(sessionId: String) -> Bool {
        return getUnreviewedCount(sessionId: sessionId) == 0
    }

    func addIgnorePattern(pattern: String, reason: String?) {
        let sql = """
        INSERT OR REPLACE INTO privacy_ignore_patterns
        (id, pattern, reason, added_at)
        VALUES (?, ?, ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, id, pattern, reason, timestamp)
            print("🔒 Ignore pattern added: \(pattern)")
        } catch {
            print("❌ Failed to add ignore pattern: \(error)")
        }
    }

    func getIgnorePatterns() -> [String] {
        let sql = "SELECT pattern FROM privacy_ignore_patterns ORDER BY added_at DESC"

        var patterns: [String] = []

        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                if let pattern = row[0] as? String {
                    patterns.append(pattern)
                }
            }
        } catch {
            print("❌ Failed to get ignore patterns: \(error)")
        }

        return patterns
    }

    // MARK: - Cards (Brain Dump Workflow)
    // Piles: INBOX, SHAPING, ACTIVE, SHIPPED, HOLD, KILL

    func createCard(sessionId: String?, content: String, pile: String = "INBOX") -> String {
        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        // Get next position in pile
        let positionSql = "SELECT COALESCE(MAX(pile_position), -1) + 1 FROM cards WHERE pile = ?"
        var nextPosition = 0

        do {
            for row in try db.prepare(positionSql, pile) {
                nextPosition = Int(row[0] as? Int64 ?? 0)
            }
        } catch {
            print("❌ Failed to get next position: \(error)")
        }

        let sql = """
        INSERT INTO cards (id, session_id, content, pile, pile_position, created_at, moved_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """

        do {
            try db.run(sql, id, sessionId, content, pile, nextPosition, timestamp, timestamp)
            print("📝 Card created: \(id) in pile \(pile)")
        } catch {
            print("❌ Failed to create card: \(error)")
        }

        return id
    }

    func getCards(pile: String?) -> [(id: String, sessionId: String?, content: String, sourceType: String, pile: String, pilePosition: Int, category: String?, tags: String?, isPrivate: Bool, createdAt: Int, movedAt: Int?)] {
        let sql: String
        if pile != nil {
            sql = """
            SELECT id, session_id, content, source_type, pile, pile_position, category, tags, is_private, created_at, moved_at
            FROM cards
            WHERE pile = ?
            ORDER BY pile_position ASC
            """
        } else {
            sql = """
            SELECT id, session_id, content, source_type, pile, pile_position, category, tags, is_private, created_at, moved_at
            FROM cards
            ORDER BY created_at DESC
            """
        }

        var cards: [(id: String, sessionId: String?, content: String, sourceType: String, pile: String, pilePosition: Int, category: String?, tags: String?, isPrivate: Bool, createdAt: Int, movedAt: Int?)] = []

        do {
            let stmt: Statement
            if let pileValue = pile {
                stmt = try db.prepare(sql, pileValue)
            } else {
                stmt = try db.prepare(sql)
            }

            for row in stmt {
                let card = (
                    id: row[0] as? String ?? "",
                    sessionId: row[1] as? String,
                    content: row[2] as? String ?? "",
                    sourceType: row[3] as? String ?? "brain_dump",
                    pile: row[4] as? String ?? "INBOX",
                    pilePosition: Int(row[5] as? Int64 ?? 0),
                    category: row[6] as? String,
                    tags: row[7] as? String,
                    isPrivate: (row[8] as? Int64 ?? 0) == 1,
                    createdAt: Int(row[9] as? Int64 ?? 0),
                    movedAt: (row[10] as? Int64).map { Int($0) }
                )
                cards.append(card)
            }
        } catch {
            print("❌ Failed to get cards: \(error)")
        }

        return cards
    }

    func moveCard(cardId: String, toPile: String) {
        let timestamp = Int(Date().timeIntervalSince1970)

        // Get next position in destination pile
        let positionSql = "SELECT COALESCE(MAX(pile_position), -1) + 1 FROM cards WHERE pile = ?"
        var nextPosition = 0

        do {
            for row in try db.prepare(positionSql, toPile) {
                nextPosition = Int(row[0] as? Int64 ?? 0)
            }
        } catch {
            print("❌ Failed to get next position: \(error)")
        }

        let sql = """
        UPDATE cards
        SET pile = ?, pile_position = ?, moved_at = ?
        WHERE id = ?
        """

        do {
            try db.run(sql, toPile, nextPosition, timestamp, cardId)
            print("📦 Card moved to pile \(toPile): \(cardId)")
        } catch {
            print("❌ Failed to move card: \(error)")
        }
    }

    func updateCardPrivacy(cardId: String, isPrivate: Bool) {
        let sql = """
        UPDATE cards
        SET is_private = ?
        WHERE id = ?
        """

        do {
            try db.run(sql, isPrivate ? 1 : 0, cardId)
            print("🔒 Card privacy updated: \(cardId) -> \(isPrivate ? "private" : "public")")
        } catch {
            print("❌ Failed to update card privacy: \(error)")
        }
    }

    func deleteCard(cardId: String) {
        let sql = "DELETE FROM cards WHERE id = ?"

        do {
            try db.run(sql, cardId)
            print("🗑️ Card deleted: \(cardId)")
        } catch {
            print("❌ Failed to delete card: \(error)")
        }
    }

    func getCardsBySession(sessionId: String) -> [(id: String, sessionId: String?, content: String, sourceType: String, pile: String, pilePosition: Int, category: String?, tags: String?, isPrivate: Bool, createdAt: Int, movedAt: Int?)] {
        let sql = """
        SELECT id, session_id, content, source_type, pile, pile_position, category, tags, is_private, created_at, moved_at
        FROM cards
        WHERE session_id = ?
        ORDER BY created_at ASC
        """

        var cards: [(id: String, sessionId: String?, content: String, sourceType: String, pile: String, pilePosition: Int, category: String?, tags: String?, isPrivate: Bool, createdAt: Int, movedAt: Int?)] = []

        do {
            let stmt = try db.prepare(sql, sessionId)
            for row in stmt {
                let card = (
                    id: row[0] as? String ?? "",
                    sessionId: row[1] as? String,
                    content: row[2] as? String ?? "",
                    sourceType: row[3] as? String ?? "brain_dump",
                    pile: row[4] as? String ?? "INBOX",
                    pilePosition: Int(row[5] as? Int64 ?? 0),
                    category: row[6] as? String,
                    tags: row[7] as? String,
                    isPrivate: (row[8] as? Int64 ?? 0) == 1,
                    createdAt: Int(row[9] as? Int64 ?? 0),
                    movedAt: (row[10] as? Int64).map { Int($0) }
                )
                cards.append(card)
            }
        } catch {
            print("❌ Failed to get cards by session: \(error)")
        }

        return cards
    }

    // MARK: - Session Privacy Level

    func setSessionPrivacyLevel(sessionId: String, level: String) {
        let sql = """
        UPDATE sessions
        SET privacy_level = ?
        WHERE id = ?
        """

        do {
            try db.run(sql, level, sessionId)
            print("🔒 Session privacy level set to '\(level)': \(sessionId)")
        } catch {
            print("❌ Failed to set session privacy level: \(error)")
        }
    }

    func getSessionPrivacyLevel(sessionId: String) -> String {
        let sql = "SELECT privacy_level FROM sessions WHERE id = ?"

        do {
            for row in try db.prepare(sql, sessionId) {
                return row[0] as? String ?? "public"
            }
        } catch {
            print("❌ Failed to get session privacy level: \(error)")
        }

        return "public"
    }

    func getPrivateSessions() -> [Recording] {
        let sql = "SELECT id, created_at, completed_at, status, chunk_count, privacy_level FROM sessions WHERE privacy_level = 'private' ORDER BY created_at DESC"

        var sessions: [Recording] = []

        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                let recording = Recording(
                    id: row[0] as? String ?? "",
                    createdAt: Int(row[1] as? Int64 ?? 0),
                    completedAt: (row[2] as? Int64).map { Int($0) },
                    status: row[3] as? String ?? "unknown",
                    chunkCount: Int(row[4] as? Int64 ?? 0),
                    privacyLevel: row[5] as? String ?? "private"
                )
                sessions.append(recording)
            }
        } catch {
            print("❌ Failed to load private sessions: \(error)")
        }

        return sessions
    }

    func getPublicSessions() -> [Recording] {
        let sql = "SELECT id, created_at, completed_at, status, chunk_count, privacy_level FROM sessions WHERE privacy_level = 'public' ORDER BY created_at DESC"

        var sessions: [Recording] = []

        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                let recording = Recording(
                    id: row[0] as? String ?? "",
                    createdAt: Int(row[1] as? Int64 ?? 0),
                    completedAt: (row[2] as? Int64).map { Int($0) },
                    status: row[3] as? String ?? "unknown",
                    chunkCount: Int(row[4] as? Int64 ?? 0),
                    privacyLevel: row[5] as? String ?? "public"
                )
                sessions.append(recording)
            }
        } catch {
            print("❌ Failed to load public sessions: \(error)")
        }

        return sessions
    }
}
