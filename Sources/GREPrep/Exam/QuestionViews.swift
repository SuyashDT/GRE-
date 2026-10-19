import Charts
import SwiftUI
import GRECore

enum QuestionMode: Equatable {
    /// Timed test: answer freely, no feedback.
    case test
    /// Untimed drill: answer, then the answer is revealed with an explanation.
    case practice(revealed: Bool)
    /// Read-only review after a test.
    case review

    var isInteractive: Bool {
        switch self {
        case .test: return true
        case let .practice(revealed): return !revealed
        case .review: return false
        }
    }

    var showsFeedback: Bool { !isInteractive }
}

/// One question with its passage or data set, laid out like the real test:
/// stimulus on the left, question and answer choices on the right.
struct QuestionScreen: View {
    let question: Question
    let stimulus: Stimulus?
    @Binding var response: Response
    let mode: QuestionMode
    var timeSpent: Double?

    var body: some View {
        if let stimulus {
            HSplitView {
                ScrollView {
                    StimulusView(
                        stimulus: stimulus,
                        selection: question.format == .sentence ? $response.selected : nil,
                        correctSentence: mode.showsFeedback && question.format == .sentence ? question.correct?.first : nil,
                        isInteractive: mode.isInteractive
                    )
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 360, idealWidth: 560)
                ScrollView {
                    questionColumn
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 360, idealWidth: 520)
            }
        } else {
            ScrollView {
                questionColumn
                    .padding(32)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var questionColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.directions)
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if question.isComparison {
                ComparisonHeader(question: question)
            } else {
                RichText(question.prompt)
                    .font(.title3)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            answerArea

            if mode.showsFeedback {
                FeedbackView(question: question, response: response, timeSpent: timeSpent)
            }
        }
    }

    @ViewBuilder
    private var answerArea: some View {
        switch question.format {
        case .single, .multiple:
            ChoiceList(
                options: question.displayOptions,
                isMultiple: question.format == .multiple,
                selection: $response.selected,
                correct: mode.showsFeedback ? Set(question.correct ?? []) : nil,
                isInteractive: mode.isInteractive
            )
        case .blanks:
            BlanksView(
                blanks: question.blanks ?? [],
                choices: $response.blankChoices,
                correct: mode.showsFeedback ? question.correct : nil,
                isInteractive: mode.isInteractive
            )
        case .numeric:
            NumericEntryView(
                text: $response.numberText, prefix: question.entryPrefix, suffix: question.entrySuffix,
                isInteractive: mode.isInteractive
            )
        case .fraction:
            FractionEntryView(
                numerator: $response.numberText, denominator: $response.denominatorText,
                prefix: question.entryPrefix, suffix: question.entrySuffix, isInteractive: mode.isInteractive
            )
        case .sentence:
            let selected = response.selected.first
            Label(selected.map { "You selected sentence \($0 + 1)." } ?? "Click a sentence in the passage to select it.",
                  systemImage: "hand.point.up.left")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Quantitative comparison

struct ComparisonHeader: View {
    let question: Question

    var body: some View {
        VStack(spacing: 14) {
            let info = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !info.isEmpty && info != "Compare Quantity A and Quantity B." {
                RichText(info)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 0) {
                quantity("Quantity A", question.quantityA ?? "")
                Divider()
                quantity("Quantity B", question.quantityB ?? "")
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        }
    }

    private func quantity(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .underline()
            RichText(value)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Answer choices

struct ChoiceList: View {
    let options: [String]
    let isMultiple: Bool
    @Binding var selection: Set<Int>
    /// When set, correct options are highlighted.
    let correct: Set<Int>?
    let isInteractive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    toggle(index)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        indicator(index)
                        RichText(option)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        feedbackIcon(index)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(index), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(border(index), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isInteractive)
                .accessibilityLabel("Choice \(Question.letter(index)): \(option)")
                .accessibilityAddTraits(selection.contains(index) ? .isSelected : [])
            }
        }
    }

    private func toggle(_ index: Int) {
        guard isInteractive else { return }
        if isMultiple {
            if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
        } else {
            selection = [index]
        }
    }

    @ViewBuilder
    private func indicator(_ index: Int) -> some View {
        let isOn = selection.contains(index)
        if isMultiple {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .foregroundStyle(isOn ? Theme.selection : .secondary)
                .font(.title3)
        } else {
            Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isOn ? Theme.selection : .secondary)
                .font(.title3)
        }
    }

    @ViewBuilder
    private func feedbackIcon(_ index: Int) -> some View {
        if let correct {
            if correct.contains(index) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.correct)
            } else if selection.contains(index) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.incorrect)
            }
        }
    }

    private func background(_ index: Int) -> Color {
        if let correct {
            if correct.contains(index) { return Theme.correct.opacity(0.12) }
            if selection.contains(index) { return Theme.incorrect.opacity(0.1) }
            return .clear
        }
        return selection.contains(index) ? Theme.selection.opacity(0.1) : .clear
    }

    private func border(_ index: Int) -> Color {
        if let correct {
            if correct.contains(index) { return Theme.correct.opacity(0.6) }
            if selection.contains(index) { return Theme.incorrect.opacity(0.6) }
        }
        return selection.contains(index) ? Theme.selection.opacity(0.6) : Color.secondary.opacity(0.25)
    }
}

