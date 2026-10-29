//
//  LineChangeMapper.swift
//  CodeEdit
//

import CodeEditSourceEditor

/// Maps a parsed unified diff onto the gutter's ``LineChange`` model.
///
/// One pass over the diff, no document access and no string formatting: hunks arrive with parsed line numbers, so the
/// mapping is linear in the number of diff lines.
enum LineChangeMapper {
    static func changes(from diff: FileDiff) -> [LineChange] {
        var result: [LineChange] = []
        for hunk in diff.hunks {
            append(hunk, to: &result)
        }
        return coalesce(result)
    }

    private static func append(_ hunk: DiffHunk, to result: inout [LineChange]) {
        var additions = 0
        var deletions = 0
        var runs = AdditionRuns()

        for line in hunk.lines {
            switch line.kind {
            case .addition:
                additions += 1
                if let number = line.newLineNumber {
                    runs.append(number)
                }
            case .deletion:
                deletions += 1
            case .context:
                // Not produced by a `-U0` diff, but a context line still separates addition runs.
                runs.flush()
            }
        }
        runs.flush()

        let markerLine = max(1, hunk.newStart)
        guard !runs.ranges.isEmpty else {
            if deletions > 0 {
                result.append(LineChange(kind: .deleted, lines: markerLine...markerLine))
            }
            return
        }

        let kind: LineChange.Kind = deletions == 0 ? .added : .modified
        for run in runs.ranges {
            result.append(LineChange(kind: kind, lines: run))
        }
        // A modified block already shows where lines changed; only flag a deletion that is larger than the block
        // replacing it, so a plain 1:1 replacement does not gain a second marker.
        if deletions > additions {
            result.append(LineChange(kind: .deleted, lines: markerLine...markerLine))
        }
    }

    /// Collects consecutive new-file line numbers into runs.
    private struct AdditionRuns {
        private(set) var ranges: [ClosedRange<Int>] = []
        private var start: Int?
        private var end = 0

        mutating func append(_ line: Int) {
            guard let current = start else {
                start = line
                end = line
                return
            }
            if line == end + 1 {
                end = line
            } else {
                ranges.append(current...end)
                start = line
                end = line
            }
        }

        mutating func flush() {
            if let start {
                ranges.append(start...end)
            }
            start = nil
        }
    }

    /// Sorts by position and merges adjacent same-kind ranges so the gutter draws one bar per block.
    private static func coalesce(_ changes: [LineChange]) -> [LineChange] {
        guard changes.count > 1 else { return changes }
        let sorted = changes.sorted { lhs, rhs in
            if lhs.lines.lowerBound == rhs.lines.lowerBound {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }
            return lhs.lines.lowerBound < rhs.lines.lowerBound
        }

        var result: [LineChange] = []
        result.reserveCapacity(sorted.count)
        for change in sorted {
            if let last = result.last,
               last.kind == change.kind,
               change.lines.lowerBound <= last.lines.upperBound + 1 {
                result[result.count - 1] = LineChange(
                    kind: last.kind,
                    lines: last.lines.lowerBound...max(last.lines.upperBound, change.lines.upperBound)
                )
            } else {
                result.append(change)
            }
        }
        return result
    }
}

private extension LineChange.Kind {
    var sortRank: Int {
        switch self {
        case .added: return 0
        case .modified: return 1
        case .deleted: return 2
        }
    }
}
