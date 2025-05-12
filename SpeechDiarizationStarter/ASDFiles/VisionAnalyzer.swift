//
//  VisionAnalyzer.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 12/05/2025.
//


import AVFoundation
import Vision

class VisionAnalyzer: ObservableObject {
    private let videoURL: URL
    private var videoAsset: AVAsset
    private var videoTrack: AVAssetTrack?
     let sequenceRequestHandler = VNSequenceRequestHandler()
    
    private var faceTrackingHistory: [UUID: [FaceProfile.TimeRange]] = [:]
    @Published var faceProfiles: [FaceProfile] = []
    
    init(videoURL: URL) {
        self.videoURL = videoURL
        self.videoAsset = AVAsset(url: videoURL)
        
        Task {
            let tracks = try await videoAsset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                self.videoTrack = track
            }
        }
    }
    
    func detectAndTrackFaces() async throws -> [FaceProfile] {
        let generator = AVAssetImageGenerator(asset: videoAsset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        
        let duration = try await videoAsset.load(.duration)
        let nominalFrameRate = try await videoTrack?.load(.nominalFrameRate) ?? 30.0
        let frameCount = Int(duration.seconds * Double(nominalFrameRate))
        let samplingInterval = max(frameCount / 300, 1)
        
        var activeFaceTracks: [UUID: (lastBox: CGRect, lastTime: Double, avgPosition: CGPoint)] = [:]
        var faceTemporalData: [UUID: (history: [Double], sum: Double)] = [:]
        var faceTrackingHistory: [UUID: [FaceProfile.TimeRange]] = [:]
        
        for frameIdx in stride(from: 0, to: frameCount, by: samplingInterval) {
            let time = CMTime(seconds: Double(frameIdx) / Double(nominalFrameRate), preferredTimescale: 600)
            
            guard let cgImage = try await getVideoFrame(at: time) else {
                continue
            }
            
            let faceRequest = VNDetectFaceLandmarksRequest()
            faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
            
            //The simulator can not use the Nerual Engine, so adding this line allows me to debug without a real device
            #if targetEnvironment(simulator)
            if #available(iOS 17.0, *) {
                if let cpuDevice = MLComputeDevice.allComputeDevices.first(where: { $0.description.contains("MLCPUComputeDevice") }) {
                    faceRequest.setComputeDevice(.some(cpuDevice), for: .main)
                }
            } else {
                faceRequest.usesCPUOnly = true
            }
            #endif
            
            try sequenceRequestHandler.perform([faceRequest], on: cgImage)
            
            guard let observations = faceRequest.results as? [VNFaceObservation] else {
                continue
            }
            
            for observation in observations {
                let boundingBox = observation.boundingBox
                let timestamp = time.seconds
                
                var mouthOpenness: Double = 0.0
                if let innerLips = observation.landmarks?.innerLips,
                   let outerLips = observation.landmarks?.outerLips {
                    
                    let innerPoints = innerLips.normalizedPoints
                    let outerPoints = outerLips.normalizedPoints
                    
                    let innerVertical = (innerPoints.max(by: { $0.y < $1.y })?.y ?? 0) -
                                       (innerPoints.min(by: { $0.y < $1.y })?.y ?? 0)
                    let outerVertical = (outerPoints.max(by: { $0.y < $1.y })?.y ?? 0) -
                                       (outerPoints.min(by: { $0.y < $1.y })?.y ?? 0)
                    
                    mouthOpenness = Double(max(innerVertical, outerVertical) * boundingBox.height)
                }
                
                let faceCenter = CGPoint(
                    x: boundingBox.midX,
                    y: boundingBox.midY
                )
                
                var matchedTrackID: UUID?
                for (trackID, trackInfo) in activeFaceTracks {
                    let distance = sqrt(pow(faceCenter.x - trackInfo.avgPosition.x, 2) +
                                   pow(faceCenter.y - trackInfo.avgPosition.y, 2))
                    
                    if (distance < 0.15) && ((timestamp - trackInfo.lastTime) < 1.0) {
                        matchedTrackID = trackID
                        
                        let newAvgPos = CGPoint(
                            x: (trackInfo.avgPosition.x * 0.7 + faceCenter.x * 0.3),
                            y: (trackInfo.avgPosition.y * 0.7 + faceCenter.y * 0.3)
                        )
                        
                        activeFaceTracks[trackID] = (boundingBox, timestamp, newAvgPos)
                        break
                    }
                }
                
                let trackID = matchedTrackID ?? UUID()
                if matchedTrackID == nil {
                    activeFaceTracks[trackID] = (boundingBox, timestamp, faceCenter)
                }
                
                var trackData = faceTemporalData[trackID] ?? (history: [], sum: 0.0)
                trackData.history.append(mouthOpenness)
                trackData.sum += mouthOpenness
                faceTemporalData[trackID] = trackData
                
                let avgOpenness = trackData.history.isEmpty ? 0.0 :
                                trackData.sum / Double(trackData.history.count)
                let isSpeaking = mouthOpenness > max(0.05, avgOpenness * 1.5)
                
                let timeRange = FaceProfile.TimeRange(
                    timestamp: timestamp,
                    boundingBox: boundingBox,
                    isSpeaking: isSpeaking,
                    mouthOpenness: mouthOpenness
                )
                
                if faceTrackingHistory[trackID] == nil {
                    faceTrackingHistory[trackID] = []
                }
                faceTrackingHistory[trackID]?.append(timeRange)
            }
            
            let currentTime = time.seconds
            activeFaceTracks = activeFaceTracks.filter {
                currentTime - $0.value.lastTime <= 1.0
            }
        }
        
        var faceProfiles: [FaceProfile] = []
        for (trackID, timeRanges) in faceTrackingHistory {
            guard timeRanges.count >= 10 else {
                continue
            }
            
            let avgX = timeRanges.map { $0.boundingBox.midX }.reduce(0, +) / Double(timeRanges.count)
            let avgY = timeRanges.map { $0.boundingBox.midY }.reduce(0, +) / Double(timeRanges.count)
            
            let totalMouthOpenness = timeRanges.reduce(0.0) { $0 + $1.mouthOpenness }
            let avgMouthOpenness = totalMouthOpenness / Double(timeRanges.count)
            let speakingCount = timeRanges.filter { $0.isSpeaking }.count
            
            let profile = FaceProfile(
                trackID: trackID,
                timeRanges: timeRanges,
                avgPosition: CGPoint(x: avgX, y: avgY),
                mouthOpennessHistory: timeRanges.map { $0.mouthOpenness },
                avgMouthOpenness: avgMouthOpenness
            )
            
            faceProfiles.append(profile)
        }
        
        return faceProfiles.sorted { $0.avgPosition.x < $1.avgPosition.x }
    }

     func getVideoFrame(at time: CMTime) async throws -> CGImage? {
        let generator = AVAssetImageGenerator(asset: videoAsset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) {
                requestedTime, image, actualTime, result, error in
                
                switch result {
                case .succeeded where image != nil:
                    continuation.resume(returning: image)
                case .failed where error != nil:
                    continuation.resume(throwing: error!)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