/// Text Completion answer area: one column of choices per blank.
struct BlanksView: View {
    let blanks: [[String]]
    @Binding var choices: [Int?]
    let correct: [Int]?
    let isInteractive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(blanks.enumerated()), id: \.offset) { blankIndex, options in
                VStack(spacing: 0) {
                    if blanks.count > 1 {
                        Text("Blank (\(Question.romanNumeral(blankIndex + 1)))")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                    }
                    ForEach(Array(options.enumerated()), id: \.offset) { optionIndex, option in
                        Button {
                            select(blankIndex, optionIndex)
                        } label: {
                            Text(option)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .padding(.horizontal, 8)
                                .background(cellBackground(blankIndex, optionIndex))
                                .foregroundStyle(isChosen(blankIndex, optionIndex) && correct == nil ? Color.white : Color.primary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isInteractive)
                        if optionIndex < options.count - 1 { Divider() }
                    }
                }
                .frame(maxWidth: 240)
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
            }
        }
    }

    private func isChosen(_ blank: Int, _ option: Int) -> Bool {
        choices.indices.contains(blank) && choices[blank] == option
    }

    private func select(_ blank: Int, _ option: Int) {
        guard isInteractive else { return }
        var updated = choices
        if updated.count < blanks.count {
            updated += Array(repeating: nil, count: blanks.count - updated.count)
        }
        updated[blank] = updated[blank] == option ? nil : option
        choices = updated
    }

    private func cellBackground(_ blank: Int, _ option: Int) -> Color {
        if let correct, correct.indices.contains(blank) {
            if correct[blank] == option { return Theme.correct.opacity(0.25) }
            if isChosen(blank, option) { return Theme.incorrect.opacity(0.2) }
            return .clear
        }
        return isChosen(blank, option) ? Theme.selection : .clear
    }
}

struct NumericEntryView: View {
    @Binding var text: String
    let prefix: String?
    let suffix: String?
    let isInteractive: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let prefix { Text(prefix).font(.title3) }
            EntryBox(text: $text, isInteractive: isInteractive)
            if let suffix { Text(suffix).font(.title3) }
        }
    }
}

struct FractionEntryView: View {
    @Binding var numerator: String
    @Binding var denominator: String
    let prefix: String?
    let suffix: String?
    let isInteractive: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let prefix { Text(prefix).font(.title3) }
            VStack(spacing: 6) {
                EntryBox(text: $numerator, isInteractive: isInteractive)
                Rectangle().frame(width: 140, height: 2)
                EntryBox(text: $denominator, isInteractive: isInteractive)
            }
            if let suffix { Text(suffix).font(.title3) }
        }
    }
}

/// A numeric entry box that only accepts digits, one decimal point and a leading minus sign.
struct EntryBox: View {
    @Binding var text: String
    let isInteractive: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.title3, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 140)
            .disabled(!isInteractive)
            .onChange(of: text) { _, newValue in
                let filtered = Self.filter(newValue)
                if filtered != newValue { text = filtered }
            }
    }

    static func filter(_ value: String) -> String {
        var result = ""
        for character in value.replacingOccurrences(of: "\u{2212}", with: "-") {
            if character.isNumber && character.isASCII {
                result.append(character)
            } else if character == "." && !result.contains(".") {
                result.append(character)
            } else if character == "-" && result.isEmpty {
                result.append(character)
            }
        }
        return String(result.prefix(12))
    }
}

// MARK: - Feedback

struct FeedbackView: View {
    let question: Question
    let response: Response
    var timeSpent: Double?

