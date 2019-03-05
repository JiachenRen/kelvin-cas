//
//  Mode.swift
//  Kelvin
//
//  Created by Jiachen Ren on 1/9/19.
//  Copyright © 2019 Jiachen Ren. All rights reserved.
//

import Foundation

public struct Mode {
    public static var shared: Mode = Mode()
    
    // The rounding mode.
    public var rounding: Rounding = .approximate
    
    private var formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .scientific
        formatter.exponentSymbol = "*10^"
        return formatter
    }()
    
    func format(_ val: Float80) -> String {
        let absVal = abs(val)
        if absVal < Float80(Double.greatestFiniteMagnitude) && absVal > Float80(Double.leastNormalMagnitude) {
            let d = Double(round(1E10 * val) / 1E10)
            let absD = abs(d)
            if absD > 1E15 || absD < 1E-4 {
                return formatter.string(for: d)!
            }
            return d.description
        }
        return val.description.replacingOccurrences(of: "e+", with: "*10^")
            .replacingOccurrences(of: "e-", with: "*10^-")
    }
}

public enum Rounding {
    
    /// Constants are left as-is, and decimals are converted to fractions
    case exact
    
    /// Constants are unwrapped into their numerical values
    case approximate
}
