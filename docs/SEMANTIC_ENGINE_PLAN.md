# Semantic Engine Integration Plan
## Named Entity Recognition (NER) for BrainPhArt Privacy Scanner

**Document Version:** 1.0
**Created:** December 26, 2025
**Purpose:** Evaluate and plan integration of NER capabilities for enhanced PII detection
**Constraint:** LOCAL PROCESSING ONLY - Nothing leaves the device

---

## Executive Summary

The current `PrivacyScanner.swift` uses regex patterns and keyword matching for PII detection. This plan evaluates three approaches to add Named Entity Recognition (NER) for improved detection of names, addresses, and contextual entities.

**Recommended Approach:** Hybrid - Apple NLTagger for immediate use + Presidio Python Server for advanced detection.

---

## Current State Analysis

### Existing PrivacyScanner.swift Capabilities

**File Location:** `/Users/kjd/01-projects/IAC-001-a-BrainPh-art-Audio-Recorder/Sources/BrainPhArt/PrivacyScanner.swift`

**Current Detection Methods:**
1. **Regex Patterns** - SSN, Credit Card, Email, Phone, IP Address, Currency
2. **Keyword Matching** - Medical, Mental Health, Financial, Embarrassing, Legal, Addiction topics
3. **LLM Classification** - Uses local Ollama (dolphin3) for semantic analysis

**Limitations:**
- Cannot detect person names without explicit keyword
- Cannot detect organization names
- Cannot detect location/address references without patterns
- No understanding of context (e.g., "Dr. Smith called" vs. "Smith & Sons Ltd")

---

## Architecture Options

### Option 1: Presidio Python Server (Local REST API)

**Description:** Run Microsoft Presidio as a local Python Flask/FastAPI server, call from Swift via HTTP.

**Architecture:**
```
+----------------+     HTTP (localhost:5000)     +------------------+
| Swift App      | <-------------------------->  | Presidio Server  |
| (BrainPhArt)   |                               | (Python/Flask)   |
+----------------+                               +------------------+
                                                        |
                                                        v
                                                 +-------------+
                                                 | SpaCy/BERT  |
                                                 | NER Models  |
                                                 +-------------+
```

**Presidio Components Required:**
- `presidio-analyzer` - PII detection engine
- `presidio-anonymizer` - Optional, for redaction
- SpaCy NLP engine (`en_core_web_lg` or `en_core_web_trf`)
- Optional: Transformers (`dslim/bert-base-NER`) for higher accuracy

**Entities Detected:**
| Entity Type | Example | Detection Method |
|-------------|---------|------------------|
| PERSON | "John Smith" | SpaCy/BERT NER |
| LOCATION | "123 Main Street, London" | SpaCy/BERT NER |
| ORGANIZATION | "Microsoft Corporation" | SpaCy/BERT NER |
| EMAIL_ADDRESS | "john@example.com" | Regex |
| PHONE_NUMBER | "+1-555-123-4567" | Regex + Context |
| CREDIT_CARD | "4111-1111-1111-1111" | Regex + Luhn |
| SSN/NI_NUMBER | "123-45-6789" | Regex |
| DATE_TIME | "January 15, 2025" | SpaCy NER |
| MEDICAL_LICENSE | "GMC 1234567" | Regex |

**Pros:**
- Most comprehensive PII detection available
- Presidio is actively maintained by Microsoft
- Supports custom recognizers for UK-specific patterns
- Models run entirely locally
- Can use transformer models (BERT) for higher accuracy
- Already proven in enterprise deployments

**Cons:**
- Requires Python runtime alongside Swift app
- Memory overhead (~500MB-2GB depending on model)
- Startup latency (5-10 seconds to load models)
- Additional complexity in deployment/distribution

**Implementation Effort:** Medium (2-3 days)

