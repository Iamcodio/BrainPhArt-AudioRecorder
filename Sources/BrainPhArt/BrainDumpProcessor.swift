import Foundation

/// Brain Dump Processor - Integrates with existing Brain Dump workflow
/// Uses KEYWORD MATCHING for domain classification (fast, reliable)
/// Uses local Ollama ONLY for simple privacy yes/no detection
/// Maintains privacy: everything processed locally, user controls what's public
actor BrainDumpProcessor {

    static let shared = BrainDumpProcessor()

    // MARK: - Domain Classification (Keyword-based, NOT LLM)

    /// The 5 domains from the brain dump system
    enum Domain: String, CaseIterable {
        case mentalHealth = "MENTAL_HEALTH"
        case businessTechnical = "BUSINESS_TECHNICAL"
        case personalSocial = "PERSONAL_SOCIAL"
        case financialTasks = "FINANCIAL_TASKS"
        case creativeIdeas = "CREATIVE_IDEAS"

        var displayName: String {
            switch self {
            case .mentalHealth: return "Mental Health"
            case .businessTechnical: return "Business/Technical"
            case .personalSocial: return "Personal/Social"
            case .financialTasks: return "Financial/Tasks"
            case .creativeIdeas: return "Creative/Ideas"
            }
        }

        var emoji: String {
            switch self {
            case .mentalHealth: return "🧠"
            case .businessTechnical: return "💼"
            case .personalSocial: return "👥"
            case .financialTasks: return "💰"
            case .creativeIdeas: return "🎨"
            }
        }

        /// Keywords that indicate this domain (for fast local classification)
        var keywords: [String] {
            switch self {
            case .mentalHealth:
                return ["anxiety", "depression", "therapy", "medication", "meds", "xanax",
                        "sleep", "suds", "mood", "feeling", "emotional", "mental", "recovery",
                        "trauma", "ptsd", "panic", "stress", "overwhelm", "exhausted",
                        "psychiatrist", "psychologist", "counselor", "mindfulness", "meditation"]
            case .businessTechnical:
                return ["code", "project", "api", "server", "database", "github", "deploy",
                        "revenue", "business", "startup", "market", "product", "customer",
                        "technical", "software", "app", "website", "seo", "marketing",
                        "extrophi", "matrix", "ollama", "claude", "whisper", "swift"]
            case .personalSocial:
                return ["friend", "family", "relationship", "social", "conversation",
                        "mum", "dad", "brother", "sister", "partner", "wife", "husband",
                        "community", "people", "trust", "connection", "lonely", "together"]
            case .financialTasks:
                return ["money", "budget", "expense", "income", "payment", "debt", "savings",
                        "euro", "pound", "dollar", "welfare", "benefit", "rent", "bill",
                        "task", "todo", "priority", "deadline", "schedule", "appointment"]
            case .creativeIdeas:
                return ["idea", "creative", "write", "book", "blog", "content", "story",
                        "innovation", "concept", "vision", "imagine", "design", "art",
                        "poetry", "music", "inspiration", "breakthrough", "insight"]
            }
        }
    }

    /// 4D Classification coordinates
    struct FourDCoordinates {
        let clarity: Int      // How clear and well-defined (0-10)
        let impact: Int       // How much this matters (0-10)
        let actionable: Int   // Can be acted on (0-10)
        let universal: Int    // Applies beyond personal context (0-10)

        var formatted: String {
            "C:\(clarity), I:\(impact), A:\(actionable), U:\(universal)"
        }

        var averageScore: Double {
            Double(clarity + impact + actionable + universal) / 4.0
        }
    }

    /// A classified insight from the brain dump
    struct ClassifiedInsight {
        let content: String
        let domain: Domain
        let coordinates: FourDCoordinates
        let isPrivate: Bool
        let suggestedPrivacyReason: String?
    }

    /// Baseline metrics from brain dump
    struct BaselineMetrics {
        var sleepHours: Double?
        var sleepQuality: String?
        var exercise: Bool?
        var exerciseDuration: Int?
        var daylight: Bool?
        var sudsLevel: Int?  // 0-10
        var energyLevel: Int?  // 1-5
        var outlookLevel: Int?  // 1-5
    }

    // MARK: - Processing (Keyword-based, fast, works offline)

    /// Process a transcript using KEYWORD MATCHING for domains
    /// and simple LLM prompt for privacy detection
    func processTranscript(_ transcript: String) async -> [ClassifiedInsight] {
        let thoughts = TranscriptParser.extractAtomicThoughts(transcript)

        var insights: [ClassifiedInsight] = []

        for thought in thoughts {
            // Domain classification: KEYWORDS (fast, no LLM needed)
            let domain = classifyDomainByKeywords(thought)

            // Privacy detection: Simple LLM yes/no OR regex fallback
            let (isPrivate, reason) = await detectPrivacy(thought)

            // 4D scores: Heuristic based on content (no LLM needed)
            let coords = estimateFourD(thought, domain: domain)

            insights.append(ClassifiedInsight(
                content: thought,
                domain: domain,
                coordinates: coords,
                isPrivate: isPrivate,
                suggestedPrivacyReason: reason
            ))
        }

        return insights
    }

    /// Classify domain using KEYWORD MATCHING (fast, reliable, works offline)
    func classifyDomainByKeywords(_ text: String) -> Domain {
        let lower = text.lowercased()
        var scores: [Domain: Int] = [:]

        for domain in Domain.allCases {
            let count = domain.keywords.filter { lower.contains($0) }.count
            scores[domain] = count
        }

        // Return domain with highest keyword match, default to creative
        if let best = scores.max(by: { $0.value < $1.value }), best.value > 0 {
            return best.key
        }
        return .creativeIdeas
    }

    /// Detect privacy using SIMPLE prompt that works with 7B models
    /// Falls back to regex if LLM fails
    private func detectPrivacy(_ text: String) async -> (Bool, String?) {
        // First try full scan: regex + topic keywords (instant, no LLM needed)
        let regexMatches = PrivacyScanner.fullScan(text)
        if !regexMatches.isEmpty {
            let types = regexMatches.map { $0.patternName }.joined(separator: ", ")
            return (true, "Contains: \(types)")
        }

        // Simple LLM prompt - just YES or NO
        // This is all a 7B model can reliably handle
        let prompt = """
        Does this text contain private information like names, addresses, medical details, or financial amounts?
        Text: "\(text.prefix(300))"
        Answer only YES or NO.
        """

        do {
            let response = try await OllamaClient.shared.generate(prompt: prompt, model: nil)
            let answer = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            if answer.contains("YES") {
                return (true, "LLM flagged as private")
            } else {
                return (false, nil)
            }
        } catch {
            // LLM failed, default to checking for personal words
            let personalWords = ["my", "i ", "me ", "we ", "our "]
            let hasPersonal = personalWords.contains { text.lowercased().contains($0) }
            return (hasPersonal, hasPersonal ? "Contains personal pronouns" : nil)
        }
    }

    /// Estimate 4D coordinates using HEURISTICS (no LLM needed)
    private func estimateFourD(_ text: String, domain: Domain) -> FourDCoordinates {
        let wordCount = text.split(separator: " ").count
        let hasActionWords = ["should", "need to", "must", "will", "going to", "plan to"]
            .contains { text.lowercased().contains($0) }
        let hasQuestion = text.contains("?")

        // Clarity: longer, more detailed = clearer
        let clarity = min(10, max(3, wordCount / 3))

        // Impact: domain-based defaults
        let impact: Int
        switch domain {
        case .mentalHealth: impact = 8  // Mental health always high impact
        case .businessTechnical: impact = 7
        case .financialTasks: impact = 7
        case .personalSocial: impact = 6
        case .creativeIdeas: impact = 5
        }

        // Actionable: contains action words
        let actionable = hasActionWords ? 8 : (hasQuestion ? 4 : 5)

        // Universal: shorter insights tend to be more universal
        let universal = wordCount < 20 ? 7 : (wordCount < 50 ? 5 : 3)

        return FourDCoordinates(
            clarity: clarity,
            impact: impact,
            actionable: actionable,
            universal: universal
        )
    }

    // MARK: - Export

    /// Generate markdown archive in the brain dump format
    func generateArchive(
        date: Date,
        insights: [ClassifiedInsight],
        metrics: BaselineMetrics?
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        var output = """
        # Daily Brain Dump Archive - \(dateString)

        """

        // Metrics section
        if let m = metrics {
            output += """
            ## DAILY METRICS
            **Sleep:** \(m.sleepHours.map { String($0) } ?? "N/A") hours / Quality: \(m.sleepQuality ?? "N/A")
            **Exercise:** \(m.exercise == true ? "Yes" : "No") / Duration: \(m.exerciseDuration.map { "\($0) mins" } ?? "N/A") / Daylight: \(m.daylight == true ? "Yes" : "No")
            **SUDS (Anxiety):** \(m.sudsLevel.map { String($0) } ?? "N/A")/10
            **Energy:** \(m.energyLevel.map { String($0) } ?? "N/A")/5
            **Outlook:** \(m.outlookLevel.map { String($0) } ?? "N/A")/5

            ---

            """
        }

        // Group insights by domain
        for domain in Domain.allCases {
            let domainInsights = insights.filter { $0.domain == domain }
            if !domainInsights.isEmpty {
                output += """

                ## \(domain.emoji) \(domain.displayName.uppercased()) DOMAIN

                """

                for insight in domainInsights {
                    let privacyTag = insight.isPrivate ? " [PRIVATE]" : ""
                    output += """
                    - \(insight.content)\(privacyTag)
                      (\(insight.coordinates.formatted))

                    """
                }
            }
        }

        // Actionable items
        let actionableInsights = insights
            .filter { $0.coordinates.actionable >= 7 }
            .sorted { $0.coordinates.impact > $1.coordinates.impact }

        if !actionableInsights.isEmpty {
            output += """

            ## ACTIONABLE ITEMS

            """
            for insight in actionableInsights.prefix(10) {
                let priority = insight.coordinates.impact >= 8 ? "HIGH" : (insight.coordinates.impact >= 6 ? "MEDIUM" : "LOW")
                output += "- [ ] \(insight.content) [\(priority)]\n"
            }
        }

        // Public-ready content
        let publicInsights = insights
            .filter { !$0.isPrivate && $0.coordinates.universal >= 6 }
            .sorted { $0.coordinates.averageScore > $1.coordinates.averageScore }

        if !publicInsights.isEmpty {
            output += """

            ## PUBLIC-READY CONTENT (for blog/book)

            """
            for insight in publicInsights.prefix(10) {
                output += "- \(insight.content)\n"
            }
        }

        output += """

        ---
        **Processed with BrainPhArt** - Local-first, privacy-controlled brain dump processing
        """

        return output
    }

    /// Save archive to the brain dump sessions folder
    func saveArchive(_ content: String, date: Date) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let monthFolder = formatter.string(from: date)

        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        let basePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("09-personal/BrainDumpSessions/sessions")
            .appendingPathComponent(monthFolder)

        // Create folder if needed
        try FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true)

        let filePath = basePath.appendingPathComponent("\(dateString)_brain_dump_archive.md")

        try content.write(to: filePath, atomically: true, encoding: .utf8)
        print("[BrainDumpProcessor] Saved archive to: \(filePath.path)")
    }

    // MARK: - Quick Analysis

    /// Quick domain classification - just uses keywords (no LLM)
    func quickClassify(_ text: String) -> Domain {
        return classifyDomainByKeywords(text)
    }

    /// Check if text is likely private (quick check, no LLM)
    func quickPrivacyCheck(_ text: String) -> Bool {
        // Full scan: regex + topic keywords
        return !PrivacyScanner.fullScan(text).isEmpty ||
               PrivacyScanner.containsPrivateTopics(text)
    }
}
