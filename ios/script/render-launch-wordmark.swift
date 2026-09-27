// Renders LaunchWordmark.imageset from the same BrandWordmarkArt the app draws.
//
// UILaunchScreen centers this image in the safe area. AccountEntryLayout
// derives the artwork offset from the same padding and button metrics used
// by Welcome. Static launch art targets the default content size; Dynamic
// Type can enlarge the live wordmark and actions after launch.
//
// Run from ios/ after changing the wordmark, the theme colors, or the Welcome
// layout:
//
//   swiftc -parse-as-library -o /tmp/render-launch-wordmark \
//     script/render-launch-wordmark.swift \
//     OrganizedGlitter/Authentication/BrandWordmarkArt.swift \
//   && /tmp/render-launch-wordmark

import AppKit
import SwiftUI

@main
@MainActor
enum RenderLaunchWordmark {
  static let output = URL(
    fileURLWithPath: "OrganizedGlitter/Resources/Assets.xcassets/LaunchWordmark.imageset")

  static func main() throws {
    let font = URL(fileURLWithPath: "OrganizedGlitter/Resources/Fonts/Caveat.ttf")
    guard CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil) else {
      fatalError("Run from ios/: could not register \(font.path)")
    }

    let appearances: [(name: String, foreground: Color, primary: Color, accent: Color)] = [
      ("light", rgb(0x46323E), rgb(0xD23C77), rgb(0x8535D4)),
      ("dark", rgb(0xF7F2F7), rgb(0xF58AB5), rgb(0xCAA4F9)),
    ]
    for appearance in appearances {
      let art = BrandWordmarkArt(
        size: AccountEntryLayout.welcomeWordmarkSize,
        foreground: appearance.foreground,
        primary: appearance.primary,
        accent: appearance.accent,
        sparkles: .still
      )
      .offset(y: AccountEntryLayout.launchWordmarkOffset)
      .frame(
        width: AccountEntryLayout.launchCanvas.width,
        height: AccountEntryLayout.launchCanvas.height
      )

      for scale in [2, 3] {
        let renderer = ImageRenderer(content: art)
        renderer.scale = CGFloat(scale)
        guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { fatalError("Could not render \(appearance.name) @\(scale)x") }
        try png.write(to: output.appending(path: "wordmark-\(appearance.name)@\(scale)x.png"))
      }
    }
  }

  static func rgb(_ hex: UInt32) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
