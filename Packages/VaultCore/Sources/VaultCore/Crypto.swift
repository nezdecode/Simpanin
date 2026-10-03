import Crypto
import Foundation

/// Associated data bound to every seal. The strings are part of the v1 on-disk format
/// (design doc, "On-disk format"); changing one makes existing vaults unreadable.
public enum AssociatedData: Sendable, Equatable {
    /// index.enc and index.prev.enc: "index|v1|<vaultId>"
    case index(VaultID)
    /// A document's sealed fields: "fields|v1|<docId>"
    case fields(DocumentID)
    /// A page file's sealed content: "page|v1|<docId>|<pageId>"
    case page(DocumentID, PageID)
    /// A document key sealed with the wrap key: "dk|v1|<docId>"
    case documentKey(DocumentID)

    public var string: String {
        switch self {
        case .index(let vault): "index|v1|\(vault.string)"
        case .fields(let doc): "fields|v1|\(doc.string)"
        case .page(let doc, let page): "page|v1|\(doc.string)|\(page.string)"
        case .documentKey(let doc): "dk|v1|\(doc.string)"
        }
    }

    var bytes: Data { Data(string.utf8) }
}

/// Key derivation and AES-256-GCM sealing for the vault.
public enum VaultCrypto {
    static let indexKeyInfo = "vault.index.v1"
    static let wrapKeyInfo = "vault.wrap.v1"
    static let keyByteCount = 32

    /// A new random 256-bit key (vault key or document key).
    public static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    /// HKDF-SHA256 from the vault key, info "vault.index.v1", salt = vault id.
    public static func indexKey(from vaultKey: SymmetricKey, vaultID: VaultID) -> SymmetricKey {
        derive(from: vaultKey, vaultID: vaultID, info: indexKeyInfo)
    }

    /// HKDF-SHA256 from the vault key, info "vault.wrap.v1", salt = vault id.
    public static func wrapKey(from vaultKey: SymmetricKey, vaultID: VaultID) -> SymmetricKey {
        derive(from: vaultKey, vaultID: vaultID, info: wrapKeyInfo)
    }

    private static func derive(from vaultKey: SymmetricKey, vaultID: VaultID, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: vaultKey,
            salt: Data(vaultID.string.utf8),
            info: Data(info.utf8),
            outputByteCount: keyByteCount
        )
    }

    /// AES-256-GCM with a fresh random 12-byte nonce. Returns nonce || ciphertext || tag.
    public static func seal(_ plaintext: Data, with key: SymmetricKey, as ad: AssociatedData) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: ad.bytes)
        guard let combined = box.combined else { throw VaultError.corruptFile }
        return combined
    }

    /// Opens data from `seal`. Any failure (wrong key, wrong associated data, tampered or
    /// truncated bytes) is reported as `.authenticationFailed`.
    public static func open(_ sealed: Data, with key: SymmetricKey, as ad: AssociatedData) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            return try AES.GCM.open(box, using: key, authenticating: ad.bytes)
        } catch {
            throw VaultError.authenticationFailed
        }
    }

    /// Seals a document key with the wrap key using AES-GCM (not AES.KeyWrap, which
    /// cannot bind associated data) and "dk|v1|<docId>".
    public static func sealDocumentKey(_ key: SymmetricKey, with wrapKey: SymmetricKey, documentID: DocumentID) throws -> Data {
        let raw = key.withUnsafeBytes { Data($0) }
        return try seal(raw, with: wrapKey, as: .documentKey(documentID))
    }

    public static func openDocumentKey(_ sealed: Data, with wrapKey: SymmetricKey, documentID: DocumentID) throws -> SymmetricKey {
        let raw = try open(sealed, with: wrapKey, as: .documentKey(documentID))
        guard raw.count == keyByteCount else { throw VaultError.corruptFile }
        return SymmetricKey(data: raw)
    }
}
