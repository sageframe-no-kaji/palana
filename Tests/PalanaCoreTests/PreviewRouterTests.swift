// PreviewRouterTests — the pure routing, sniff, and cap of the preview pane
// (ho-16). Text-vs-quick-look by extension, the extensionless content sniff,
// the remote → local-only branch, non-file → info-only, and the 256 KB cap.
// The app's PreviewController and the QLPreviewView representable are the
// view/IO layer over this; pinning the decisions here is the coverage.

import Foundation
import Testing

@testable import PalanaCore

@Suite("PreviewRouter — routing, sniff, cap")
struct PreviewRouterTests {
    /// A local regular-file entry with the given name.
    private func file(_ name: String, kind: FileEntry.Kind = .file) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: kind,
            size: 10,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "me",
            group: "staff")
    }

    // MARK: - Remote is local-only, always

    @Test("a remote source → remoteInfoOnly regardless of the name")
    func remoteAlwaysInfoOnly() {
        #expect(
            PreviewRouter.route(isLocal: false, entry: file("notes.md"), contentHead: nil)
                == .remoteInfoOnly)
        #expect(
            PreviewRouter.route(isLocal: false, entry: file("photo.png"), contentHead: nil)
                == .remoteInfoOnly)
    }

    // MARK: - Non-file entries

    @Test("a local directory → infoOnly, not a content preview")
    func directoryInfoOnly() {
        #expect(
            PreviewRouter.route(isLocal: true, entry: file("src", kind: .directory), contentHead: nil)
                == .infoOnly)
    }

    @Test("a local symlink → infoOnly")
    func symlinkInfoOnly() {
        #expect(
            PreviewRouter.route(isLocal: true, entry: file("link", kind: .symlink), contentHead: nil)
                == .infoOnly)
    }

    // MARK: - Text by extension

    @Test("text-family extensions route to text without reading the head")
    func textExtensionsRouteToText() {
        for name in ["notes.md", "config.yaml", "main.swift", "server.log", "data.json", "x.TOML"] {
            #expect(
                PreviewRouter.route(isLocal: true, entry: file(name), contentHead: nil) == .text,
                "\(name) should route to text")
        }
    }

    @Test("uppercase extensions match (case-insensitive)")
    func uppercaseExtensionMatches() {
        #expect(PreviewRouter.isTextExtension("README.MD"))
        #expect(PreviewRouter.isTextExtension("Notes.Md"))
    }

    // MARK: - Quick-look by extension

    @Test("images, PDF, media, archives route to quickLook — even PDF's text-like head")
    func binaryExtensionsRouteToQuickLook() {
        for name in ["photo.png", "scan.pdf", "clip.mov", "art.jpg", "bundle.tar", "z.gz"] {
            #expect(
                PreviewRouter.route(isLocal: true, entry: file(name), contentHead: nil)
                    == .quickLook,
                "\(name) should route to quickLook")
        }
    }

    @Test("a PDF is quickLook even though its header is valid UTF-8 with no NUL")
    func pdfHeaderDoesNotFoolRouting() {
        // "%PDF-1.7" sniffs as text, but the .pdf extension wins → quickLook.
        let head = Data("%PDF-1.7\n%âãÏÓ".utf8)
        #expect(PreviewRouter.route(isLocal: true, entry: file("doc.pdf"), contentHead: head) == .quickLook)
    }

    // MARK: - Extensionless: the content sniff

    @Test("an extensionless file with a text head → text")
    func extensionlessTextHead() {
        let head = Data("#!/bin/sh\necho hello\n".utf8)
        #expect(PreviewRouter.route(isLocal: true, entry: file("runme"), contentHead: head) == .text)
    }

    @Test("an extensionless file with a NUL in the head → quickLook")
    func extensionlessBinaryHead() {
        let head = Data([0x7F, 0x45, 0x4C, 0x46, 0x00, 0x01])  // ELF magic + NUL
        #expect(
            PreviewRouter.route(isLocal: true, entry: file("a.out"), contentHead: head) == .quickLook)
    }

    @Test("a dotfile is extensionless and sniffs by content")
    func dotfileSniffs() {
        // ".bashrc" has no extension (leading dot only) → sniff decides.
        #expect(PreviewRouter.fileExtension(of: ".bashrc") == nil)
        let head = Data("export PATH=$PATH:/usr/local/bin\n".utf8)
        #expect(PreviewRouter.route(isLocal: true, entry: file(".bashrc"), contentHead: head) == .text)
    }

    @Test("an extensionless file with no head read defaults to quickLook")
    func extensionlessNoHeadDefaultsQuickLook() {
        #expect(PreviewRouter.route(isLocal: true, entry: file("Makefile"), contentHead: nil) == .quickLook)
    }

    // MARK: - fileExtension edge cases

    @Test("fileExtension handles multi-dot names, dotfiles, and no-extension")
    func fileExtensionEdges() {
        #expect(PreviewRouter.fileExtension(of: "archive.tar.gz") == "gz")
        #expect(PreviewRouter.fileExtension(of: "Makefile") == nil)
        #expect(PreviewRouter.fileExtension(of: ".gitignore") == nil)
        #expect(PreviewRouter.fileExtension(of: "trailing.") == nil)
        #expect(PreviewRouter.fileExtension(of: "UPPER.MD") == "md")
    }

    // MARK: - looksLikeText

    @Test("empty head reads as text")
    func emptyHeadIsText() {
        #expect(PreviewRouter.looksLikeText(head: Data()))
    }

    @Test("plain ASCII and UTF-8 read as text")
    func asciiAndUTF8AreText() {
        #expect(PreviewRouter.looksLikeText(head: Data("hello world\n".utf8)))
        #expect(PreviewRouter.looksLikeText(head: Data("café — naïve — 日本語".utf8)))
    }

    @Test("a NUL byte anywhere in the window reads as binary")
    func nulIsBinary() {
        #expect(!PreviewRouter.looksLikeText(head: Data([0x41, 0x42, 0x00, 0x43])))
    }

    @Test("invalid UTF-8 (a lone high byte) reads as binary")
    func invalidUTF8IsBinary() {
        #expect(!PreviewRouter.looksLikeText(head: Data([0x41, 0xFF, 0xFE, 0x42])))
    }

    @Test("a multibyte character split at the window tail is tolerated as text")
    func truncatedMultibyteStillText() {
        // "日" is 3 UTF-8 bytes; keep only its first two, mimicking a window cut.
        var bytes = Data("ok ".utf8)
        let ku = Array("日".utf8)
        bytes.append(contentsOf: ku.prefix(2))
        #expect(PreviewRouter.looksLikeText(head: bytes))
    }

    // MARK: - The cap

    @Test("a small read decodes whole, not truncated")
    func smallReadNotTruncated() {
        let data = Data("short file\n".utf8)
        let preview = PreviewRouter.decodeCapped(data, cap: 1024)
        #expect(preview.text == "short file\n")
        #expect(!preview.truncated)
    }

    @Test("a read past the cap is truncated to the cap and flagged")
    func largeReadTruncates() {
        let data = Data(repeating: UInt8(ascii: "x"), count: 1000)
        let preview = PreviewRouter.decodeCapped(data, cap: 256)
        #expect(preview.text.count == 256)
        #expect(preview.truncated)
    }

    @Test("a read exactly at the cap is not truncated")
    func exactCapNotTruncated() {
        let data = Data(repeating: UInt8(ascii: "y"), count: 256)
        let preview = PreviewRouter.decodeCapped(data, cap: 256)
        #expect(preview.text.count == 256)
        #expect(!preview.truncated)
    }

    @Test("the default cap is 256 KB")
    func defaultCapIs256K() {
        #expect(PreviewRouter.textCap == 256 * 1024)
    }
}
