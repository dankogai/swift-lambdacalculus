/// A term of the combinator calculus, as spoken by
/// [swift-combinators](https://github.com/dankogai/swift-combinators):
/// the classic notation parses and prints identically in both packages,
/// so terms travel freely between them.  swift-combinators compiles
/// λ-terms *into* combinators by bracket abstraction; this module goes
/// the other way — ``Term/init(_:)-swift.init`` expands each primitive
/// into its defining abstraction, yielding an ordinary λ-``Term``.
///
/// ```swift
/// let flip = try Term(combinator: "S(K(SI))K")
/// flip("x", "y").normalized()   // y x
/// ```
public indirect enum Combinator: Hashable, Sendable {
    /// The substitution combinator: `S x y z → x z (y z)`.
    case s
    /// The constant combinator: `K x y → x`.
    case k
    /// The identity combinator: `I x → x`.
    case i
    /// The composition combinator: `B x y z → x (y z)`.
    case b
    /// The exchange combinator: `C x y z → x z y`.
    case c
    /// The duplication combinator: `W x y → x y y`.
    case w
    /// Barker's iota combinator: `ι x → x S K`.
    case iota
    /// The one-point-basis combinator: `X a → a K S K`.
    case x
    /// A free variable.
    case variable(String)
    /// The application of one term to another, `f x`.
    case apply(Combinator, Combinator)
}

extension Combinator {
    /// Applies this term to `arguments`, associating to the left.
    public func callAsFunction(_ arguments: Combinator...) -> Combinator {
        arguments.reduce(self) { .apply($0, $1) }
    }

    /// Decomposes a term into the head of its application spine and the
    /// arguments applied to it, in order: `SKKx` decomposes into
    /// `(head: .s, arguments: [.k, .k, .variable("x")])`.
    public var spine: (head: Combinator, arguments: [Combinator]) {
        var arguments = [Combinator]()
        var current = self
        while case .apply(let function, let argument) = current {
            arguments.append(argument)
            current = function
        }
        return (current, arguments.reversed())
    }
}

extension Combinator: CustomStringConvertible {
    /// The term in the classic notation, matching swift-combinators'
    /// printing: juxtaposition for application, parentheses only where
    /// grouping demands them, and spaces only around multi-character
    /// variable names.
    public var description: String {
        let (head, arguments) = spine
        let pieces = [head.atomDescription] + arguments.map(\.argumentDescription)
        let unambiguous = pieces.allSatisfy { $0.count == 1 || $0.hasPrefix("(") }
        return pieces.joined(separator: unambiguous ? "" : " ")
    }

    private var atomDescription: String {
        switch self {
        case .s: "S"
        case .k: "K"
        case .i: "I"
        case .b: "B"
        case .c: "C"
        case .w: "W"
        case .iota: "ι"
        case .x: "X"
        case .variable(let name): name
        case .apply: "(\(description))"
        }
    }

    private var argumentDescription: String {
        if case .apply = self { "(\(description))" } else { atomDescription }
    }
}

// MARK: - Parsing

extension Combinator {
    /// Parses a term written in the classic notation, as printed by this
    /// type or by swift-combinators.
    ///
    /// Application is juxtaposition and associates to the left; `S`, `K`,
    /// `I`, `B`, `C`, `W`, `ι` and `X` denote the primitive combinators and
    /// any other single letter or digit (optionally primed) is a free
    /// variable, so `SKKx` is `(((S K) K) x)`.  Parentheses group, and
    /// whitespace is insignificant.  λ-abstractions are *not* combinator
    /// notation — parse those with `Term.init(_:)` instead (eliminating
    /// them into combinators is swift-combinators' direction).
    public init(_ source: some StringProtocol) throws {
        var parser = CombinatorParser(source)
        self = try parser.parseTerm()
        try parser.expectEnd()
    }
}

extension Combinator: ExpressibleByStringLiteral {
    /// Parses a term from a literal, e.g. `let flip: Combinator = "S(K(SI))K"`.
    /// Traps on malformed input; use `Combinator.init(_:)` to handle errors.
    public init(stringLiteral value: String) {
        do {
            self = try Combinator(value)
        } catch {
            fatalError("invalid combinator expression \(value.debugDescription): \(error)")
        }
    }
}

private struct CombinatorParser {
    static let primitives: [Character: Combinator] = [
        "S": .s, "K": .k, "I": .i, "B": .b, "C": .c, "W": .w, "ι": .iota, "X": .x,
    ]

    let chars: [Character]
    var pos = 0

    init(_ source: some StringProtocol) {
        chars = Array(source)
    }

    var peek: Character? { pos < chars.count ? chars[pos] : nil }

    mutating func skipWhitespace() {
        while let c = peek, c.isWhitespace { pos += 1 }
    }

    mutating func expectEnd() throws {
        skipWhitespace()
        if let c = peek {
            throw ParseError(message: "unexpected \(c.debugDescription)", position: pos)
        }
    }

    mutating func parseTerm() throws -> Combinator {
        skipWhitespace()
        let start = pos
        var term: Combinator?
        while let c = peek, c != ")" {
            let atom = try parseAtom()
            term = term.map { .apply($0, atom) } ?? atom
            skipWhitespace()
        }
        guard let term else {
            throw ParseError(message: "expected a term", position: start)
        }
        return term
    }

    mutating func parseAtom() throws -> Combinator {
        skipWhitespace()
        guard let c = peek else {
            throw ParseError(message: "expected a term", position: pos)
        }
        if c == "(" {
            pos += 1
            let term = try parseTerm()
            skipWhitespace()
            guard peek == ")" else {
                throw ParseError(message: "expected ')'", position: pos)
            }
            pos += 1
            return term
        }
        if c == "λ" || c == "\\" {
            throw ParseError(
                message: "λ is not combinator notation; parse λ-terms with Term.init",
                position: pos
            )
        }
        if let primitive = Self.primitives[c] {
            pos += 1
            return primitive
        }
        guard c.isLetter || c.isNumber else {
            throw ParseError(message: "unexpected \(c.debugDescription)", position: pos)
        }
        pos += 1
        var name = String(c)
        while let prime = peek, prime == "'" || prime == "′" {
            name.append(prime)
            pos += 1
        }
        return .variable(name)
    }
}

// MARK: - Combinator → λ

extension Term {
    /// The λ-image of a combinator term: each primitive becomes its defining
    /// abstraction, and applications and variables are preserved.  The
    /// abstractions match the table swift-combinators uses for the reverse
    /// lifting, so the two packages agree term for term.
    ///
    /// ```swift
    /// Term(Combinator.b)   // λa.λb.λc.a (b c)
    /// ```
    public init(_ combinator: Combinator) {
        switch combinator {
        case .variable(let name): self = .variable(name)
        case .apply(let function, let argument):
            self = .application(Term(function), Term(argument))
        case .s: self = "λa b c.a c (b c)"
        case .k: self = "λa b.a"
        case .i: self = "λa.a"
        case .b: self = "λa b c.a (b c)"
        case .c: self = "λa b c.a c b"
        case .w: self = "λa b.a b b"
        case .iota: self = "λa.a (λb c d.b d (c d)) (λb c.b)"
        case .x: self = "λa.a (λb c.b) (λb c d.b d (c d)) (λb c.b)"
        }
    }

    /// Parses classic combinator notation and expands it to a λ-term
    /// in one step.
    ///
    /// ```swift
    /// try Term(combinator: "SKK").normalized()   // λa.a (α-equivalent)
    /// ```
    public init(combinator source: some StringProtocol) throws {
        self = Term(try Combinator(source))
    }
}
