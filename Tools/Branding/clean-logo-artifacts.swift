import AppKit
import Foundation

struct Options {
    let input: URL
    let output: URL
}

enum CleanupError: Error, CustomStringConvertible {
    case usage
    case unreadableImage
    case unsupportedBitmap
    case unableToEncode
    case unableToWrite(URL)

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift clean-logo-artifacts.swift --input <PNG> --output <PNG>"
        case .unreadableImage:
            return "Could not decode the input PNG."
        case .unsupportedBitmap:
            return "Expected a non-planar, 8-bit RGBA bitmap."
        case .unableToEncode:
            return "Could not encode the cleaned PNG."
        case let .unableToWrite(url):
            return "Could not write PNG: \(url.path)"
        }
    }
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var values: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let key = arguments[index]
        guard index + 1 < arguments.count, key == "--input" || key == "--output" else {
            throw CleanupError.usage
        }
        values[key] = arguments[index + 1]
        index += 2
    }

    guard let input = values["--input"], let output = values["--output"] else {
        throw CleanupError.usage
    }
    return Options(input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output))
}

struct BitmapLayout {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytesPerPixel: Int
    let alphaOffset: Int
    let colorOffset: Int

    init(bitmap: NSBitmapImageRep) {
        width = bitmap.pixelsWide
        height = bitmap.pixelsHigh
        bytesPerRow = bitmap.bytesPerRow
        bytesPerPixel = bitmap.bitsPerPixel / 8
        let alphaFirst = bitmap.bitmapFormat.contains(.alphaFirst)
        alphaOffset = alphaFirst ? 0 : bytesPerPixel - 1
        colorOffset = alphaFirst ? 1 : 0
    }

    func alphaIndex(for pixel: Int) -> Int {
        let pixelX = pixel % width
        let pixelY = pixel / width
        return pixelY * bytesPerRow + pixelX * bytesPerPixel + alphaOffset
    }

    func colorOffset(for pixel: Int) -> Int {
        let pixelX = pixel % width
        let pixelY = pixel / width
        return pixelY * bytesPerRow + pixelX * bytesPerPixel + colorOffset
    }

    func isPerimeter(_ pixel: Int) -> Bool {
        let pixelX = pixel % width
        let pixelY = pixel / width
        return pixelX < width / 10 || pixelX >= width * 9 / 10
            || pixelY < height / 10 || pixelY >= height * 9 / 10
    }
}

struct ComponentScan {
    let visited: [UInt8]
    let largest: [Int]
}

func scanComponents(
    pixels: UnsafeMutablePointer<UInt8>,
    layout: BitmapLayout
) -> ComponentScan {
    let pixelCount = layout.width * layout.height
    var visited = [UInt8](repeating: 0, count: pixelCount)
    var largest: [Int] = []

    for start in 0..<pixelCount {
        guard pixels[layout.alphaIndex(for: start)] > 0, visited[start] == 0 else { continue }
        var component = [start]
        var cursor = 0
        visited[start] = 1

        while cursor < component.count {
            let current = component[cursor]
            let pixelX = current % layout.width
            let pixelY = current / layout.width
            cursor += 1
            let neighbors = [
                pixelX > 0 ? current - 1 : -1,
                pixelX + 1 < layout.width ? current + 1 : -1,
                pixelY > 0 ? current - layout.width : -1,
                pixelY + 1 < layout.height ? current + layout.width : -1
            ]

            for neighbor in neighbors where neighbor >= 0 && visited[neighbor] == 0 {
                guard pixels[layout.alphaIndex(for: neighbor)] > 0 else { continue }
                visited[neighbor] = 1
                component.append(neighbor)
            }
        }

        if component.count > largest.count {
            largest = component
        }
    }

    return ComponentScan(visited: visited, largest: largest)
}

func hasStrongPerimeterColor(
    pixel: Int,
    pixels: UnsafeMutablePointer<UInt8>,
    layout: BitmapLayout
) -> Bool {
    guard layout.isPerimeter(pixel) else { return false }
    let offset = layout.colorOffset(for: pixel)
    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    return max(red, max(green, blue)) - min(red, min(green, blue)) > 80
}

func cleanup(_ options: Options) throws -> Int {
    guard let data = try? Data(contentsOf: options.input),
          let bitmap = NSBitmapImageRep(data: data) else {
        throw CleanupError.unreadableImage
    }
    guard bitmap.bitsPerPixel == 32,
          bitmap.samplesPerPixel == 4,
          !bitmap.isPlanar,
          let pixels = bitmap.bitmapData else {
        throw CleanupError.unsupportedBitmap
    }

    let layout = BitmapLayout(bitmap: bitmap)
    let scan = scanComponents(pixels: pixels, layout: layout)
    guard !scan.largest.isEmpty else { throw CleanupError.unreadableImage }
    var keep = [UInt8](repeating: 0, count: layout.width * layout.height)
    for pixel in scan.largest {
        keep[pixel] = 1
    }

    let removedPixels = removeArtifacts(pixels: pixels, layout: layout, scan: scan, keep: keep)
    try writePNG(bitmap, to: options.output)
    return removedPixels
}

func removeArtifacts(
    pixels: UnsafeMutablePointer<UInt8>,
    layout: BitmapLayout,
    scan: ComponentScan,
    keep: [UInt8]
) -> Int {
    var removedPixels = 0
    for pixel in scan.visited.indices where scan.visited[pixel] > 0 {
        let isDetached = keep[pixel] == 0
        guard isDetached || hasStrongPerimeterColor(pixel: pixel, pixels: pixels, layout: layout) else {
            continue
        }
        pixels[layout.alphaIndex(for: pixel)] = 0
        removedPixels += 1
    }
    return removedPixels
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let cleanedData = bitmap.representation(using: .png, properties: [:]) else {
        throw CleanupError.unableToEncode
    }
    do {
        try cleanedData.write(to: url, options: .atomic)
    } catch {
        throw CleanupError.unableToWrite(url)
    }
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let removedPixels = try cleanup(options)
    print("Removed \(removedPixels) peripheral artifact pixels from \(options.input.lastPathComponent)")
    print("Wrote \(options.output.path)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
