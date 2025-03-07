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
    var imageData: Data?
    var bodyFatAnalysis: String?
    
    init(timestamp: Date, imageData: Data? = nil, bodyFatAnalysis: String? = nil) {
        self.timestamp = timestamp
        self.imageData = imageData
        self.bodyFatAnalysis = bodyFatAnalysis
    }
}
