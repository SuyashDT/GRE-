import SwiftUI
import GRECore

enum Theme {
    /// Dark slate bar across the top of the exam, like the real test's interface.
    static let examBar = Color(red: 0.13, green: 0.22, blue: 0.30)
    static let examSubBar = Color(nsColor: .controlBackgroundColor)
    static let selection = Color.accentColor
    static let correct = Color(red: 0.13, green: 0.6, blue: 0.33)
    static let incorrect = Color(red: 0.82, green: 0.22, blue: 0.2)
    static let marked = Color.orange
    static let highlight = Color.yellow.opacity(0.45)

    static func color(for measure: Measure) -> Color {
        measure == .verbal ? .indigo : .teal
    }

    static func color(for area: Lesson.Area) -> Color {
        switch area {
        case .general: return .gray
        case .writing: return .purple
        case .verbal: return .indigo
        case .quant: return .teal
        }
    }

    static func icon(for category: QuestionCategory) -> String {
        switch category {
        case .textCompletion: return "text.insert"
        case .sentenceEquivalence: return "equal.square"
        case .readingComprehension: return "book"
        case .quantitativeComparison: return "lessthan.square"
        case .problemSolving: return "function"
        case .multipleAnswer: return "checklist"
        case .numericEntry: return "number.square"
        case .dataInterpretation: return "chart.bar.doc.horizontal"
        }
    }
}

enum Format {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func minutesSeconds(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Inline Markdown (bold/italic) with fill-in blanks kept as literal underscores.
struct RichText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(Self.attributed(text))
    }

    static func attributed(_ text: String) -> AttributedString {
        let escaped = escapeBlanks(text)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: escaped, options: options)) ?? AttributedString(text)
    }

    /// "_____" would otherwise be read as emphasis markers.
    static func escapeBlanks(_ text: String) -> String {
        var result = ""
        var run = 0
        func flush() {
            if run >= 3 {
                result += String(repeating: "\\_", count: run)
            } else {
                result += String(repeating: "_", count: run)
            }
            run = 0
        }
        for character in text {
            if character == "_" {
                run += 1
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}

/// Renders a lesson body: paragraphs separated by blank lines, and "- " bullet lists.
struct MarkdownBlocks: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                if chunk.isList {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(chunk.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(chunk.ordered ? "\(line.number)." : "•")
                                    .foregroundStyle(.secondary)
                                RichText(line.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    RichText(chunk.lines.map(\.text).joined(separator: " "))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .lineSpacing(3)
    }

    struct Line {
        let number: Int
        let text: String
    }

    struct Chunk {
        let isList: Bool
        let ordered: Bool
        let lines: [Line]
    }

    var chunks: [Chunk] {
        text.components(separatedBy: "\n\n").compactMap { block -> Chunk? in
            let rawLines = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !rawLines.isEmpty else { return nil }
            let bullets = rawLines.allSatisfy { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            if bullets {
                return Chunk(isList: true, ordered: false, lines: rawLines.enumerated().map {
                    Line(number: $0.offset + 1, text: String($0.element.dropFirst(2)))
                })
            }
            let numbered = rawLines.allSatisfy { line in
                guard let dot = line.firstIndex(of: ".") else { return false }
                return !line[..<dot].isEmpty && line[..<dot].allSatisfy(\.isNumber)
            }
            if numbered {
                return Chunk(isList: true, ordered: true, lines: rawLines.enumerated().map { offset, line in
                    let dot = line.firstIndex(of: ".")!
                    let text = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
                    return Line(number: offset + 1, text: text)
                })
            }
            return Chunk(isList: false, ordered: false, lines: rawLines.map { Line(number: 0, text: $0) })
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