**Sources:**
- [Microsoft Presidio Documentation](https://microsoft.github.io/presidio/analyzer/)
- [Presidio Transformers Integration](https://microsoft.github.io/presidio/analyzer/nlp_engines/transformers/)
- [Presidio SpaCy/Stanza Configuration](https://microsoft.github.io/presidio/analyzer/nlp_engines/spacy_stanza/)

---

### Option 2: Apple NLTagger (Native Swift)

**Description:** Use Apple's built-in Natural Language framework for NER, zero external dependencies.

**Architecture:**
```
+----------------+     Direct API Call     +------------------+
| Swift App      | <--------------------->  | NLTagger        |
| (BrainPhArt)   |                         | (NaturalLanguage)|
+----------------+                         +------------------+
                                                   |
                                           (Built into macOS)
```

**Implementation Example:**
```swift
import NaturalLanguage

extension PrivacyScanner {

    /// Uses Apple NLTagger for Named Entity Recognition
    /// Detects: PersonalName, PlaceName, OrganizationName
    static func scanWithNLTagger(_ text: String) -> [PIIMatch] {
        var matches: [PIIMatch] = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, tokenRange in

            guard let tag = tag else { return true }

            let entityType: String?
            switch tag {
            case .personalName:
                entityType = "NER:Person"
            case .placeName:
                entityType = "NER:Location"
            case .organizationName:
                entityType = "NER:Organization"
            default:
                entityType = nil
            }

            if let type = entityType {
                let matchedText = String(text[tokenRange])
                let startOffset = text.distance(from: text.startIndex, to: tokenRange.lowerBound)
                let endOffset = text.distance(from: text.startIndex, to: tokenRange.upperBound)

                matches.append(PIIMatch(
                    patternName: type,
                    matchedText: matchedText,
                    startOffset: startOffset,
                    endOffset: endOffset
                ))
            }

            return true // Continue enumeration
        }

        return matches
    }
}
```

**Entities Detected:**
| Entity Type | NLTag | Example |
|-------------|-------|---------|
| Person | `.personalName` | "John Smith", "Dr. Williams" |
| Location | `.placeName` | "London", "United Kingdom" |
| Organization | `.organizationName` | "Apple", "NHS" |

**Pros:**
- Zero dependencies - built into macOS 10.14+
- Instant startup - no model loading
- Minimal memory overhead
- Native Swift integration
- Runs entirely on-device
- No additional processes to manage

**Cons:**
- Limited entity types (only Person, Place, Organization)
- Cannot detect structured PII (SSN, credit cards) - still need regex
- Less accurate than SpaCy/BERT for complex text
- No customization options
- English-centric (limited multilingual support)

**Implementation Effort:** Low (1 day)

**Sources:**
- [Apple Developer: Identifying People, Places, and Organizations](https://developer.apple.com/documentation/naturallanguage/identifying-people-places-and-organizations)
- [NLTagger Documentation](https://developer.apple.com/documentation/naturallanguage/nltagger)

---

### Option 3: Core ML with Custom NER Model

**Description:** Convert or train a NER model for Core ML, run natively in Swift.

**Architecture:**
```
+----------------+     Core ML API     +------------------+
| Swift App      | <----------------->  | NER.mlmodel     |
| (BrainPhArt)   |                     | (Core ML Model) |
+----------------+                     +------------------+
```

**Model Options:**

1. **Pre-trained from Hugging Face:**
   - `dslim/bert-base-NER` - Good general NER
   - `Jean-Baptiste/roberta-large-ner-english` - High accuracy
   - Convert to Core ML using `coremltools`

2. **Apple Foundation Models Framework (macOS 26+):**
   - New framework announced at WWDC 2025
   - ~3B parameter on-device language model
   - Built-in entity extraction via Content Tagging Adapter
   - Requires macOS 26 or later (Not available until late 2025)

3. **Train Custom Model:**
   - Use Create ML or PyTorch
   - Train on PII-specific dataset
   - Convert to Core ML

**Conversion Example (PyTorch to Core ML):**
```python
import coremltools as ct
from transformers import AutoModelForTokenClassification

# Load BERT NER model
model = AutoModelForTokenClassification.from_pretrained("dslim/bert-base-NER")

# Convert to Core ML
mlmodel = ct.convert(
    model,
    inputs=[ct.TensorType(shape=(1, 512), dtype=np.int32, name="input_ids")],
    convert_to="mlprogram"
)
mlmodel.save("BERT_NER.mlpackage")
```

**Pros:**
- Native Swift integration
- Optimized for Apple Silicon (Neural Engine)
- No external runtime required
- Fast inference

**Cons:**
- Conversion is non-trivial for NER models
- Tokenization must be reimplemented in Swift
- Large model size (200MB-500MB)
- No direct SpaCy-to-CoreML path exists
- Apple Foundation Models require macOS 26+

**Implementation Effort:** High (5-7 days)

**Sources:**
- [Core ML Tools Conversion Guide](https://apple.github.io/coremltools/docs-guides/source/convert-nlp-model.html)
- [Apple Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [WWDC 2025: Foundation Models](https://developer.apple.com/videos/play/wwdc2025/286/)

---

## Comparison Matrix

| Criteria | Presidio Server | Apple NLTagger | Core ML Model |
|----------|-----------------|----------------|---------------|
| **Entity Types** | 50+ built-in | 3 (Person/Place/Org) | Depends on model |
| **Accuracy** | High (BERT option) | Medium | High |
| **Startup Time** | 5-10 seconds | Instant | 1-2 seconds |
| **Memory Usage** | 500MB-2GB | Minimal (~10MB) | 200-500MB |
| **Dependencies** | Python + packages | None | None |
| **Customization** | Extensive | None | Requires retraining |
| **macOS Version** | 10.15+ | 10.14+ | 11.0+ |
| **Implementation** | Medium | Low | High |
| **Maintenance** | Updates via pip | Apple managed | Manual updates |

---

## Recommended Approach: Hybrid Architecture

Given the constraints and requirements, I recommend a **phased hybrid approach**:

### Phase 1: Immediate (Day 1)
**Add Apple NLTagger to PrivacyScanner**

- Zero new dependencies
- Catches person names, locations, organizations
- Complements existing regex patterns
- Can be implemented in 1 hour

```swift
// Add to PrivacyScanner.swift
static func fullScanWithNER(_ text: String) -> [PIIMatch] {
    var allMatches = scan(text)           // Existing regex
    allMatches.append(contentsOf: scanTopics(text))  // Keywords
    allMatches.append(contentsOf: scanWithNLTagger(text))  // NER

    // Deduplicate overlapping matches
    return deduplicateMatches(allMatches)
}
```

### Phase 2: Enhanced Detection (Week 1)
**Add Presidio Python Server**

- For transcripts requiring high-accuracy PII detection
- Run as background daemon (launchd)
- Swift calls via URLSession to localhost

**Server Setup:**
```bash
# Create Python environment
uv venv presidio-env
source presidio-env/bin/activate

# Install Presidio with SpaCy
uv pip install presidio-analyzer presidio-anonymizer
python -m spacy download en_core_web_lg

# Create simple Flask API
# presidio_server.py - see Integration Steps below
```

### Phase 3: Future (macOS 26)
**Apple Foundation Models Integration**

- When macOS 26 ships, evaluate Foundation Models framework
- Content Tagging Adapter provides entity extraction
- Replace Presidio if Apple's solution is sufficient

---

## Integration with Existing PrivacyScanner.swift

### Current Flow:
```
Transcript Text
      |
      v
+------------------+
| PrivacyScanner   |
|   .scan()        |  (Regex patterns)
|   .scanTopics()  |  (Keyword matching)
|   .classifyWithLLM() | (Ollama)
+------------------+
      |
      v
[PIIMatch Array]
```

### Proposed Enhanced Flow:
```
Transcript Text
      |
      v
+------------------+
| PrivacyScanner   |
|   .scan()        |  (Regex patterns)
|   .scanTopics()  |  (Keywords)
|   .scanWithNLTagger() | (Apple NER) <-- NEW
|   .scanWithPresidio() | (Optional) <-- NEW
|   .classifyWithLLM()  | (Ollama backup)
+------------------+
      |
      v
[PIIMatch Array - Deduplicated]
      |
      v
+------------------+
| PrivacyReviewUI  |
| (User confirms)  |
+------------------+
```

### Code Changes Required:

**1. Add NLTagger Extension:**
```swift
// PrivacyScanner.swift - Add import
import NaturalLanguage

// Add new method (see Option 2 implementation above)
static func scanWithNLTagger(_ text: String) -> [PIIMatch]
```

**2. Add Presidio Client (Optional):**
```swift
// New file: PresidioClient.swift
struct PresidioClient {
    static let shared = PresidioClient()

    private let baseURL = URL(string: "http://localhost:5000")!

    func analyze(_ text: String) async throws -> [PIIMatch] {
        var request = URLRequest(url: baseURL.appendingPathComponent("analyze"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["text": text, "language": "en"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let results = try JSONDecoder().decode([PresidioResult].self, from: data)

        return results.map { result in
            PIIMatch(
                patternName: "Presidio:\(result.entity_type)",
                matchedText: result.text,
                startOffset: result.start,
                endOffset: result.end
            )
        }
    }
}

struct PresidioResult: Codable {
    let entity_type: String
    let text: String
    let start: Int
    let end: Int
    let score: Double
}
```

**3. Update fullScan Method:**
```swift
static func fullScanEnhanced(_ text: String) async -> [PIIMatch] {
    var allMatches: [PIIMatch] = []

    // Layer 1: Regex patterns (fastest)
    allMatches.append(contentsOf: scan(text))

    // Layer 2: Topic keywords
    allMatches.append(contentsOf: scanTopics(text))

    // Layer 3: Apple NLTagger NER (fast, built-in)
    allMatches.append(contentsOf: scanWithNLTagger(text))

    // Layer 4: Presidio (if available, optional)
    if await isPresidioAvailable() {
        do {
            let presidioMatches = try await PresidioClient.shared.analyze(text)
            allMatches.append(contentsOf: presidioMatches)
        } catch {
            print("Presidio unavailable, skipping: \(error)")
        }
    }

    // Layer 5: LLM (for complex/contextual detection - optional)
    // let llmMatches = await classifyWithLLM(text)
    // allMatches.append(contentsOf: llmMatches)

    return deduplicateMatches(allMatches)
}

private static func deduplicateMatches(_ matches: [PIIMatch]) -> [PIIMatch] {
    // Remove overlapping matches, prefer higher-confidence sources
    var result: [PIIMatch] = []
    let sorted = matches.sorted { $0.startOffset < $1.startOffset }

    for match in sorted {
        // Check if this overlaps with any existing match
        let overlaps = result.contains { existing in
            match.startOffset < existing.endOffset && match.endOffset > existing.startOffset
        }

        if !overlaps {
            result.append(match)
        }
    }

    return result
}
```

---

## Presidio Server Setup (Detailed)

### Installation Script

Create: `~/brainphart/presidio/setup.sh`
```bash
#!/bin/bash
set -e

PRESIDIO_DIR="$HOME/brainphart/presidio"
mkdir -p "$PRESIDIO_DIR"
cd "$PRESIDIO_DIR"

# Create Python environment using uv
uv venv .venv
source .venv/bin/activate

# Install dependencies
uv pip install flask presidio-analyzer presidio-anonymizer
python -m spacy download en_core_web_lg

echo "Presidio installed successfully!"
```

### Flask Server

Create: `~/brainphart/presidio/server.py`
```python
#!/usr/bin/env python3
"""
Presidio NER Server for BrainPhArt
Runs locally on port 5000
"""

from flask import Flask, request, jsonify
from presidio_analyzer import AnalyzerEngine, RecognizerRegistry
from presidio_analyzer.nlp_engine import NlpEngineProvider

app = Flask(__name__)

# Initialize Presidio with SpaCy
configuration = {
    "nlp_engine_name": "spacy",
    "models": [{"lang_code": "en", "model_name": "en_core_web_lg"}],
}

provider = NlpEngineProvider(nlp_configuration=configuration)
nlp_engine = provider.create_engine()

registry = RecognizerRegistry()
registry.load_predefined_recognizers(nlp_engine=nlp_engine)

analyzer = AnalyzerEngine(
    nlp_engine=nlp_engine,
    registry=registry,
    supported_languages=["en"]
)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.get_json()
    text = data.get('text', '')
    language = data.get('language', 'en')

    results = analyzer.analyze(
        text=text,
        language=language,
        return_decision_process=False
    )

    return jsonify([
        {
            "entity_type": r.entity_type,
            "text": text[r.start:r.end],
            "start": r.start,
            "end": r.end,
            "score": r.score
        }
        for r in results
    ])

if __name__ == '__main__':
    print("Starting Presidio NER Server on http://localhost:5000")
    app.run(host='127.0.0.1', port=5000, debug=False)
```

### LaunchAgent (Auto-start on Login)

Create: `~/Library/LaunchAgents/com.brainphart.presidio.plist`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.brainphart.presidio</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/kjd/brainphart/presidio/.venv/bin/python</string>
        <string>/Users/kjd/brainphart/presidio/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/kjd/brainphart/presidio/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/kjd/brainphart/presidio/stderr.log</string>
</dict>
</plist>
```

Load with: `launchctl load ~/Library/LaunchAgents/com.brainphart.presidio.plist`

---

## Testing Plan

### Unit Tests

```swift
// PrivacyScannerTests.swift

func testNLTaggerDetectsPerson() {
    let text = "I spoke with Dr. James Wilson about my condition."
    let matches = PrivacyScanner.scanWithNLTagger(text)

    XCTAssertTrue(matches.contains { $0.patternName == "NER:Person" && $0.matchedText == "James Wilson" })
}

func testNLTaggerDetectsOrganization() {
    let text = "I work at Microsoft in the London office."
    let matches = PrivacyScanner.scanWithNLTagger(text)

    XCTAssertTrue(matches.contains { $0.patternName == "NER:Organization" && $0.matchedText == "Microsoft" })
    XCTAssertTrue(matches.contains { $0.patternName == "NER:Location" && $0.matchedText == "London" })
}

func testCombinedDetection() async {
    let text = "John Smith's SSN is 123-45-6789 and he lives in Manchester."
    let matches = await PrivacyScanner.fullScanEnhanced(text)

    XCTAssertTrue(matches.contains { $0.patternName == "NER:Person" })
    XCTAssertTrue(matches.contains { $0.patternName == "SSN" })
    XCTAssertTrue(matches.contains { $0.patternName == "NER:Location" })
}
```

### Integration Test with Presidio

```bash
# Test Presidio server
curl -X POST http://localhost:5000/analyze \
  -H "Content-Type: application/json" \
  -d '{"text": "John Smith works at Microsoft", "language": "en"}'

# Expected response:
# [
#   {"entity_type": "PERSON", "text": "John Smith", "start": 0, "end": 10, "score": 0.85},
#   {"entity_type": "ORGANIZATION", "text": "Microsoft", "start": 20, "end": 29, "score": 0.85}
# ]
```

---

## Security Considerations

1. **Presidio Server Binding:** Only bind to `127.0.0.1` (localhost), never `0.0.0.0`
2. **No External Calls:** All models run locally, no API calls to cloud services
3. **Model Integrity:** Verify SpaCy model checksums after download
4. **Sandbox Compatibility:** Flask server runs in user space, no root required
5. **Data Retention:** Presidio does not store analyzed text

---

## Performance Estimates

| Method | Time per 1000 chars | Memory |
|--------|---------------------|--------|
| Regex (existing) | <1ms | Minimal |
| Topic Keywords | <1ms | Minimal |
| NLTagger | 5-10ms | ~10MB |
| Presidio (SpaCy) | 50-100ms | ~800MB |
| Presidio (BERT) | 200-500ms | ~2GB |
| Ollama LLM | 2-5 seconds | ~4GB |

**Recommendation:** Use NLTagger for real-time scanning, Presidio for batch processing of completed transcripts.

---

## Implementation Timeline

| Phase | Task | Duration |
|-------|------|----------|
| 1.1 | Add `scanWithNLTagger()` to PrivacyScanner | 1 hour |
| 1.2 | Test with existing transcripts | 30 min |
| 1.3 | Update `fullScan()` to include NER | 30 min |
| 2.1 | Set up Presidio Python environment | 1 hour |
| 2.2 | Create Flask server | 1 hour |
| 2.3 | Create PresidioClient.swift | 1 hour |
| 2.4 | Add LaunchAgent for auto-start | 30 min |
| 2.5 | Integration testing | 1 hour |
| 3.0 | Documentation and cleanup | 1 hour |

**Total: ~8 hours**

---

## Conclusion

The hybrid approach provides the best balance of:
- **Immediate value:** NLTagger adds person/place/org detection today
- **Enhanced accuracy:** Presidio provides 50+ entity types when needed
- **Future-proofing:** Apple Foundation Models path for macOS 26+
- **Privacy:** Everything runs locally, nothing leaves the device

Start with Phase 1 (NLTagger) for immediate improvement, then add Presidio if higher accuracy is required for sensitive transcripts.

---

## References

- [Microsoft Presidio GitHub](https://github.com/microsoft/presidio)
- [Presidio Analyzer Documentation](https://microsoft.github.io/presidio/analyzer/)
- [Presidio REST API Setup](https://microsoft.github.io/presidio/installation/)
- [Presidio Transformers Integration](https://microsoft.github.io/presidio/analyzer/nlp_engines/transformers/)
- [SpaCy REST Services](https://github.com/explosion/spacy-services)
- [SpaCy Flask NER Tutorial](https://www.kdnuggets.com/2019/04/building-flask-api-automatically-extract-named-entities-spacy.html)
- [Apple NLTagger Documentation](https://developer.apple.com/documentation/naturallanguage/nltagger)
- [Apple NER Example](https://developer.apple.com/documentation/naturallanguage/identifying-people-places-and-organizations)
- [Core ML Tools Conversion](https://apple.github.io/coremltools/docs-guides/source/convert-nlp-model.html)
- [Apple Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [WWDC 2025: Foundation Models](https://developer.apple.com/videos/play/wwdc2025/286/)
