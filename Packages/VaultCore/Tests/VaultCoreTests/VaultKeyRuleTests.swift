import Crypto
import Foundation
import Testing
@testable import VaultCore

/// Required test 7: create a new vault key only when the key store reports the key does
/// not exist. Any other error means the key exists but is locked: surface it, create nothing.
@Suite("Vault key rule")
struct VaultKeyRuleTests {
    static let lockedFailures: [InMemoryKeyStore.ReadFailure] = [.locked, .interactionNotAllowed, .unexpected]

    @Test func newVaultCreatesKeyOnlyWhenNotFound() async throws {
        let vault = try TestVault()
        let report = try await vault.makeStore().open()
        #expect(report.createdVault)
        #expect(await vault.keyStore.createCount == 1)
        #expect(await vault.keyStore.key(for: try vault.header().vaultId) != nil)
    }

    @Test(arguments: lockedFailures)
    func lockedKeyStoreNeverCreatesANewVault(_ failure: InMemoryKeyStore.ReadFailure) async throws {
        let vault = try TestVault()
        await vault.keyStore.setReadFailure(failure)
        await #expect(throws: VaultError.vaultKeyUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 0)
        #expect(try vault.allFiles().isEmpty)  // nothing written
    }

    @Test(arguments: lockedFailures)
    func lockedKeyStoreNeverReplacesAnExistingKey(_ failure: InMemoryKeyStore.ReadFailure) async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        let id = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                                fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        let header = try vault.header()
        let key = try #require(await vault.keyStore.key(for: header.vaultId))
        let filesBefore = try vault.allFiles().map { try Data(contentsOf: $0) }

        await vault.keyStore.setReadFailure(failure)
        await #expect(throws: VaultError.vaultKeyUnavailable) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 1)
        #expect(bytes(try #require(await vault.keyStore.key(for: header.vaultId))) == bytes(key))
        #expect(try vault.header() == header)
        #expect(try vault.allFiles().map { try Data(contentsOf: $0) } == filesBefore)

        // Once the key store unlocks again, everything is still there.
        await vault.keyStore.setReadFailure(nil)
        let reopened = vault.makeStore()
        try await reopened.open()
        #expect(try await reopened.fields(of: id) == Synthetic.ktpFields)
    }

    @Test func existingVaultWithMissingKeyIsNotRecreated() async throws {
        let vault = try TestVault()
        let store = vault.makeStore()
        try await store.open()
        _ = try await store.createDocument(type: .ktp, expiry: nil, pinned: false,
                                           fields: Synthetic.ktpFields, pages: [Synthetic.page("k")])
        let header = try vault.header()
        await vault.keyStore.setKey(nil, for: header.vaultId)

        await #expect(throws: VaultError.vaultKeyMissing) { try await vault.makeStore().open() }
        #expect(await vault.keyStore.createCount == 1)
        #expect(await vault.keyStore.key(for: header.vaultId) == nil)
        #expect(try vault.header() == header)
    }
}
