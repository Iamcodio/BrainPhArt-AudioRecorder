# Swift 6 Concurrency & SQLite.swift Reference
**Downloaded:** December 25, 2025  
**For:** BrainPhArt Audio Recorder

---

## Swift 6.2 Concurrency Model (September 2025)

### Key Changes in Swift 6.2

1. **Single-threaded by default**: Code runs on main actor unless specified
2. **Actor isolation improvements**: Better deadlock prevention
3. **Improved async debugging**: LLDB can step through async calls
4. **Task naming**: Human-readable task names in debugger

### Official Swift Concurrency Resources

- **Main Documentation**: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
- **Swift 6.2 Announcement**: https://www.swift.org/blog/swift-6.2-released/
- **Actor Proposal (SE-0306)**: https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md
- **Concurrency Guidelines**: https://www.swift.org/documentation/server/guides/libraries/concurrency-adoption-guidelines.html

---

## SQLite.swift Thread Safety (CRITICAL)

### Official Documentation Quote

> "Every Connection comes equipped with its own serial queue for statement execution and **can be safely accessed across threads**."
> 
> — SQLite.swift Documentation, Index.md

**Source:** https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md

### What This Means

**SQLite.swift ALREADY HAS BUILT-IN THREAD SAFETY.**

Each `Connection` object:
- Has its own `DispatchQueue` (serial)
- All database operations run on that queue
- Thread-safe by design
- No manual synchronization needed

### Correct Usage Pattern

```swift
// ✅ CORRECT - Connection is already thread-safe
final class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: Connection!
    
    init() {
        db = try Connection(dbPath)
    }
    
    func createSession(id: String) {
        // This is already thread-safe
        // SQLite.swift's internal queue handles synchronization
        try db.run(sql, id, timestamp)
    }
}
```

**No need for:**
- `@unchecked Sendable` ❌
- Actor wrapper ❌ (unless you want async API)
- Manual locks ❌
- Additional queues ❌

### Important Notes

1. **One connection per database file** is thread-safe
2. **Multiple connections to same file** need busy timeout:
   ```swift
   db.busyTimeout = 5  // Wait 5 seconds for lock
   ```
3. **Transactions block other threads** until complete

### When You WOULD Need Actor

If you want async/await API for better Swift 6 integration:

```swift
actor DatabaseManager {
    private var db: Connection!
    
    func createSession(id: String) async throws {
        try db.run(sql, id, timestamp)
    }
}
```

**Benefit:** Compiler-enforced async calls, better fits Swift concurrency model

**Trade-off:** All database calls become `await`

---

## Actor Pattern (SE-0306)

### What is an Actor?

Actors are reference types that protect mutable state through **isolation**.

```swift
actor Counter {
    private var value = 0
    
    func increment() {
        value += 1  // Only one caller at a time
    }
    
    func getValue() -> Int {
        return value
    }
}

// Usage
let counter = Counter()
await counter.increment()  // Suspends until actor is available
let val = await counter.getValue()
```

### Key Rules

1. **All methods are async by default** (except `nonisolated`)
2. **Serial execution** - one task at a time
3. **Re-entrant** - actor can call its own methods without deadlock
4. **Cross-actor calls must await**

### Actor Isolation

```swift
actor MyActor {
    var state = 0  // Actor-isolated
    
    func modify() {
        state += 1  // ✅ Synchronous access
    }
    
    nonisolated func read() -> Int {
        // ❌ ERROR: Cannot access actor-isolated state
        return state
    }
}
```

### @MainActor

Special global actor for UI code:

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var data: String = ""
    
    func update() {
        // Runs on main thread automatically
        data = "Updated"
    }
}
```

---

## Sendable Protocol

### What is Sendable?

Protocol that marks types safe to pass across concurrency boundaries.

### Built-in Sendable Types

- Value types: `Int`, `String`, `Array`, `Dictionary`
- Immutable classes
- Actors (implicitly Sendable)

### Making Custom Types Sendable

```swift
// Value type - automatically Sendable if all properties are Sendable
struct User: Sendable {
    let id: Int
    let name: String
}

