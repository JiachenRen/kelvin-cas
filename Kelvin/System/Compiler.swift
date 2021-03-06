//
//  Compiler.swift
//  Kelvin
//
//  Created by Jiachen Ren on 11/4/18.
//  Copyright © 2018 Jiachen Ren. All rights reserved.
//

import Foundation
import BigInt

/// Created by Jiachen on 19/05/2017.
public class Compiler {
    
    /// Shared singleton instance of Compiler
    public static var shared: Compiler {
        return Compiler()
    }
    
    public enum Bracket: String {
        case curly = "{}"
        case square = "[]"
        case round = "()"
        
        static var all: [Bracket] {
            return [.round, .curly, .square]
        }
    }

    /// Symbols from binary operators, shorthands, and syntactic sugars.
    private var symbols: String {
        let operators = Syntax.tokens
                .keys.reduce("") {
            "\($0)\($1)"
        }
        let brackets = Bracket.all.reduce("") {
            $0 + $1.rawValue
        }
        return ",;\(brackets)\(operators)"
    }

    /// A dictionary that maps a operator reference to its token.
    typealias OperatorReference = Dictionary<String, Token>

    /// A dictionary that maps a node reference to a node value.
    typealias NodeReference = Dictionary<String, Node>

    /// Flags are unique unicode codes that are only understood by the compiler.
    private class Flag {

        /// Denotes a reference to a node.
        static let node = Tokenizer.next()

        /// Denotes a reference to an operator.
        static let `operator` = Tokenizer.next()
    }

    /// Used to restore escape characters to their original form
    /// e.g \t becomes a tab.
    private let escapeCharDict: [String: String] = [
        "\\n": "\n",
        "\\r": "\r",
        "\\t": "\t",
        "\\\"": "\"",
        "\\\\": "\\"
    ]
    
    /// Cache compiled expressions to allow incremental compilation (way faster)
    private var compiledExpressions = [String: Node]()
    
    /// Prepositions
    private let prepositions = Pair.Preposition.allCases.reduce(into: [:]) {
        $0[$1.rawValue] = $1
    }

