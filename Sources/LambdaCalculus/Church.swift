/// Church encodings of booleans, numerals and the fixed-point combinator.
public enum Church {
    // MARK: booleans

    public static let `true`: Term = "λt.λf.t"
    public static let `false`: Term = "λt.λf.f"
    public static let and: Term = "λp.λq.p q p"
    public static let or: Term = "λp.λq.p p q"
    public static let not: Term = "λp.λt.λf.p f t"
    /// `if c then t else f` is just `c t f`; provided for readability.
    public static let ifThenElse: Term = "λc.λt.λf.c t f"

    // MARK: numerals

    /// The Church numeral for `n`: `λf.λx.f (f … (f x))` with `n` copies of `f`.
    public static func numeral(_ n: Int) -> Term {
        precondition(n >= 0, "Church numerals encode non-negative integers")
        var body = Term.variable("x")
        for _ in 0..<n { body = .application(.variable("f"), body) }
        return .lambda("f", "x", body: body)
    }

    public static let succ: Term = "λn.λf.λx.f (n f x)"
    public static let plus: Term = "λm.λn.λf.λx.m f (n f x)"
    public static let times: Term = "λm.λn.λf.m (n f)"
    public static let power: Term = "λm.λn.n m"
    public static let pred: Term = "λn.λf.λx.n (λg.λh.h (g f)) (λu.x) (λu.u)"
    public static let isZero: Term = "λn.n (λx.λt.λf.f) (λt.λf.t)"

    // MARK: recursion

    /// The Y combinator: `Y g` reduces to `g (Y g)` under normal order.
    public static let fix: Term = "λg.(λx.g (x x)) (λx.g (x x))"
}

extension Term {
    /// Decodes a Church numeral in β-normal form back to an `Int`,
    /// or `nil` if the term is not (alpha-equivalent to) a numeral.
    public var churchInt: Int? {
        guard case .abstraction(let f, .abstraction(let x, var body)) = self else { return nil }
        var n = 0
        while true {
            switch body {
            case .variable(let v) where v == x:
                return n
            case .application(.variable(let g), let rest) where g == f && f != x:
                n += 1
                body = rest
            default:
                return nil
            }
        }
    }

    /// Decodes a Church boolean in β-normal form back to a `Bool`,
    /// or `nil` if the term is not (alpha-equivalent to) `λt.λf.t` / `λt.λf.f`.
    public var churchBool: Bool? {
        guard case .abstraction(let t, .abstraction(let f, .variable(let v))) = self else { return nil }
        // check the inner binder first: it shadows the outer one when t == f
        if v == f { return false }
        if v == t { return true }
        return nil
    }
}
