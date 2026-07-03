// Throwaway entry model and loose parser. The committed FileEntry model
// is ho-04's, with parsing rigor this spike deliberately does not have.

import Foundation

public struct SpikeEntry: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let path: String
    public let size: Int64
    public let mtime: Date
    public let kind: String

    public init(id: Int, name: String, path: String, size: Int64, mtime: Date, kind: String) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.mtime = mtime
        self.kind = kind
    }
}

public enum SpikeParser {
    /// Parses `find -printf "%y\t%s\t%T@\t%p\n"` output.
    public static func parse(_ data: Data) -> [SpikeEntry] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var entries: [SpikeEntry] = []
        var nextID = 0
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }
            let path = String(fields[3])
            entries.append(
                SpikeEntry(
                    id: nextID,
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    size: Int64(fields[1]) ?? 0,
                    mtime: Date(timeIntervalSince1970: Double(fields[2]) ?? 0),
                    kind: fields[0] == "d" ? "directory" : "file"
                ))
            nextID += 1
        }
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return entries
    }
}
