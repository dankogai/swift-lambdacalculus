import Testing
@testable import LambdaCalculus

@Suite struct ParserTests {
    @Test func basics() throws {
        #expect(try Term("x") == .variable("x"))
        #expect(try Term("λx.x") == .abstraction("x", .variable("x")))
        #expect(try Term("\\x.x") == .abstraction("x", .variable("x")))
        #expect(try Term("f x") == .application(.variable("f"), .variable("x")))
    }

    @Test func applicationIsLeftAssociative() throws {
        let parsed = try Term("f x y")
        #expect(parsed == .application(.application(.variable("f"), .variable("x")), .variable("y")))
        #expect(try Term("f (x y)") != parsed)
    }

    @Test func lambdaBodyExtendsRight() throws {
        #expect(try Term("λx.f x") == .abstraction("x", .application(.variable("f"), .variable("x"))))
        #expect(try Term("λf x.f x") == Term("λf.λx.f x"))
        #expect(try Term("f λx.x") == .application(.variable("f"), .abstraction("x", .variable("x"))))
    }

    @Test func identifiers() throws {
        #expect(try Term("λfoo_1'.foo_1'") == .abstraction("foo_1'", .variable("foo_1'")))
    }

    @Test func malformed() {
        for source in ["", "(", "λ.x", "λx x", "x)", "λ", "x y)"] {
            #expect(throws: ParseError.self) { try Term(source) }
        }
    }

    @Test func descriptionRoundTrips() throws {
        for source in ["λx.x", "λf.λx.f (f x)", "(λx.x x) (λx.x x)", "f (g h) i", "λn.λf.λx.n (λg.λh.h (g f)) (λu.x) (λu.u)"] {
            let term = try Term(source)
            #expect(try Term(term.description) == term)
        }
    }
}

@Suite struct SubstitutionTests {
    @Test func freeVariables() throws {
        #expect(try Term("λx.x y").freeVariables == ["y"])
        #expect(try Term("λx.λy.x y").freeVariables == [])
        #expect(try Term("x (λx.x)").freeVariables == ["x"])
    }

    @Test func simple() throws {
        let term = try Term("x y").substituting("x", with: "λz.z")
        #expect(term == (try Term("(λz.z) y")))
    }

    @Test func boundVariablesAreUntouched() throws {
        let term = try Term("λx.x y").substituting("x", with: "z")
        #expect(term == (try Term("λx.x y")))
    }

    @Test func captureIsAvoided() throws {
        // naive substitution of y := x in λx.y would capture x
        let term = try Term("λx.y").substituting("y", with: "x")
        #expect(term.isAlphaEquivalent(to: "λz.x"))
        #expect(!term.isAlphaEquivalent(to: "λx.x"))
    }
}

@Suite struct AlphaEquivalenceTests {
    @Test func positive() {
        #expect(Term("λx.x").isAlphaEquivalent(to: "λy.y"))
        #expect(Term("λx.λy.x").isAlphaEquivalent(to: "λa.λb.a"))
        #expect(Term("λx.x z").isAlphaEquivalent(to: "λy.y z"))
    }

    @Test func negative() {
        #expect(!Term("λx.λy.x").isAlphaEquivalent(to: "λx.λy.y"))
        #expect(!Term("λx.x z").isAlphaEquivalent(to: "λy.y w"))  // different free variables
        #expect(!Term("x").isAlphaEquivalent(to: "y"))
    }
}

@Suite struct ReductionTests {
    @Test func identity() {
        #expect(Term("(λx.x) y").normalized() == .variable("y"))
    }

    @Test func kCombinatorDiscardsDivergentArgument() {
        // normal order never evaluates the discarded Ω
        let term = Term("(λx.λy.x) z ((λx.x x) (λx.x x))")
        #expect(term.normalized() == .variable("z"))
    }

    @Test func omegaDiverges() {
        #expect(Term("(λx.x x) (λx.x x)").normalized(maxSteps: 1000) == nil)
    }

    @Test func skkIsIdentity() {
        let s: Term = "λx.λy.λz.x z (y z)"
        let k: Term = "λx.λy.x"
        #expect(s(k, k).normalized()!.isAlphaEquivalent(to: "λx.x"))
    }

    @Test func reductionSequenceEndsAtNormalForm() {
        let steps = Array(Term("(λx.x) ((λy.y) z)").reductionSequence)
        #expect(steps.count == 3)
        #expect(steps.last == .variable("z"))
        #expect(steps.last!.isNormalForm)
    }
}

