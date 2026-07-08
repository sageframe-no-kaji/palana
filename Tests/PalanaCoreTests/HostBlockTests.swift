// HostBlock unit battery — compose, validate, and the parser's add/remove
// transforms. Pure text; no ssh, no filesystem outside temp dirs.

import Testing

@testable import PalanaCore

// MARK: - compose

@Suite("HostBlock compose")
struct HostBlockComposeTests {
    @Test("full block emits all five lines in order with four-space indent")
    func fullBlock() {
        let block = HostBlock(
            alias: "kanyo",
            hostName: "192.168.1.50",
            user: "deploy",
            port: 2222,
            identityFile: "~/.ssh/id_ed25519"
        )
        let expected = """
            Host kanyo
                HostName 192.168.1.50
                User deploy
                Port 2222
                IdentityFile ~/.ssh/id_ed25519
            """
        #expect(block.compose() == expected)
    }

    @Test("minimal block emits only Host and HostName")
    func minimalBlock() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local")
        let expected = """
            Host jodo
                HostName jodo.local
            """
        #expect(block.compose() == expected)
    }

    @Test("user present, port and identityFile nil — only User line added")
    func userOnly() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", user: "admin")
        let text = block.compose()
        #expect(text.contains("    User admin"))
        #expect(!text.contains("Port"))
        #expect(!text.contains("IdentityFile"))
    }

    @Test("port present, user and identityFile nil — only Port line added")
    func portOnly() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 2222)
        let text = block.compose()
        #expect(text.contains("    Port 2222"))
        #expect(!text.contains("User"))
        #expect(!text.contains("IdentityFile"))
    }

    @Test("identityFile present, user and port nil — only IdentityFile line added")
    func identityFileOnly() {
        let block = HostBlock(
            alias: "jodo",
            hostName: "jodo.local",
            identityFile: "~/.ssh/jodo_ed25519"
        )
        let text = block.compose()
        #expect(text.contains("    IdentityFile ~/.ssh/jodo_ed25519"))
        #expect(!text.contains("User"))
        #expect(!text.contains("Port"))
    }

    @Test("composed block has no trailing blank line")
    func noTrailingBlankLine() {
        let block = HostBlock(
            alias: "jodo",
            hostName: "jodo.local",
            user: "admin",
            port: 22,
            identityFile: "~/.ssh/id_ed25519"
        )
        let text = block.compose()
        #expect(!text.hasSuffix("\n"))
    }

    @Test("four-space indent is literal spaces, not tabs")
    func indentIsSpaces() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 22)
        for line in block.compose().components(separatedBy: "\n").dropFirst() {
            #expect(line.hasPrefix("    "))
            #expect(!line.hasPrefix("\t"))
        }
    }

    @Test("empty user string is suppressed from compose")
    func emptyUserSuppressed() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", user: "")
        let text = block.compose()
        #expect(!text.contains("User"))
    }

    @Test("empty identityFile string is suppressed from compose")
    func emptyIdentityFileSuppressed() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", identityFile: "")
        let text = block.compose()
        #expect(!text.contains("IdentityFile"))
    }
}

// MARK: - validate

@Suite("HostBlock validate")
struct HostBlockValidateTests {
    @Test("a fully valid block yields no errors")
    func validBlockNoErrors() {
        let block = HostBlock(
            alias: "jodo",
            hostName: "jodo.local",
            user: "admin",
            port: 22,
            identityFile: "~/.ssh/id_ed25519"
        )
        #expect(block.validate().isEmpty)
    }

    @Test("minimal valid block yields no errors")
    func minimalValidBlock() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local")
        #expect(block.validate().isEmpty)
    }

    @Test("empty alias yields aliasEmpty")
    func emptyAlias() {
        let block = HostBlock(alias: "", hostName: "jodo.local")
        #expect(block.validate() == [.aliasEmpty])
    }

    @Test("alias with a space yields aliasContainsWhitespace")
    func aliasWithSpace() {
        let block = HostBlock(alias: "my host", hostName: "jodo.local")
        #expect(block.validate() == [.aliasContainsWhitespace])
    }

    @Test("alias with a tab yields aliasContainsWhitespace")
    func aliasWithTab() {
        let block = HostBlock(alias: "my\thost", hostName: "jodo.local")
        #expect(block.validate() == [.aliasContainsWhitespace])
    }

    @Test("wildcard alias yields aliasIsWildcard")
    func wildcardAlias() {
        let block = HostBlock(alias: "*.sageframe.net", hostName: "jodo.local")
        #expect(block.validate() == [.aliasIsWildcard])
    }

    @Test("question-mark alias yields aliasIsWildcard")
    func questionMarkAlias() {
        let block = HostBlock(alias: "?jodo", hostName: "jodo.local")
        #expect(block.validate() == [.aliasIsWildcard])
    }

    @Test("negation alias yields aliasIsWildcard")
    func negationAlias() {
        let block = HostBlock(alias: "!jodo", hostName: "jodo.local")
        #expect(block.validate() == [.aliasIsWildcard])
    }

    @Test("empty hostName yields hostNameEmpty")
    func emptyHostName() {
        let block = HostBlock(alias: "jodo", hostName: "")
        #expect(block.validate() == [.hostNameEmpty])
    }

    @Test("port 0 yields portOutOfRange")
    func portZero() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 0)
        #expect(block.validate() == [.portOutOfRange(0)])
    }

    @Test("port 65536 yields portOutOfRange")
    func portTooHigh() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 65536)
        #expect(block.validate() == [.portOutOfRange(65536)])
    }

    @Test("port 70000 yields portOutOfRange")
    func portSeventy() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 70_000)
        #expect(block.validate() == [.portOutOfRange(70_000)])
    }

    @Test("port 1 is the legal minimum")
    func portMinimum() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 1)
        #expect(block.validate().isEmpty)
    }

    @Test("port 65535 is the legal maximum")
    func portMaximum() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: 65535)
        #expect(block.validate().isEmpty)
    }

    @Test("multiple independent broken rules all appear")
    func multipleErrors() {
        let block = HostBlock(alias: "", hostName: "")
        let errors = block.validate()
        #expect(errors.contains(.aliasEmpty))
        #expect(errors.contains(.hostNameEmpty))
    }

    @Test("nil port carries no validation penalty")
    func nilPortIsValid() {
        let block = HostBlock(alias: "jodo", hostName: "jodo.local", port: nil)
        #expect(block.validate().isEmpty)
    }
}
