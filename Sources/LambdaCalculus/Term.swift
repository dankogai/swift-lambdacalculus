/// A term of the untyped lambda calculus.
public indirect enum Term: Hashable, Sendable {
    /// A variable, e.g. `x`.
    case variable(String)
    /// An abstraction `λx.body`.
    case abstraction(String, Term)
    /// An application `f a`.
    case application(Term, Term)
}

extension Term {
    /// The set of variable names that occur free in this term.
    public var freeVariables: Set<String> {
        switch self {
        case .variable(let name):
            return [name]
        case .abstraction(let parameter, let body):
            return body.freeVariables.subtracting([parameter])
        case .application(let function, let argument):
            return function.freeVariables.union(argument.freeVariables)
        }
    }

    /// `true` iff the term is a lone abstraction — a value in the weak sense.
    public var isAbstraction: Bool {
        if case .abstraction = self { return true }
        return false
    }

    /// Capture-avoiding substitution: replaces every free occurrence of
    /// `name` in this term with `term`, renaming bound variables as needed.
    public func substituting(_ name: String, with term: Term) -> Term {
        substituting(name, with: term, whoseFreeVariablesAre: term.freeVariables)
    }

    // `termFV` is FV(term), computed once by the caller: recomputing it at
    // every abstraction node would make substitution quadratic in term size.
    private func substituting(
        _ name: String, with term: Term, whoseFreeVariablesAre termFV: Set<String>
    ) -> Term {
        switch self {
        case .variable(let v):
            return v == name ? term : self
        case .application(let function, let argument):
            return .application(
                function.substituting(name, with: term, whoseFreeVariablesAre: termFV),
                argument.substituting(name, with: term, whoseFreeVariablesAre: termFV)
            )
        case .abstraction(let parameter, let body):
            if parameter == name { return self }
            guard termFV.contains(parameter) else {
                return .abstraction(
                    parameter, body.substituting(name, with: term, whoseFreeVariablesAre: termFV)
                )
            }
            let fresh = Term.freshName(
                parameter,
                avoiding: termFV.union(body.freeVariables).union([name])
            )
            let renamed = body.substituting(parameter, with: .variable(fresh))
            return .abstraction(
                fresh, renamed.substituting(name, with: term, whoseFreeVariablesAre: termFV)
            )
        }
    }

    static func freshName(_ base: String, avoiding taken: Set<String>) -> String {
        var name = base
        repeat { name += "'" } while taken.contains(name)
        return name
    }
}

extension Term {
    /// Structural equality up to renaming of bound variables.
    public func isAlphaEquivalent(to other: Term) -> Bool {
        func go(_ a: Term, _ b: Term, _ ea: [String: Int], _ eb: [String: Int], _ depth: Int) -> Bool {
            switch (a, b) {
            case (.variable(let x), .variable(let y)):
                switch (ea[x], eb[y]) {
                case (let i?, let j?): return i == j
                case (nil, nil): return x == y
                default: return false
                }
            case (.abstraction(let x, let bodyA), .abstraction(let y, let bodyB)):
                var ea = ea, eb = eb
                ea[x] = depth
                eb[y] = depth
                return go(bodyA, bodyB, ea, eb, depth + 1)
            case (.application(let fa, let aa), .application(let fb, let ab)):
                return go(fa, fb, ea, eb, depth) && go(aa, ab, ea, eb, depth)
            default:
                return false
            }
        }
        return go(self, other, [:], [:], 0)
    }
}

extension Term: CustomStringConvertible {
    /// Renders the term with a minimal set of parentheses,
    /// e.g. `λf.λx.f (f x)`. The output parses back to an
    /// alpha-equivalent (in fact identical) term.
    public var description: String {
        switch self {
        case .variable(let name):
            return name
        case .abstraction(let parameter, let body):
            return "λ\(parameter).\(body)"
        case .application(let function, let argument):
            let f = function.isAbstraction ? "(\(function))" : "\(function)"
            let a: String
            if case .variable = argument { a = "\(argument)" } else { a = "(\(argument))" }
            return "\(f) \(a)"
        }
    }
}

extension Term {
    /// Builds the application `self a₀ a₁ …`, so you can write
    /// `plus(two, three)` instead of nesting `.application` by hand.
    public func callAsFunction(_ arguments: Term...) -> Term {
        arguments.reduce(self) { .application($0, $1) }
    }

    /// Shorthand for `.abstraction`, binding the parameters left to right:
    /// `Term.lambda("f", "x", body:)` is `λf.λx.body`.
    public static func lambda(_ parameters: String..., body: Term) -> Term {
        parameters.reversed().reduce(body) { .abstraction($1, $0) }
    }
}

extension Term: ExpressibleByStringLiteral {
    /// Parses a term from a literal, e.g. `let id: Term = "λx.x"`.
    /// Traps on malformed input; use `Term.init(_:)` to handle errors.
    public init(stringLiteral value: String) {
        do {
            self = try Term(value)
        } catch {
            fatalError("invalid lambda term literal \(value.debugDescription): \(error)")
        }
    }
}