    var body: some View {
        let state = question.state(of: response)
        let isCorrect = question.isCorrect(response)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if state == .unanswered {
                    Label("Not answered", systemImage: "minus.circle.fill").foregroundStyle(.secondary)
                } else if isCorrect {
                    Label("Correct", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.correct)
                } else {
                    Label("Incorrect", systemImage: "xmark.circle.fill").foregroundStyle(Theme.incorrect)
                }
                Spacer()
                if let timeSpent, timeSpent > 0 {
                    Label(Format.minutesSeconds(timeSpent), systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.headline)

            if !isCorrect {
                if state != .unanswered {
                    LabeledContent("Your answer") { RichText(question.responseText(response)) }
                }
                LabeledContent("Correct answer") { RichText(question.correctAnswerText) }
            }

            Divider()
            Text("Explanation").font(.subheadline.weight(.semibold))
            RichText(question.explanation)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Pill(text: question.category.title, color: Theme.color(for: question.category.measure))
                Pill(text: question.topic)
                Pill(text: "Difficulty \(question.difficulty)/5")
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Stimulus

struct StimulusView: View {
    let stimulus: Stimulus
    /// Non-nil for select-in-passage questions: the selected sentence index.
    var selection: Binding<Set<Int>>?
    var correctSentence: Int?
    var isInteractive: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = stimulus.title {
                Text(title).font(.headline)
            }
            switch stimulus.kind {
            case .passage:
                passage
            case .data:
                DataStimulusView(stimulus: stimulus)
            }
        }
    }

    private var passage: some View {
        let starts = stimulus.paragraphStartIndices
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((stimulus.paragraphs ?? []).enumerated()), id: \.offset) { index, paragraph in
                Text(paragraphText(paragraph, start: starts[safe: index] ?? 0))
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .tint(Color.primary)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "gre-sentence", let index = Int(url.host ?? ""), isInteractive, let selection else {
                return .handled
            }
            selection.wrappedValue = selection.wrappedValue == [index] ? [] : [index]
            return .handled
        })
    }

    private func paragraphText(_ sentences: [String], start: Int) -> AttributedString {
        var text = AttributedString()
        for (offset, sentence) in sentences.enumerated() {
            let index = start + offset
            var piece = RichText.attributed(sentence)
            if selection != nil {
                piece.link = URL(string: "gre-sentence://\(index)")
                if let correctSentence, correctSentence == index {
                    piece[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Theme.correct.opacity(0.3)
                } else if selection?.wrappedValue.contains(index) == true {
                    piece[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] =
                        correctSentence == nil ? Theme.highlight : Theme.incorrect.opacity(0.25)
                }
            }
            text += piece
            if offset < sentences.count - 1 { text += AttributedString(" ") }
        }
        return text
    }
}

struct DataStimulusView: View {
    let stimulus: Stimulus

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let intro = stimulus.intro {
                RichText(intro).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array((stimulus.tables ?? []).enumerated()), id: \.offset) { _, table in
                DataTableView(table: table)
            }
            ForEach(Array((stimulus.charts ?? []).enumerated()), id: \.offset) { _, chart in
                DataChartView(spec: chart)
            }
        }
    }
}

struct DataTableView: View {
    let table: DataTable

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = table.title {
                Text(title).font(.subheadline.weight(.semibold))
            }
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                        cell(column, header: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            cell(value, header: false)
                                .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
        }
    }

    private func cell(_ text: String, header: Bool) -> some View {
        Text(text)
            .font(header ? .subheadline.weight(.semibold) : .body)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(header ? Color.secondary.opacity(0.14) : Color.clear)
            .border(Color.secondary.opacity(0.2), width: 0.5)
    }
}

struct DataChartView: View {
    let spec: ChartSpec

    struct Point: Identifiable {
        let id: String
        let category: String
        let series: String
        let value: Double
    }

    private var points: [Point] {
        spec.series.flatMap { series in
            zip(spec.categories, series.values).map { category, value in
                Point(id: "\(series.name)|\(category)", category: category, series: series.name, value: value)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = spec.title {
                Text(title).font(.subheadline.weight(.semibold))
            }
            chart
                .frame(height: spec.type == .pie ? 300 : 260)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch spec.type {
        case .bar:
            Chart(points) { point in
                BarMark(
                    x: .value(spec.xLabel ?? "Category", point.category),
                    y: .value(spec.yLabel ?? "Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .position(by: .value("Series", point.series))
                .annotation(position: .top) {
                    Text(NumberFormatting.plain(point.value))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxisLabel { Text(spec.xLabel ?? "") }
            .chartYAxisLabel { Text(spec.yLabel ?? "") }
        case .line:
            Chart(points) { point in
                LineMark(
                    x: .value(spec.xLabel ?? "Category", point.category),
                    y: .value(spec.yLabel ?? "Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .symbol(by: .value("Series", point.series))
                PointMark(
                    x: .value(spec.xLabel ?? "Category", point.category),
                    y: .value(spec.yLabel ?? "Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .annotation(position: .top) {
                    Text(NumberFormatting.plain(point.value))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxisLabel { Text(spec.xLabel ?? "") }
            .chartYAxisLabel { Text(spec.yLabel ?? "") }
        case .pie:
            Chart(points) { point in
                SectorMark(angle: .value("Value", point.value), angularInset: 1)
                    .foregroundStyle(by: .value("Category", point.category))
                    .annotation(position: .overlay) {
                        Text(NumberFormatting.plain(point.value))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
    }
}
