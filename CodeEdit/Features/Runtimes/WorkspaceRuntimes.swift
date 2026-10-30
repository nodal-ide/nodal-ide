import Foundation

/// A runtime selection for one kind (a version and optional package manager).
struct RuntimeSelection: Codable, Hashable {
    var version: String?
    var packageManager: String?

    var isEmpty: Bool {
        (version?.isEmpty ?? true) && (packageManager?.isEmpty ?? true)
    }
}

/// The `runtimes` section of the project settings.
struct WorkspaceRuntimes: Codable, Hashable {
    var selections: [RuntimeKind: RuntimeSelection] = [:]

    var php: RuntimeSelection {
        get { selections[.php] ?? .init() }
        set { selections[.php] = newValue }
    }

    var node: RuntimeSelection {
        get { selections[.node] ?? .init() }
        set { selections[.node] = newValue }
    }

    init(selections: [RuntimeKind: RuntimeSelection] = [:]) {
        self.selections = selections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var parsed: [RuntimeKind: RuntimeSelection] = [:]

        for key in container.allKeys {
            if let kind = RuntimeKind(rawValue: key.stringValue) {
                if let selection = try? container.decode(RuntimeSelection.self, forKey: key) {
                    parsed[kind] = selection
                }
            }
        }
        self.selections = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (kind, selection) in selections {
            guard !selection.isEmpty else { continue }
            guard let key = DynamicCodingKey(stringValue: kind.rawValue) else { continue }
            try container.encode(selection, forKey: key)
        }
    }

    func selection(for kind: RuntimeKind) -> RuntimeSelection {
        selections[kind] ?? .init()
    }

    mutating func setSelection(_ selection: RuntimeSelection, for kind: RuntimeKind) {
        selections[kind] = selection
    }

    var isEmpty: Bool {
        selections.values.allSatisfy(\.isEmpty)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
