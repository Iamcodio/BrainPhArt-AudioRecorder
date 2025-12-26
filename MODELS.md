# Anthropic Claude Models Reference

Last updated: December 26, 2025

## Latest Models (Claude 4.5)

| Model | API ID | Alias | Release Date |
|-------|--------|-------|--------------|
| **Claude Opus 4.5** | `claude-opus-4-5-20251101` | `claude-opus-4-5` | Nov 1, 2025 |
| **Claude Sonnet 4.5** | `claude-sonnet-4-5-20250929` | `claude-sonnet-4-5` | Sep 29, 2025 |
| **Claude Haiku 4.5** | `claude-haiku-4-5-20251001` | `claude-haiku-4-5` | Oct 1, 2025 |

### Pricing (per million tokens)

| Model | Input | Output |
|-------|-------|--------|
| Opus 4.5 | $5 | $25 |
| Sonnet 4.5 | $3 | $15 |
| Haiku 4.5 | $1 | $5 |

### Capabilities

- **Context window**: 200K tokens (Sonnet 4.5 supports 1M beta)
- **Max output**: 64K tokens
- **Extended thinking**: Yes (all 4.5 models)
- **Vision**: Yes (all models)

## Legacy Models (Still Available)

| Model | API ID | Alias | Release Date |
|-------|--------|-------|--------------|
| Claude Opus 4.1 | `claude-opus-4-1-20250805` | `claude-opus-4-1` | Aug 5, 2025 |
| Claude Opus 4 | `claude-opus-4-20250514` | `claude-opus-4-0` | May 14, 2025 |
| Claude Sonnet 4 | `claude-sonnet-4-20250514` | `claude-sonnet-4-0` | May 14, 2025 |
| Claude Sonnet 3.7 | `claude-3-7-sonnet-20250219` | `claude-3-7-sonnet-latest` | Feb 19, 2025 |
| Claude Haiku 3 | `claude-3-haiku-20240307` | — | Mar 7, 2024 |

### Legacy Pricing

| Model | Input | Output |
|-------|-------|--------|
| Opus 4.1 / 4 | $15 | $75 |
| Sonnet 4 / 3.7 | $3 | $15 |
| Haiku 3 | $0.25 | $1.25 |

## Deprecated/Retired

- **Claude 3 Opus** (2024-02-29) - Deprecated Jun 30, 2025, retiring Jan 5, 2026
- **Claude 3 Sonnet** (2024-02-29) - Retired Jul 21, 2025
- **Claude 2.1** - Retired Jul 21, 2025

## Quick Reference

```swift
// For BrainPhArt LLMService.swift
struct ClaudeModels {
    // Latest (recommended)
    static let opus = "claude-opus-4-5-20251101"
    static let sonnet = "claude-sonnet-4-5-20250929"
    static let haiku = "claude-haiku-4-5-20251001"

    // Aliases (auto-update to latest)
    static let opusAlias = "claude-opus-4-5"
    static let sonnetAlias = "claude-sonnet-4-5"
    static let haikuAlias = "claude-haiku-4-5"
}
```

## Platform IDs

### AWS Bedrock

```
anthropic.claude-opus-4-5-20251101-v1:0
anthropic.claude-sonnet-4-5-20250929-v1:0
anthropic.claude-haiku-4-5-20251001-v1:0
```

### Google Vertex AI

```
claude-opus-4-5@20251101
claude-sonnet-4-5@20250929
claude-haiku-4-5@20251001
```

## Knowledge Cutoffs

| Model | Reliable Knowledge | Training Data |
|-------|-------------------|---------------|
| Opus 4.5 | May 2025 | Aug 2025 |
| Sonnet 4.5 | Jan 2025 | Jul 2025 |
| Haiku 4.5 | Feb 2025 | Jul 2025 |

## Source

[Claude Models Overview - Anthropic Docs](https://platform.claude.com/docs/en/about-claude/models/overview)
