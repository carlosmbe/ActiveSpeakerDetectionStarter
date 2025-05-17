//
//  RealTimeFaces.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 16/05/2025.
//

import SwiftUI
import AVFoundation
import Vision

class RealTimeVideoAnalyzer: ObservableObject {
//Note that this function is only for visualization purposes and is different from the main algorithm
    
    @Published var faceBoxes: [FaceBox] = []

    private let playerItem: AVPlayerItem
    private let videoOutput: AVPlayerItemVideoOutput
    private var displayLink: CADisplayLink?

    private let lipMovementThreshold: CGFloat = 1 //MARK: You Can and Should Change this for your own testing values. Otherwise,its always green
    
    private let sequenceRequestHandler = VNSequenceRequestHandler()

    init(playerItem: AVPlayerItem) {
        self.playerItem = playerItem

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(outputSettings: settings)
        playerItem.add(videoOutput)
    }

    deinit {
        stopDisplayLink()
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
      //  print("Face Tracking On")
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
      //  print("Face Tracking Off")
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let currentItemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        guard currentItemTime.isValid else { return }

        guard videoOutput.hasNewPixelBuffer(forItemTime: currentItemTime),
              let pixelBuffer = videoOutput.copyPixelBuffer(
                forItemTime: currentItemTime,
                itemTimeForDisplay: nil
              )
        else {
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
     
        // Create the Face Landmarks request
        let faceRequest = VNDetectFaceLandmarksRequest { [weak self] req, err in
            guard let self = self else { return }

            guard let results = req.results as? [VNFaceObservation], !results.isEmpty else {
            //    print("No faces found in this frame.")
                DispatchQueue.main.async {
                    self.faceBoxes = []
                }
                return
            }

           // print("Found \(results.count) face(s) in this frame.")

            var newFaceBoxes = [FaceBox]()
            for obs in results {
                var lipDistance: CGFloat = 0
                if let outerLips = obs.landmarks?.outerLips {
                    lipDistance = self.computeLipDistance(
                        outerLips: outerLips,
                        in: obs.boundingBox,
                        pixelBuffer: pixelBuffer
                    )
                }

                let isSpeaker = (lipDistance > self.lipMovementThreshold)
                newFaceBoxes.append(FaceBox(boundingBox: obs.boundingBox, isSpeaker: isSpeaker))
            }

            DispatchQueue.main.async {
                self.faceBoxes = newFaceBoxes
            }
        }

        do {
            try sequenceRequestHandler.perform([faceRequest], on: pixelBuffer)
        } catch {
            print("Vision error: \(error)")
        }
    }

    private func computeLipDistance(outerLips: VNFaceLandmarkRegion2D,
                                    in boundingBox: CGRect,
                                    pixelBuffer: CVPixelBuffer) -> CGFloat {

        let yValues = outerLips.normalizedPoints.map { $0.y }
        guard let minY = yValues.min(), let maxY = yValues.max() else { return 0 }

        let pixelBufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let distance = (maxY - minY) * boundingBox.height * pixelBufferHeight
        return distance
    }
}
