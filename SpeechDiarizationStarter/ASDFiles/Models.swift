//
//  Models.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 12/05/2025.
//

import Foundation
import SwiftUI

struct SpeakerProfile: Identifiable {
    let id = UUID()
    var speakerID: Int
    var faceID: UUID?
    var segments: [TimeSegment]
    var embedding: [Float]?
    
    struct TimeSegment {
        let start: Float
        let end: Float
    }
}

struct FaceProfile: Identifiable {
    let id = UUID()
    var trackID: UUID
    var timeRanges: [TimeRange]
    var avgPosition: CGPoint
    var mouthOpennessHistory: [Double] = []
    var avgMouthOpenness: Double = 0.0
    
    struct TimeRange {
        let timestamp: Double
        let boundingBox: CGRect
        let isSpeaking: Bool
        let mouthOpenness: Double
    }
}


class CombinedAnalysisResult: ObservableObject {
    @Published var matchedSpeakers: [MatchedSpeaker] = []
    @Published var preprocessingComplete = false
    
    struct MatchedSpeaker: Identifiable {
        let id = UUID()
        let speakerID: Int
        let faceID: UUID?
        let position: CGPoint?
        let segments: [SpeakerProfile.TimeSegment]
        var isCurrentlySpeaking: Bool = false
    }
}
