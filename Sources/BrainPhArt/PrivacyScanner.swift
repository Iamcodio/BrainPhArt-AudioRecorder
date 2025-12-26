import Foundation

/// Represents a detected PII match in text
struct PIIMatch {
    let patternName: String
    let matchedText: String
    let startOffset: Int
    let endOffset: Int
}

/// Auto-detects potential PII (personally identifiable information) in text
struct PrivacyScanner {

    /// Regex patterns for common PII types
    static let patterns: [String: String] = [
        "SSN": #"\d{3}-\d{2}-\d{4}"#,
        "Credit Card": #"\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}"#,
        "Email": #"\w+@\w+\.\w+"#,
        "Phone": #"\(?\d{3}\)?[\s-]?\d{3}[\s-]?\d{4}"#,
        "IP Address": #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#,
        // Money patterns - catches £4,000, $50, €100, etc.
        "Currency": #"[£$€]\s?\d[\d,\.]*"#,
        "Money Words": #"\d[\d,\.]*\s*(pounds?|dollars?|euros?|quid|grand|k\b)"#
    ]

    /// Topic keywords that suggest private/sensitive content
    static let privateTopics: [String: [String]] = [
        "Medical": [
            "doctor", "hospital", "medication", "prescription", "diagnosis",
            "hemorrhoid", "piles", "ointment", "cream", "suppository",
            "blood", "symptom", "disease", "illness", "surgery", "operation",
            "therapist", "psychiatrist", "counselor", "psychologist",
            "xanax", "antidepressant", "ssri", "prozac", "valium",
            "cancer", "tumor", "biopsy", "scan", "mri", "x-ray"
        ],
        "Mental Health": [
            "depressed", "depression", "anxiety", "anxious", "panic attack",
            "suicidal", "self-harm", "cutting", "overdose", "breakdown",
            "mental health", "bipolar", "schizophrenia", "ptsd", "trauma",
            "feel low", "feel down", "can't cope", "hopeless", "worthless"
        ],
        "Financial": [
            "salary", "income", "debt", "loan", "mortgage", "bank account",
            "stock market", "trading", "investment", "portfolio", "shares",
            "tax return", "owe money", "credit score", "bankruptcy",
            "made money", "lost money", "profit", "bonus"
        ],
        "Embarrassing": [
            "anus", "rectum", "rectal", "bowel", "constipation", "diarrhea",
            "penis", "vagina", "genitals", "erectile", "impotent",
            "std", "herpes", "chlamydia", "gonorrhea", "hiv",
            "vomit", "puke", "shit myself", "wet myself", "incontinence"
        ],
        "Legal": [
            "arrested", "court case", "lawsuit", "criminal record",
            "police", "prison", "jail", "conviction", "probation",
            "lawyer", "solicitor", "court order", "restraining order"
        ],
        "Addiction": [
            "alcoholic", "addict", "addiction", "rehab", "withdrawal",
            "cocaine", "heroin", "meth", "overdose", "relapse",
            "aa meeting", "na meeting", "sponsor", "sober", "recovery"
        ]
    ]

    /// Scans text for potential PII matches
    /// - Parameter text: The text to scan for PII
    /// - Returns: Array of PIIMatch objects for user review
    static func scan(_ text: String) -> [PIIMatch] {
        var matches: [PIIMatch] = []

        for (patternName, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let results = regex.matches(in: text, options: [], range: range)

            for result in results {
                guard let matchRange = Range(result.range, in: text) else {
                    continue
                }

                let matchedText = String(text[matchRange])
                let startOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
                let endOffset = text.distance(from: text.startIndex, to: matchRange.upperBound)

                let match = PIIMatch(
                    patternName: patternName,
                    matchedText: matchedText,
                    startOffset: startOffset,
                    endOffset: endOffset
                )
                matches.append(match)
            }
        }

        // Sort by start offset for consistent ordering
        return matches.sorted { $0.startOffset < $1.startOffset }
    }

