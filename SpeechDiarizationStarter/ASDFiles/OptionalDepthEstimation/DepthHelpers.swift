//
//  DepthHelpers.swift
//  SpeechDiarizationStarter
//
//  Created by Carlos Mbendera on 17/05/2025.
//

import CoreML
import UIKit

struct ImageProcessor {
    static func loadImageAsPixelBuffer(from url: URL) -> CVPixelBuffer? {
        guard let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        
        let size = CGSize(width: 1536, height: 1536)
        let scale = image.scale
        let orientation = image.imageOrientation
        
        // Resize the image to 1536x1536
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = resizedImage?.cgImage else {
            return nil
        }
        
        // Convert the CGImage to a CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                               width: Int(size.width),
                               height: Int(size.height),
                               bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        
        return buffer
    }
    
    static func depthMapToImage(depthMap: MLMultiArray) -> UIImage? {
        let width = depthMap.shape[2].intValue
        let height = depthMap.shape[3].intValue
        
        // Create a CGContext to draw the depth map
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        // Normalize depth values and map them to grayscale intensities
        let depthValues = depthMap.dataPointer.bindMemory(to: Float16.self, capacity: width * height)
        var maxDepth: Float16 = 0
        for i in 0..<width * height {
            if depthValues[i] > maxDepth {
                maxDepth = depthValues[i]
            }
        }
        
        let grayValues = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        defer { grayValues.deallocate() }
        
        for i in 0..<width * height {
            let normalizedDepth = depthValues[i] / maxDepth
            grayValues[i] = UInt8(normalizedDepth * 255)
        }
        
        // Draw the grayscale values into the context
        context.data?.copyMemory(from: grayValues, byteCount: width * height)
        
        // Create a CGImage from the context
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        // Convert CGImage to UIImage
        return UIImage(cgImage: cgImage)
    }
}

struct DepthCalculator {
    static func getDepthForBox(_ box: DepthBox, depthMap: MLMultiArray) -> Float {
        // Convert normalized bounding box to image coordinates (1536x1536)
        let imageWidth: CGFloat = 1536
        let imageHeight: CGFloat = 1536
        
        let boundingBoxInImageCoordinates = CGRect(
            x: box.boundingBox.origin.x * imageWidth,
            y: box.boundingBox.origin.y * imageHeight,
            width: box.boundingBox.width * imageWidth,
            height: box.boundingBox.height * imageHeight
        )
        
        return getDepthFor(boundingBoxInImageCoordinates, depthMap: depthMap)
    }
    
    static func getDepthFor(_ boundingBox: CGRect, depthMap: MLMultiArray) -> Float {
        let width = depthMap.shape[2].intValue
        let height = depthMap.shape[3].intValue
        
        // Convert bounding box coordinates to depth map coordinates
        let scaleX = CGFloat(width) / 1536.0
        let scaleY = CGFloat(height) / 1536.0
        
        let x = Int(boundingBox.origin.x * scaleX)
        let y = Int(boundingBox.origin.y * scaleY)
        let boxWidth = Int(boundingBox.width * scaleX)
        let boxHeight = Int(boundingBox.height * scaleY)
        
        // Ensure the bounding box is within the depth map bounds
        let xStart = max(0, x)
        let yStart = max(0, y)
        let xEnd = min(x + boxWidth, width)
        let yEnd = min(y + boxHeight, height)
        
        // Access the depth values from the MLMultiArray
        let depthValues = depthMap.dataPointer.bindMemory(to: Float16.self, capacity: width * height)
        
        // Collect depth values within the bounding box
        var depths: [Float] = []
        for row in yStart..<yEnd {
            for col in xStart..<xEnd {
                let index = row * width + col
                if index >= 0 && index < width * height {
                    depths.append(Float(depthValues[index]))
                }
            }
        }
        
        // Calculate the average depth value
        return depths.isEmpty ? 0 : depths.reduce(0, +) / Float(depths.count)
    }
}
