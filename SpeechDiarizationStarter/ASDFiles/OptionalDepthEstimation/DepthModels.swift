//
//  DepthModels.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 17/05/2025.
//

import CoreML
import UIKit

struct DepthBox: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    var depth: Float = 0
}

struct DepthMapData {
    let depthImage: UIImage
    let depthMapArray: MLMultiArray
}
