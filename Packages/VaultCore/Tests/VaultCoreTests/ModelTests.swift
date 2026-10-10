//
//  ModelTests.swift
//  VaultCoreTests
//
//  Created by Inez Amanda on 4/10/26.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import VaultCore

@Suite("Models and on-disk format")
struct ModelTests {
    let docID = DocumentID(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    let pageID = PageID(UUID(uuidString: "99999999-8888-7777-6666-555555555555")!)

    func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Identifiers

    @Test func identifiersUseOneLowercaseSpelling() throws {
        // Hex letters in the id, so an uppercase spelling would show.
        let lowercase = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let id = DocumentID(try #require(UUID(uuidString: lowercase.uppercased())))
        #expect(id.string == lowercase)
        #expect(DocumentID(string: lowercase) == id)
        #expect(DocumentID(string: lowercase.uppercased()) == nil)
        #expect(DocumentID(string: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeeE") == nil)
        #expect(DocumentID(string: "not-a-uuid") == nil)
        let encoded = try VaultJSON.encoder.encode([id])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["\#(lowercase)"]"#)
        #expect(try VaultJSON.decoder.decode([DocumentID].self, from: encoded) == [id])
        #expect(throws: DecodingError.self) {
            try VaultJSON.decoder.decode([DocumentID].self, from: Data(#"["\#(lowercase.uppercased())"]"#.utf8))
        }
        // A new random id is lowercase too.
        let random = PageID()
        #expect(random.string == random.uuid.uuidString.lowercased())
    }

    // MARK: Calendar dates (expiry has no time of day or time zone)

    @Test func calendarDateCodesAsISODay() throws {
        let date = try #require(CalendarDate(year: 2030, month: 8, day: 17))
        let encoded = try VaultJSON.encoder.encode([date])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["2030-08-17"]"#)
        #expect(try VaultJSON.decoder.decode([CalendarDate].self, from: encoded) == [date])
        #expect(CalendarDate(year: 2030, month: 13, day: 1) == nil)
        #expect(CalendarDate(year: 2030, month: 2, day: 30) == nil)
        #expect(throws: DecodingError.self) {
            try VaultJSON.decoder.decode([CalendarDate].self, from: Data(#"["17-08-2030"]"#.utf8))
        }
        #expect(CalendarDate(year: 2030, month: 8, day: 17)! < CalendarDate(year: 2031, month: 1, day: 1)!)
    }

    // MARK: Document types are open strings, so a newer type still decodes

    @Test func documentTypesKeepUnknownValues() throws {
        #expect(DocumentType.ktp.rawValue == "ktp")
        #expect(DocumentType.passport.rawValue == "passport")
        let decoded = try VaultJSON.decoder.decode([DocumentType].self, from: Data(#"["sim","visa"]"#.utf8))
        #expect(decoded == [.sim, DocumentType(rawValue: "visa")])
    }

    // MARK: vault.json

    @Test func vaultHeaderHoldsKeySlotsAsAList() throws {
        let vaultID = VaultID()
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let header = VaultHeader(vaultId: vaultID, keySlots: [KeySlot(kind: .device, createdAt: created)])
        let object = try jsonObject(VaultJSON.encoder.encode(header))
        #expect(Set(object.keys) == ["formatVersion", "vaultId", "keySlots"])
        #expect(object["formatVersion"] as? Int == 1)
        #expect(object["vaultId"] as? String == vaultID.string)
        let slots = try #require(object["keySlots"] as? [[String: Any]])
        #expect(slots.count == 1)
        #expect(slots[0]["kind"] as? String == "device")
        #expect(slots[0]["sealedVaultKey"] == nil)  // the device slot is the Keychain item itself
        let decoded = try VaultJSON.decoder.decode(VaultHeader.self, from: VaultJSON.encoder.encode(header))
        #expect(decoded == header)
    }

    // MARK: index.enc plaintext

    @Test func indexJSONHasDesignDocFields() throws {
        let entry = IndexEntry(
            id: docID, type: .sim,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_790_000_100),
            expiry: CalendarDate(year: 2030, month: 8, day: 17), pinned: true, deletedAt: nil,
            sealedKey: Data([1, 2, 3]), sealedFields: Data([4, 5, 6]), pageIds: [pageID]
        )
        let index = VaultIndex(generation: 7, documents: [entry])
        let object = try jsonObject(VaultJSON.encoder.encode(index))
        #expect(Set(object.keys) == ["schemaVersion", "generation", "documents"])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["generation"] as? Int == 7)
        let doc = try #require((object["documents"] as? [[String: Any]])?.first)
        #expect(
            Set(doc.keys) == [
                "id", "type", "createdAt", "updatedAt", "expiry", "pinned",
                "sealedKey", "sealedFields", "pageIds",
            ])
        #expect(doc["expiry"] as? String == "2030-08-17")
        #expect(doc["createdAt"] as? String == "2026-09-21T14:13:20Z")
        #expect(try VaultJSON.decoder.decode(VaultIndex.self, from: VaultJSON.encoder.encode(index)) == index)
    }

    // MARK: pages/<pageId>.enc

    @Test func pageFileLayoutIsLengthPrefixedHeaderThenSealedBytes() throws {
        let header = PageHeader(docId: docID, pageId: pageID, position: 1, sealedKey: Data(repeating: 7, count: 60))
        let sealed = Data(repeating: 9, count: 40)
        let encoded = try PageFile(header: header, sealedContent: sealed).encoded()

        let length = Int(encoded.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        let headerJSON = try jsonObject(encoded.dropFirst(4).prefix(length))
        #expect(Set(headerJSON.keys) == ["formatVersion", "docId", "pageId", "position", "sealedKey"])
        #expect(headerJSON["formatVersion"] as? Int == 1)
        #expect(headerJSON["position"] as? Int == 1)
        #expect(Data(encoded.suffix(from: 4 + length)) == sealed)

        let decoded = try PageFile(decoding: encoded)
        #expect(decoded.header == header)
        #expect(decoded.sealedContent == sealed)
    }

    @Test func truncatedPageFileIsCorrupt() throws {
        let encoded = try PageFile(
            header: PageHeader(docId: docID, pageId: pageID, position: 0, sealedKey: Data([1])),
            sealedContent: Data([2])
        ).encoded()
        try #require(encoded.count > 10)
        for cut in [0, 2, 4, 10] {
            #expect(throws: VaultError.corruptFile) { try PageFile(decoding: encoded.prefix(cut)) }
        }
        var huge = encoded
        huge.replaceSubrange(0..<4, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: VaultError.corruptFile) { try PageFile(decoding: huge) }
    }

    // MARK: projection.json

    @Test func projectionHoldsOnlyIdTypeExpiryAndOffsets() throws {
        let projection = Projection(documents: [
            ProjectionEntry(
                id: docID, type: .sim, expiry: CalendarDate(year: 2030, month: 8, day: 17),
                reminderOffsets: [60, 30, 7])
        ])
        let object = try jsonObject(VaultJSON.encoder.encode(projection))
        #expect(Set(object.keys) == ["schemaVersion", "documents"])
        let entry = try #require((object["documents"] as? [[String: Any]])?.first)
        #expect(Set(entry.keys) == ["id", "type", "expiry", "reminderOffsets"])
        #expect(try VaultJSON.decoder.decode(Projection.self, from: VaultJSON.encoder.encode(projection)) == projection)
    }
}
