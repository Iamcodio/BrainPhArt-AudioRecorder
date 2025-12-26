import Foundation

/// Grammar checking engine
/// - Rule-based for common errors (fast, offline)
/// - Optional LanguageTool API for comprehensive checking
actor GrammarEngine {

    static let shared = GrammarEngine()

    // MARK: - Grammar Issue

    struct GrammarIssue {
        let message: String
        let suggestion: String?
        let startOffset: Int
        let endOffset: Int
        let ruleId: String
    }

    // MARK: - Rule-Based Checks (Fast, Offline)

    /// Common grammar patterns to check
    private let rules: [(pattern: String, message: String, suggestion: String?)] = [
        // Double words
        (#"\b(\w+)\s+\1\b"#, "Repeated word", nil),

        // Missing capital after period
        (#"\.\s+[a-z]"#, "Sentence should start with capital", nil),

        // Common confused words
        (#"\btheir\s+is\b"#, "Did you mean 'there is'?", "there is"),
        (#"\btheir\s+are\b"#, "Did you mean 'there are'?", "there are"),
        (#"\bits\s+a\b(?!\s+lot)"#, "Check: 'its' (possessive) vs 'it's' (it is)", nil),
        (#"\byour\s+welcome\b"#, "Did you mean 'you're welcome'?", "you're welcome"),
        (#"\byour\s+(?:right|wrong|going|doing)\b"#, "Did you mean 'you're'?", nil),
        (#"\bcould\s+of\b"#, "Did you mean 'could have'?", "could have"),
        (#"\bwould\s+of\b"#, "Did you mean 'would have'?", "would have"),
        (#"\bshould\s+of\b"#, "Did you mean 'should have'?", "should have"),

        // Common typos
        (#"\bteh\b"#, "Did you mean 'the'?", "the"),
        (#"\bwich\b"#, "Did you mean 'which'?", "which"),
        (#"\bbeacuse\b"#, "Did you mean 'because'?", "because"),
        (#"\bdefinate\b"#, "Did you mean 'definite'?", "definite"),
        (#"\bseperate\b"#, "Did you mean 'separate'?", "separate"),
        (#"\boccured\b"#, "Did you mean 'occurred'?", "occurred"),
        (#"\buntill\b"#, "Did you mean 'until'?", "until"),
        (#"\brecieve\b"#, "Did you mean 'receive'?", "receive"),

        // Subject-verb agreement (simple cases)
        (#"\bi\s+is\b"#, "Subject-verb disagreement", "I am"),
        (#"\bhe\s+are\b"#, "Subject-verb disagreement", "he is"),
        (#"\bshe\s+are\b"#, "Subject-verb disagreement", "she is"),
        (#"\bthey\s+is\b"#, "Subject-verb disagreement", "they are"),
        (#"\bwe\s+is\b"#, "Subject-verb disagreement", "we are"),

        // Missing articles (basic)
        (#"\b(?:is|was)\s+(?:good|bad|great|nice|big|small)\s+(?:idea|thing|place|person)\b"#,
         "Consider adding an article (a/an/the)", nil),
    ]

    /// Check text using rule-based patterns (fast, offline)
    func checkRules(_ text: String) -> [GrammarIssue] {
        var issues: [GrammarIssue] = []
        let lowerText = text.lowercased()

        for (pattern, message, suggestion) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: lowerText, options: [], range: range)

            for match in matches {
                guard let matchRange = Range(match.range, in: text) else { continue }

                let startOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
                let endOffset = text.distance(from: text.startIndex, to: matchRange.upperBound)

                issues.append(GrammarIssue(
                    message: message,
                    suggestion: suggestion,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    ruleId: "RULE_BASED"
                ))
            }
        }

        return issues.sorted { $0.startOffset < $1.startOffset }
    }

    // MARK: - LanguageTool API (Optional, more comprehensive)

    /// LanguageTool API endpoint (local or cloud)
    private var languageToolURL: URL? = URL(string: "http://localhost:8081/v2/check")

    /// Check if LanguageTool is available locally
    func isLanguageToolAvailable() async -> Bool {
        guard let url = languageToolURL else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2  // Quick timeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode < 500
            }
            return false
        } catch {
            return false
        }
    }

    /// Check text using LanguageTool API (if available)
    func checkWithLanguageTool(_ text: String) async -> [GrammarIssue] {
        guard let url = languageToolURL else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&language=en-GB"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let matches = json["matches"] as? [[String: Any]] else {
                return []
            }

            return matches.compactMap { match -> GrammarIssue? in
                guard let message = match["message"] as? String,
                      let offset = match["offset"] as? Int,
                      let length = match["length"] as? Int,
                      let rule = match["rule"] as? [String: Any],
                      let ruleId = rule["id"] as? String else {
                    return nil
                }

                var suggestion: String? = nil
                if let replacements = match["replacements"] as? [[String: Any]],
                   let first = replacements.first,
                   let value = first["value"] as? String {
                    suggestion = value
                }

                return GrammarIssue(
                    message: message,
                    suggestion: suggestion,
                    startOffset: offset,
                    endOffset: offset + length,
                    ruleId: ruleId
                )
            }
        } catch {
            print("[GrammarEngine] LanguageTool error: \(error)")
            return []
        }
    }

    // MARK: - Combined Check

    /// Full grammar check: rules first, then LanguageTool if available
    func fullCheck(_ text: String) async -> [GrammarIssue] {
        // Always do rule-based (instant)
        var issues = checkRules(text)

        // Try LanguageTool if available
        if await isLanguageToolAvailable() {
            let ltIssues = await checkWithLanguageTool(text)
            issues.append(contentsOf: ltIssues)
        }

        // Deduplicate by position
        var seen = Set<Int>()
        return issues
            .sorted { $0.startOffset < $1.startOffset }
            .filter { issue in
                if seen.contains(issue.startOffset) { return false }
                seen.insert(issue.startOffset)
                return true
            }
    }

    // MARK: - Configuration

    /// Set custom LanguageTool URL (e.g., local server)
    func setLanguageToolURL(_ url: String) {
        languageToolURL = URL(string: url)
    }
}
