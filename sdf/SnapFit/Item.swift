//
//  Item.swift
//  SnapFit
//
//  Created by Sunny Wang on 12/25/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
