// Reads a composed command the way a POSIX shell would split it — words
// with their quoting removed, grouped into simple commands at unquoted
// separators. Enactment's source-removal check judges what the shell
// would pass as arguments, not whitespace fragments of a quoted path:
// a file named `a --remove-source-files b` is one operand, never an
// option (review 2026-11-18, F11).
//
// Deliberately small: single quotes, double quotes with their four
// escapes, backslash outside quotes, and the separators ; | & ( ) and
// newline. Expansions ($VAR, $(...), backticks) are kept as literal text;
// the check this serves never composes them.

/// One shell word: as written, and as the shell would pass it.
struct ShellWord: Equatable {
    /// The word exactly as it appears in the command.
    var raw: String
    /// The word after quote removal — the argument the program receives.
    var value: String
}

enum ShellWords {
    /// The simple commands in `command`, each a list of words.
    ///
    /// An unterminated quote runs to the end of the text, as it would
    /// leave the shell waiting for more input; the words read so far are
    /// still returned.
    static func simpleCommands(in command: String) -> [[ShellWord]] {
        var reader = Reader()
        for character in command {
            reader.take(character)
        }
        reader.endWord()
        reader.endCommand()
        return reader.commands
    }

    /// A character-at-a-time reader; its state is the quote it is inside.
    private struct Reader {
        var commands: [[ShellWord]] = []
        var words: [ShellWord] = []
        var raw = ""
        var value = ""
        var inWord = false
        var quote: Character?
        var escaping = false

        mutating func take(_ character: Character) {
            if escaping {
                escaping = false
                raw.append(character)
                // Inside double quotes a backslash escapes only $ ` " \ and
                // newline; before anything else it stays.
                if quote == "\"", !"$`\"\\\n".contains(character) { value.append("\\") }
                if character != "\n" { value.append(character) }
                return
            }
            switch quote {
            case "'":
                raw.append(character)
                if character == "'" { quote = nil } else { value.append(character) }
            case "\"":
                raw.append(character)
                if character == "\"" {
                    quote = nil
                } else if character == "\\" {
                    escaping = true
                } else {
                    value.append(character)
                }
            default:
                takeUnquoted(character)
            }
        }

        private mutating func takeUnquoted(_ character: Character) {
            switch character {
            case " ", "\t":
                endWord()
            case "\n", "\r\n", ";", "|", "&", "(", ")":
                endWord()
                endCommand()
            case "'", "\"":
                inWord = true
                raw.append(character)
                quote = character
            case "\\":
                inWord = true
                raw.append(character)
                escaping = true
            default:
                inWord = true
                raw.append(character)
                value.append(character)
            }
        }

        mutating func endWord() {
            guard inWord else { return }
            words.append(ShellWord(raw: raw, value: value))
            raw = ""
            value = ""
            inWord = false
        }

        mutating func endCommand() {
            guard !words.isEmpty else { return }
            commands.append(words)
            words = []
        }
    }
}

extension PlanEngine {
    /// The programs whose arguments are themselves shell text another
    /// shell will read — `ssh host 'cmd'`, `sh -c 'cmd'`.
    private static let commandCarriers: Set<String> = ["ssh", "sh", "bash", "dash", "zsh", "ksh", "env"]

    /// True when the shell, reading `command`, would pass a source-removal
    /// option to some program.
    ///
    /// Each simple command's arguments are judged after quote removal, up
    /// to an unquoted `--`, after which everything is an operand. A quoted
    /// path that merely contains an option-shaped word is one argument
    /// that is not an option. The arguments of `ssh`, `sh`, or `env` are
    /// read again as command text — the shell at the other end joins and
    /// reads them — so an option nested there is still found. In carried
    /// text the program's position is unknown (ssh's destination comes
    /// first), so any carrier word ahead of the operands is followed.
    /// Nesting deeper than any composed plan is refused.
    static func commandNamesSourceRemoval(_ command: String, depth: Int = 0) -> Bool {
        guard depth < 4 else { return true }
        for words in ShellWords.simpleCommands(in: command) {
            var operands = false
            for (index, word) in words.enumerated() {
                if index > 0, word.raw == "--" {
                    operands = true
                    continue
                }
                guard !operands else { break }
                if index > 0, namesSourceRemoval(word.value) { return true }
                guard index == 0 || depth > 0, commandCarriers.contains(lastPathComponent(of: word.value))
                else { continue }
                let carried = words[(index + 1)...].map(\.value).joined(separator: " ")
                if commandNamesSourceRemoval(carried, depth: depth + 1) { return true }
            }
        }
        return false
    }

    private static func lastPathComponent(of path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
    }
}
