/// Error thrown by `Term.init(_:)` on malformed input.
public struct ParseError: Error, CustomStringConvertible, Sendable {
    public let message: String
    /// Offset (in characters) into the source where the error was detected.
    public let position: Int

    public var description: String { "\(message) at position \(position)" }
}

extension Term {
    /// Parses a term from a string.
    ///
    /// Grammar (applications are left-associative and bind tighter than `λ`,
    /// whose body extends as far right as possible):
    ///
    ///     term ::= lambda | application
    ///     lambda ::= ("λ" | "\") ident+ "." term
    ///     application ::= atom+
    ///     atom ::= ident | "(" term ")"
    ///
    /// `λx y.body` is shorthand for `λx.λy.body`. Identifiers are runs of
    /// letters, digits, `_` and `'`, starting with a letter or `_`.
    public init(_ source: some StringProtocol) throws {
        var parser = Parser(source)
        self = try parser.parseTerm()
        try parser.expectEnd()
    }
}

private struct Parser {
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

    static func isIdentifierStart(_ c: Character) -> Bool {
        (c.isLetter && c != "λ") || c == "_"
    }

    static func isIdentifierBody(_ c: Character) -> Bool {
        isIdentifierStart(c) || c.isNumber || c == "'"
    }

    mutating func parseIdentifier() throws -> String {
        skipWhitespace()
        guard let c = peek, Self.isIdentifierStart(c) else {
            throw ParseError(message: "expected identifier", position: pos)
        }
        var name = ""
        while let c = peek, Self.isIdentifierBody(c) {
            name.append(c)
            pos += 1
        }
        return name
    }

    mutating func parseTerm() throws -> Term {
        skipWhitespace()
        if peek == "λ" || peek == "\\" {
            pos += 1
            var parameters = [try parseIdentifier()]
            skipWhitespace()
            while let c = peek, Self.isIdentifierStart(c) {
                parameters.append(try parseIdentifier())
                skipWhitespace()
            }
            guard peek == "." else {
                throw ParseError(message: "expected '.' after λ-binders", position: pos)
            }
            pos += 1
            let body = try parseTerm()
            return parameters.reversed().reduce(body) { .abstraction($1, $0) }
        }
        return try parseApplication()
    }

    mutating func parseApplication() throws -> Term {
        var term = try parseAtom()
        while true {
            skipWhitespace()
            guard let c = peek else { break }
            if c == "λ" || c == "\\" {
                // an unparenthesized λ as an argument: its body extends to the end
                term = .application(term, try parseTerm())
                break
            }
            guard c == "(" || Self.isIdentifierStart(c) else { break }
            term = .application(term, try parseAtom())
        }
        return term
    }

    mutating func parseAtom() throws -> Term {
        skipWhitespace()
        guard let c = peek else {
            throw ParseError(message: "unexpected end of input", position: pos)
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
        return .variable(try parseIdentifier())
    }
}
