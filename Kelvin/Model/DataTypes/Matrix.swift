//
//  Matrix.swift
//  Kelvin
//
//  Created by Jiachen Ren on 1/25/19.
//  Copyright © 2019 Jiachen Ren. All rights reserved.
//

import Foundation

public struct Matrix: MutableListProtocol, NaN {
    
    public var stringified: String {
        let r = rows.reduce(nil) {
            return $0 == nil ? $1.stringified : $0!.stringified + ", " + $1.stringified
        }
        return "[\(r!)]"
    }
    
    public typealias Row = Vector
    public typealias Dimension = (rows: Int, cols: Int)
    
    var rows: [Row]
    
    var dim: Dimension
    
    var isSquareMatrix: Bool {
        return rows.count == rows.first!.count
    }
    
    subscript(_ idx: Int) -> Row {
        get {
            return rows[idx]
        }
        
        set {
           rows[idx] = newValue
        }
    }
    
    public var elements: [Node] {
        set {
            if let rows = newValue as? [Row] {
                self.rows = rows
                return
            }
            fatalError()
        }
        get {
            return self.rows
        }
    }
    
    init(_ dim: Int) {
        self.init(rows: dim, cols: dim)
    }
    
    init(rows: Int, cols: Int) {
        self.rows = [Row](repeating: Vector([Int](repeating: 0, count: cols)), count: rows)
        self.dim = (rows, cols)
    }
    
    init(_ list: ListProtocol) throws {
        if list.count == 0 {
            throw ExecutionError.general(errMsg: "cannot create matrix from empty list")
        }
        var rows = [Row]()
        var isProperMatrix = true
        for e in list.elements {
            if let row = Vector(e) {
                rows.append(row)
            } else {
                isProperMatrix = false
                break
            }
        }
        
        if !isProperMatrix {
            rows = [Row]()
            rows.append(Vector(list)!)
        }
        
        try self.init(rows)
    }
    
    init(_ rows: [Row]) throws {
        self.rows = rows
        if rows.count < 1 || rows.first!.count < 1 {
            throw ExecutionError.general(errMsg: "cannot create empty matrix")
        }
        
        for i in 0..<rows.count - 1 {
            if rows[i].count != rows[i + 1].count {
                throw ExecutionError.dimensionMismatch
            }
        }
        
        self.dim = (rows: rows.count, cols: rows[0].count)
    }
    
    public func equals(_ node: Node) -> Bool {
        guard let matrix = node as? Matrix else {
            return false
        }
        
        if matrix.dim != dim {
            return false
        }
        
        for (i, r) in matrix.rows.enumerated() {
            if r !== self[i] {
                return false
            }
        }
        
        return true
    }
    
    public func determinant() throws -> Node {
        return try Matrix.determinant(of: self, dim.rows)
    }
    
    /**
     Recursive function for finding determinant of matrix.
     n is current dimension of mat[][].
     */
    public static func determinant(of mat: Matrix, _ n: Int) throws -> Node {
        if !mat.isSquareMatrix {
            let msg = "cannot calculate determinant of non-square matrix"
            throw ExecutionError.general(errMsg: msg)
        }
        
        var d: Node = 0 // Initialize result
        
        //  Base case : if matrix contains single element
        if (n == 1) {
            return mat[0][0]
        }
        
        var temp = mat
        var sign = 1  // To store sign multiplier
        
        // Iterate for each element of first row
        for f in 0..<n {
            // Getting Cofactor of mat[0][f]
            getCofactor(mat, &temp, 0, f, n)
            let det = try determinant(of: temp, n - 1)
            d = (d + sign * mat[0][f] * det)
            
            // Terms are to be added with alternate sign
            sign = -sign
        }
        
        return d
    }
    
    private static func getCofactor(_ mat: Matrix, _ temp: inout Matrix, _ p: Int, _ q: Int, _ n: Int) {
        var i = 0, j = 0;
    
        // Looping for each element of the matrix
        for row in 0..<n {
            for col in 0..<n {
                
                // Copying into temporary matrix
                // only those element which are
                // not in given row and column
                if (row != p && col != q) {
                    temp[i][j] = mat[row][col]
                    j += 1
                    
                    // Row is filled, so increase
                    // row index and reset col index
                    if (j == n - 1) {
                        j = 0;
                        i += 1
                    }
                }
            }
        }
        
    }
    
}
