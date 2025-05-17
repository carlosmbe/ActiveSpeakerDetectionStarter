//
//  AnalyzerWithFaces.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 16/05/2025.
//

import SwiftUI
import AVKit

struct FacesCombinedAnalysisView: View {
    
    @StateObject private var realTimeAnalyzer: RealTimeVideoAnalyzer
    
    @StateObject private var coordinator: CombinedAnalysisCoordinator
    
    private let player: AVPlayer
    
    @State private var currentTime: Double = 0
    @State private var isProcessing: Bool = true
    
    init() {
        guard let url = Bundle.main.url(forResource: "Clip", withExtension: "mp4") else {
            fatalError("Video not found in bundle.")
        }
        
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        
        player.pause()
        
        let rtAnalyzer = RealTimeVideoAnalyzer(playerItem: playerItem)
        let coordinator = CombinedAnalysisCoordinator(videoURL: url)
        
        self.player = player
        self._realTimeAnalyzer = StateObject(wrappedValue: rtAnalyzer)
        self._coordinator = StateObject(wrappedValue: coordinator)
    }
    
    var body: some View {
        VStack {
            GeometryReader { proxy in
                ZStack {
                    
                    if !isProcessing {
                        VideoPlayer(player: player)
                            .clipped()
                            .zIndex(0)
                    
                    } else {
                        ProgressView()
                    }
                    
                    FaceBoundingBoxView(faceBoxes: realTimeAnalyzer.faceBoxes)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .zIndex(1)
                }
            }
            .ignoresSafeArea()
            
            // Speaker information
            if !coordinator.analysisResult.preprocessingComplete {
                Text(isProcessing ? "Processing Video / Audio..." : "Ready For Playback")
                    .padding()
            } else {
                if let currentSpeaker = coordinator.analysisResult
                    .matchedSpeakers
                    .first(where: { $0.isCurrentlySpeaking }) {
                    VStack(alignment: .leading) {
                        
                        Text("Current Speaker: \(currentSpeaker.speakerID)")
                            .font(.headline)
                        if let position = currentSpeaker.position {
                            Text("Position: (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)))")
                            Text("Audio Position: \(String(format: "%.2f", (position.x - 0.5) * 10)), \(String(format: "%.2f", (0.5 - position.y) * 10)), 0")
                                .font(.caption)
                        } else {
                            Text("Position: Unknown")
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            
            
        }
        .onAppear {
            // Start preprocessing
            Task {
                await coordinator.preprocessVideoAndAudio()
                // Print for debugging
                isProcessing = false
                print("Preprocessing complete. Matched speakers: \(coordinator.analysisResult.matchedSpeakers.count)")
            }
            
            // Time observer to update current speaker
            let interval = CMTime(seconds: 0.01, preferredTimescale: 600)
            player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                let currentTime = time.seconds
                self.currentTime = currentTime
                
                // Update current speakers and their positions
                coordinator.updateCurrentSpeakers(at: currentTime)
            }
            
            NotificationCenter.default.addObserver(
                  forName: .AVPlayerItemDidPlayToEndTime,
                  object: player.currentItem,
                  queue: .main // Perform updates on the main queue
            ) { _ in
                // Playback has finished
                realTimeAnalyzer.stopDisplayLink()
            }
        }
        .onChange(of: player.timeControlStatus){ _ in
            //Listen for changes in play/pause status of the video as we don't want the Display Link to run for every frame whilst the video is paused
            if player.timeControlStatus == .paused {
                realTimeAnalyzer.stopDisplayLink()
            }else if player.timeControlStatus == .playing{
                realTimeAnalyzer.startDisplayLink()
            }
            
        }
        .navigationTitle("Carlos' Active Speaker Detection Article ")
    }
    
}
