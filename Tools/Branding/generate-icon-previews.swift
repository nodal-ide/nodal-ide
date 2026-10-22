import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Options {
    let source: URL
    let output: URL
}

enum GeneratorError: Error, CustomStringConvertible {
    case usage
    case invalidSource(String)
    case unableToCreateImage
    case unableToCreateBitmap(size: Int)
    case unableToWrite(URL)

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift generate-icon-previews.swift --source <PNG> --output <directory>"
        case let .invalidSource(message):
            return "Invalid source image: \(message)"
        case .unableToCreateImage:
            return "Could not decode the source image."
        case let .unableToCreateBitmap(size):
            return "Could not create an sRGB bitmap at \(size)×\(size)."
        case let .unableToWrite(url):
            return "Could not write PNG: \(url.path)"
        }
    }
}

let families = ["stable", "alpha", "beta", "development", "pre-release", "finder-helper"]
let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

func parseOptions(_ arguments: [String]) throws -> Options {
    var sourcePath: String?
    var outputPath: String?
    var index = 0

    while index < arguments.count {
        let key = arguments[index]
        guard index + 1 < arguments.count else { throw GeneratorError.usage }
        let value = arguments[index + 1]

        switch key {
        case "--source": sourcePath = value
        case "--output": outputPath = value
        default: throw GeneratorError.usage
        }
        index += 2
    }

    guard let sourcePath, let outputPath else { throw GeneratorError.usage }
    return Options(source: URL(fileURLWithPath: sourcePath), output: URL(fileURLWithPath: outputPath))
}

func loadSource(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw GeneratorError.unableToCreateImage
    }
    guard image.width == image.height else {
        throw GeneratorError.invalidSource("expected a square image; got \(image.width)×\(image.height)")
    }
    guard image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast else {
        throw GeneratorError.invalidSource("expected an image with an alpha channel")
    }
    return image
}

func render(_ source: CGImage, size: Int) throws -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        .union(.byteOrder32Big)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw GeneratorError.unableToCreateBitmap(size: size)
    }

    context.interpolationQuality = .high
    context.setBlendMode(.copy)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = context.makeImage() else { throw GeneratorError.unableToCreateBitmap(size: size) }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw GeneratorError.unableToWrite(url)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw GeneratorError.unableToWrite(url) }
}

func previewCard(for family: String) -> String {
    let imageURL = "\(family)/512.png"
    return """
        <article>
          <h2>\(family)</h2>
          <div class="examples">
            <figure>
              <div class="surface light">
                <img src="\(imageURL)" alt="\(family) icon on light background">
              </div>
              <figcaption>Light · 128 px</figcaption>
            </figure>
            <figure>
              <div class="surface dark">
                <img src="\(imageURL)" alt="\(family) icon on dark background">
              </div>
              <figcaption>Dark · 128 px</figcaption>
            </figure>
            <figure>
              <div class="surface checker">
                <img src="\(imageURL)" alt="\(family) icon on transparency grid">
              </div>
              <figcaption>Transparency · 64 px</figcaption>
            </figure>
          </div>
        </article>
    """
}

func previewDocument(cards: String) -> String {
    """
    <!doctype html>
    <html lang="en">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Nodal icon previews</title>
    <style>
      :root { color-scheme: light dark; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
      body { margin: 24px; background: Canvas; color: CanvasText; }
      h1 { font-size: 22px; }
      article { padding: 16px 0; border-top: 1px solid #8886; }
      h2 { margin: 0 0 12px; text-transform: capitalize; font-size: 16px; }
      .examples { display: flex; flex-wrap: wrap; gap: 16px; }
      figure { margin: 0; text-align: center; }
      .surface { width: 160px; height: 160px; display: grid; place-items: center; border-radius: 10px; }
      .surface img { display: block; object-fit: contain; }
      .light { background: #f2f2f7; } .dark { background: #242428; }
      .light img, .dark img { width: 128px; height: 128px; }
      .checker {
        background-color: #fff;
        background-image:
          linear-gradient(45deg, #ddd 25%, transparent 25%),
          linear-gradient(-45deg, #ddd 25%, transparent 25%),
          linear-gradient(45deg, transparent 75%, #ddd 75%),
          linear-gradient(-45deg, transparent 75%, #ddd 75%);
        background-size: 16px 16px;
        background-position: 0 0, 0 8px, 8px -8px, -8px 0;
      }
      .checker img { width: 64px; height: 64px; }
      figcaption { margin-top: 6px; color: GrayText; }
      p { max-width: 800px; line-height: 1.5; }
    </style>
    <h1>Nodal icon previews</h1>
    <p>
      All channels currently use the same supplied artwork. No shipped asset catalogs are modified;
      channel-specific treatments remain subject to design review.
    </p>
    \(cards)
    </html>
    """
}

func writePreviewHTML(to url: URL) throws {
    let cards = families.map(previewCard).joined(separator: "\n")
    let html = previewDocument(cards: cards)
    do {
        try Data(html.utf8).write(to: url, options: .atomic)
    } catch {
        throw GeneratorError.unableToWrite(url)
    }
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let source = try loadSource(options.source)
    try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)

    for family in families {
        let directory = options.output.appendingPathComponent(family, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in pixelSizes {
            let image = try render(source, size: size)
            try writePNG(image, to: directory.appendingPathComponent("\(size).png"))
        }
    }
    try writePreviewHTML(to: options.output.appendingPathComponent("index.html"))
    print("Generated \(families.count * pixelSizes.count) PNG previews from \(options.source.path)")
    print("Preview: \(options.output.appendingPathComponent("index.html").path)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