@Suite struct ChurchTests {
    @Test func numeralsRoundTrip() {
        for n in 0...5 {
            #expect(Church.numeral(n).churchInt == n)
        }
        #expect(Term("λx.x").churchInt == nil)
        #expect(Church.numeral(0).isAlphaEquivalent(to: Church.false))
    }

    @Test func arithmetic() {
        let two = Church.numeral(2), three = Church.numeral(3)
        #expect(Church.succ(two).normalized()!.churchInt == 3)
        #expect(Church.plus(two, three).normalized()!.churchInt == 5)
        #expect(Church.times(two, three).normalized()!.churchInt == 6)
        #expect(Church.power(two, three).normalized()!.churchInt == 8)
        #expect(Church.pred(three).normalized()!.churchInt == 2)
        #expect(Church.pred(Church.numeral(0)).normalized()!.churchInt == 0)
    }

    @Test func booleans() {
        #expect(Church.true.churchBool == true)
        #expect(Church.false.churchBool == false)
        #expect(Church.and(Church.true, Church.false).normalized()!.churchBool == false)
        #expect(Church.or(Church.true, Church.false).normalized()!.churchBool == true)
        #expect(Church.not(Church.false).normalized()!.churchBool == true)
        #expect(Church.isZero(Church.numeral(0)).normalized()!.churchBool == true)
        #expect(Church.isZero(Church.numeral(2)).normalized()!.churchBool == false)
    }

    @Test func factorialViaFixedPoint() {
        let fact = Church.fix(
            .lambda("f", "n", body:
                Church.ifThenElse(
                    Church.isZero(.variable("n")),
                    Church.numeral(1),
                    Church.times(.variable("n"), Term.variable("f")(Church.pred(.variable("n"))))
                )
            )
        )
        #expect(fact(Church.numeral(3)).normalized(maxSteps: 100_000)!.churchInt == 6)
        #expect(fact(Church.numeral(5)).normalized(maxSteps: 1_000_000)!.churchInt == 120)
    }
}

@Suite struct CombinatorTests {
    @Test func parsing() throws {
        #expect(try Combinator("SKKx") == Combinator.s(.k, .k, .variable("x")))
        #expect(try Combinator("S(K(SI))K") == Combinator.s(Combinator.k(Combinator.s(.i)), .k))
        #expect(try Combinator("ι x'") == Combinator.iota(.variable("x'")))
        // bind to a variable: a bare literal would pick init(stringLiteral:), which traps
        for source: String in ["λx.x", "\\x.x", "(SK", "", "?"] {
            #expect(throws: ParseError.self) { try Combinator(source) }
        }
    }

    @Test func descriptionRoundTrips() throws {
        for source in ["S", "SKKx", "S(K(SI))K", "ιι", "X(XX)", "B(CW)K", "x'y"] {
            let term = try Combinator(source)
            #expect(try Combinator(term.description) == term)
        }
        #expect(Combinator("S(K(SI))K").description == "S(K(SI))K")
        // multi-character pieces get separating spaces, as in swift-combinators
        #expect(Combinator.apply(.variable("x'"), .variable("y")).description == "x' y")
    }

    @Test func primitiveLaws() throws {
        let x: Term = "x", y: Term = "y", z: Term = "z"
        #expect(Term(Combinator.s)(x, y, z).normalized() == Term("x z (y z)"))
        #expect(Term(Combinator.k)(x, y).normalized() == x)
        #expect(Term(Combinator.i)(x).normalized() == x)
        #expect(Term(Combinator.b)(x, y, z).normalized() == Term("x (y z)"))
        #expect(Term(Combinator.c)(x, y, z).normalized() == Term("x z y"))
        #expect(Term(Combinator.w)(x, y).normalized() == Term("x y y"))
    }

    @Test func classicPrograms() throws {
        // SKK is the identity
        #expect(try Term(combinator: "SKK").normalized()!.isAlphaEquivalent(to: "λx.x"))
        // S(K(SI))K flips its arguments
        let flip = try Term(combinator: "S(K(SI))K")
        #expect(flip("x", "y").normalized() == Term("y x"))
        // swift-combinators compiles λfx.f(fx) to this; it decodes back to 2
        #expect(try Term(combinator: "S(S(KS)K)(S(S(KS)K)(KI))").normalized()!.churchInt == 2)
    }

    @Test func onePointBases() throws {
        // ιι = I, and K and S are recovered from X as XXX and X(XX)
        #expect(try Term(combinator: "ιι").normalized()!.isAlphaEquivalent(to: "λa.a"))
        #expect(try Term(combinator: "XXX").normalized()!.isAlphaEquivalent(to: Term(Combinator.k)))
        #expect(try Term(combinator: "X(XX)").normalized()!.isAlphaEquivalent(to: Term(Combinator.s)))
    }
}
