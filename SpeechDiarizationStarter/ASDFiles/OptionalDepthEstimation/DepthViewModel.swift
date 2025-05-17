//
//  DepthViewModel.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 17/05/2025.
//

import UIKit
import CoreML
import Vision

@available(iOS 18.0,*)
class DepthViewModel: ObservableObject {
    @Published var mediaURL: URL = Bundle.main.url(forResource: "Photo", withExtension: "jpeg")!
    //TODO: Add Image Picker if photo is nil
    @Published var modelRunning = false
    @Published var depthImage: UIImage? = nil
    @Published var depthMapArray: MLMultiArray? = nil
    @Published var faceBoxes: [DepthBox] = []
    @Published var showingOriginalImage = false
    
    private let modelQueue = DispatchQueue(label: "com.carlosmbe.SpeechDiarizationStarter.DepthModelQueue", qos: .userInitiated)
    private let faceDetectionQueue = DispatchQueue(label: "com.carlosmbe.SpeechDiarizationStarter.faceDetection", qos: .userInitiated)
    
    func generateDepthMap() {
        modelRunning = true
        modelQueue.async {
            self.processDepthMap()
        }
    }
    
    private func processDepthMap() {
        do {
            let config = MLModelConfiguration()
            let model = try DepthPro(configuration: config)
            
            if let image = ImageProcessor.loadImageAsPixelBuffer(from: self.mediaURL) {
                let originalWidth = try MLMultiArray(shape: [1, 1, 1, 1], dataType: .float16)
                originalWidth[0] = NSNumber(value: Float(1536))
                
                let input = DepthProInput(image: image, originalWidth: originalWidth)
                let prediction = try model.prediction(input: input)
                let depthMap = prediction.depthMeters
                
                // Process face detection and depth calculation
                self.processFaceDetection(with: image, depthMap: depthMap)
                
                if let depthImageRaw = ImageProcessor.depthMapToImage(depthMap: depthMap) {
                    DispatchQueue.main.async {
                        self.depthMapArray = depthMap
                        self.depthImage = depthImageRaw
                        self.modelRunning = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.modelRunning = false
                }
            }
        } catch {
            print("Error processing depth map: \(error)")
            DispatchQueue.main.async {
                self.modelRunning = false
            }
        }
    }
    
    private func processFaceDetection(with pixelBuffer: CVPixelBuffer, depthMap: MLMultiArray) {
        faceDetectionQueue.async {
            let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Face detection error: \(error)")
                    return
                }
                
                guard let results = request.results as? [VNFaceObservation] else {
                    DispatchQueue.main.async {
                        self.faceBoxes = []
                    }
                    return
                }
                
                var detectedFaces: [DepthBox] = []
                for observation in results {
                    let faceBox = DepthBox(boundingBox: observation.boundingBox)
                    let depth = DepthCalculator.getDepthForBox(faceBox, depthMap: depthMap)
                    detectedFaces.append(DepthBox(boundingBox: faceBox.boundingBox, depth: depth))
                }
                
                DispatchQueue.main.async {
                    self.faceBoxes = detectedFaces
                }
            }
            
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? requestHandler.perform([faceRequest])
        }
    }
    
    func createRandomBox() {
        guard let depthMap = depthMapArray else { return }
        let newBox = DepthBox(boundingBox: CGRect(
            x: CGFloat.random(in: 0.1...0.9),
            y: CGFloat.random(in: 0.1...0.9),
            width: 0.1,
            height: 0.1
        ))
        
        let depth = DepthCalculator.getDepthForBox(newBox, depthMap: depthMap)
        faceBoxes = [DepthBox(boundingBox: newBox.boundingBox, depth: depth)]
    }
}
