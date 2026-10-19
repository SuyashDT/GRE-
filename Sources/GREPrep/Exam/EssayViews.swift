import AppKit
import SwiftUI
import GRECore

struct EssayTaskView: View {
    @Bindable var session: ExamSession

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Analyze an Issue")
                        .font(.title2.weight(.semibold))
                    Text("You have \(session.test.essay.minutes) minutes to plan and compose a response to the issue below. A response to any other issue will receive a score of zero.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.test.essay.statement)
                        .font(.title3.weight(.medium))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.test.essay.instructions)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Trained readers evaluate how well you consider the complexities of the issue, organize and develop your ideas, support them with relevant reasons and examples, and control the elements of standard written English.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .frame(minWidth: 320, idealWidth: 420)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your response")
                        .font(.headline)
                    Spacer()
                    Text("\(session.essayWordCount) words")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                PlainTextEditor(text: $session.essayText)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
                Text("Cut, copy, paste and undo work as usual. There is no spell-check, as on the real test.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }
}

/// A plain NSTextView with every writing aid turned off (spelling, grammar,
/// autocorrect, smart quotes, text completion), matching the GRE essay editor.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isEditable = isEditable
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Floating, draggable GRE-style calculator.
struct CalculatorPanel: View {
    @Bindable var session: ExamSession
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    private let rows: [[(String, CalculatorKey)]] = [
        [("MR", .memoryRecall), ("MC", .memoryClear), ("M+", .memoryAdd), ("(", .openParen), (")", .closeParen)],
        [("7", .digit(7)), ("8", .digit(8)), ("9", .digit(9)), ("÷", .divide), ("C", .clear)],
        [("4", .digit(4)), ("5", .digit(5)), ("6", .digit(6)), ("×", .multiply), ("CE", .clearEntry)],
        [("1", .digit(1)), ("2", .digit(2)), ("3", .digit(3)), ("−", .subtract), ("√", .squareRoot)],
        [("0", .digit(0)), (".", .decimalPoint), ("±", .negate), ("+", .add), ("=", .equals)],
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Calculator").font(.caption.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button {
                    session.isCalculatorVisible = false
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.examBar)
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.calculator.pendingExpression)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack {
                    if session.calculator.hasMemory {
                        Text("M").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(session.calculator.display)
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            .padding(.horizontal, 10)

            Button("Transfer Display") { session.transferDisplay() }
                .controlSize(.small)
                .disabled(!session.canTransferDisplay)

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(0..<rows[rowIndex].count, id: \.self) { column in
                            let key = rows[rowIndex][column]
                            Button {
                                session.calculator.press(key.1)
                            } label: {
                                Text(key.0)
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 42, height: 30)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom], 10)
        }
        .frame(width: 270)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 12, y: 4)
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
    }
}
