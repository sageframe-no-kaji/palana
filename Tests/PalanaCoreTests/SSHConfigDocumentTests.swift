// The typed config read. A missing file is absent; bytes come back exactly
// with the file's mode; anything that stops the read, or bytes that are not
// UTF-8, is a typed failure — never an empty configuration. Temporary
// directories only.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SSHConfigDocument")
struct SSHConfigDocumentTests {
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("a missing file is absent — not an error, not empty text by accident")
    func absent() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let document = try SSHConfigDocument.read(at: dir.appendingPathComponent("config"))
        #expect(document == .absent)
        #expect(!document.exists)
        #expect(document.bytes.isEmpty)
        #expect(document.posixPermissions == nil)
    }

    @Test("bytes come back exactly, with the file's mode")
    func exactBytes() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config")
        let bytes = Data("Host jodo \r\n    HostName x  \n\t\n".utf8)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let document = try SSHConfigDocument.read(at: url)
        #expect(document.bytes == bytes)
        #expect(Data(document.text.utf8) == bytes)
        #expect(document.exists)
        #expect(document.posixPermissions == 0o600)
    }

    @Test("invalid UTF-8 is a typed failure, never decoded lossily")
    func notUTF8() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config")
        try Data([0x48, 0x6F, 0x73, 0x74, 0x20, 0xFF, 0xFE, 0x0A]).write(to: url)
        #expect(throws: SSHConfigReadError.notUTF8(path: url.path)) {
            try SSHConfigDocument.read(at: url)
        }
    }

    @Test("a directory at the path is unreadable, not absent")
    func directoryIsUnreadable() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try SSHConfigDocument.read(at: dir)
            Issue.record("expected an unreadable failure")
        } catch .unreadable(let path, let reason) {
            #expect(path == dir.path)
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("wrong failure: \(error)")
        }
    }

    @Test("a BOM survives the round trip byte for byte")
    func bomRoundTrip() throws {
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("Host jodo\n".utf8)
        let document = try SSHConfigDocument(bytes: bytes, path: "x", posixPermissions: nil)
        #expect(Data(document.text.utf8) == bytes)
    }

    @Test("a composed document's bytes are its text")
    func composed() {
        let document = SSHConfigDocument(text: "Host jodo\n", posixPermissions: 0o644)
        #expect(document.bytes == Data("Host jodo\n".utf8))
        #expect(document.text == "Host jodo\n")
        #expect(document.exists)
        #expect(document.posixPermissions == 0o644)
    }
}
