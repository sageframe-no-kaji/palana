// Add and remove transforms for SSHConfigParser. Pure text — no ssh, no
// filesystem. Fixtures drawn from the same config shapes the existing
// parser battery uses.

import Testing

@testable import PalanaCore

// MARK: - adding

@Suite("SSHConfigParser adding")
struct SSHConfigParserAddingTests {
    // A config that matches the existing parser battery shapes.
    private let twoBlockConfig = """
        Host jodo
            HostName 192.168.1.20
            User admin

        Host chumon
            HostName 192.168.1.21
        """

    private let singleBlockConfig = "Host jodo\n    HostName jodo.local\n    User admin\n"

    // A minimal block to use as the added entry.
    private var newBlock: HostBlock {
        HostBlock(alias: "mandala", hostName: "192.168.1.190")
    }

    @Test("adding into empty text produces the block with no leading blank line")
    func addIntoEmpty() throws {
        let result = try #require(SSHConfigParser.adding(newBlock, to: ""))
        #expect(result == newBlock.compose())
        #expect(!result.hasPrefix("\n"))
    }

    @Test("adding into whitespace-only text treats input as empty")
    func addIntoWhitespace() throws {
        let result = try #require(SSHConfigParser.adding(newBlock, to: "   \n\n  "))
        #expect(result == newBlock.compose())
    }

    @Test("adding into text with one block appends after a single blank separator")
    func addAfterOneBlock() throws {
        let result = try #require(SSHConfigParser.adding(newBlock, to: singleBlockConfig))
        let parts = result.components(separatedBy: "\n\n")
        // Two parts separated by exactly one blank line.
        #expect(parts.count == 2)
        #expect(parts[1] == newBlock.compose())
    }

    @Test("adding into text with multiple blocks appends at the end")
    func addAfterMultipleBlocks() throws {
        let result = try #require(SSHConfigParser.adding(newBlock, to: twoBlockConfig))
        #expect(result.hasSuffix("\n\n" + newBlock.compose()))
        // Original aliases still enumerate.
        let aliases = SSHConfigParser.hosts(in: result)
        #expect(aliases.contains("jodo"))
        #expect(aliases.contains("chumon"))
        #expect(aliases.contains("mandala"))
    }

    @Test("adding a duplicate alias returns nil")
    func addDuplicateAliasReturnsNil() {
        let duplicate = HostBlock(alias: "jodo", hostName: "192.168.99.1")
        #expect(SSHConfigParser.adding(duplicate, to: twoBlockConfig) == nil)
    }

    @Test("an alias that is a substring of an existing alias is NOT a false duplicate")
    func substringAliasNotDuplicate() throws {
        // "jo" is a substring of "jodo" but a distinct alias.
        let sub = HostBlock(alias: "jo", hostName: "192.168.1.99")
        let result = try #require(SSHConfigParser.adding(sub, to: twoBlockConfig))
        let aliases = SSHConfigParser.hosts(in: result)
        #expect(aliases.contains("jo"))
        #expect(aliases.contains("jodo"))
    }

    @Test("added block round-trips through hosts(in:)")
    func addedBlockEnumerates() throws {
        let result = try #require(SSHConfigParser.adding(newBlock, to: singleBlockConfig))
        #expect(SSHConfigParser.hosts(in: result).contains("mandala"))
    }

    @Test("adding a full block (all fields) appends correctly")
    func addFullBlock() throws {
        let full = HostBlock(
            alias: "kanyo",
            hostName: "192.168.1.50",
            user: "deploy",
            port: 2222,
            identityFile: "~/.ssh/id_ed25519"
        )
        let result = try #require(SSHConfigParser.adding(full, to: singleBlockConfig))
        #expect(result.contains("Host kanyo"))
        #expect(result.contains("    HostName 192.168.1.50"))
        #expect(result.contains("    User deploy"))
        #expect(result.contains("    Port 2222"))
        #expect(result.contains("    IdentityFile ~/.ssh/id_ed25519"))
    }
}

// MARK: - removing

@Suite("SSHConfigParser removing")
struct SSHConfigParserRemovingTests {
    private let threeBlockConfig = """
        Host jodo
            HostName 192.168.1.20
            User admin

        Host chumon
            HostName 192.168.1.21

        Host mandala
            HostName 192.168.1.190
        """

