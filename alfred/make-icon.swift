#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Generates the Alfred workflow icon. Kept as code rather than a committed
// binary so the mark can be adjusted — colour, weight, proportion — without
// anyone having to open a drawing tool or find the original file.
//
//   swift make-icon.swift workflow/icon.png
//
// Alfred renders this at roughly 40pt in the results list, so the whole design
// is one heavy stroke plus one block: a prompt chevron and a cursor. No thin
// lines and no detail that dies below 64px. It says "drive this from the
// keyboard", which is what nimbus is for.

let S = 512
let ink = CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
let paper = CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
let accent = CGColor(red: 0.29, green: 0.85, blue: 0.71, alpha: 1)

let ctx = CGContext(
    data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Rounded-square tile, matching the corner radius macOS uses for app icons.
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                   cornerWidth: 114, cornerHeight: 114, transform: nil))
ctx.clip()
ctx.setFillColor(ink)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// Prompt chevron.
let chevron = CGMutablePath()
chevron.move(to: CGPoint(x: 128, y: 344))
chevron.addLine(to: CGPoint(x: 232, y: 250))
chevron.addLine(to: CGPoint(x: 128, y: 156))
ctx.addPath(chevron)
ctx.setStrokeColor(paper)
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// Cursor, sitting on the chevron's baseline.
ctx.addPath(CGPath(roundedRect: CGRect(x: 274, y: 134, width: 118, height: 44),
                   cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.setFillColor(accent)
ctx.fillPath()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(S)x\(S))")
