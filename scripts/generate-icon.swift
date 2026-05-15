#!/usr/bin/env swift
import AppKit
import Foundation

// Black background with a white mic.fill SF Symbol, inscribed in the macOS
// 1024×1024 template (824×824 live area, 100px margin) so the Dock's drop
// shadow and Tahoe's icon chrome have somewhere to live without overlapping
// the glyph.
let brandColor = NSColor.black
let liveAreaFraction: CGFloat = 824.0 / 1024.0
let cornerRadiusFraction: CGFloat = 0.225
let glyphFraction: CGFloat = 0.55

func renderIcon(size: CGFloat) -> NSImage {
  let intSize = Int(size)
  let bmp = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: intSize,
    pixelsHigh: intSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  bmp.size = NSSize(width: size, height: size)

  NSGraphicsContext.saveGraphicsState()
  let ctx = NSGraphicsContext(bitmapImageRep: bmp)!
  ctx.imageInterpolation = .high
  NSGraphicsContext.current = ctx

  let liveArea = size * liveAreaFraction
  let inset = (size - liveArea) / 2
  let rect = NSRect(x: inset, y: inset, width: liveArea, height: liveArea)
  let radius = liveArea * cornerRadiusFraction
  let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
  brandColor.setFill()
  path.fill()

  let glyphPointSize = liveArea * glyphFraction
  let config = NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold)
  guard
    let baseGlyph = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil),
    let glyph = baseGlyph.withSymbolConfiguration(config)
  else {
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: NSSize(width: size, height: size))
    img.addRepresentation(bmp)
    return img
  }
  let tinted = NSImage(size: glyph.size, flipped: false) { drawRect in
    glyph.draw(in: drawRect)
    NSColor.white.set()
    drawRect.fill(using: .sourceAtop)
    return true
  }
  let glyphRect = NSRect(
    x: (size - tinted.size.width) / 2,
    y: (size - tinted.size.height) / 2,
    width: tinted.size.width,
    height: tinted.size.height
  )
  tinted.draw(in: glyphRect)

  NSGraphicsContext.restoreGraphicsState()

  let canvas = NSImage(size: NSSize(width: size, height: size))
  canvas.addRepresentation(bmp)
  return canvas
}

func writePNG(_ image: NSImage, to url: URL) throws {
  let rep: NSBitmapImageRep
  if let bmp = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
    rep = bmp
  } else {
    guard
      let tiff = image.tiffRepresentation,
      let bmp2 = NSBitmapImageRep(data: tiff)
    else {
      throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    rep = bmp2
  }
  guard let png = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
  }
  try png.write(to: url)
}

guard CommandLine.arguments.count >= 2 else {
  FileHandle.standardError.write(Data("usage: generate-icon.swift <output-appiconset-dir>\n".utf8))
  exit(2)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: CGFloat)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024),
]

for entry in sizes {
  let image = renderIcon(size: entry.px)
  let url = outDir.appendingPathComponent(entry.name)
  try writePNG(image, to: url)
  print("wrote \(entry.name) (\(Int(entry.px))px)")
}

let contents: [String: Any] = [
  "images": [
    ["filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"],
    ["filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"],
    ["filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"],
    ["filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"],
    ["filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"],
    ["filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"],
    ["filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"],
    ["filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"],
    ["filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"],
    ["filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"],
  ],
  "info": ["author": "xcode", "version": 1],
]
var json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
json.append(contentsOf: "\n".utf8)
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote Contents.json")
