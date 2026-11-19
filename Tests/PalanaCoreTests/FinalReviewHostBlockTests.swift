// The 2026-11-18 final review's F08: host-block values are written as
// ssh_config arguments, so a key path with spaces stays one argument and
// a value can never start a directive of its own.

import Testing

@testable import PalanaCore

@Suite("Final review F08 — host block serialization")
struct FinalReviewHostBlockTests {
    @Test("a key path with spaces is double-quoted; plain values stay bare")
    func spacedPathIsQuoted() {
        let block = HostBlock(
            alias: "nas", hostName: "nas.local", user: "op", identityFile: "/Users/op/keys with spaces/id_ed25519")
        #expect(block.validate().isEmpty)
        #expect(
            block.compose()
                == "Host nas\n    HostName nas.local\n    User op\n    IdentityFile \"/Users/op/keys with spaces/id_ed25519\""
        )
    }

    @Test("quotes and backslashes are escaped inside the quoted argument; % is doubled for IdentityFile")
    func escapes() {
        #expect(HostBlock.argument(#"/k/a "b" c"#) == #""/k/a \"b\" c""#)
        #expect(HostBlock.argument(#"/k/back\slash"#) == #""/k/back\\slash""#)
        #expect(HostBlock.argument("/k/it's#1") == #""/k/it's#1""#)
        #expect(HostBlock.argument("/plain/path") == "/plain/path")
        let block = HostBlock(alias: "nas", hostName: "h", identityFile: "/k/100%/id")
        #expect(block.compose().hasSuffix("IdentityFile /k/100%%/id"))
    }

    @Test("a line break or control character in any written field is refused, by field")
    func controlCharactersRefused() {
        let block = HostBlock(
            alias: "nas", hostName: "h\nProxyCommand x", user: "op\r", identityFile: "/k/id\nHost *")
        let errors = block.validate()
        #expect(errors.contains(.fieldContainsControlCharacter("HostName")))
        #expect(errors.contains(.fieldContainsControlCharacter("User")))
        #expect(errors.contains(.fieldContainsControlCharacter("IdentityFile")))
    }

    @Test("a hostname with a space is refused")
    func hostNameWhitespaceRefused() {
        #expect(HostBlock(alias: "nas", hostName: "nas local").validate() == [.hostNameContainsWhitespace])
    }
}
