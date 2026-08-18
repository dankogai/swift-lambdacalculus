[![build status](https://github.com/dankogai/swift-lambdacalculus/actions/workflows/swift.yml/badge.svg)](https://github.com/dankogai/swift-lambdacalculus/actions/workflows/swift.yml)

# swift-lambdacalculus

The untyped lambda calculus in Swift: parsing, capture-avoiding substitution, normal-order β-reduction, and Church encodings.

## Synopsis

```swift
import LambdaCalculus

// terms parse from string literals; both λ and \ work
let id: Term = "λx.x"
let term = try Term("(λx.λy.x) a b")
term.normalized()                      // Optional(a)

// α-equivalence, free variables, one-step reduction
Term("λx.x").isAlphaEquivalent(to: "λy.y")   // true
Term("λx.x y").freeVariables                 // ["y"]
Term("(λx.x) y").reducedOnce                 // Optional(y)

// terms with no normal form return nil instead of looping forever
Term("(λx.x x) (λx.x x)").normalized(maxSteps: 1000)  // nil

// Church encodings: numerals, booleans, and the Y combinator
let two = Church.numeral(2), three = Church.numeral(3)
Church.plus(two, three).normalized()!.churchInt       // Optional(5)
Church.isZero(two).normalized()!.churchBool           // Optional(false)

// combinator calculus interop: classic notation parses and expands to λ
let flip = try Term(combinator: "S(K(SI))K")      // Sabc = ac(bc), Kab = a, Ia = a
flip("x", "y").normalized()                       // Optional(y x)
try Term(combinator: "SKK").normalized()!
    .isAlphaEquivalent(to: "λx.x")                // true

// recursion via the fixed-point combinator
let fact = Church.fix(
    .lambda("f", "n", body:
        Church.ifThenElse(
            Church.isZero(.variable("n")),
            Church.numeral(1),
            Church.times(.variable("n"), Term.variable("f")(Church.pred(.variable("n"))))
        )
    )
)
fact(Church.numeral(5)).normalized(maxSteps: 1_000_000)!.churchInt  // Optional(120)
```

## Description

A `Term` is exactly the grammar of the untyped lambda calculus:

```swift
public indirect enum Term: Hashable, Sendable {
    case variable(String)
    case abstraction(String, Term)   // λx.body
    case application(Term, Term)     // f a
}
```

- **Parsing** — `Term.init(_:)` throws `ParseError`; `Term` is also `ExpressibleByStringLiteral`. Applications are left-associative, λ-bodies extend as far right as possible, and `λx y.e` abbreviates `λx.λy.e`.
- **Printing** — `description` renders with minimal parentheses and round-trips through the parser.
- **Substitution** — `substituting(_:with:)` is capture-avoiding; bound variables are freshened with primes (`x` → `x'`) when needed.
- **Reduction** — `reducedOnce` performs a single normal-order (leftmost-outermost) β-step, `reductionSequence` traces every step, and `normalized(maxSteps:)` reduces to β-normal form efficiently, returning `nil` if the step budget is exhausted. Normal order is normalizing, so a normal form is found whenever one exists — which is what makes `Church.ifThenElse` lazy and `Church.fix` usable.
- **Church encodings** — `Church` provides booleans (`true`, `false`, `and`, `or`, `not`, `ifThenElse`), numerals (`numeral(_:)`, `succ`, `plus`, `times`, `power`, `pred`, `isZero`), and the fixed-point combinator `fix`. Decode normal forms back with `.churchInt` and `.churchBool`.
- **Combinator calculus** — `Combinator` speaks the classic notation of [swift-combinators](https://github.com/dankogai/swift-combinators) (`S`, `K`, `I`, `B`, `C`, `W`, `ι`, `X`, juxtaposition, e.g. `"S(K(SI))K"`), printing and parsing identically. `Term.init(_:)` expands each primitive into the same defining abstraction that package uses for its reverse lifting, so the two are interchangeable: swift-combinators compiles λ → combinator by bracket abstraction, and this package converts combinator → λ.

## Design notes

- **How `normalized` stays fast.** Iterating `reducedOnce` re-searches the whole
  term from the root for every step — O(steps × size). `normalized(maxSteps:)`
  instead reduces the head along the application spine to weak-head normal form
  and then normalizes the remaining subterms. The strategy is still
  leftmost-outermost, so it reaches the same normal forms; only the traversal
  differs. Fuel counts β-steps, so the count can differ slightly from the
  single-step path. On the factorial benchmark (5! via `fix`) this plus the
  substitution fix below took the test suite from 92s to under 4s.
- **Substitution computes free variables once.** `substituting(_:with:)`
  determines the replacement term's free-variable set a single time and threads
  it through the traversal. Recomputing it at every abstraction node — the
  obvious recursive formulation — makes substitution quadratic in term size,
  which dominates everything once Church-encoded terms grow.
- **String literals trap; `init(_:)` throws — and literals pick the trap.**
  `let id: Term = "λx.x"` parses at initialization and traps on malformed
  input, while `try Term(source)` throws `ParseError`. But Swift resolves
  `Term("λx.x")` with a *bare literal* argument to the literal initializer too,
  so it traps rather than throws — even under `try`. To exercise the throwing
  parser (e.g. when testing malformed input), bind the source to a `String`
  first. The same holds for `Combinator`.
- **Interchange with swift-combinators is by notation, not by dependency.**
  Both packages parse and print the same classic combinator notation, and
  `Term.init(_:)` uses the same primitive-expansion table as that package's
  reverse lifting, so terms travel between them as strings with no code
  dependency either way. The division of labor: λ → combinator (bracket
  abstraction) lives there; combinator → λ lives here. One asymmetry: this
  package's identifiers are words (`plus`, `iszero`), swift-combinators'
  variables are single letters — so the REPLs share semantics, not vocabulary.
- **Decoding is ambiguous at 0.** `λt.λf.f` is both the Church numeral 0 and
  Church `false`, so the REPL annotates it `-- 0, false`. This mirrors `ski`.

## The `lambda` REPL

The package ships an executable, the mirror image of swift-combinators' `ski`:

```sh
swift run lambda                     # interactive
swift run lambda '(λx.x) y'         # evaluate one expression
swift run lambda -v 'succ zero'      # show every reduction step
```

```
λ> plus two three
λf.λx.f (f (f (f (f x))))    -- 5
λ> fix (λf.λn.if (iszero n) one (times n (f (pred n)))) three
λf.λx.f (f (f (f (f (f x)))))    -- 6
λ> :ski S(K(SI))Kab
b a
```

Church numerals (`zero` … `nine`), arithmetic, booleans, `fix`, and the
combinators `S K I B C W` are predefined; `:let name = <expr>` binds more.
`:v` traces every step, `:ski` evaluates classic combinator notation via its
λ-image, and `:help` lists the rest.

## Usage

### Swift Package Manager

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/dankogai/swift-lambdacalculus.git", from: "0.0.1")
```

and `"LambdaCalculus"` to your target dependencies.

### Run tests

```sh
swift test
```

## License

[MIT](LICENSE)
