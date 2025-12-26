//
//  PrivacyManager.swift
//  BrainPhArt
//
//  Created by BrainPhArt Team
//  Two-tier privacy system: PRIVATE (local only) vs PUBLIC (can be published)
//

import Foundation
import CryptoKit

// MARK: - Privacy Level Enum

enum PrivacyLevel: String, Codable {
    case `private` = "private"   // Never leaves device, local LLM only
    case `public` = "public"     // Can be published, can use external APIs
}

// MARK: - Privacy Manager Actor

actor PrivacyManager {
    static let shared = PrivacyManager()

    // MARK: - Private Properties

    private var vaultUnlocked: Bool = false

    // UserDefaults keys (will migrate to Keychain later)
    private let vaultPasswordHashKey = "brainphart.vault.passwordHash"
    private let cardPrivacyPrefix = "brainphart.privacy.card."
    private let sessionPrivacyPrefix = "brainphart.privacy.session."
    private let privateCardIdsKey = "brainphart.privacy.privateCardIds"
    private let privateSessionIdsKey = "brainphart.privacy.privateSessionIds"

    private let defaults = UserDefaults.standard

    // MARK: - Initialization

    private init() {}

    // MARK: - External API Access Checks

    /// Check if a card's content can use external APIs (only public content)
    func canUseExternalAPI(cardId: String) -> Bool {
        let level = getPrivacyLevel(cardId: cardId)
        return level == .public
    }

    /// Check if a session's content can use external APIs (only public content)
    func canUseExternalAPI(sessionId: String) -> Bool {
        let level = getPrivacyLevel(sessionId: sessionId)
        return level == .public
    }

    // MARK: - Publishing Checks

    /// Check if a card can be published
    func canPublish(cardId: String) -> Bool {
        let level = getPrivacyLevel(cardId: cardId)
        return level == .public
    }

    /// Check if a session can be published
    func canPublish(sessionId: String) -> Bool {
        let level = getPrivacyLevel(sessionId: sessionId)
        return level == .public
    }

    // MARK: - Vault Operations

    /// Unlock the vault with password
    /// Returns true if password is correct, false otherwise
    func unlockVault(password: String) -> Bool {
        guard let storedHash = defaults.string(forKey: vaultPasswordHashKey) else {
            // No password set yet - vault is open by default until password is set
            vaultUnlocked = true
            return true
        }

        let inputHash = hashPassword(password)
        if inputHash == storedHash {
            vaultUnlocked = true
            return true
        }

        return false
    }

    /// Lock the vault
    func lockVault() {
        vaultUnlocked = false
    }

    /// Check if vault is currently unlocked
    func isVaultUnlocked() -> Bool {
        // If no password is set, vault is always "unlocked"
        if defaults.string(forKey: vaultPasswordHashKey) == nil {
            return true
        }
        return vaultUnlocked
    }

    /// Set or change the vault password
    /// Returns true if password was set successfully
    func setVaultPassword(password: String) -> Bool {
        guard !password.isEmpty else {
            return false
        }

        let hash = hashPassword(password)
        defaults.set(hash, forKey: vaultPasswordHashKey)
        vaultUnlocked = true  // Auto-unlock after setting password
        return true
    }

    /// Check if a vault password has been set
    func hasVaultPassword() -> Bool {
        return defaults.string(forKey: vaultPasswordHashKey) != nil
    }

    // MARK: - Privacy Level Management

    /// Set privacy level for a card
    func setPrivacyLevel(cardId: String, level: PrivacyLevel) {
        let key = cardPrivacyPrefix + cardId
        defaults.set(level.rawValue, forKey: key)

        // Update the list of private card IDs
        var privateIds = getPrivateCardIds()
        if level == .private {
            if !privateIds.contains(cardId) {
                privateIds.append(cardId)
            }
        } else {
            privateIds.removeAll { $0 == cardId }
        }
        defaults.set(privateIds, forKey: privateCardIdsKey)
    }

    /// Set privacy level for a session
    func setPrivacyLevel(sessionId: String, level: PrivacyLevel) {
        let key = sessionPrivacyPrefix + sessionId
        defaults.set(level.rawValue, forKey: key)

        // Update the list of private session IDs
        var privateIds = getPrivateSessionIds()
        if level == .private {
            if !privateIds.contains(sessionId) {
                privateIds.append(sessionId)
            }
        } else {
            privateIds.removeAll { $0 == sessionId }
        }
        defaults.set(privateIds, forKey: privateSessionIdsKey)
    }

    /// Get privacy level for a card (defaults to public)
    func getPrivacyLevel(cardId: String) -> PrivacyLevel {
        let key = cardPrivacyPrefix + cardId
        guard let rawValue = defaults.string(forKey: key),
              let level = PrivacyLevel(rawValue: rawValue) else {
            return .public  // Default to public
        }
        return level
    }

    /// Get privacy level for a session (defaults to public)
    func getPrivacyLevel(sessionId: String) -> PrivacyLevel {
        let key = sessionPrivacyPrefix + sessionId
        guard let rawValue = defaults.string(forKey: key),
              let level = PrivacyLevel(rawValue: rawValue) else {
            return .public  // Default to public
        }
        return level
    }

    // MARK: - Private Content Retrieval

    /// Get all card IDs marked as private
    func getPrivateCardIds() -> [String] {
        return defaults.stringArray(forKey: privateCardIdsKey) ?? []
    }

    /// Get all session IDs marked as private
    func getPrivateSessionIds() -> [String] {
        return defaults.stringArray(forKey: privateSessionIdsKey) ?? []
    }

    // MARK: - Publishing Blocker

    /// Check if a session is ready to publish
    /// Returns (ready: Bool, blockers: [String]) where blockers lists reasons why it can't be published
    func checkPublishReady(sessionId: String) -> (ready: Bool, blockers: [String]) {
        var blockers: [String] = []

        // Check if session itself is private
        if getPrivacyLevel(sessionId: sessionId) == .private {
            blockers.append("Session is marked as private")
        }

        // Check for private cards in this session
        // Note: In a full implementation, this would query the database
        // For now, we check all private cards (caller should filter by session)
        let privateCards = getPrivateCardIds()
        let sessionPrivateCards = privateCards.filter { $0.hasPrefix(sessionId) }
        if !sessionPrivateCards.isEmpty {
            blockers.append("\(sessionPrivateCards.count) card(s) marked as private")
        }

        // Check if vault is locked (can't verify private content status)
        if hasVaultPassword() && !vaultUnlocked {
            blockers.append("Vault is locked - unlock to verify private content")
        }

        // Future: Add PII detection check
        // blockers.append("Session contains unreviewed PII")

        return (blockers.isEmpty, blockers)
    }

    /// Check if a session is ready to publish with associated card IDs
    /// This version accepts card IDs that belong to the session for more accurate checking
    func checkPublishReady(sessionId: String, cardIds: [String]) -> (ready: Bool, blockers: [String]) {
        var blockers: [String] = []

        // Check if session itself is private
        if getPrivacyLevel(sessionId: sessionId) == .private {
            blockers.append("Session is marked as private")
        }

        // Check each card's privacy level
        var privateCardCount = 0
        for cardId in cardIds {
            if getPrivacyLevel(cardId: cardId) == .private {
                privateCardCount += 1
            }
        }

        if privateCardCount > 0 {
            blockers.append("\(privateCardCount) card(s) marked as private")
        }

        // Check if vault is locked (can't verify private content status)
        if hasVaultPassword() && !vaultUnlocked {
            blockers.append("Vault is locked - unlock to verify private content")
        }

        return (blockers.isEmpty, blockers)
    }

    // MARK: - Private Helpers

    /// Hash a password using SHA-256 with a salt
    /// Note: For production, consider using bcrypt or Argon2 via a library
    private func hashPassword(_ password: String) -> String {
        // Simple salt - in production, use a unique salt per password stored separately
        let salt = "brainphart.vault.salt.v1"
        let saltedPassword = salt + password

        guard let data = saltedPassword.data(using: .utf8) else {
            return ""
        }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Convenience Extensions

extension PrivacyManager {
    /// Bulk check for external API access
    func canUseExternalAPI(cardIds: [String]) -> Bool {
        for cardId in cardIds {
            if !canUseExternalAPI(cardId: cardId) {
                return false
            }
        }
        return true
    }

    /// Bulk set privacy level for multiple cards
    func setPrivacyLevel(cardIds: [String], level: PrivacyLevel) {
        for cardId in cardIds {
            setPrivacyLevel(cardId: cardId, level: level)
        }
    }

    /// Get count of private items
    func getPrivateContentCount() -> (cards: Int, sessions: Int) {
        return (getPrivateCardIds().count, getPrivateSessionIds().count)
    }
}
