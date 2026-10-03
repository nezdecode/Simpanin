import Crypto
import Foundation
import Testing
@testable import VaultCore

@Suite("Crypto")
struct CryptoTests {
    let vaultID = VaultID(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
    let docID = DocumentID(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    let otherDocID = DocumentID(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    let pageID = PageID(UUID(uuidString: "99999999-8888-7777-6666-555555555555")!)

    // MARK: Associated data strings are part of the v1 format and must never change.

    @Test func associatedDataStringsMatchDesignDoc() {
        #expect(AssociatedData.index(vaultID).string == "index|v1|6f9619ff-8b86-d011-b42d-00c04fc964ff")
        #expect(AssociatedData.fields(docID).string == "fields|v1|11111111-2222-3333-4444-555555555555")
        #expect(AssociatedData.page(docID, pageID).string
            == "page|v1|11111111-2222-3333-4444-555555555555|99999999-8888-7777-6666-555555555555")
        #expect(AssociatedData.documentKey(docID).string == "dk|v1|11111111-2222-3333-4444-555555555555")
    }

    // MARK: Key derivation

    @Test func derivedKeysMatchIndependentHKDF() {
        let vaultKey = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))
        let salt = Data("6f9619ff-8b86-d011-b42d-00c04fc964ff".utf8)
        let index = VaultCrypto.indexKey(from: vaultKey, vaultID: vaultID)
        let wrap = VaultCrypto.wrapKey(from: vaultKey, vaultID: vaultID)
        #expect(index.bitCount == 256)
        #expect(wrap.bitCount == 256)
        #expect(bytes(index) == referenceHKDF(ikm: bytes(vaultKey), salt: salt, info: Data("vault.index.v1".utf8)))
        #expect(bytes(wrap) == referenceHKDF(ikm: bytes(vaultKey), salt: salt, info: Data("vault.wrap.v1".utf8)))
        #expect(bytes(index) != bytes(wrap))
    }

    @Test func derivedKeysDependOnVaultID() {
        let vaultKey = VaultCrypto.newKey()
        let other = VaultID()
        #expect(bytes(VaultCrypto.indexKey(from: vaultKey, vaultID: vaultID))
            != bytes(VaultCrypto.indexKey(from: vaultKey, vaultID: other)))
    }

    @Test func newKeysAre256BitAndRandom() {
        let a = VaultCrypto.newKey(), b = VaultCrypto.newKey()
        #expect(a.bitCount == 256)
        #expect(bytes(a) != bytes(b))
    }

    // MARK: Seal and open for every kind of associated data

    static let kinds: [String] = ["index", "fields", "page", "documentKey"]

    func ad(_ kind: String) -> AssociatedData {
        switch kind {
        case "index": .index(vaultID)
        case "fields": .fields(docID)
        case "page": .page(docID, pageID)
        default: .documentKey(docID)
        }
    }

    @Test(arguments: kinds)
    func sealOpenRoundTrip(kind: String) throws {
        let key = VaultCrypto.newKey()
        let plaintext = Data("synthetic \(kind) payload".utf8)
        let sealed = try VaultCrypto.seal(plaintext, with: key, as: ad(kind))
        #expect(sealed != plaintext)
        #expect(sealed.count == 12 + plaintext.count + 16)  // nonce + ciphertext + tag
        #expect(try VaultCrypto.open(sealed, with: key, as: ad(kind)) == plaintext)
    }

    @Test(arguments: kinds)
    func flippingAnyByteFailsToOpen(kind: String) throws {
        let key = VaultCrypto.newKey()
        let sealed = try VaultCrypto.seal(Data("synthetic payload".utf8), with: key, as: ad(kind))
        for position in sealed.indices {
            var tampered = sealed
            tampered[position] ^= 0x01
            #expect(throws: VaultError.authenticationFailed) {
                try VaultCrypto.open(tampered, with: key, as: ad(kind))
            }
        }
    }

    @Test func freshNonceForEverySeal() throws {
        let key = VaultCrypto.newKey()
        let a = try VaultCrypto.seal(Data("same".utf8), with: key, as: .fields(docID))
        let b = try VaultCrypto.seal(Data("same".utf8), with: key, as: .fields(docID))
        #expect(a.prefix(12) != b.prefix(12))
    }

    @Test func wrongAssociatedDataFailsToOpen() throws {
        let key = VaultCrypto.newKey()
        let sealed = try VaultCrypto.seal(Data("x".utf8), with: key, as: .page(docID, pageID))
        #expect(throws: VaultError.authenticationFailed) {
            try VaultCrypto.open(sealed, with: key, as: .page(otherDocID, pageID))
        }
        #expect(throws: VaultError.authenticationFailed) {
            try VaultCrypto.open(sealed, with: key, as: .fields(docID))
        }
    }

    @Test func wrongKeyFailsToOpen() throws {
        let sealed = try VaultCrypto.seal(Data("x".utf8), with: VaultCrypto.newKey(), as: .index(vaultID))
        #expect(throws: VaultError.authenticationFailed) {
            try VaultCrypto.open(sealed, with: VaultCrypto.newKey(), as: .index(vaultID))
        }
    }

    @Test func truncatedInputFailsToOpen() {
        #expect(throws: VaultError.authenticationFailed) {
            try VaultCrypto.open(Data([1, 2, 3]), with: VaultCrypto.newKey(), as: .index(vaultID))
        }
    }

    // MARK: Document keys are sealed with AES-GCM and "dk|v1|<docId>"

    @Test func documentKeyRoundTrip() throws {
        let wrap = VaultCrypto.newKey(), dk = VaultCrypto.newKey()
        let sealed = try VaultCrypto.sealDocumentKey(dk, with: wrap, documentID: docID)
        #expect(sealed.count == 12 + 32 + 16)
        // It is a plain AES-GCM seal with the dk associated data, not AES.KeyWrap.
        #expect(try VaultCrypto.open(sealed, with: wrap, as: .documentKey(docID)) == bytes(dk))
        #expect(bytes(try VaultCrypto.openDocumentKey(sealed, with: wrap, documentID: docID)) == bytes(dk))
    }

    @Test func documentKeyBoundToItsDocument() throws {
        let wrap = VaultCrypto.newKey()
        let sealed = try VaultCrypto.sealDocumentKey(VaultCrypto.newKey(), with: wrap, documentID: docID)
        #expect(throws: VaultError.authenticationFailed) {
            try VaultCrypto.openDocumentKey(sealed, with: wrap, documentID: otherDocID)
        }
    }
}

func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

/// RFC 5869 HKDF-SHA256 written out with HMAC, independent of Crypto's HKDF type,
/// so a change of label, salt or algorithm in VaultCrypto is caught.
func referenceHKDF(ikm: Data, salt: Data, info: Data, length: Int = 32) -> Data {
    let prk = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt)))
    var okm = Data(), block = Data(), counter: UInt8 = 1
    while okm.count < length {
        block = Data(HMAC<SHA256>.authenticationCode(for: block + info + [counter], using: SymmetricKey(data: prk)))
        okm += block
        counter += 1
    }
    return okm.prefix(length)
}
