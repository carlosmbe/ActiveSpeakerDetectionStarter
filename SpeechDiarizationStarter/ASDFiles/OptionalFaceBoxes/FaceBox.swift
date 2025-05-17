//
//  FaceBox.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 16/05/2025.
//

import SwiftUI

struct FaceBox: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let isSpeaker: Bool
}

struct FaceBoundingBoxView: View {
    let faceBoxes: [FaceBox]
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(faceBoxes) { faceBox in
                    let rect = convertNormalizedRect(faceBox.boundingBox, in: proxy.size)
                    
                    Rectangle()
                        .stroke(faceBox.isSpeaker ? Color.green : Color.red, lineWidth: 3)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }
    
    private func convertNormalizedRect(_ boundingBox: CGRect, in containerSize: CGSize) -> CGRect {

        let x = boundingBox.origin.x * containerSize.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * containerSize.height
        let w = boundingBox.width * containerSize.width
        let h = boundingBox.height * containerSize.height
        
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
