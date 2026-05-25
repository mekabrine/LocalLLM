import Foundation
import CoreGraphics
import CoreImage
import CoreML
import UIKit

struct GeneratedImageResult: Sendable {
    let fileURL: URL
    let prompt: String
    let sizeDescription: String
}

enum CoreMLImageGenerationBackend {
    static func generate(
        prompt: String,
        modelURL: URL,
        size: ImageGenerationSize,
        quality: ImageGenerationQuality
    ) async throws -> GeneratedImageResult {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else {
            throw NSError(domain: "LocalLLM.ImageGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a prompt before generating an image."])
        }

        guard supportsModel(at: modelURL) else {
            throw NSError(domain: "LocalLLM.ImageGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Local image generation needs a Core ML image model folder or compiled model (.mlpackage or .mlmodelc). GGUF text models cannot render images."])
        }

        return try await Task.detached(priority: .userInitiated) {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            let dimensions = dimensions(for: size)
            let input = try inputProvider(for: model, prompt: cleanPrompt, dimensions: dimensions, quality: quality)
            let output = try model.prediction(from: input)
            let image = try image(from: output)
            let fileURL = try save(image: image, prompt: cleanPrompt)
            return GeneratedImageResult(fileURL: fileURL, prompt: cleanPrompt, sizeDescription: "\(dimensions.width) × \(dimensions.height)")
        }.value
    }

    static func supportsModel(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "mlmodelc" || ext == "mlpackage" { return true }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let modelFile = url.appendingPathComponent("Manifest.json")
            let compiledFile = url.appendingPathComponent("model.mil")
            return FileManager.default.fileExists(atPath: modelFile.path) || FileManager.default.fileExists(atPath: compiledFile.path) || ext.isEmpty
        }
        return false
    }

    private static func inputProvider(
        for model: MLModel,
        prompt: String,
        dimensions: (width: Int, height: Int),
        quality: ImageGenerationQuality
    ) throws -> MLDictionaryFeatureProvider {
        var values: [String: MLFeatureValue] = [:]
        var didSetPrompt = false

        for (name, description) in model.modelDescription.inputDescriptionsByName {
            switch description.type {
            case .string:
                values[name] = MLFeatureValue(string: prompt)
                didSetPrompt = true
            case .int64:
                values[name] = MLFeatureValue(int64: int64Value(for: name, dimensions: dimensions, quality: quality))
            case .double:
                values[name] = MLFeatureValue(double: doubleValue(for: name, quality: quality))
            default:
                throw NSError(domain: "LocalLLM.ImageGeneration", code: 3, userInfo: [NSLocalizedDescriptionKey: "This Core ML image model asks for unsupported input '\(name)'. LocalLLM supports prompt-string image models with optional numeric width, height, seed, step, and guidance inputs."])
            }
        }

        guard didSetPrompt else {
            throw NSError(domain: "LocalLLM.ImageGeneration", code: 4, userInfo: [NSLocalizedDescriptionKey: "This Core ML model does not expose a text prompt input, so LocalLLM cannot use it for text-to-image generation."])
        }

        return try MLDictionaryFeatureProvider(dictionary: values)
    }

    private static func int64Value(for name: String, dimensions: (width: Int, height: Int), quality: ImageGenerationQuality) -> Int64 {
        let lower = name.lowercased()
        if lower.contains("width") { return Int64(dimensions.width) }
        if lower.contains("height") { return Int64(dimensions.height) }
        if lower.contains("step") || lower.contains("iteration") { return Int64(stepCount(for: quality)) }
        if lower.contains("seed") { return Int64(Date().timeIntervalSince1970) }
        return 0
    }

    private static func doubleValue(for name: String, quality: ImageGenerationQuality) -> Double {
        let lower = name.lowercased()
        if lower.contains("guidance") || lower.contains("scale") { return quality == .fast ? 5.0 : quality == .balanced ? 7.5 : 9.0 }
        if lower.contains("strength") { return 1.0 }
        return 0.0
    }

    private static func stepCount(for quality: ImageGenerationQuality) -> Int {
        switch quality {
        case .fast: return 12
        case .balanced: return 20
        case .high: return 28
        }
    }

    private static func dimensions(for size: ImageGenerationSize) -> (width: Int, height: Int) {
        switch size {
        case .square512: return (512, 512)
        case .square768: return (768, 768)
        case .portrait: return (512, 768)
        case .landscape: return (768, 512)
        }
    }

    private static func image(from output: MLFeatureProvider) throws -> UIImage {
        for name in output.featureNames {
            guard let value = output.featureValue(for: name) else { continue }
            if let buffer = value.imageBufferValue {
                let ciImage = CIImage(cvPixelBuffer: buffer)
                let context = CIContext(options: nil)
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { continue }
                return UIImage(cgImage: cgImage)
            }
            if let multiArray = value.multiArrayValue, let image = image(from: multiArray) {
                return image
            }
        }

        throw NSError(domain: "LocalLLM.ImageGeneration", code: 5, userInfo: [NSLocalizedDescriptionKey: "The image model ran, but it did not return a pixel buffer or image-shaped tensor."])
    }

    private static func image(from array: MLMultiArray) -> UIImage? {
        let shape = array.shape.map { $0.intValue }
        let height: Int
        let width: Int
        let channelFirst: Bool
        let batchOffset: [NSNumber]

        if shape.count == 4, shape[1] == 3 {
            height = shape[2]
            width = shape[3]
            channelFirst = true
            batchOffset = [0]
        } else if shape.count == 4, shape[3] == 3 {
            height = shape[1]
            width = shape[2]
            channelFirst = false
            batchOffset = [0]
        } else if shape.count == 3, shape[0] == 3 {
            height = shape[1]
            width = shape[2]
            channelFirst = true
            batchOffset = []
        } else if shape.count == 3, shape[2] == 3 {
            height = shape[0]
            width = shape[1]
            channelFirst = false
            batchOffset = []
        } else {
            return nil
        }

        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                for c in 0..<3 {
                    let indexes: [NSNumber]
                    if channelFirst {
                        indexes = batchOffset + [NSNumber(value: c), NSNumber(value: y), NSNumber(value: x)]
                    } else {
                        indexes = batchOffset + [NSNumber(value: y), NSNumber(value: x), NSNumber(value: c)]
                    }
                    bytes[pixelIndex + c] = byteValue(array[indexes].doubleValue)
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func byteValue(_ value: Double) -> UInt8 {
        let scaled: Double
        if value < 0 {
            scaled = ((value + 1.0) * 0.5) * 255.0
        } else if value <= 1.0 {
            scaled = value * 255.0
        } else {
            scaled = value
        }
        return UInt8(max(0, min(255, Int(scaled.rounded()))))
    }

    private static func save(image: UIImage, prompt: String) throws -> URL {
        guard let data = image.pngData() else {
            throw NSError(domain: "LocalLLM.ImageGeneration", code: 6, userInfo: [NSLocalizedDescriptionKey: "Generated image could not be encoded as PNG."])
        }
        let folder = try generatedImagesDirectory()
        let fileName = "LocalLLM-\(Int(Date().timeIntervalSince1970))-\(safeFileName(prompt)).png"
        let url = folder.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func generatedImagesDirectory() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "LocalLLM.ImageGeneration", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not find the app Documents folder."])
        }
        let folder = documents.appendingPathComponent("Generated Images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func safeFileName(_ prompt: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = prompt.prefix(32).map { character -> Character in
            String(character).rangeOfCharacter(from: allowed) == nil ? "-" : character
        }
        let result = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "image" : result
    }
}
