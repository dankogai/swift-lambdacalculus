extension Term {
    /// Performs one step of β-reduction in normal order (leftmost-outermost
    /// redex first, reducing under abstractions), or returns `nil` if the
    /// term is already in β-normal form.
    ///
    /// Normal order is normalizing: it reaches the normal form whenever one
    /// exists, which is what makes Church-encoded conditionals and the
    /// Y combinator usable.
    public var reducedOnce: Term? {
        switch self {
        case .variable:
            return nil
        case .application(.abstraction(let parameter, let body), let argument):
            return body.substituting(parameter, with: argument)
        case .application(let function, let argument):
            if let f = function.reducedOnce { return .application(f, argument) }
            if let a = argument.reducedOnce { return .application(function, a) }
            return nil
        case .abstraction(let parameter, let body):
            guard let b = body.reducedOnce else { return nil }
            return .abstraction(parameter, b)
        }
    }

    /// `true` iff no β-redex remains anywhere in the term.
    public var isNormalForm: Bool { reducedOnce == nil }

    /// Reduces the term to β-normal form in normal order, giving up and
    /// returning `nil` after `maxSteps` β-reductions (the untyped calculus
    /// has terms with no normal form, e.g. `(λx.x x) (λx.x x)`).
    ///
    /// Unlike iterating `reducedOnce`, this does not re-traverse the whole
    /// term on each step: it reduces the head along the application spine
    /// to weak-head normal form, then normalizes the remaining subterms.
    /// The strategy is still leftmost-outermost, so it finds the normal
    /// form whenever one exists.
    public func normalized(maxSteps: Int = 10_000) -> Term? {
        var fuel = maxSteps
        return normalized(fuel: &fuel)
    }

    private func normalized(fuel: inout Int) -> Term? {
        guard let weak = weakHeadNormalized(fuel: &fuel) else { return nil }
        switch weak {
        case .variable:
            return weak
        case .abstraction(let parameter, let body):
            guard let b = body.normalized(fuel: &fuel) else { return nil }
            return .abstraction(parameter, b)
        case .application(let function, let argument):
            // the head is a stuck variable, so no new top-level redex can appear
            guard let f = function.normalized(fuel: &fuel),
                  let a = argument.normalized(fuel: &fuel) else { return nil }
            return .application(f, a)
        }
    }

    private func weakHeadNormalized(fuel: inout Int) -> Term? {
        var head = self
        var spine = [Term]()  // pending arguments, innermost last
        while true {
            switch head {
            case .application(let function, let argument):
                spine.append(argument)
                head = function
            case .abstraction(let parameter, let body) where !spine.isEmpty:
                guard fuel > 0 else { return nil }
                fuel -= 1
                head = body.substituting(parameter, with: spine.removeLast())
            default:
                return spine.reversed().reduce(head) { .application($0, $1) }
            }
        }
    }

    /// The sequence of terms visited by repeated normal-order reduction,
    /// starting with `self` and ending at the normal form — or unbounded
    /// if the term diverges. Handy for tracing:
    ///
    ///     for step in term.reductionSequence { print(step) }
    public var reductionSequence: some Sequence<Term> {
        sequence(first: self) { $0.reducedOnce }
    }
}
