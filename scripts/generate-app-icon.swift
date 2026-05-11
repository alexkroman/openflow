#!/usr/bin/env swift
// Generates OpenFlow's AppIcon asset catalog from the SF Symbol `mic.fill`.
// Run: swift scripts/generate-app-icon.swift
//
// Renders a 1024x1024 master (slate-blue squircle + white mic), then sips it
// down into every slot required by macOS' AppIcon.appiconset.

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()
let catalog = repoRoot.appendingPathComponent("App/OpenFlow/OpenFlow/Assets.xcassets")
let appIconSet = catalog.appendingPathComponent("AppIcon.appiconset")

if FileManager.default.fileExists(atPath: appIconSet.path) {
  try FileManager.default.removeItem(at: appIconSet)
}
try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

func renderMaster(size: CGFloat) -> Data {
  let pixelSize = NSSize(width: size, height: size)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 32
  )!
  rep.size = pixelSize

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  // Apple's macOS Big Sur icon grid: a ~824/1024 squircle centered in the
  // canvas with ~100pt of transparent margin per side. Dock + Finder size
  // every app to that template, so a full-bleed squircle looks oversized
  // and a small inner subject looks shrunken next to other apps.
  let squircleSize = size * (824.0 / 1024.0)
  let inset = (size - squircleSize) / 2
  let squircleRect = NSRect(x: inset, y: inset, width: squircleSize, height: squircleSize)
  let radius = squircleSize * 0.2237

  NSGraphicsContext.current?.saveGraphicsState()
  let bgPath = NSBezierPath(roundedRect: squircleRect, xRadius: radius, yRadius: radius)
  bgPath.addClip()

  let top = NSColor(srgbRed: 0.42, green: 0.51, blue: 0.66, alpha: 1)
  let bottom = NSColor(srgbRed: 0.18, green: 0.23, blue: 0.32, alpha: 1)
  let gradient = NSGradient(starting: top, ending: bottom)!
  gradient.draw(in: squircleRect, angle: -90)

  // White `mic.fill` sized to ~58% of the squircle (not the canvas).
  let symbolConfig = NSImage.SymbolConfiguration(pointSize: squircleSize * 0.58, weight: .medium)
    .applying(.init(paletteColors: [.white]))
  let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "OpenFlow")!
    .withSymbolConfiguration(symbolConfig)!
  let symSize = symbol.size
  let origin = NSPoint(
    x: (size - symSize.width) / 2,
    y: (size - symSize.height) / 2
  )
  symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.current?.restoreGraphicsState()

  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let masterURL = URL(fileURLWithPath: NSTemporaryDirectory())
  .appendingPathComponent("openflow-icon-\(UUID().uuidString).png")
try renderMaster(size: 1024).write(to: masterURL)
defer { try? FileManager.default.removeItem(at: masterURL) }

struct Slot { let pixels: Int; let filename: String; let logical: Int; let scale: String }
let slots: [Slot] = [
  .init(pixels: 16, filename: "icon_16.png", logical: 16, scale: "1x"),
  .init(pixels: 32, filename: "icon_16@2x.png", logical: 16, scale: "2x"),
  .init(pixels: 32, filename: "icon_32.png", logical: 32, scale: "1x"),
  .init(pixels: 64, filename: "icon_32@2x.png", logical: 32, scale: "2x"),
  .init(pixels: 128, filename: "icon_128.png", logical: 128, scale: "1x"),
  .init(pixels: 256, filename: "icon_128@2x.png", logical: 128, scale: "2x"),
  .init(pixels: 256, filename: "icon_256.png", logical: 256, scale: "1x"),
  .init(pixels: 512, filename: "icon_256@2x.png", logical: 256, scale: "2x"),
  .init(pixels: 512, filename: "icon_512.png", logical: 512, scale: "1x"),
  .init(pixels: 1024, filename: "icon_512@2x.png", logical: 512, scale: "2x"),
]

for slot in slots {
  let dest = appIconSet.appendingPathComponent(slot.filename)
  if slot.pixels == 1024 {
    try FileManager.default.copyItem(at: masterURL, to: dest)
  } else {
    let task = Process()
    task.launchPath = "/usr/bin/sips"
    task.arguments = ["-z", "\(slot.pixels)", "\(slot.pixels)", masterURL.path, "--out", dest.path]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("sips failed for \(slot.filename)") }
  }
}

let contents: [String: Any] = [
  "info": ["version": 1, "author": "xcode"],
  "images": slots.map { slot -> [String: String] in
    [
      "size": "\(slot.logical)x\(slot.logical)",
      "idiom": "mac",
      "filename": slot.filename,
      "scale": slot.scale,
    ]
  },
]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  .write(to: appIconSet.appendingPathComponent("Contents.json"))

try JSONSerialization.data(
  withJSONObject: ["info": ["version": 1, "author": "xcode"]],
  options: [.prettyPrinted, .sortedKeys]
).write(to: catalog.appendingPathComponent("Contents.json"))

print("Wrote \(slots.count) icons → \(appIconSet.path)")
