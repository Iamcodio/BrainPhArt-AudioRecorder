import Foundation
import SQLite

/// Custom spell checker using SQLite dictionary storage.
/// Does NOT use Apple's NSSpellChecker - uses our own dictionary tables.
actor SpellEngine {

    /// Shared singleton instance
    static let shared = SpellEngine()

    /// In-memory word set for fast O(1) lookups
    private var wordSet: Set<String> = []

    /// Database connection (same database as DatabaseManager)
    private var db: Connection?

    /// Track if dictionary has been loaded
    private var isLoaded = false

    /// Current language setting
    private var currentLanguage: String = "en-GB"

    private init() {
        db = Self.setupDatabase()
    }

    /// Reload dictionary with specified language
    func reloadDictionary(language: String) async {
        currentLanguage = language
        isLoaded = false
        await loadDictionary()
        print("[SpellEngine] Reloaded dictionary for \(language)")
    }

    // MARK: - Database Setup

    private static func setupDatabase() -> Connection? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/brainphart")

        let dbPath = path.appendingPathComponent("database.db").path

        do {
            return try Connection(dbPath)
        } catch {
            print("[SpellEngine] Failed to open database: \(error)")
            return nil
        }
    }

    // MARK: - Public API

    /// Load all dictionary words into memory for fast lookup.
    /// Call this once at app startup or before first spell check.
    func loadDictionary() async {
        guard let db = db else {
            print("[SpellEngine] No database connection")
            return
        }

        // Get language from UserDefaults if not set
        if currentLanguage.isEmpty {
            currentLanguage = UserDefaults.standard.string(forKey: "spellCheckLanguage") ?? "en-GB"
        }

        wordSet.removeAll()

        // Load standard dictionary words
        let standardSql = "SELECT word FROM dictionary_words"
        do {
            let stmt = try db.prepare(standardSql)
            for row in stmt {
                if let word = row[0] as? String {
                    wordSet.insert(word.lowercased())
                }
            }
        } catch {
            print("[SpellEngine] Failed to load standard dictionary: \(error)")
        }

        // Load custom dictionary words
        let customSql = "SELECT word FROM custom_dictionary"
        do {
            let stmt = try db.prepare(customSql)
            for row in stmt {
                if let word = row[0] as? String {
                    wordSet.insert(word.lowercased())
                }
            }
        } catch {
            print("[SpellEngine] Failed to load custom dictionary: \(error)")
        }

        // Add language-specific spellings
        if currentLanguage == "en-GB" {
            // British spellings
            for word in britishSpellings {
                wordSet.insert(word)
            }
            // Remove American-only spellings
            for word in americanOnlySpellings {
                wordSet.remove(word)
            }
        } else {
            // American spellings
            for word in americanSpellings {
                wordSet.insert(word)
            }
            // Remove British-only spellings
            for word in britishOnlySpellings {
                wordSet.remove(word)
            }
        }

        isLoaded = true
        print("[SpellEngine] Loaded \(wordSet.count) words into dictionary (\(currentLanguage))")
    }

    // MARK: - British vs American Spellings

    /// British spellings to add when en-GB is selected
    private let britishSpellings: Set<String> = [
        // -our endings
        "colour", "colours", "coloured", "colouring", "colourful",
        "favour", "favours", "favoured", "favouring", "favourite", "favourites",
        "honour", "honours", "honoured", "honouring", "honourable",
        "labour", "labours", "laboured", "labouring",
        "neighbour", "neighbours", "neighbouring", "neighbourhood",
        "behaviour", "behaviours", "behavioural",
        "humour", "humours", "humoured", "humouring", "humorous",
        "flavour", "flavours", "flavoured", "flavouring",
        "vapour", "vapours",
        "odour", "odours",
        "rumour", "rumours", "rumoured",
        "savour", "savours", "savoured", "savouring", "savoury",
        "vigour", "vigorous",
        // -ise endings
        "organise", "organises", "organised", "organising", "organisation", "organisations",
        "realise", "realises", "realised", "realising",
        "recognise", "recognises", "recognised", "recognising",
        "specialise", "specialises", "specialised", "specialising",
        "apologise", "apologises", "apologised", "apologising",
        "criticise", "criticises", "criticised", "criticising",
        "emphasise", "emphasises", "emphasised", "emphasising",
        "summarise", "summarises", "summarised", "summarising",
        "analyse", "analyses", "analysed", "analysing",
        "paralyse", "paralyses", "paralysed", "paralysing",
        "catalyse", "catalyses", "catalysed", "catalysing",
        // -re endings
        "centre", "centres", "centred", "centring",
        "theatre", "theatres",
        "metre", "metres",
        "litre", "litres",
        "fibre", "fibres",
        "spectre", "spectres",
        "sombre",
        "calibre",
        // -ce/-se differences
        "defence", "defences",
        "offence", "offences",
        "licence", "licences",
        "practise", "practises", "practised", "practising",
        // -ogue endings
        "catalogue", "catalogues", "catalogued", "cataloguing",
        "dialogue", "dialogues",
        "monologue", "monologues",
        "prologue", "prologues",
        "epilogue", "epilogues",
        // Double consonants
        "travelling", "travelled", "traveller", "travellers",
        "cancelled", "cancelling", "cancellation",
        "labelled", "labelling",
        "modelled", "modelling",
        "counselled", "counselling", "counsellor", "counsellors",
        "marvelled", "marvelling", "marvellous",
        "jewellery",
        "fulfil", "fulfils", "fulfilled", "fulfilling", "fulfilment",
        "skilful", "wilful",
        // Other British
        "grey", "greys",
        "cheque", "cheques",
        "kerb", "kerbs",
        "tyre", "tyres",
        "aluminium",
        "mum", "mums",
        "whilst",
        "amongst",
        "towards",
        "backwards", "forwards", "afterwards", "upwards", "downwards",
        "programme", "programmes", "programmed", "programming",
        "aeroplane", "aeroplanes",
        "pyjamas",
        "draught", "draughts", "draughty",
        "plough", "ploughs", "ploughed", "ploughing",
        "gaol", "gaols",
        "storey", "storeys",
        "connexion",
        "enquiry", "enquiries", "enquire", "enquires", "enquired", "enquiring",
    ]

    /// American spellings to add when en-US is selected
    private let americanSpellings: Set<String> = [
        "color", "colors", "colored", "coloring", "colorful",
        "favor", "favors", "favored", "favoring", "favorite", "favorites",
        "honor", "honors", "honored", "honoring", "honorable",
        "labor", "labors", "labored", "laboring",
        "neighbor", "neighbors", "neighboring", "neighborhood",
        "behavior", "behaviors", "behavioral",
        "humor", "humors", "humored", "humoring",
        "flavor", "flavors", "flavored", "flavoring",
        "vapor", "vapors",
        "odor", "odors",
        "rumor", "rumors", "rumored",
        "savor", "savors", "savored", "savoring", "savory",
        "vigor",
        "organize", "organizes", "organized", "organizing", "organization", "organizations",
        "realize", "realizes", "realized", "realizing",
        "recognize", "recognizes", "recognized", "recognizing",
        "specialize", "specializes", "specialized", "specializing",
        "apologize", "apologizes", "apologized", "apologizing",
        "criticize", "criticizes", "criticized", "criticizing",
        "emphasize", "emphasizes", "emphasized", "emphasizing",
        "summarize", "summarizes", "summarized", "summarizing",
        "analyze", "analyzes", "analyzed", "analyzing",
        "paralyze", "paralyzes", "paralyzed", "paralyzing",
        "catalyze", "catalyzes", "catalyzed", "catalyzing",
        "center", "centers", "centered", "centering",
        "theater", "theaters",
        "meter", "meters",
        "liter", "liters",
        "fiber", "fibers",
        "specter", "specters",
        "somber",
        "caliber",
        "defense", "defenses",
        "offense", "offenses",
        "license", "licenses", "licensed", "licensing",
        "practice", "practices", "practiced", "practicing",
        "catalog", "catalogs", "cataloged", "cataloging",
        "dialog", "dialogs",
        "monolog", "monologs",
        "prolog", "prologs",
        "epilog", "epilogs",
        "traveling", "traveled", "traveler", "travelers",
        "canceled", "canceling", "cancelation",
        "labeled", "labeling",
        "modeled", "modeling",
        "counseled", "counseling", "counselor", "counselors",
        "marveled", "marveling", "marvelous",
        "jewelry",
        "fulfill", "fulfills", "fulfilled", "fulfilling", "fulfillment",
        "skillful", "willful",
        "gray", "grays",
        "check", "checks",
        "curb", "curbs",
        "tire", "tires",
        "aluminum",
        "mom", "moms",
        "while",
        "among",
        "toward",
        "backward", "forward", "afterward", "upward", "downward",
        "program", "programs", "programmed", "programming",
        "airplane", "airplanes",
        "pajamas",
        "draft", "drafts", "drafty",
        "plow", "plows", "plowed", "plowing",
        "jail", "jails",
        "story", "stories",
        "connection",
        "inquiry", "inquiries", "inquire", "inquires", "inquired", "inquiring",
    ]

    /// American-only spellings to remove when British is selected
    private let americanOnlySpellings: Set<String> = [
        "color", "colors", "colored", "coloring", "colorful",
        "favor", "favors", "favored", "favoring", "favorite", "favorites",
        "honor", "honors", "honored", "honoring", "honorable",
        "gray", "grays",
        "tire", "tires",
        "aluminum",
        "mom", "moms",
        "airplane", "airplanes",
        "jail", "jails",
        "pajamas",
    ]

    /// British-only spellings to remove when American is selected
    private let britishOnlySpellings: Set<String> = [
        "colour", "colours", "coloured", "colouring", "colourful",
        "favour", "favours", "favoured", "favouring", "favourite", "favourites",
        "honour", "honours", "honoured", "honouring", "honourable",
        "grey", "greys",
        "tyre", "tyres",
        "aluminium",
        "mum", "mums",
        "aeroplane", "aeroplanes",
        "gaol", "gaols",
        "pyjamas",
    ]

    /// Check if a word is spelled correctly.
    /// - Parameter word: The word to check
    /// - Returns: true if word is in dictionary, false otherwise
    func isCorrect(word: String) -> Bool {
        let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Empty or single character words are considered correct
        if normalized.isEmpty || normalized.count == 1 {
            return true
        }

        // Numbers are correct
        if normalized.allSatisfy({ $0.isNumber }) {
            return true
        }

        // Check common contractions (these are always correct)
        if commonContractions.contains(normalized) {
            return true
        }

        // Check common conversational words (always correct)
        if commonConversationalWords.contains(normalized) {
            return true
        }

        // Check against dictionary
        if wordSet.contains(normalized) {
            return true
        }

        // For words with apostrophes, also check the base word
        if normalized.contains("'") {
            let parts = normalized.split(separator: "'")
            if parts.count == 2 {
                let base = String(parts[0])
                // If base is in dictionary, likely a valid contraction
                if wordSet.contains(base) || commonConversationalWords.contains(base) {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Common Words Lists

    /// Common contractions that are always correct
    private let commonContractions: Set<String> = [
        // I contractions
        "i'm", "i've", "i'll", "i'd",
        // You contractions
        "you're", "you've", "you'll", "you'd",
        // We contractions
        "we're", "we've", "we'll", "we'd",
        // They contractions
        "they're", "they've", "they'll", "they'd",
        // He/She/It contractions
        "he's", "he'll", "he'd", "she's", "she'll", "she'd", "it's", "it'll",
        // Not contractions
        "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't",
        "won't", "wouldn't", "don't", "doesn't", "didn't", "can't", "couldn't",
        "shouldn't", "mightn't", "mustn't", "shan't", "needn't",
        // Other contractions
        "that's", "there's", "here's", "what's", "who's", "how's", "where's",
        "let's", "that'll", "there'll", "who'll", "what'll",
        "ain't", "gonna", "wanna", "gotta", "kinda", "sorta",
        "could've", "would've", "should've", "might've", "must've",
        "y'all", "ma'am", "ne'er", "e'er", "o'clock",
    ]

    /// Common conversational words that might be missing from technical dictionaries
    private let commonConversationalWords: Set<String> = [
        // Common words
        "yeah", "yep", "nope", "okay", "ok", "nah", "uh", "um", "hmm", "huh",
        "wow", "whoa", "oops", "ouch", "ugh", "yay", "hey", "hi", "hello", "bye",
        // Pronouns and basics
        "i", "me", "my", "mine", "we", "us", "our", "ours",
        "you", "your", "yours", "he", "him", "his", "she", "her", "hers",
        "it", "its", "they", "them", "their", "theirs",
        // Common verbs
        "am", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "having", "do", "does", "did", "doing",
        "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "get", "got", "getting", "go", "goes", "went", "going", "gone",
        "come", "came", "coming", "make", "made", "making",
        "take", "took", "taking", "taken", "give", "gave", "giving", "given",
        "see", "saw", "seeing", "seen", "think", "thought", "thinking",
        "know", "knew", "knowing", "known", "feel", "felt", "feeling",
        "want", "wanted", "wanting", "need", "needed", "needing",
        "say", "said", "saying", "tell", "told", "telling",
        // Common adjectives
        "good", "bad", "great", "nice", "fine", "okay",
        "big", "small", "little", "large", "long", "short",
        "old", "new", "young", "high", "low",
        "right", "wrong", "true", "false",
        "happy", "sad", "angry", "tired", "sick",
        // Common nouns
        "thing", "things", "stuff", "way", "ways", "time", "times",
        "day", "days", "night", "nights", "week", "weeks", "month", "months", "year", "years",
        "man", "men", "woman", "women", "person", "people", "child", "children",
        "baby", "babies", "kid", "kids", "guy", "guys", "girl", "girls", "boy", "boys",
        "mum", "mom", "dad", "father", "mother", "brother", "sister", "family",
        "friend", "friends", "mate", "mates",
        "place", "places", "home", "house", "room", "rooms",
        "money", "job", "work", "life",
        // Common adverbs
        "very", "really", "quite", "pretty", "just", "only", "even", "still",
        "also", "too", "now", "then", "here", "there", "always", "never",
        "sometimes", "often", "usually", "probably", "maybe", "perhaps",
        "actually", "basically", "literally", "seriously", "honestly",
        // Common prepositions
        "in", "on", "at", "to", "for", "with", "from", "by", "about", "into",
        "through", "during", "before", "after", "above", "below", "between",
        // Common conjunctions
        "and", "or", "but", "so", "because", "if", "when", "while", "although",
        // Slang/informal (UK/Irish)
        "bloody", "bloody", "blimey", "bollocks", "bugger", "crikey",
        "shitty", "crappy", "fucking", "fuck", "shit", "damn", "crap",
        "brilliant", "lovely", "cheers", "mate", "innit", "dunno", "reckon",
        "quid", "fiver", "tenner", "grand",
        // Common Irish/UK terms
        "mam", "da", "gran", "granny", "grandad", "nanny",
        "pub", "pint", "cuppa", "brekkie", "sarnie", "biscuit", "biscuits",
        "telly", "loo", "bin", "rubbish", "queue", "lift", "flat",
        "holiday", "holidays", "fortnight",
        // Medical/body (commonly discussed)
        "piles", "hemorrhoid", "hemorrhoids", "ointment", "cream",
        // Tech/modern
        "wifi", "internet", "app", "apps", "phone", "laptop", "email", "online",
        "google", "youtube", "facebook", "twitter", "instagram",
    ]

    /// Get spelling suggestions for a misspelled word.
    /// Uses Levenshtein distance to find similar words.
    /// - Parameters:
    ///   - word: The misspelled word
    ///   - limit: Maximum number of suggestions to return (default 5)
    /// - Returns: Array of suggested words, sorted by edit distance (closest first)
    func suggest(word: String, limit: Int = 5) -> [String] {
        let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        guard !normalized.isEmpty else {
            return []
        }

        // Collect candidates within edit distance 1-2
        var candidates: [(word: String, distance: Int)] = []

        for dictWord in wordSet {
            // Skip words with very different lengths (optimization)
            let lengthDiff = abs(dictWord.count - normalized.count)
            if lengthDiff > 2 {
                continue
            }

            let distance = levenshteinDistance(normalized, dictWord)

            // Only include words within distance 1-2
            if distance >= 1 && distance <= 2 {
                candidates.append((word: dictWord, distance: distance))
            }
        }

        // Sort by distance (closest first), then alphabetically for ties
        candidates.sort { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            return lhs.word < rhs.word
        }

        // Return up to limit suggestions
        return Array(candidates.prefix(limit).map { $0.word })
    }

    /// Add a word to the custom dictionary.
    /// - Parameter word: The word to add
    func addToCustomDictionary(word: String) async {
        guard let db = db else {
            print("[SpellEngine] No database connection")
            return
        }

        let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        guard !normalized.isEmpty else {
            return
        }

        // Add to in-memory set
        wordSet.insert(normalized)

        // Persist to database
        let sql = """
        INSERT OR IGNORE INTO custom_dictionary (id, word, added_at)
        VALUES (?, ?, ?)
        """

        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        do {
            try db.run(sql, id, normalized, timestamp)
            print("[SpellEngine] Added '\(normalized)' to custom dictionary")
        } catch {
            print("[SpellEngine] Failed to add word to custom dictionary: \(error)")
        }
    }

    /// Remove a word from the custom dictionary.
    /// - Parameter word: The word to remove
    func removeFromCustomDictionary(word: String) async {
        guard let db = db else {
            print("[SpellEngine] No database connection")
            return
        }

        let normalized = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Remove from in-memory set
        wordSet.remove(normalized)

        // Remove from database
        let sql = "DELETE FROM custom_dictionary WHERE word = ?"

        do {
            try db.run(sql, normalized)
            print("[SpellEngine] Removed '\(normalized)' from custom dictionary")
        } catch {
            print("[SpellEngine] Failed to remove word from custom dictionary: \(error)")
        }
    }

    /// Get all words in the custom dictionary.
    /// - Returns: Array of custom dictionary words
    func getCustomDictionaryWords() async -> [String] {
        guard let db = db else {
            return []
        }

        var words: [String] = []

        let sql = "SELECT word FROM custom_dictionary ORDER BY word ASC"

        do {
            let stmt = try db.prepare(sql)
            for row in stmt {
                if let word = row[0] as? String {
                    words.append(word)
                }
            }
        } catch {
            print("[SpellEngine] Failed to get custom dictionary words: \(error)")
        }

        return words
    }

    /// Check if dictionary has been loaded.
    func isDictionaryLoaded() -> Bool {
        return isLoaded
    }

    /// Get the number of words in the dictionary.
    func wordCount() -> Int {
        return wordSet.count
    }

    // MARK: - Levenshtein Distance

    /// Calculate the Levenshtein (edit) distance between two strings.
    /// This is the minimum number of single-character edits (insertions, deletions, or substitutions)
    /// required to change one string into the other.
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: The edit distance between the two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)

        let m = s1Array.count
        let n = s2Array.count

        // Handle edge cases
        if m == 0 { return n }
        if n == 0 { return m }

        // Create distance matrix
        // Using two rows for space optimization
        var previousRow = Array(0...n)
        var currentRow = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            currentRow[0] = i

            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1

                currentRow[j] = min(
                    currentRow[j - 1] + 1,      // insertion
                    previousRow[j] + 1,          // deletion
                    previousRow[j - 1] + cost    // substitution
                )
            }

            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }
}
