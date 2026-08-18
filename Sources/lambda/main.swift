import Foundation
import LambdaCalculus

/// A tiny read-eval-print loop for the untyped lambda calculus,
/// the mirror image of swift-combinators' `ski`.
///
///     swift run lambda                    # interactive
///     swift run lambda '(λx.x) y'        # evaluate one expression
///     swift run lambda -v 'plus two two'  # show every reduction step

let maxSteps = 10_000

var definitions: [String: Term] = [
    "true": Church.true, "false": Church.false,
    "and": Church.and, "or": Church.or, "not": Church.not, "if": Church.ifThenElse,
    "succ": Church.succ, "plus": Church.plus, "times": Church.times,
    "power": Church.power, "pred": Church.pred, "iszero": Church.isZero,
    "fix": Church.fix,
    "S": Term(Combinator.s), "K": Term(Combinator.k), "I": Term(Combinator.i),
    "B": Term(Combinator.b), "C": Term(Combinator.c), "W": Term(Combinator.w),
]
for (n, name) in ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    .enumerated() {
    definitions[name] = Church.numeral(n)
}

@MainActor
func expand(_ term: Term) -> Term {
    var expanded = term
    for (name, value) in definitions where term.freeVariables.contains(name) {
        expanded = expanded.substituting(name, with: value)
    }
    return expanded
}

func annotated(_ normal: Term) -> String {
    var annotations: [String] = []
    if let n = normal.churchInt { annotations.append("\(n)") }
    if let b = normal.churchBool { annotations.append("\(b)") }
    return "\(normal)\(annotations.isEmpty ? "" : "    -- \(annotations.joined(separator: ", "))")"
}

@MainActor
func evaluate(_ term: Term, verbose: Bool) {
    if verbose {
        for step in term.reductionSequence.prefix(maxSteps + 1) { print("  \(step)") }
    }
    guard let normal = term.normalized(maxSteps: maxSteps) else {
        print("error: no β-normal form within \(maxSteps) steps")
        return
    }
    print(annotated(normal))
}

@MainActor
func evaluate(_ source: String, verbose: Bool) {
    do {
        evaluate(expand(try Term(source)), verbose: verbose)
    } catch {
        print("error: \(error)")
    }
}

/// Splits a leading `-v` off an expression, e.g. for `:ski -v SKKx`.
func verboseFlag(_ text: String) -> (verbose: Bool, rest: String) {
    text.hasPrefix("-v ")
        ? (true, String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        : (false, text)
}

let help = """
    <expression>        β-reduce a λ-term to normal form; λx.body and \\x.body
                        both abstract, and λx y.body binds two variables
    :v <expr>           print every reduction step
    :let name = <expr>  bind a name, usable as a free variable afterwards
    :env                list the bound names (Church numerals zero…nine,
                        arithmetic, booleans, fix, and S K I B C W)
    :ski [-v] <expr>    parse classic combinator notation (S, K, I, B, C, W,
                        ι, X) and β-reduce its λ-image
    :help               this message
    :quit               leave
    """

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    let verbose = arguments.first == "-v"
    evaluate(arguments.drop { $0 == "-v" }.joined(separator: " "), verbose: verbose)
} else {
    print("Lambda calculus. :help for help, :quit to leave.")
    while true {
        print("λ> ", terminator: "")
        guard let line = readLine() else { break }
        let input = line.trimmingCharacters(in: .whitespaces)
        switch input {
        case "": continue
        case ":quit", ":q": exit(0)
        case ":help", ":h", ":?": print(help)
        case ":env":
            let width = definitions.keys.map(\.count).max() ?? 0
            for (name, term) in definitions.sorted(by: { $0.key < $1.key }) {
                print("  \(name.padding(toLength: width, withPad: " ", startingAt: 0))  \(term)")
            }
        case let input where input.hasPrefix(":ski "):
            let (verbose, text) = verboseFlag(
                String(input.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            do {
                evaluate(try Term(combinator: text), verbose: verbose)
            } catch {
                print("error: \(error)")
            }
        case let input where input.hasPrefix(":v "):
            evaluate(String(input.dropFirst(3)), verbose: true)
        case let input where input.hasPrefix(":let "):
            let parts = input.dropFirst(5).split(separator: "=", maxSplits: 1)
            let name = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard parts.count == 2, (try? Term(name)) == .variable(name) else {
                print("error: expected :let name = <expression>")
                continue
            }
            do {
                definitions[name] = expand(try Term(String(parts[1])))
            } catch {
                print("error: \(error)")
            }
        case let input where input.hasPrefix(":"):
            print("error: unknown command \(input); try :help")
        default:
            evaluate(input, verbose: false)
        }
    }
}
