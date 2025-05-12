//
//  SpeechAnalyzer.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 12/05/2025.
//


import AVFoundation
import Speech

class SpeechAnalyzer: ObservableObject {
    @Published var isAudioReady = false
    @Published var recognizedUtterances: [RecognizedUtterance] = []
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioURL: URL?
    private let sdViewModel = SDViewModel()
    
    struct RecognizedUtterance {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }
    
    func prepareAudio(sourceURL: URL) {
        Task {
            do {
                let convertedAudioURL = try await convertMediaToMonoFloat32WAV(inputURL: sourceURL)
                
                DispatchQueue.main.async {
                    self.audioURL = convertedAudioURL
                    self.isAudioReady = true
                }
            } catch {
                print("Error converting audio: \(error)")
            }
        }
    }
    
    func performSpeechRecognition() async throws -> [RecognizedUtterance] {
        guard let audioURL = self.audioURL else {
            throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio URL not available"])
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.taskHint = .dictation
            request.shouldReportPartialResults = false
            
            var utterances: [RecognizedUtterance] = []
            
            let recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else {
                    continuation.resume(returning: [])
                    return
                }
                
                if result.isFinal {
                    let segments = result.bestTranscription.segments
                    for segment in segments {
                        let utterance = RecognizedUtterance(
                            text: segment.substring,
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration
                        )
                        utterances.append(utterance)
                    }
                    
                    continuation.resume(returning: utterances)
                }
            }
        }
    }
    
    func performSpeakerDiarization() async -> [SpeakerProfile] {
        guard let audioURL = self.audioURL else { return [] }
        
        let speakerCount = 2
        let segments = await sdViewModel.runDiarization(
            waveFileName: "",
            numSpeakers: speakerCount,
            fullPath: audioURL
        )
        
        var speakerMap: [Int: [SpeakerProfile.TimeSegment]] = [:]
        
        for segment in segments {
            let timeSegment = SpeakerProfile.TimeSegment(start: segment.start, end: segment.end)
            if speakerMap[segment.speaker] == nil {
                speakerMap[segment.speaker] = []
            }
            speakerMap[segment.speaker]?.append(timeSegment)
        }
        
        var speakerProfiles: [SpeakerProfile] = []
        for (speakerID, segments) in speakerMap {
            let profile = SpeakerProfile(
                speakerID: speakerID,
                faceID: nil,
                segments: segments,
                embedding: nil
            )
            speakerProfiles.append(profile)
        }
        
        return speakerProfiles
    }
    
    func matchUtterancesToSpeakers(
        utterances: [RecognizedUtterance],
        speakerProfiles: [SpeakerProfile]
    ) -> [(utterance: RecognizedUtterance, speakerID: Int)] {
        var matchedUtterances: [(utterance: RecognizedUtterance, speakerID: Int)] = []
        
        for utterance in utterances {
            if utterance.endTime - utterance.startTime < 0.5 {
                continue
            }
            
            var bestSpeakerID = -1
            var longestOverlap: Float = 0
            
            for speaker in speakerProfiles {
                var totalOverlap: Float = 0
                
                for segment in speaker.segments {
                    let overlapStart = max(Float(utterance.startTime), segment.start)
                    let overlapEnd = min(Float(utterance.endTime), segment.end)
                    
                    if overlapEnd > overlapStart {
                        totalOverlap += overlapEnd - overlapStart
                    }
                }
                
                if totalOverlap > longestOverlap {
                    longestOverlap = totalOverlap
                    bestSpeakerID = speaker.speakerID
                }
            }
            
            if bestSpeakerID >= 0 && longestOverlap > 0 {
                matchedUtterances.append((utterance, bestSpeakerID))
            }
        }
        
        return matchedUtterances
    }
}
