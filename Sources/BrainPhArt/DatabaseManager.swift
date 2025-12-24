import Foundation
import SQLite

@MainActor
class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: Connection?
    
    private let sessions = Table("sessions")
    private let sessionId = Expression<String>("id")
    private let sessionCreatedAt = Expression<Int64>("created_at")
    private let sessionCompletedAt = Expression<Int64?>("completed_at")
    private let sessionStatus = Expression<String>("status")
    private let sessionChunkCount = Expression<Int>("chunk_count")
    
    private let chunks = Table("chunks")
    private let chunkId = Expression<String>("id")
    private let chunkSessionId = Expression<String>("session_id")
    private let chunkNumber = Expression<Int>("chunk_num")
    private let chunkFilePath = Expression<String>("file_path")
    private let chunkDuration = Expression<Int>("duration_ms")
    private let chunkCreatedAt = Expression<Int64>("created_at")
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let appFolder = appSupport.appendingPathComponent("brainphart")
            
            if !fileManager.fileExists(atPath: appFolder.path) {
                try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
            }
            
            let dbPath = appFolder.appendingPathComponent("database.db").path
            db = try Connection(dbPath)
            print("✅ Database opened at: \(dbPath)")
            
            try createTables()
            
        } catch {
            print("❌ Database setup failed: \(error)")
        }
    }
    
    private func createTables() throws {
        guard let db = db else { return }
        
        try db.run(sessions.create(ifNotExists: true) { t in
            t.column(sessionId, primaryKey: true)
            t.column(sessionCreatedAt)
            t.column(sessionCompletedAt)
            t.column(sessionStatus)
            t.column(sessionChunkCount, defaultValue: 0)
        })
        
        try db.run(chunks.create(ifNotExists: true) { t in
            t.column(chunkId, primaryKey: true)
            t.column(chunkSessionId)
            t.column(chunkNumber)
            t.column(chunkFilePath)
            t.column(chunkDuration)
            t.column(chunkCreatedAt)
            t.foreignKey(chunkSessionId, references: sessions, sessionId, delete: .cascade)
        })
        
        print("✅ Tables created")
    }
    
    func createSession() -> String {
        guard let db = db else { return "" }
        
        let id = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)
        
        do {
            try db.run(sessions.insert(
                sessionId <- id,
                sessionCreatedAt <- now,
                sessionStatus <- "recording",
                sessionChunkCount <- 0
            ))
            print("✅ Session created: \(id)")
            return id
        } catch {
            print("❌ Failed to create session: \(error)")
            return ""
        }
    }
    
    func completeSession(id: String) {
        guard let db = db else { return }
        
        let session = sessions.filter(sessionId == id)
        let now = Int64(Date().timeIntervalSince1970)
        
        do {
            try db.run(session.update(
                sessionStatus <- "complete",
                sessionCompletedAt <- now
            ))
            print("✅ Session completed: \(id)")
        } catch {
            print("❌ Failed to complete session: \(error)")
        }
    }
    
    func loadSessions() -> [(id: String, createdAt: Int64, status: String, chunkCount: Int)] {
        guard let db = db else { return [] }
        
        var results: [(String, Int64, String, Int)] = []
        
        do {
            for session in try db.prepare(sessions.order(sessionCreatedAt.desc)) {
                results.append((
                    session[sessionId],
                    session[sessionCreatedAt],
                    session[sessionStatus],
                    session[sessionChunkCount]
                ))
            }
        } catch {
            print("❌ Failed to load sessions: \(error)")
        }
        
        return results
    }
    
    func deleteSession(id: String) {
        guard let db = db else { return }
        
        let session = sessions.filter(sessionId == id)
        
        do {
            try db.run(session.delete())
            print("✅ Session deleted: \(id)")
        } catch {
            print("❌ Failed to delete session: \(error)")
        }
    }
    
    func saveChunk(sessionId: String, chunkNum: Int, filePath: String, durationMs: Int) {
        guard let db = db else { return }
        
        let id = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)
        
        do {
            try db.run(chunks.insert(
                chunkId <- id,
                chunkSessionId <- sessionId,
                chunkNumber <- chunkNum,
                chunkFilePath <- filePath,
                chunkDuration <- durationMs,
                chunkCreatedAt <- now
            ))
            
            let session = sessions.filter(self.sessionId == sessionId)
            try db.run(session.update(sessionChunkCount <- sessionChunkCount + 1))
            
            print("✅ Chunk saved: \(chunkNum) for session \(sessionId)")
        } catch {
            print("❌ Failed to save chunk: \(error)")
        }
    }
}