    private let singleBlockConfig = "Host jodo\n    HostName jodo.local\n    User admin\n"

    @Test("removing a middle block leaves neighbours intact, no double blank")
    func removeMiddleBlock() throws {
        let result = try #require(SSHConfigParser.removing(alias: "chumon", from: threeBlockConfig))
        #expect(!result.contains("chumon"))
        #expect(result.contains("Host jodo"))
        #expect(result.contains("Host mandala"))
        // No consecutive blank lines.
        #expect(!result.contains("\n\n\n"))
    }

    @Test("removing the only block leaves no orphan content")
    func removeOnlyBlock() throws {
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: singleBlockConfig))
        #expect(!result.contains("jodo"))
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("removing the last block in a multi-block config leaves the others")
    func removeLastBlock() throws {
        let result = try #require(
            SSHConfigParser.removing(alias: "mandala", from: threeBlockConfig))
        #expect(!result.contains("mandala"))
        #expect(result.contains("Host jodo"))
        #expect(result.contains("Host chumon"))
    }

    @Test("removing the first block leaves the others intact")
    func removeFirstBlock() throws {
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: threeBlockConfig))
        #expect(!result.contains("Host jodo"))
        #expect(result.contains("Host chumon"))
        #expect(result.contains("Host mandala"))
        #expect(!result.hasPrefix("\n"))
    }

    @Test("an absent alias returns nil")
    func absentAliasReturnsNil() {
        #expect(SSHConfigParser.removing(alias: "ghost", from: threeBlockConfig) == nil)
    }

    @Test("removing from empty text returns nil")
    func removeFromEmptyReturnsNil() {
        #expect(SSHConfigParser.removing(alias: "jodo", from: "") == nil)
    }

    @Test("a block at EOF (no trailing newline) is removed correctly")
    func removeBlockAtEOFNoNewline() throws {
        let config = "Host jodo\n    HostName jodo.local\nHost chumon\n    HostName chumon.local"
        let result = try #require(SSHConfigParser.removing(alias: "chumon", from: config))
        #expect(!result.contains("chumon"))
        #expect(result.contains("Host jodo"))
    }

    @Test("an alias hidden by palana:hide is still removed by removing")
    func removeHiddenAlias() throws {
        let config = """
            Host jodo
                # palana: hide
                HostName jodo.local
            Host chumon
                HostName chumon.local
            """
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: config))
        #expect(!result.contains("Host jodo"))
        #expect(!result.contains("palana: hide"))
        #expect(result.contains("Host chumon"))
    }

    @Test("Include directives outside the removed block are preserved")
    func includeDirectiveSurvivesRemove() throws {
        let config = """
            Include config.d/*

            Host jodo
                HostName jodo.local

            Host chumon
                HostName chumon.local
            """
        let result = try #require(SSHConfigParser.removing(alias: "jodo", from: config))
        #expect(result.contains("Include config.d/*"))
        #expect(!result.contains("Host jodo"))
        #expect(result.contains("Host chumon"))
    }
}

// MARK: - Round-trip

@Suite("SSHConfigParser add+remove round-trip")
struct SSHConfigParserRoundTripTests {
    private let baseConfig = """
        Host jodo
            HostName 192.168.1.20
            User admin

        Host chumon
            HostName 192.168.1.21
        """

    @Test("adding then removing the same alias returns text equivalent to the original")
    func addThenRemoveRoundTrip() throws {
        let block = HostBlock(alias: "mandala", hostName: "192.168.1.190")
        let added = try #require(SSHConfigParser.adding(block, to: baseConfig))
        let removed = try #require(SSHConfigParser.removing(alias: "mandala", from: added))

        // Normalize trailing whitespace on both sides before comparing.
        let normalize: (String) -> String = { text in
            text
                .components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #expect(normalize(removed) == normalize(baseConfig))
    }

    @Test("round-trip preserves all original aliases")
    func roundTripPreservesAliases() throws {
        let block = HostBlock(alias: "kanyo", hostName: "192.168.1.50")
        let added = try #require(SSHConfigParser.adding(block, to: baseConfig))
        let removed = try #require(SSHConfigParser.removing(alias: "kanyo", from: added))
        let aliases = SSHConfigParser.hosts(in: removed)
        #expect(aliases.contains("jodo"))
        #expect(aliases.contains("chumon"))
        #expect(!aliases.contains("kanyo"))
    }
}