    /// Compiles a single line expression.
    ///
    /// - Parameter expr: String representation of an expression
    /// - Returns: Parent node of the compiled expression.
    public func compile(_ expr: String) throws -> Node {
        var expr = expr
        
        let preserved = expr
        if let compiled = compiledExpressions[expr] {
            return compiled
        }
        
        // Encode strings
        var dict = Dictionary<String, Node>()
        encodeStrings(&expr, dict: &dict)

        try validate(expr)
        applyTrailingClosureSyntax(&expr)
        
        // Format lists
        while expr.contains("{") {
            expr = replace(expr, "{", "}", "list(", ")")
        }

        // Sort keywords by compilation precedence
        let keywords = Syntax.tokens.map {
                $0.value
            }.sorted {
                $0.compilationPriority > $1.compilationPriority
            }
        
        // Encode expressions with keyword tokens before compilation (tokenization)
        for keyword in keywords {
            expr = tokenize(keyword, for: expr)
        }

        format(&expr)

        // Convert all binary operations to functions with parameters.
        // i.e. a+b becomes &?(a,b)
        let binOps = try binaryToFunction(&expr)

        // Construct operation tree
        let parent = try resolve(expr, &dict, binOps)

        // Restore tokens to their original form.
        let compiled =  try postprocess(parent)
        compiledExpressions[preserved] = compiled
        return compiled
    }

    
    /// Compiles a multi-line document into a statements marked with line number.
    /// - Parameter document: A string containing multiple lines of code
    /// - Returns: A program.
    public func compile(document: String, workItem: DispatchWorkItem? = nil) throws -> [Program.Statement] {
        let lines = document.split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
        var statements = [Program.Statement]()
        var buff: String? = nil
        
        var openBrackets: [Bracket: Int] = [
            .curly: 0,
            .square: 0,
            .round: 0
        ]
        
        for (i, var line) in lines.enumerated() {
            if let item = workItem, item.isCancelled {
                throw CompilerError.cancelled
            }
            
            // Remove trailing and padding white spaces
            line = line.trimmed

            // Character '#' serves as a precursor for comment
            // Empty lines are omitted.
            if line.starts(with: "#") || line == "" {
                continue
            }
            
            // Update bracket depths
            let curOpenBrackets = countOpenBrackets(line)
            openBrackets[.square]! += curOpenBrackets[.square]!
            openBrackets[.round]! += curOpenBrackets[.round]!
            openBrackets[.curly]! += curOpenBrackets[.curly]!
            
            for (bracket, depth) in openBrackets {
                if depth < 0 {
                    let e = CompilerError.syntax(errMsg: "\(bracket.rawValue) mismatch in \"\(line)\"")
                    throw CompilerError.on(line: i + 1, e)
                }
            }
            
            if openBrackets.allSatisfy({$0.value == 0}) {
                
                // All brackets have been closed at this point.
                if let b = buff {
                    line = b + line
                    buff = nil
                }
            } else if openBrackets.allSatisfy({$0.value >= 0}) {
                
                if buff == nil {
                    buff = ""
                }
                buff?.append(line)
                
                continue
            } else {
                
                // Brackets mismatch, deliberately bail out
                do {
                    let _ = try compile(line)
                } catch let e as CompilerError {
                    throw CompilerError.on(line: i + 1, e)
                }
            }

            do {
                let node = try compile(line)
                let statement = Program.Statement(line: i + 1, node: node)
                statements.append(statement)
            } catch let e as CompilerError {
                // Ignore empty errors
                switch e {
                case .emptyString:
                    // Do nothing
                    break
                default:
                    throw CompilerError.on(line: i + 1, e)
                }
            }
        }
        
        for (key, value) in openBrackets {
            if value != 0 {
                throw CompilerError.on(
                    line: lines.count,
                    CompilerError.syntax(errMsg: "\(key.rawValue) mismatch"))
            }
        }

        return statements
    }
    
    
    /// Counts the number of open brackets (round, curly, and square) in the line.
    /// - Returns: A dictionary containing the number of open brackets for each type.
    public func countOpenBrackets(_ line: String) -> [Bracket: Int] {
        var counts = [Int](repeating: 0, count: 3)
        // Remove quotation marks so quoted parenthesis won't be counted
        let stripped = line.replacingOccurrences(of: #"(["])(\\?.)*?\1"#, with: "", options: .regularExpression)
        for c in stripped {
            switch c {
            case "{":
                counts[0] += 1
            case "}":
                counts[0] -= 1
            case "[":
                counts[1] += 1
            case "]":
                counts[1] -= 1
            case "(":
                counts[2] += 1
            case ")":
                counts[2] -= 1
            default:
                continue
            }
        }
        
        var openBrackets = [Bracket: Int]()
        openBrackets[.curly] = counts[0]
        openBrackets[.square] = counts[1]
        openBrackets[.round] = counts[2]
        
        return openBrackets
    }
    
    private func applyTrailingClosureSyntax(_ expr: inout String) {
        
        // Convert f {} to f(#())
        let regex = try! NSRegularExpression(pattern: "\\w+\\s*\\{", options: [])
        var startIdx = 0
        while let match = regex.firstMatch(in: expr, options: [], range: NSRange(location: startIdx, length: expr.count - startIdx)) {
            let range = match.range
            let _0 = expr.startIndex
            let lb = expr.index(_0, offsetBy: range.lowerBound)
            let leftBracketIdx = expr.index(_0, offsetBy: range.upperBound - 1)
            let rightBracketIdx = find(expr, start: leftBracketIdx, close: "}")!
            let left = expr[_0..<lb]
            let right = expr[expr.index(after: rightBracketIdx)...]
            let name = expr[lb..<leftBracketIdx].trimmingCharacters(in: .whitespaces)
            
            if name[.implicitTrailingClosure] {
                let closure = expr[expr.index(after: leftBracketIdx)..<rightBracketIdx]
                let formatted = "\(name)(\(Closure.symbol)(\(closure)))"
                expr = left + formatted + right
                startIdx = left.count + formatted.count
            } else {
                startIdx = expr.distance(from: _0, to: rightBracketIdx)
            }
            
            if startIdx >= expr.count {
                break
            }
        }
        
        // Remove white spaces b/w parenthesis and trailing closure
        expr = expr.replacingOccurrences(of: #"\)\s*\{"#, with: "){", options: .regularExpression)
        
        // Convert f(a){...} to f(a,#(...))
        while let range = expr.range(of: "){") {
            let closingCurlyBracketIdx = find(expr, start: expr.index(before: range.upperBound), close: "}")!
            let insideCurlyBrackets = String(expr[range.upperBound..<closingCurlyBracketIdx])
            let left = expr[expr.startIndex..<range.lowerBound]
            let right = expr[expr.index(after: closingCurlyBracketIdx)...]
            expr = "\(left), \(Closure.symbol)(\(insideCurlyBrackets)))\(right)"
        }
    }

    /// Replaces strings in the expression w/ node references and store the
    /// actual string values into the node reference dictionary.
    /// They are converted back at the final step of compilation.
    private func encodeStrings(_ expr: inout String, dict: inout NodeReference) {

        // Regex for matching string inside double quotes
        let regex = try! NSRegularExpression(pattern: #"(["])(\\?.)*?\1"#, options: NSRegularExpression.Options.caseInsensitive)

        var count = 0
        while true {
            let range = NSMakeRange(0, expr.count)
            let rg = regex.rangeOfFirstMatch(in: expr, options: [], range: range)

            // No more matches, break the loop.
            if rg.upperBound == Int.max {
                break
            }

            var left = ""
            var extracted = ""
            var right = ""

            for (i, c) in expr.enumerated() {
                let s = "\(c)"
                if i < rg.lowerBound {
                    left += s
                } else if i == rg.lowerBound || i == rg.upperBound - 1 {
                    continue // Skip left & right quotation mark
                } else if i < rg.upperBound {
                    extracted += s
                } else {
                    right += s
                }
            }

            let encoded = "\(Flag.node)\(count)"

            // Update the expression with the code for the extracted string.
            expr = "\(left)\(encoded)\(right)"

            // Restore escape characters to their original form.
            for (key, value) in escapeCharDict {
                extracted = extracted.replacingOccurrences(of: key, with: value)
            }

            // Store the extracted string as a node reference
            dict[encoded] = String(extracted)

            count += 1
        }
    }

    
    /// Replace keywords and their symbols with their tokens.
    ///
    /// - Parameters:
    ///    - keyword: The keyword to be encoded
    private func tokenize(_ keyword: Keyword, for expr: String) -> String {
        var expr = expr
        var c = keyword.token
        var n = keyword.name

        // Replace operators with their code
        if let o = keyword.operator?.name {
            
            // If there exists multiple definitions of the same operator,
            // use the encoding for the most prioritized definition
            // in terms of associative property.
            if let disambiguated = Syntax.ambiguousOperators[o] {
                c = disambiguated.first!.token
            }
            
            expr = expr.replacingOccurrences(of: o, with: "\(c)")
        }

        // Replace infix function names with operator
        if let _ = Variable(n) {
            
            switch keyword.associativity {
            case .infix:
                n = "\\s\(n)\\s"
            case .prefix:
                n = "\\b\(n)\\s"
            case .postfix:
                n = "\\s\(n)\\b"
            }
            
            let regex = try! NSRegularExpression(pattern: n, options: .caseInsensitive)
            let str = NSMutableString(string: expr)
            let range = NSMakeRange(0, expr.count)
            regex.replaceMatches(in: str, options: [], range: range, withTemplate: "\(c)")
            return str as String
        }
        
        return expr
    }

    
    /// During compilation, everything is encoded into a AST.
    /// This function decodes the AST and does numerous post-compilation processings.
    /// e.g. `list(a,b,c) -> {a,b,c}`
    ///      `=(a+b, c+x) -> a+b=c+x`
    ///
    /// - Parameter parent: The parent node to have DTs restored.
    /// - Returns: The parent node with DTs restored.
    private func postprocess(_ parent: Node) throws -> Node {
        var parent = parent

        func name(_ node: Node) -> String? {
            return (node as? Function)?.name
        }

        func args(_ node: Node) -> [Node] {
            return (node as! Function).elements
        }

        // Decode encoded operators & keywords
        parent = parent.replacing(by: {
            let keyword = Syntax.tokens[Token(name($0)!)]!
            return Function(keyword.name, args($0))
        }) {
            // If the name of the function is an encoding key,
            // Replace it with its common name.
            if let name = name($0), name.count == 1 {
                return Syntax.tokens[Token(name)] != nil
            }
            return false
        }

        // Restore list() to {}
        parent = parent.replacing(by: { List(args($0)) }) {
            name($0) == .list
        }
        
        // Restore closures
        parent = parent.replacing(by: {
            let a = args($0)
            if a.count == 0 {
                return Closure(KVoid())
            }
            return Closure(a[0])
        }) {
            name($0) == Closure.symbol
        }

        // Restore equations
        parent = try parent.replacing(by: {
            let elements = args($0)
            if elements.count != 2 {
                throw CompilerError.syntax(errMsg: "expected expr. on both sides of '='")
            }
            return Equation(lhs: args($0)[0], rhs: args($0)[1])
        }) {
            name($0) == .equates
        }
        
        // Prepositions
        parent = parent.replacing(by: {
            let prep = Pair.Preposition(rawValue: name($0)!)!
            return Pair(args($0)[0], args($0)[1], preposition: prep)
        }) {
            prepositions[name($0) ?? ""] != nil && args($0).count == 2
        }
        
        // Restore else {...}
        parent = parent.replacing(by: {
            let fun = $0 as! Function
            fun[1] = Closure(fun[1] as! List)!
            return fun
        }) {
            if let fun = $0 as? Function, fun.name == .else {
                if let list = fun.elements.last as? List {
                    if Closure(list) != nil {
                        return true
                    }
                }
            }
            return false
        }
        
        // Infer matrices
        parent = try parent.replacing(by: {
            let vec = $0 as! Vector
            var isMatrix = vec.elements.count > 0
            let vectors = vec.elements.map {(v) -> Vector? in
                if let vec = v as? Vector {
                    return vec
                }
                isMatrix = false
                return nil
            }
            
            if isMatrix {
                return try Matrix(vectors.compactMap { $0 })
            }
            return vec
        }) {
            $0 is Vector && $0.contains(where: { $0 is Vector }, depth: 1)
        }
        
        // Define prefix, postfix, infix, and auto syntax.
        if let assocFun = parent as? Function {
            let assoc = assocFun.name
            switch assoc {
            case .prefix, .infix, .postfix, .auto:
                guard let arg = assocFun.elements.first else {
                    throw CompilerError.illegalArgument(errMsg: "expected function, but found nothing");
                }
                let fun = try arg ~> Function.self
                let name = fun.name
                try Assert.newKeyword(name)
                switch assoc {
                    case .prefix:
                        // prefix f(_) {...}; prefix f(a)
                        try Assert.numArgs(fun.count, 2)
                        Syntax.define(for: name, associativity: .prefix)
                    case .postfix:
                        // postfix f(_) {...}; postfix f(a)
                        try Assert.numArgs(fun.count, 2)
                        Syntax.define(for: name, associativity: .postfix, precedence: .binary)
                    case .infix:
                        // infix f(_) {...}; infix f(a,b)
                        try Assert.numArgs(fun.count, 3)
                        Syntax.define(for: name, associativity: .infix)
                    case .auto:
                        // auto f(_) {...}; auto f(a)
                        try defineSyntax(for: fun)
                default:
                    fatalError()
                }
                parent = Function(.define, assocFun.elements)
            default:
                break
            }
        }
        
        return parent
    }
    
    /// Automatically derives prefix syntax for unary operations and infix syntax for binary operations.
    /// If a custom syntax definition for the operation already exists, the automatic definitions are omitted.
    /// - Parameter operation: The operation to derive a syntax definition for.
    private func defineSyntax(for fun: Function) throws {
        let name = fun.name
        guard Syntax.glossary[name] == nil else {
            throw CompilerError.duplicateKeyword(name)
        }
        switch fun.count {
        case 2:
            Syntax.define(
                for: name,
                associativity: .prefix,
                checkAmbiguity: false
            )
        case 3:
            Syntax.define(
                for: name,
                associativity: .infix,
                precedence: .binary,
                checkAmbiguity: false
            )
        default:
            break
        }
    }
    
    
    /// Finds the start index of the prefix before square brackets or parenthesis.
    /// e.g.
    /// in `38+random()`, the index of `r` is returned;
    /// In `a+list[b]`, index of `l` is returned b/c the brackets in this case constitutes a subscript.
    /// In `34+(a+b)`, nil is returned b/c `()` in `(a+b)` only denotes a parenthesis.
    ///
    /// - Parameters:
    ///    - lb: The index of the left bracket/parenthesis
    /// - Returns: The start index of the subscript operand or the name of the function.
    private func indexOfPrefix(before lb: String.Index, in expr: String) -> String.Index? {
        var prefixIdx = lb
        while let b = expr.index(prefixIdx, offsetBy: -1, limitedBy: expr.startIndex) {
            if symbols.contains(expr[b]) {
                break
            }
            prefixIdx = b
        }
        
        return prefixIdx == lb ? nil : prefixIdx
    }

    
    /// Turns a properly encoded/formatted string that represents an expression into a parent node. Working from
    /// inside out, the innermost parenthesis is identified and resolved; then, its content is extracted and resolved
    /// recursively. This way, a complex expression is systematically broken down and resolved.
    ///
    /// - Parameters:
    ///    - expr: The expression to be resolved
    ///    - dict: An empty node reference dictionary [String: Node] that is populated as the expression is resolved.
    ///    - binOps: A dictionary that maps a binary operator reference to an operator encoding.
    /// - Returns: The parent node that represents the expression.
    private func resolve(_ expr: String, _ dict: inout NodeReference, _ binOps: OperatorReference) throws -> Node {
        var expr = expr
        
        // Store the resolved node in the reference dictionary, then update the expression
        // by replacing the node w/ its reference.
        func update(_ node: Node, _ r: ClosedRange<String.Index>, _ prefixIdx: String.Index?) {
            let id = "\(Flag.node)\(dict.count)"
            dict[id] = node
            let left = String(expr[expr.startIndex..<(prefixIdx ?? r.lowerBound)])
            let right = String(expr[expr.index(after: r.upperBound)...])
            expr = left + id + right
        }
        
        // Resolve functions and binary operations. Start from inside and work outside -
        // first, identify the innermost parenthesis, process what's inside the parenthesis
        // to generate a node. Then, the node is added to the NodeReference dictionary,
        // and the innermost parenthesis along with its content is replaced with a string
        // that maps to the node.
        while expr.contains("(") {
            
            // Find the range of the innermost pairing of parenthesis
            let r = innermost(expr, "(", ")")
            
            let idx1 = expr.index(after: r.lowerBound)
            let idx2 = expr.index(before: r.upperBound)
            
            // If a prefix idx exists, what's inside the parenthesis are arguments to
            // a function whose name is represented by the prefix.
            let prefixIdx = indexOfPrefix(before: r.lowerBound, in: expr)
            
            // Range inside parenthesis
            // A range isn't use here to avoid error caused by upperBound < lowerBound
            let ir = [idx1, idx2]

            var node: Node? = nil
            
            if let prefixIdx = prefixIdx {
                
                // In case of definitions like random(), where it takes in no arguments.
                var name = String(expr[prefixIdx..<r.lowerBound])
                if let bin = binOps[name] {
                    name = bin.description
                }

                // Remove trailing and padding white spaces around the name.
                name = name.trimmed

                if ir[0] == r.upperBound {
                    
                    // Function w/ no arguments.
                    node = Function(name, [])
                } else {
                    
                    // Recursively resolve the arguments of the function.
                    let nested = try resolve(String(expr[ir[0]...ir[1]]), &dict, binOps)
                    if let list = nested as? List {
                        node = Function(name, list.elements)
                    } else {
                        node = Function(name, [nested])
                    }
                }
            } else {
                if ir[0] == r.upperBound {
                    node = KVoid()
                } else {
                    node = try resolve(String(expr[ir[0]...ir[1]]), &dict, binOps)
                }
            }

            // Update the expression.
            update(node!, r, prefixIdx)
        }
        
        // Resolve vectors and subscripts
        while expr.contains("[") {
            
            // Find the range of the innermost pairing of square brackets.
            let r = innermost(expr, "[", "]")
            
            // Empty square brackets [] denote an empty vector.
            if expr.index(after: r.lowerBound) == r.upperBound {
                if indexOfPrefix(before: r.lowerBound, in: expr) != nil {
                    throw CompilerError.syntax(errMsg: "cannot subscript with empty square brackets []")
                }
                update(Vector([]), r, nil)
                continue
            }
            
            // Find the range of string inside the brackets.
            let insideR = expr.index(after: r.lowerBound)...expr.index(before: r.upperBound)
            let inside = String(expr[insideR])
            
            // Recursively resolve the vector/subscript argument.
            let sub = try resolve(inside, &dict, binOps)
            
            // If there is a prefix, the brackets denote a subscript;
            // otherwise it denotes a vector.
            let prefixIdx = indexOfPrefix(before: r.lowerBound, in: expr)
            
            var node: Node?
            if let subscriptIdx = prefixIdx {
                
                // Subscript
                let operandStr = String(expr[subscriptIdx..<r.lowerBound])
                let operand = try resolve(operandStr, &dict, binOps)
                node = Function(.get, [operand, sub])
            } else {
                
                // Vector
                if let list = sub as? List {
                    node = Vector(list.elements)
                } else {
                    node = Vector([sub])
                }
            }
            
            // Update the expression.
            update(node!, r, prefixIdx)
        }

        if expr.contains(";") {
            let nodes = try expr.split(separator: ";")
                .map {
                    try resolve(String($0), &dict, binOps)
            }
            return Statements(nodes)
        } else if expr.contains(",") {
            
            // Resolve lists.
            let nodes = try expr.split(separator: ",")
                    .map {
                        try resolve(String($0), &dict, binOps)
                    }
            return List(nodes)
        } else {
            
            // The base case of the recursion tree where there are no more
            // square brackets, parentheses, functions, or lists.
            expr = expr.trimmed

            // Try turning the expr into a node by first trying it as a node reference,
            // then an integer, next a double, and finally a boolean.
            if let node = dict[expr] ?? Int(expr) ?? BigInt(expr) ?? Float80(expr) ?? Bool(expr) {
                return node
            } else if let fun = FlowControl.parse(expr) {
                // Flow control statements (return, throw, continue, break)
                return fun
            } else {
                if expr.starts(with: KType.marker) {
                    expr.removeFirst()
                    guard let type = KType(rawValue: expr) else {
                        throw CompilerError.invalidType(literal: expr)
                    }
                    return type
                }
                
                // If none of the types above apply, then try to use it as a variable name.
                if expr.starts(with: Constant.marker) {
                    let literal = String(expr.dropFirst())
                    guard let const = Constant(literal) else {
                        throw CompilerError.noSuchConstant(literal: literal)
                    }
                    return const
                }
                guard let v = Variable(expr) else {
                    throw CompilerError.syntax(errMsg: "illegal variable name '\(expr)'")
                }
                return v
            }
        }
    }

    private func binaryToFunction(_ expr: inout String) throws -> OperatorReference {
        let keywords = Syntax.tokens.values
        let sorted = keywords.sorted {
            $0.precedence > $1.precedence
        }

        var prioritized = [[Keyword]]()
        var cur = sorted[0].precedence
        
        // Split operators into precedence groups
        var precedenceGroup = [Keyword]()
        
        sorted.forEach {
            
            // For each cluster in the group, the operators are
            // arranged according to their precedence. The operators with
            // higher precedence are processed first.
            if $0.precedence != cur {
                cur = $0.precedence
                
                // First add the prefix and postfix group, as they need to be
                // processed first; then add the infix group
                prioritized.append(precedenceGroup)
                
                // Clear precedence group buffer.
                precedenceGroup = [Keyword]()
            }
            
            precedenceGroup.append($0)
        }
        
        // Add the remaining groups with lowest precedence.
        prioritized.append(precedenceGroup)

        var dict = OperatorReference()
        for keywords in prioritized {
            var grp = [Character: String]()
            keywords.forEach {
                let id = "\(Flag.operator)\(dict.count)"
                dict[id] = $0.token
                grp[$0.token] = id
            }
            try parenthesize(&expr, grp, keywords.first!.precedence)
        }
        return dict
    }
    
    private enum Order {
        case leftToRight
        case rightToLeft
    }
    
    /// Finds the index of the first appearance of any of the operators.
    /// e.g. in a+b-c, first index returns index of "+", then next time, after
    /// "+" is parenthesized, index for "-" is returned.
    ///
    /// - Parameter operators: A group of operators with same precedence.
    /// - Returns: The first index of any of the operators, if there is one.
    private func index(
        order: Order,
        from startIdx: String.Index,
        of encodings: [Token: String],
        in expr: String
    ) -> String.Index? {
        let seq = expr[startIdx..<expr.endIndex].enumerated()
        switch order {
        case .rightToLeft:
            for (i, c) in seq.reversed() {
                if encodings[c] != nil {
                    return expr.index(startIdx, offsetBy: i)
                }
            }
        case .leftToRight:
            for (i, c) in seq {
                if encodings[c] != nil {
                    return expr.index(startIdx, offsetBy: i)
                }
            }
        }
        return nil
    }

    private func parenthesize(
        _ expr: inout String,
        _ grp: [Token: String],
        _ precedence: Keyword.Precedence
    ) throws {
        var curIdx = expr.startIndex
        let order: Order = precedence == .prefix ? .rightToLeft : .leftToRight
        
        while let idx = index(order: order, from: curIdx, of: grp, in: expr) {
            let idx_ = expr.index(after: idx)
            let _idx = expr.index(before: idx)
            var left: String?, right: String?
            var begin = expr.startIndex, end = expr.endIndex
            let r = binRange(expr, idx)


            // To the right of binary operator
            if expr[idx_] == "(" {
                
                // a + (...)
                end = find(expr, start: idx_, close: ")")!
                right = String(expr[idx_...end])
            } else if expr[idx_] == "{" {
                
                // a + {...}
                end = find(expr, start: idx_, close: "}")!
                right = String(expr[idx_...end])
            } else if expr[idx_] == "[" {
                
                // a + [...], in this case, [] denotes a vector.
                end = find(expr, start: idx_, close: "]")!
                right = String(expr[idx_...end])
            } else if let p = expr.index(r.upperBound, offsetBy: 1, limitedBy: expr.index(before: expr.endIndex)), expr[p] == "(" {
                
                // a + func(...), the right hand side is a function
                end = find(expr, start: p, close: ")")!
                right = String(expr[idx_...end])
            } else {
                
                // a + b?, right hand side is a variable, or no right hand side.
                if idx_ <= r.upperBound {
                    let rop = String(expr[idx_...r.upperBound])
                    right = rop
                }
                end = r.upperBound
            }
            
            // a + matrix[a][b]...; a + f()[a]...; a + {a, b, c}[d]; the right hand side is a (chained) subscript.
            while let m = expr.index(end, offsetBy: 1, limitedBy: expr.index(before: expr.endIndex)) {
                if expr[m] != "[" {
                    break
                }
                end = find(expr, start: m, close: "]")!
                right = String(expr[idx_...end])
            }
            
            var anchor = _idx
            if expr[_idx] == "]" {
                
                // [a, b, c] + d or matrix[a][b][...] + c. Find the open square bracket that pairs with _idx
                begin = find(expr, end: _idx, open: "[")!
                
                // Then, trace to the beginning of all chaining squarebrackets.
                while var b = expr.index(begin, offsetBy: -1, limitedBy: expr.startIndex) {
                    if expr[b] == "]" {
                        begin = find(expr, end: b, open: "[")!
                        continue
                    } else if symbols.contains(expr[b]) {
                        break
                    } else {
                        
                        // We've arrived as the beginning index of all chaining brackets, check if a
                        // prefix is present. If it is, set 'begin' to the start index of prefix.
                        while let k = expr.index(b, offsetBy: -1, limitedBy: expr.startIndex) {
                            if symbols.contains(expr[k]) {
                                break
                            }
                            b = k
                        }
                        begin = b
                    }
                }
                left = String(expr[begin..._idx])
                if let i = expr.index(begin, offsetBy: -1, limitedBy: expr.startIndex) {
                    anchor = i
                }
            }

            // To the left of binary operator
            if expr[anchor] == ")" {
                
                // (a - c) + b or func(a) + b. First find the index of the open parenthesis.
                begin = find(expr, end: anchor, open: "(")!
                
                // Then, check if there is a prefix before the open index.
                while let b = expr.index(begin, offsetBy: -1, limitedBy: expr.startIndex) {
                    if symbols.contains(expr[b]) {
                        break
                    }
                    begin = b
                }
                left = String(expr[begin..._idx])
            } else if expr[anchor] == "}" {
                
                // {...} + a
                begin = find(expr, end: anchor, open: "{")!
                left = String(expr[begin..._idx])
            } else if anchor == _idx { // If the anchor hasn't been moved due to subscripts...
                
                // A pain old variable.
                if r.lowerBound <= _idx {
                    let lop = String(expr[r.lowerBound..._idx])
                    left = lop
                }
                begin = r.lowerBound
            }

            let keyword = Syntax.tokens[expr[idx]]!
            let (args, correctedEncoding: e) = try resolveAssociativity(keyword, left, right)
            
            let rLeft = String(expr[..<begin])
            let rRight = String(expr[expr.index(after: end)...])
            let token = e ?? expr[idx]
            
            if let id = grp[token] {
                expr = rLeft + "\(id)(\(args))" + rRight
            } else {
                
                // The current interpretation of the operation does not fit its precedence group!
                // Change the binary operator token to the correct one!
                // The corrected token will be parenthesized later.
                expr = "\(expr[..<idx])\(token)\(expr[expr.index(after: idx)...])"
                curIdx = expr.index(after: curIdx)
            }
        }
    }
    
    private func resolveAssociativity(
        _ keyword: Keyword,
        _ left: String?,
        _ right: String?
        ) throws -> (String, correctedEncoding: Token?) {
        
        func fun(_ s: Keyword) throws -> String {
            var args = ""
            var error: String?
            if let l = left, let r = right {
                if s.associativity != .infix {
                    error = "infix"
                }
                args = "\(l),\(r)"
            } else if let r = right {
                if s.associativity != .prefix {
                    error = "prefix"
                }
                args = "\(r)"
            } else if let l = left {
                if s.associativity != .postfix {
                    error = "postfix"
                }
                args = "\(l)"
            }
            
            if let e = error {
                let n = s.name
                let o = s.operator?.name ?? ""
                let msg = "\(n), i.e. '\(o)' cannot be used as a/an \(e) operator"
                throw CompilerError.syntax(errMsg: msg)
            }
            
            return args
        }
        
        if let o = keyword.operator?.name  {
            if let arr = Syntax.ambiguousOperators[o] {
                for s in arr {
                    if let i = try? fun(s) {
                        return (i, s.token)
                    }
                }
            }
        }
        
        return (try fun(keyword), nil)
    }

    private func replace(_ expr: inout String, of target: String, with replacement: String) {
        expr = expr.replacingOccurrences(of: target, with: replacement)
    }

    /// Formats the raw String to prepare it for the formulation into a Function instance.
    /// For instance, the call to formatCoefficients("x+2x^2+3x+4") would return "x+2*x^2+3*x+4"
    ///
    /// - Parameter expr: The expression to have coefficients and negative sign formatted
    private func format(_ expr: inout String) {

        // Remove white spaces for ease of processing
        expr = expr.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        // Add another layer of parenthesis to prevent an error
        expr = "(\(expr))"

        // Apply implied multiplicity
        // f1() should be seen as a function whereas 3(x) = 3*x
        // 3a*4x = 3*a*4*x, +3(x+b) = 3*(x+b), (a+b)(a-b) = (a+b)*(a-b)
        let e = Syntax.glossary[.mult]!.token
        expr = expr.replacingOccurrences(of: #"\b(\d+|\))([a-zA-Z_$]+|\()"#, with: "$1\(e)$2", options: .regularExpression)
    }

    /// Finds all indices in which the substring occurs in the given string
    ///
    /// - Parameter substr: A string to look for in str
    /// - Parameter str: A string containing multiple (or none) occurences of substr
    /// - Returns: The indices at which substr occurs in str.
    private func findIndices(of substr: String, in str: String) -> [String.Index] {
        var indices = [String.Index]()
        if let r = str.range(of: substr) {
            indices.append(r.lowerBound)
            let left = str[...r.lowerBound]
            let right = String(str[str.index(after: r.lowerBound)...])
            let subIndices = findIndices(of: substr, in: right)
            indices.append(contentsOf: subIndices.map {
                str.index($0, offsetBy: left.count)
            })
        }
        return indices
    }

    private func binRange(_ segment: String, _ binIdx: String.Index) -> ClosedRange<String.Index> {
        var beginIdx = binIdx
        var endIdx = binIdx
        
        while let idx = segment.index(beginIdx, offsetBy: -1, limitedBy: segment.startIndex) {
            if symbols.contains(segment[idx]) {
                break
            }
            beginIdx = idx
        }
        
        while let idx = segment.index(endIdx, offsetBy: 1, limitedBy: segment.endIndex) {
            if symbols.contains(segment[idx]) {
                break
            }
            endIdx = idx
        }
        
        return beginIdx...endIdx
    }

    /// Validates the expression for parenthesis/brackets match, illegal symbols, etc.
    private func validate(_ expr: String) throws {
        func matches(_ expr: String, _ chars: [String]) -> Bool {
            var n: Int? = nil
            for char in chars {
                let c = Character(char)
                if n == nil {
                    n = count(expr, char: c)
                } else if count(expr, char: c) != n {
                    return false
                }
            }
            return true
        }
        
        for bracket in Bracket.all {
            if !matches(expr, bracket.rawValue.map {"\($0)"}) {
                throw CompilerError.syntax(errMsg: "\(bracket) mismatch in \"\(expr)\"")
            }
        }

        if expr == "" {
            throw CompilerError.emptyString
        } else if count(expr, char: "\"") % 2 != 0 {
            throw CompilerError.syntax(errMsg: "\" mismatch in \"\(expr)\"")
        }
    }

    /// - Parameters:
    ///    - exp: The expression to be modified
    ///    - open: Open bracket symbol
    ///    - close: Close bracket symbol
    ///    - rp1: Replacement for "open"
    ///    - rp2: Replacement for "close"
    /// - Returns: Expression with "open" replaced with "open1" and "close" replaced with "close1"
    private func replace(_ exp: String, _ open: Character, _ close: Character, _ rp1: String, _ rp2: String) -> String {
        let r = self.innermost(exp, open, close)
        let idx1 = exp.index(after: r.lowerBound)
        let idx2 = exp.index(after: r.upperBound)

        let tmp1 = String(exp[..<r.lowerBound])
        let tmp2 = String(exp[idx1..<r.upperBound])
        let tmp3 = String(exp[idx2...])

        return tmp1 + rp1 + tmp2 + rp2 + tmp3
    }

    /// - Returns: The indices of the innermost opening and the closing parenthesis/brackets
    private func innermost(_ exp: String, _ open: Character, _ close: Character) -> ClosedRange<String.Index> {
        let closeIdx = exp.firstIndex(of: close)!
        let openIdx = exp[..<closeIdx].lastIndex(of: open)!
        return openIdx...closeIdx
    }

    /// Call to `findMatchingIndex("(56+(34+2))*(32+(13+34+2))",4,")")` returns `9`
    /// Call to `findMatchingIndex("(56+(34+2))*(32+(13+34+2))",0,")")` returns `10`
    ///
    /// - Parameters:
    ///    - start: the starting index, i.e starting idx of parenthesis/bracket
    ///    - close: the char that completes the parenthesis/bracket together with the char at start idx.
    /// - Returns: the index at which the parenthesis/bracket terminates
    private func find(_ expr: String, start: String.Index, close: Character) -> String.Index? {
        let open = expr[start]
        var stacks = 0
        for (idx, c) in expr[start...].enumerated() {
            switch c {
            case open: stacks += 1
            case close: stacks -= 1
            default: break
            }
            if stacks == 0 {
                return expr.index(start, offsetBy: idx)
            }
        }
        return nil
    }

    /// - Returns: the index at which the parenthesis/bracket opens
    private func find(_ expr: String, end: String.Index, open: Character) -> String.Index? {
        let close = expr[end]
        var stacks = 0
        for (idx, c) in expr[...end].enumerated().reversed() {
            switch c {
            case close: stacks += 1
            case open: stacks -= 1
            default: break
            }
            if stacks == 0 {
                return expr.index(expr.startIndex, offsetBy: idx)
            }
        }
        return nil
    }

    /// - Parameter s: String that is going to be indexed for occurrence of char c
    /// - Parameter c: char c for num of occurrence.
    /// - Returns: The number of times that `c` shows up in `s`.
    private func count(_ s: String, char: Character) -> Int {
        var count = 0
        for c in s {
            if c == char {
                count += 1
            }
        }
        return count;
    }
}

