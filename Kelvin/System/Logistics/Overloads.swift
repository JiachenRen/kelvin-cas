//
//  Overloads.swift
//  Kelvin
//
//  Created by Jiachen Ren on 10/7/19.
//  Copyright © 2019 Jiachen Ren. All rights reserved.
//

import Foundation

public func ===(_ lhs: Node, _ rhs: Node) -> Bool {
    return lhs.equals(rhs)
}

public func !==(_ lhs: Node, _ rhs: Node) -> Bool {
    return !(lhs === rhs)
}

public func +(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.add, [lhs, rhs])
}

public func -(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.minus, [lhs, rhs])
}

public func ^(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.power, [lhs, rhs])
}

public func *(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.mult, [lhs, rhs])
}

infix operator ~>

@discardableResult
public func ~><T>(_ lhs: Node?, _ rhs: T.Type) throws -> T {
    return try Assert.cast(lhs, to: rhs)
}

infix operator **

public func **(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.matrixMultiplication, [lhs, rhs])
}

prefix operator *

public prefix func *(_ args: [Node]) -> Node {
    assert(args.count > 2)
    return Function(.mult, args.map {$0})
}

prefix operator **

public prefix func **(_ args: [Node]) -> Node {
    if args.count == 0 {
        return 1
    } else if args.count == 1 {
        return args[0]
    }
    return Function(.mult, args.map {$0})
}

prefix operator +

public prefix func +(_ args: [Node]) -> Node {
    assert(args.count >= 2)
    return Function(.add, args.map {$0})
}

prefix operator ++

public prefix func ++(_ args: [Node]) -> Node {
    if args.count == 0 {
        return 0
    } else if args.count == 1 {
        return args[0]
    }
    return Function(.add, args.map {$0})
}

postfix operator ++

public postfix func ++(_ arg: Node) -> Node {
    return Function(.increment, [arg])
}

postfix operator --

public postfix func --(_ arg: Node) -> Node {
    return Function(.decrement, [arg])
}

infix operator +==

public func +==(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.addAssign, [lhs, rhs])
}

infix operator -==

public func -==(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.minusAssign, [lhs, rhs])
}

infix operator *==

public func *==(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.multAssign, [lhs, rhs])
}

infix operator /==

public func /==(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.divAssign, [lhs, rhs])
}

infix operator &&&

public func &&&(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.and, [lhs, rhs])
}

infix operator |||

public func |||(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.or, [lhs, rhs])
}

prefix operator !!

public prefix func !!(_ arg: Node) -> Node {
    return Function(.not, [arg])
}

postfix operator ~!

public postfix func ~!(_ arg: Node) -> Node{
    return Function(.factorial, [arg])
}

prefix operator √

public prefix func √(_ arg: Node) -> Node {
    return Function(.sqrt, [arg])
}

public func /(_ lhs: Node, _ rhs: Node) -> Node {
    return Function(.div, [lhs, rhs])
}

public prefix func -(_ arg: Node) -> Node {
    return Function(.negate, [arg])
}

public func sin(_ arg: Node) -> Node {
    return Function(.sin, [arg])
}

public func cos(_ arg: Node) -> Node {
    return Function(.cos, [arg])
}

public func tan(_ arg: Node) -> Node {
    return Function(.tan, [arg])
}

public func atan(_ arg: Node) -> Node {
    return Function(.atan, [arg])
}

public func acos(_ arg: Node) -> Node {
    return Function(.acos, [arg])
}

public func asin(_ arg: Node) -> Node {
    return Function(.asin, [arg])
}

public func tanh(_ arg: Node) -> Node {
    return Function(.tanh, [arg])
}

public func cosh(_ arg: Node) -> Node {
    return Function(.cosh, [arg])
}

public func sinh(_ arg: Node) -> Node {
    return Function(.sinh, [arg])
}

public func log(_ arg: Node) -> Node {
    return Function(.log, [arg])
}

public func ln(_ arg: Node) -> Node {
    return Function(.ln, [arg])
}

public func sign(_ arg: Node) -> Node {
    return Function(.sign, [arg])
}

postfix operator ≈

public postfix func ≈(_ node: Node) -> Float80? {
    return node.evaluated?.float80
}

postfix operator ≈!

public postfix func ≈!(_ node: Node) -> Float80 {
    return (node≈)!
}

postfix operator &

public postfix func &(_ str: String) -> Variable {
    return Variable(str)!
}
