#!/usr/bin/env swift
// make_icon.swift — wrap a full-bleed square source into Apple's macOS app-icon
// grid: on a 1024 canvas, an 824×824 body (≈100px clear margin), continuous
// ("squircle") corners at 185.4px. This is the defined macOS spec, not a choice.
//
//   swift scripts/make_icon.swift <src.png> <dst.png>

import SwiftUI

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    guard args.count >= 3, let src = NSImage(contentsOfFile: args[1]) else {
        FileHandle.standardError.write(Data("usage: make_icon.swift <src> <dst>\n".utf8))
        exit(2)
    }
    let canvas: CGFloat = 1024
    let body: CGFloat = 824
    let corner: CGFloat = 185.4

    let content = ZStack {
        Color.clear
        Image(nsImage: src)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: body, height: body)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
    .frame(width: canvas, height: canvas)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 1.0
    renderer.isOpaque = false

    guard let img = renderer.nsImage,
        let tiff = img.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: args[2]))
        print("wrote \(args[2]) — Apple grid: 1024 canvas, 824 body, 185.4px continuous")
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}
