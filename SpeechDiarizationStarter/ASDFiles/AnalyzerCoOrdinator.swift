//
//  AnalyzerCoOrdinator.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 12/05/2025.
//

import AVFoundation
import Combine
import Vision
import Speech

class CombinedAnalysisCoordinator: ObservableObject {
    @Published var analysisResult = CombinedAnalysisResult()
    @Published var processingProgress: Double = 0.0
    
    private let speechAnalyzer: SpeechAnalyzer
    private let visionAnalyzer: VisionAnalyzer
    private var cancellables = Set<AnyCancellable>()
    
    init(videoURL: URL, audioURL: URL? = nil) {
        self.speechAnalyzer = SpeechAnalyzer()
        self.visionAnalyzer = VisionAnalyzer(videoURL: videoURL)
        
        // Start the audio conversion process
        speechAnalyzer.prepareAudio(sourceURL: audioURL ?? videoURL)
    }
    
    func preprocessVideoAndAudio() async {
        // Wait for audio conversion to complete
        while !speechAnalyzer.isAudioReady {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        do {
           print("Starting speech recognition...")
            
            // Perform speech recognition
            let utterances = try await speechAnalyzer.performSpeechRecognition()
            speechAnalyzer.recognizedUtterances = utterances
            
            print("Performing speaker diarization...")
            
            // Perform speaker diarization
            let speakerProfiles = await speechAnalyzer.performSpeakerDiarization()
            
            print("Detecting and tracking faces...")
            
            // Process video frames to detect and track faces
            let faceProfiles = try await visionAnalyzer.detectAndTrackFaces()
            visionAnalyzer.faceProfiles = faceProfiles
            
            print("Matching faces to speakers...")
            
            // Match speech utterances to speaker segments
            let matchedUtterances = speechAnalyzer.matchUtterancesToSpeakers(
                utterances: speechAnalyzer.recognizedUtterances,
                speakerProfiles: speakerProfiles
            )
            
            // Match faces to speakers
            try await matchFacesToSpeakersUsingUtterances(
                matchedUtterances: matchedUtterances,
                speakerProfiles: speakerProfiles,
                faceProfiles: faceProfiles
            )
            
            print( "Processing complete!")
            
            DispatchQueue.main.async {
                self.analysisResult.preprocessingComplete = true
            }
        } catch {
            print("Error preprocessing video and audio: \(error)")
        }
    }
    
    
    private func matchFacesToSpeakersUsingUtterances(
        matchedUtterances: [(utterance: SpeechAnalyzer.RecognizedUtterance, speakerID: Int)],
        speakerProfiles: [SpeakerProfile],
        faceProfiles: [FaceProfile]
    ) async throws {
        var matchedSpeakers: [CombinedAnalysisResult.MatchedSpeaker] = []
        var speakerToFaceMatches: [Int: [(faceID: UUID, score: Double)]] = [:]
        var faceSpeakerScores: [UUID: [Int: Double]] = [:]
        
        // 1. Pre-calculate face-speaker segment affinity scores
        for speaker in speakerProfiles {
            for segment in speaker.segments {
                let start = Double(segment.start)
                let end = Double(segment.end)
                
                for face in faceProfiles {
                    let speakingMoments = face.timeRanges.filter {
                        $0.timestamp >= start &&
                        $0.timestamp <= end &&
                        $0.isSpeaking
                    }
                    
                    let segmentScore = speakingMoments.reduce(0.0) { total, moment in
                        let timeWeight = 1 - min(1, abs(moment.timestamp - (start + end)/2) / (end - start))
                        return total + moment.mouthOpenness * timeWeight
                    }
                    
                    faceSpeakerScores[face.trackID, default: [:]][speaker.speakerID, default: 0] += segmentScore
                }
            }
        }
        
        // 2. Process each utterance with temporal sampling
        for (utterance, speakerID) in matchedUtterances {
            guard utterance.endTime - utterance.startTime >= 0.3 else { continue }
            
            let sampleCount = Int((utterance.endTime - utterance.startTime) / 0.25)
            let sampleStep = (utterance.endTime - utterance.startTime) / Double(max(1, sampleCount))
            
            for sampleIndex in 0..<max(1, sampleCount) {
                let analysisTime = utterance.startTime + Double(sampleIndex) * sampleStep
                
                guard let cgImage = try await visionAnalyzer.getVideoFrame(at: CMTime(seconds: analysisTime, preferredTimescale: 600)) else {
                    continue
                }
                
                let faceRequest = VNDetectFaceLandmarksRequest()
                try visionAnalyzer.sequenceRequestHandler.perform([faceRequest], on: cgImage)
                guard let observations = faceRequest.results as? [VNFaceObservation] else {
                    continue
                }
                
                for observation in observations {
                    let boundingBox = observation.boundingBox
                    let faceCenter = CGPoint(
                        x: boundingBox.midX,
                        y: boundingBox.midY
                    )
                    
                    var mouthOpenness: Double = 0
                    if let innerLips = observation.landmarks?.innerLips,
                       let outerLips = observation.landmarks?.outerLips {
                        let innerPoints = innerLips.normalizedPoints
                        let outerPoints = outerLips.normalizedPoints
                        
                        let innerVertical = (innerPoints.max(by: { $0.y < $1.y })?.y ?? 0 ) -
                                         (innerPoints.min(by: { $0.y < $1.y })?.y ?? 0)
                                          
                        let outerVertical = (outerPoints.max(by: { $0.y < $1.y })?.y ?? 0 ) - (outerPoints.min(by: { $0.y < $1.y })?.y ?? 0)
                        
                        mouthOpenness = Double(max(innerVertical, outerVertical) * boundingBox.height)
                    }
                    
                    guard mouthOpenness > 0.03 else { continue }
                    
                    var bestMatch: (faceID: UUID, score: Double)? = nil
                    
                    for faceProfile in faceProfiles {
                        guard let closestTimeRange = faceProfile.timeRanges.min(by: {
                            abs($0.timestamp - analysisTime) < abs($1.timestamp - analysisTime)
                        }) else { continue }
                        
                        let timeDelta = abs(closestTimeRange.timestamp - analysisTime)
                        guard timeDelta < 0.5 else { continue }
                        
                        let overlapRect = boundingBox.intersection(closestTimeRange.boundingBox)
                        let iouScore = overlapRect.width * overlapRect.height /
                                      (boundingBox.width * boundingBox.height +
                                       closestTimeRange.boundingBox.width * closestTimeRange.boundingBox.height -
                                       overlapRect.width * overlapRect.height)
                        
                        let temporalScore = 1 - min(1, timeDelta / 0.5)
                        let segmentAffinity = faceSpeakerScores[faceProfile.trackID]?[speakerID] ?? 0
                        let normalizedSegmentScore = min(segmentAffinity / 100, 1.0)
                        
                        let spatialConsistency = calculateSpatialConsistency(
                            faceID: faceProfile.trackID,
                            speakerID: speakerID,
                            faceProfiles: faceProfiles,
                            speakerProfiles: speakerProfiles
                        )
                        
                        let score = (iouScore * 0.3) +
                                   (temporalScore * 0.2) +
                                   (mouthOpenness * 0.2) +
                                   (normalizedSegmentScore * 0.2) +
                                   (spatialConsistency * 0.1)
                        
                        if score > (bestMatch?.score ?? 0.5) {
                            bestMatch = (faceProfile.trackID, score)
                        }
                    }
                    
                    if let match = bestMatch, match.score > 0.5 {
                        speakerToFaceMatches[speakerID, default: []].append((match.faceID, match.score))
                    }
                }
            }
        }
        
        // 3. Determine best face match for each speaker
        for speakerID in speakerToFaceMatches.keys {
            guard let matches = speakerToFaceMatches[speakerID], !matches.isEmpty else { continue }
            
            var faceScores: [UUID: Double] = [:]
            for (faceID, score) in matches {
                faceScores[faceID, default: 0] += score
            }
            
            if let bestMatch = faceScores.max(by: { $0.value < $1.value }),
               let speaker = speakerProfiles.first(where: { $0.speakerID == speakerID }),
               let face = faceProfiles.first(where: { $0.trackID == bestMatch.key }) {
                
                let matchedSpeaker = CombinedAnalysisResult.MatchedSpeaker(
                    speakerID: speakerID,
                    faceID: bestMatch.key,
                    position: face.avgPosition,
                    segments: speaker.segments
                )
                
                matchedSpeakers.append(matchedSpeaker)
            }
        }
        
        // 4. Handle unmatched speakers with fallback strategy
        let matchedSpeakerIDs = Set(matchedSpeakers.map { $0.speakerID })
        let unmatchedSpeakers = speakerProfiles.filter { !matchedSpeakerIDs.contains($0.speakerID) }
        
        for speaker in unmatchedSpeakers {
            var bestFace: (id: UUID, score: Double)? = nil
            for face in faceProfiles {
                let score = faceSpeakerScores[face.trackID]?[speaker.speakerID] ?? 0
                if score > (bestFace?.score ?? 0) {
                    bestFace = (face.trackID, score)
                }
            }
            
            if let bestFace = bestFace, bestFace.score > 0 {
                let matchedSpeaker = CombinedAnalysisResult.MatchedSpeaker(
                    speakerID: speaker.speakerID,
                    faceID: bestFace.id,
                    position: faceProfiles.first { $0.trackID == bestFace.id }?.avgPosition,
                    segments: speaker.segments
                )
                matchedSpeakers.append(matchedSpeaker)
            }
        }
        
        DispatchQueue.main.async {
            self.analysisResult.matchedSpeakers = matchedSpeakers.sorted { $0.speakerID < $1.speakerID }
        }
    }
    
    private func calculateSpatialConsistency(
        faceID: UUID,
        speakerID: Int,
        faceProfiles: [FaceProfile],
        speakerProfiles: [SpeakerProfile]
    ) -> Double {
        guard let speaker = speakerProfiles.first(where: { $0.speakerID == speakerID }),
              let face = faceProfiles.first(where: { $0.trackID == faceID })
        else { return 0.0 }
        
        var positions: [CGPoint] = []
        var timestamps: [Double] = []
        
        for segment in speaker.segments {
            let start = Double(segment.start)
            let end = Double(segment.end)
            let step = (end - start) / 4
            
            for sampleTime in stride(from: start, through: end, by: step) {
                if let closest = face.timeRanges.min(by: {
                    abs($0.timestamp - sampleTime) < abs($1.timestamp - sampleTime)
                }) {
                    positions.append(CGPoint(
                        x: closest.boundingBox.midX,
                        y: closest.boundingBox.midY
                    ))
                    timestamps.append(closest.timestamp)
                }
            }
        }
        
        guard positions.count > 1 else { return 1.0 }
        
        let avgX = positions.map { $0.x }.reduce(0, +) / Double(positions.count)
        let avgY = positions.map { $0.y }.reduce(0, +) / Double(positions.count)
        let positionVariance = positions.reduce(0) {
            $0 + pow($1.x - avgX, 2) + pow($1.y - avgY, 2)
        } / Double(positions.count)
        
        let timeVariance = timestamps.reduce(0) {
            let mean = timestamps.reduce(0, +) / Double(timestamps.count)
            return $0 + pow($1 - mean, 2)
        } / Double(timestamps.count)
        
        let combinedScore = 1 / (1 + (positionVariance * 0.7 + timeVariance * 0.3))
        return min(max(combinedScore, 0), 1)
    }
    
    func getCurrentSpeaker(at time: Double) -> CombinedAnalysisResult.MatchedSpeaker? {
        for speaker in analysisResult.matchedSpeakers {
            for segment in speaker.segments {
                if Double(segment.start) <= time && time <= Double(segment.end) {
                    return speaker
                }
            }
        }
        return nil
    }
    
        func updateCurrentSpeakers(at time: Double) {
        DispatchQueue.main.async {
            for i in 0..<self.analysisResult.matchedSpeakers.count {
                self.analysisResult.matchedSpeakers[i].isCurrentlySpeaking = false
            }
            
            for i in 0..<self.analysisResult.matchedSpeakers.count {
                let speaker = self.analysisResult.matchedSpeakers[i]
                for segment in speaker.segments {
                    if Double(segment.start) <= time && time <= Double(segment.end) {
                        self.analysisResult.matchedSpeakers[i].isCurrentlySpeaking = true
                        break
                    }
                }
            }
            // This ensures that the View refreshed whenever we call this function
            self.objectWillChange.send()
        }
    }
}
