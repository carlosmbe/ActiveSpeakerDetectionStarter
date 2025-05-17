//
//  DepthTestView.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 17/05/2025.
//

import SwiftUI

@available(iOS 18.0, *)
struct DepthTestView: View {
    @StateObject private var viewModel = DepthViewModel()
    
    var body: some View {
        VStack {
            if viewModel.modelRunning {
                ProgressView()
                    .padding()
                Text("Processing depth map...")
            } else if let depthImage = viewModel.depthImage {
                depthMapView(depthImage: depthImage)
            } else {
                Button("Generate Depth Map") {
                    viewModel.generateDepthMap()
                }
                .padding()
            }
        }
    }
    
    private func depthMapView(depthImage: UIImage) -> some View {
        VStack {
            // Toggle button to switch between original and depth image
            Button(viewModel.showingOriginalImage ? "Show Depth Map" : "Show Original Image") {
                viewModel.showingOriginalImage.toggle()
            }
            .padding()
            
            ZStack {
                // Show either the original image or the depth map
                if viewModel.showingOriginalImage, let originalImage = UIImage(contentsOfFile: viewModel.mediaURL.path) {
                    Image(uiImage: originalImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(uiImage: depthImage)
                        .resizable()
                        .scaledToFit()
                }
                
                // Overlay face bounding boxes with depth
                GeometryReader { proxy in
                    ForEach(viewModel.faceBoxes) { faceBox in
                        let rect = convertNormalizedRect(faceBox.boundingBox, in: proxy.size)
                        
                        Rectangle()
                            .stroke(Color.green, lineWidth: 3)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        
                        // Display depth value near the box
                        Text(String(format: "%.2f m", faceBox.depth))
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .padding(4)
                            .position(x: rect.midX, y: rect.minY - 20)
                    }
                }
            }
            
            HStack {
                Button("Find Faces") {
                    viewModel.generateDepthMap()
                }
                
                Button("Random Box") {
                    viewModel.createRandomBox()
                }
            }
            .padding()
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
