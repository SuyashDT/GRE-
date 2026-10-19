import Foundation

public enum CalculatorKey: Hashable, Sendable {
    case digit(Int)
    case decimalPoint
    case add, subtract, multiply, divide
    case openParen, closeParen
    case equals
    case squareRoot
    case negate
    case clear
    case clearEntry
    case memoryRecall, memoryClear, memoryAdd
}

/// The GRE on-screen calculator: four functions, square root, sign change,
/// parentheses and memory, following the standard order of operations.
public struct CalculatorEngine: Sendable, Equatable {
    enum Token: Equatable, Sendable {
        case number(Double)
        case op(Character)
        case open
        case close
    }

    /// Digits shown on the GRE calculator display.
    public static let maxDigits = 8

    private(set) var tokens: [Token] = []
    /// The number being typed, as text.
    private(set) var entry: String = ""
    /// Value shown after an operation completes (when `entry` is empty).
    private(set) var shownValue: Double = 0
    private(set) var justEvaluated = false
    /// The entry holds a computed value (√, ±, MR), so typing starts a new number.
    private(set) var entryIsResult = false
    public private(set) var memory: Double = 0
    public private(set) var hasError = false

    public init() {}

    public var hasMemory: Bool { memory != 0 }

    /// The current display contents.
    public var display: String {
        if hasError { return "Error" }
        if !entry.isEmpty { return entry }
        return Self.format(shownValue)
    }

    /// The expression waiting to be evaluated, e.g. "3 + 4 ×".
    public var pendingExpression: String {
        tokens.map { token -> String in
            switch token {
            case let .number(value): return Self.format(value)
            case let .op(symbol): return String(symbol)
            case .open: return "("
            case .close: return ")"
            }
        }.joined(separator: " ")
    }

    /// Numeric value of the display, for "Transfer Display".
    public var displayValue: Double? {
        hasError ? nil : (entry.isEmpty ? shownValue : Double(entry))
    }

    public mutating func press(_ key: CalculatorKey) {
        if hasError, key != .clear { return }
        switch key {
        case let .digit(digit):
            if justEvaluated { resetExpression() }
            if entryIsResult { entry = ""; entryIsResult = false }
            if entry == "0" { entry = "" }
            if entry == "-0" { entry = "-" }
            guard entry.filter(\.isNumber).count < Self.maxDigits else { return }
            entry += String(digit)
        case .decimalPoint:
            if justEvaluated { resetExpression() }
            if entryIsResult { entry = ""; entryIsResult = false }
            guard !entry.contains(".") else { return }
            entry = (entry.isEmpty || entry == "-") ? entry + "0." : entry + "."
        case .add: applyOperator("+")
        case .subtract: applyOperator("−")
        case .multiply: applyOperator("×")
        case .divide: applyOperator("÷")
        case .openParen:
            if justEvaluated { resetExpression() }
            if !entry.isEmpty { return } // a number can't be followed directly by "("
            if case .number = tokens.last { return }
            if case .close = tokens.last { return }
            tokens.append(.open)
        case .closeParen:
            let opens = tokens.filter { $0 == .open }.count
            let closes = tokens.filter { $0 == .close }.count
            guard opens > closes else { return }
            commitEntry()
            if case .op = tokens.last { tokens.removeLast() }
            if case .open = tokens.last { tokens.removeLast(); return }
            tokens.append(.close)
            refreshShownValue()
        case .equals:
            commitEntry()
            if case .op = tokens.last { tokens.removeLast() }
            let opens = tokens.filter { $0 == .open }.count
            let closes = tokens.filter { $0 == .close }.count
            tokens += Array(repeating: .close, count: max(0, opens - closes))
            guard !tokens.isEmpty else { return }
            if let value = Self.evaluate(tokens) {
                setResult(value)
            } else {
                hasError = true
            }
            tokens = []
            justEvaluated = true
        case .squareRoot:
            let value = currentValue
            guard value >= 0 else { hasError = true; return }
            replaceCurrent(with: value.squareRoot())
        case .negate:
            if !entry.isEmpty {
                entry = entry.hasPrefix("-") ? String(entry.dropFirst()) : "-" + entry
            } else {
                replaceCurrent(with: -shownValue)
            }
        case .clear:
            self = CalculatorEngine(memory: memory)
        case .clearEntry:
            entry = ""
            entryIsResult = false
            shownValue = 0
        case .memoryRecall:
            if justEvaluated { resetExpression() }
            setEntryFromValue(memory)
        case .memoryClear:
            memory = 0
        case .memoryAdd:
            if let value = displayValue { memory += value }
        }
    }