// Class - must be explicitly marked and have immutable storage
final class Config: Sendable {
    let apiKey: String  // Must be let, not var
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
}
```

### @unchecked Sendable (Use Sparingly!)

```swift
// Only use when:
// 1. Wrapping C APIs with their own thread safety
// 2. Manually synchronized with locks
// 3. You've ACTUALLY implemented thread safety

final class ThreadSafeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    
    func get(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}
```

**Warning:** `@unchecked Sendable` disables compiler safety checks. Only use when necessary.

---

## Swift 6 Concurrency Patterns

### Pattern 1: Actor for Shared State

```swift
actor SessionManager {
    private var sessions: [String: Session] = [:]
    
    func add(_ session: Session) {
        sessions[session.id] = session
    }
    
    func get(_ id: String) -> Session? {
        return sessions[id]
    }
}

// Usage
let manager = SessionManager()
await manager.add(newSession)
```

### Pattern 2: @MainActor for UI

```swift
@MainActor
class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    
    func startRecording() async {
        isRecording = true
        // All UI updates guaranteed on main thread
    }
}
```

### Pattern 3: Task for Background Work

```swift
Task.detached {
    // Runs on background thread
    let data = await heavyComputation()
    
    await MainActor.run {
        // Switch to main for UI update
        updateUI(with: data)
    }
}
```

---

## Common Mistakes to Avoid

### Mistake 1: Unnecessary @unchecked Sendable

```swift
// ❌ WRONG
final class DatabaseManager: @unchecked Sendable {
    private var db: Connection!  // SQLite.swift already handles this!
}

// ✅ CORRECT
final class DatabaseManager {
    private var db: Connection!  // Let SQLite.swift handle thread safety
}
```

### Mistake 2: Blocking in Actors

```swift
actor DataLoader {
    func load() {
        // ❌ WRONG - Blocks actor, prevents other tasks
        Thread.sleep(forTimeInterval: 1.0)
    }
    
    func loadCorrect() async {
        // ✅ CORRECT - Suspends without blocking
        try? await Task.sleep(for: .seconds(1))
    }
}
```

### Mistake 3: Force-Unwrapping Across Await

```swift
actor MyActor {
    func process() async {
        let value = someValue!  // Captured
        await slowOperation()
        use(value!)  // ⚠️ Value might have changed during await
    }
}
```

---

## Debugging Concurrency Issues

### Enable Strict Concurrency Checking

In Package.swift:
```swift
.target(
    name: "MyTarget",
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
    ]
)
```

### Runtime Data Race Detection

Use Thread Sanitizer in Xcode:
1. Edit Scheme
2. Run → Diagnostics
3. Enable "Thread Sanitizer"

### LLDB Commands (Swift 6.2+)

```
(lldb) po await actor.method()  // Call async method
(lldb) po $currentTask  // See current task context
```

---

## References

1. **Swift 6.2 Released**: https://www.swift.org/blog/swift-6.2-released/
2. **Concurrency Book**: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/
3. **SQLite.swift Docs**: https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md
4. **Actor Proposal**: https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md
5. **Sendable Checking**: https://www.swift.org/documentation/concurrency/

---

## TL;DR for BrainPhArt

1. **SQLite.swift is ALREADY thread-safe** - no need for manual synchronization
2. **Remove `@unchecked Sendable`** from DatabaseManager (unnecessary)
3. **Use actors only if you want async API** (not required for thread safety)
4. **@MainActor for AudioRecorder** (it's UI-bound via @Published)
5. **Enable StrictConcurrency** to catch issues at compile time

**Bottom line:** Current code is more complicated than it needs to be. SQLite.swift handles thread safety. Just use it directly.
