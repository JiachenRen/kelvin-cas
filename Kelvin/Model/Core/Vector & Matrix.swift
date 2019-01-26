//
//  Vector & Matrix.swift
//  Kelvin
//
//  Created by Jiachen Ren on 1/24/19.
//  Copyright © 2019 Jiachen Ren. All rights reserved.
//

import Foundation

let vectorOperations: [Operation] = [
    .init("+", [.vec, .vec]) {
        let vec1 = $0[0] as! Vector
        let vec2 = $0[1] as! Vector
        
        return try vec1.perform(+, with: vec2)
    },
    .init("-", [.vec, .vec]) {
        let vec1 = $0[0] as! Vector
        let vec2 = $0[1] as! Vector
        
        return try vec1.perform(-, with: vec2)
    },
    .init("*", [.vec, .vec]) {
        let vec1 = $0[0] as! Vector
        let vec2 = $0[1] as! Vector
        
        return try vec1.perform(*, with: vec2)
    },
    .init("/", [.vec, .vec]) {
        let vec1 = $0[0] as! Vector
        let vec2 = $0[1] as! Vector
        
        return try vec1.perform(*, with: vec2)
    },
    .init("unitVec", [.vec]) {
        return ($0[0] as! Vector).unitVector
    },
    .init("mag", [.vec]) {
        return ($0[0] as! Vector).magnitude
    }
]

let matrixOperations: [Operation] = [
    .init("det", [.matrix]) {
        let mat = $0[0] as! Matrix
        return try mat.determinant()
    }
]