    private init(memory: Double) {
        self.memory = memory
    }

    private var currentValue: Double {
        entry.isEmpty ? shownValue : (Double(entry) ?? 0)
    }

    /// Puts a computed value (√, ±, MR) in place of the number being typed.
    private mutating func replaceCurrent(with value: Double) {
        guard value.isFinite else { hasError = true; return }
        let wasEvaluated = justEvaluated
        setEntryFromValue(value)
        justEvaluated = wasEvaluated && entry.isEmpty
    }

    private mutating func setEntryFromValue(_ value: Double) {
        let text = Self.format(value)
        if text == "Error" { hasError = true; return }
        entry = text
        entryIsResult = true
    }

    private mutating func applyOperator(_ symbol: Character) {
        if justEvaluated {
            // Continue calculating from the previous result.
            tokens = [.number(shownValue)]
            justEvaluated = false
            entry = ""
        } else if !entry.isEmpty {
            commitEntry()
        } else if case .op = tokens.last {
            tokens[tokens.count - 1] = .op(symbol)
            return
        } else if tokens.isEmpty || tokens.last == .open {
            // Operator with no left operand uses the shown value (usually 0).
            tokens.append(.number(shownValue))
        }
        tokens.append(.op(symbol))
        refreshShownValue()
    }

    private mutating func commitEntry() {
        guard !entry.isEmpty else {
            if justEvaluated {
                tokens = [.number(shownValue)]
                justEvaluated = false
            }
            return
        }
        let value = Double(entry) ?? 0
        if case .close = tokens.last { tokens.append(.op("×")) }
        tokens.append(.number(value))
        shownValue = value
        entry = ""
        entryIsResult = false
    }

    /// Shows the value of everything to the left that can already be computed.
    private mutating func refreshShownValue() {
        var partial = tokens
        if case .op = partial.last { partial.removeLast() }
        let opens = partial.filter { $0 == .open }.count
        let closes = partial.filter { $0 == .close }.count
        guard opens == closes, let value = Self.evaluate(partial) else { return }
        shownValue = value
    }

    private mutating func setResult(_ value: Double) {
        guard value.isFinite, Self.format(value) != "Error" else {
            hasError = true
            return
        }
        shownValue = value
        entry = ""
        entryIsResult = false
    }

    private mutating func resetExpression() {
        tokens = []
        entry = ""
        entryIsResult = false
        shownValue = 0
        justEvaluated = false
    }

    // MARK: Evaluation (shunting-yard)

    static func precedence(_ symbol: Character) -> Int {
        symbol == "×" || symbol == "÷" ? 2 : 1
    }

    static func evaluate(_ tokens: [Token]) -> Double? {
        var output: [Double] = []
        var operators: [Token] = []

        func reduce() -> Bool {
            guard case let .op(symbol) = operators.popLast(), output.count >= 2 else { return false }
            let right = output.removeLast()
            let left = output.removeLast()
            switch symbol {
            case "+": output.append(left + right)
            case "−": output.append(left - right)
            case "×": output.append(left * right)
            case "÷":
                guard right != 0 else { return false }
                output.append(left / right)
            default: return false
            }
            return true
        }

        for token in tokens {
            switch token {
            case let .number(value):
                output.append(value)
            case let .op(symbol):
                while case let .op(top)? = operators.last, precedence(top) >= precedence(symbol) {
                    guard reduce() else { return nil }
                }
                operators.append(token)
            case .open:
                operators.append(token)
            case .close:
                while let top = operators.last, top != .open {
                    guard reduce() else { return nil }
                }
                guard operators.popLast() == .open else { return nil }
            }
        }
        while let top = operators.last {
            guard top != .open, reduce() else { return nil }
        }
        guard output.count == 1, let result = output.first, result.isFinite else { return nil }
        return result
    }

    /// Formats a value to fit the 8-digit display.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }
        let magnitude = abs(value)
        if magnitude >= pow(10, Double(maxDigits)) { return "Error" }
        if magnitude != 0 && magnitude < 1e-7 { return "0" }
        let integerDigits = magnitude < 1 ? 1 : Int(log10(magnitude)) + 1
        let decimals = max(0, maxDigits - integerDigits)
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text
    }
}
