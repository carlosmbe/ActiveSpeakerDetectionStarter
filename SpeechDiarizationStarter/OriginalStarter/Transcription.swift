//
//  Transcription.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 11/05/2025.
//



import Speech

//Struct for the results of our transciption
struct RecognizedUtterance {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

class Transcriber: ObservableObject {
    
    //Create an instance of the Speech Recognizer. If you're using a lanaguage other than english, you'd intialize it here.
    //You can also write a clever algorithm for automatic detection or allow users to pick their own language
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    // Results for speech recognition data
    var recognizedUtterances: [RecognizedUtterance] = []
    
    
    //We call this function to perform the actual transcription
    func performSpeechRecognition(audioURL: URL?) async throws -> [RecognizedUtterance] {
            guard let audioURL = audioURL else {
                throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio URL not available"])
            }
            
            guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
                throw NSError(domain: "SpeechRecognition", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available"])
            }
            
            return try await withCheckedThrowingContinuation { continuation in
                
                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                request.taskHint = .dictation
                request.shouldReportPartialResults = false
                
                let recognitionTask: SFSpeechRecognitionTask? = speechRecognizer.recognitionTask(with: request) { [self] result, error in
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
                    
                            print(utterance)
                            recognizedUtterances.append(utterance)
                        }
                        continuation.resume(returning: recognizedUtterances)
                      
                    }
                }
            }
        }
    }
