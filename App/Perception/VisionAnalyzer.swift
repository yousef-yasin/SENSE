import ImageIO
import SenseCore
import UIKit
import Vision

struct VisionResult: Sendable {
    var text: String
    var labels: [ImageLabel]
}

struct VisionAnalyzer: Sendable {
    var minimumLabelConfidence: Float = 0.3
    var maximumLabels = 5

    func analyze(_ image: UIImage) async throws -> VisionResult {
        guard let cgImage = image.cgImage else { throw SenseError.imageUnreadable }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let minimumConfidence = minimumLabelConfidence
        let limit = maximumLabels

        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.automaticallyDetectsLanguage = true

            let classifyRequest = VNClassifyImageRequest()

            try handler.perform([textRequest])
            try? handler.perform([classifyRequest])

            let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let labels = (classifyRequest.results ?? [])
                .filter { $0.confidence >= minimumConfidence }
                .prefix(limit)
                .map { ImageLabel(identifier: $0.identifier, confidence: Double($0.confidence)) }

            return VisionResult(text: lines.joined(separator: "\n"), labels: Array(labels))
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
