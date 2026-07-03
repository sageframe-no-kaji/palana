// The config parser's unit battery — aliases in, matching machinery out,
// includes followed through an injected resolver. Shapes drawn from real
// operator configs: multi-alias lines, wildcard catch-alls, config.d
// includes.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SSHConfigParser")
struct SSHConfigParserTests {
    @Test("named hosts enumerate in first-seen order")
    func basicEnumeration() {
        let config = """
            Host jodo
                HostName 192.168.1.20
            Host chumon
            Host mandala
            """
        #expect(SSHConfigParser.hosts(in: config) == ["jodo", "chumon", "mandala"])
    }

    @Test("multiple aliases on one Host line all enumerate")
    func multiAliasLine() {
        let config = "Host kanyo kanyo-prod falcon"
        #expect(SSHConfigParser.hosts(in: config) == ["kanyo", "kanyo-prod", "falcon"])
    }

    @Test("wildcard and negated patterns are machinery, not hosts")
    func wildcardsExcluded() {
        let config = """
            Host *
                ServerAliveInterval 60
            Host *.sageframe.net
            Host jodo !jodo-old ??-probe
            """
        #expect(SSHConfigParser.hosts(in: config) == ["jodo"])
    }

    @Test("comments, blank lines, and other keywords are skipped")
    func noiseSkipped() {
        let config = """
            # fleet config
            IdentityFile ~/.ssh/id_ed25519

            Match User root
                ForwardAgent no
            Host jodo
            """
        #expect(SSHConfigParser.hosts(in: config) == ["jodo"])
    }

    @Test("keyword casing and the = separator both parse")
    func syntaxVariants() {
        let config = """
            HOST jodo
            host = chumon
            """
        #expect(SSHConfigParser.hosts(in: config) == ["jodo", "chumon"])
    }

    @Test("a quoted alias with a space survives as one token")
    func quotedAlias() {
        let config = "Host \"odd host\" plain"
        #expect(SSHConfigParser.hosts(in: config) == ["odd host", "plain"])
    }

    @Test("duplicate aliases enumerate once, first position kept")
    func deduplication() {
        let config = """
            Host jodo
            Host chumon jodo
            """
        #expect(SSHConfigParser.hosts(in: config) == ["jodo", "chumon"])
    }

    @Test("Include directives are followed through the resolver")
    func includesFollowed() {
        let config = """
            Host jodo
            Include config.d/*
            Host mandala
            """
        let hosts = SSHConfigParser.hosts(in: config) { path in
            path == "config.d/*" ? ["Host chumon", "Host koan"] : []
        }
        #expect(hosts == ["jodo", "chumon", "koan", "mandala"])
    }

    @Test("nested includes recurse")
    func nestedIncludes() {
        let hosts = SSHConfigParser.hosts(in: "Include level1") { path in
            switch path {
            case "level1": ["Include level2", "Host mid"]
            case "level2": ["Host deep"]
            default: []
            }
        }
        #expect(hosts == ["deep", "mid"])
    }

    @Test("an include cycle stops at ssh's own depth cap")
    func includeCycleBounded() {
        let hosts = SSHConfigParser.hosts(in: "Include loop\nHost jodo") { _ in
            ["Include loop"]
        }
        #expect(hosts == ["jodo"])
    }

    @Test("the filesystem resolver reads relative and glob includes")
    func systemIncludeResolver() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-ssh-\(UUID().uuidString)")
        let confD = dir.appendingPathComponent("config.d")
        try FileManager.default.createDirectory(at: confD, withIntermediateDirectories: true)
        try "Host globbed-a".write(
            to: confD.appendingPathComponent("a.conf"), atomically: true, encoding: .utf8)
        try "Host globbed-b".write(
            to: confD.appendingPathComponent("b.conf"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolve = SSHConfigParser.systemInclude(relativeTo: dir)
        let hosts = SSHConfigParser.hosts(in: "Include config.d/*.conf", including: resolve)
        #expect(hosts.sorted() == ["globbed-a", "globbed-b"])
        #expect(resolve("missing-path/*.conf").isEmpty)
    }

    @Test("systemConfigText reads the config file, empty when absent")
    func systemConfigTextReads() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-ssh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(SSHConfigParser.systemConfigText(sshDirectory: dir).isEmpty)
        try "Host jodo".write(
            to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        #expect(SSHConfigParser.systemConfigText(sshDirectory: dir) == "Host jodo")
    }
}