    /// Scans text for TOPIC-based privacy concerns (medical, financial, embarrassing, etc.)
    /// Returns matches for sensitive topics found in the text
    static func scanTopics(_ text: String) -> [PIIMatch] {
        var matches: [PIIMatch] = []
        let lowerText = text.lowercased()

        for (category, keywords) in privateTopics {
            for keyword in keywords {
                // Find all occurrences of this keyword
                var searchRange = lowerText.startIndex..<lowerText.endIndex

                while let range = lowerText.range(of: keyword, options: [], range: searchRange) {
                    let startOffset = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound)
                    let endOffset = lowerText.distance(from: lowerText.startIndex, to: range.upperBound)

                    // Get the actual text from original (preserves case)
                    let originalRange = text.index(text.startIndex, offsetBy: startOffset)..<text.index(text.startIndex, offsetBy: endOffset)
                    let matchedText = String(text[originalRange])

                    matches.append(PIIMatch(
                        patternName: "Topic:\(category)",
                        matchedText: matchedText,
                        startOffset: startOffset,
                        endOffset: endOffset
                    ))

                    // Move search range forward
                    searchRange = range.upperBound..<lowerText.endIndex
                }
            }
        }

        // Remove duplicates (same position)
        var seen = Set<Int>()
        matches = matches.filter { match in
            if seen.contains(match.startOffset) {
                return false
            }
            seen.insert(match.startOffset)
            return true
        }

        return matches.sorted { $0.startOffset < $1.startOffset }
    }

    /// Full scan: regex patterns + topic keywords
    static func fullScan(_ text: String) -> [PIIMatch] {
        var allMatches = scan(text)  // Regex patterns
        allMatches.append(contentsOf: scanTopics(text))  // Topic keywords

        // Sort and deduplicate by position
        var seen = Set<Int>()
        return allMatches
            .sorted { $0.startOffset < $1.startOffset }
            .filter { match in
                if seen.contains(match.startOffset) {
                    return false
                }
                seen.insert(match.startOffset)
                return true
            }
    }

    /// Quick check: does text contain ANY private topics?
    static func containsPrivateTopics(_ text: String) -> Bool {
        let lowerText = text.lowercased()

        for (_, keywords) in privateTopics {
            for keyword in keywords {
                if lowerText.contains(keyword) {
                    return true
                }
            }
        }
        return false
    }

    /// Uses local LLM to classify text for privacy concerns
    /// - Parameter text: The transcript text to analyze
    /// - Returns: Array of PIIMatch objects identified by the LLM
    static func classifyWithLLM(_ text: String) async -> [PIIMatch] {
        let prompt = """
        Analyze the following text and identify any private or sensitive information.

        For each piece of sensitive information found, output a line in this exact format:
        TYPE|MATCHED_TEXT

        Valid types are: Name, Address, Phone, Email, SSN, Credit Card, Medical, Financial, Password, Location

        If no sensitive information is found, respond with: NONE

        Text to analyze:
        ---
        \(text)
        ---

        Respond ONLY with the formatted lines or NONE, nothing else.
        """

        do {
            let response = try await OllamaClient.shared.generate(prompt: prompt, model: "dolphin3:latest")
            return parseLLMResponse(response, originalText: text)
        } catch {
            print("LLM classification failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Parses the LLM response into PIIMatch objects
    private static func parseLLMResponse(_ response: String, originalText: String) -> [PIIMatch] {
        var matches: [PIIMatch] = []

        let lines = response.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            // Skip if response indicates no matches
            if line.uppercased() == "NONE" {
                continue
            }

            let parts = line.components(separatedBy: "|")
            guard parts.count == 2 else {
                continue
            }

            let piiType = parts[0].trimmingCharacters(in: .whitespaces)
            let matchedText = parts[1].trimmingCharacters(in: .whitespaces)

            // Find the matched text in the original to get offsets
            if let range = originalText.range(of: matchedText) {
                let startOffset = originalText.distance(from: originalText.startIndex, to: range.lowerBound)
                let endOffset = originalText.distance(from: originalText.startIndex, to: range.upperBound)

                let match = PIIMatch(
                    patternName: "LLM:\(piiType)",
                    matchedText: matchedText,
                    startOffset: startOffset,
                    endOffset: endOffset
                )
                matches.append(match)
            } else {
                // If we can't find exact match, still record it with offset 0
                let match = PIIMatch(
                    patternName: "LLM:\(piiType)",
                    matchedText: matchedText,
                    startOffset: 0,
                    endOffset: matchedText.count
                )
                matches.append(match)
            }
        }

        return matches.sorted { $0.startOffset < $1.startOffset }
    }
}
