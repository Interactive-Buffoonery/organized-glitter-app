import CoreText
import SwiftUI
import Testing
import UIKit

@testable import OrganizedGlitter

@MainActor
struct KarlaTypographyTests {
  @Test
  func bundledVariableFontRegistersItsWeights() throws {
    let fonts = try #require(Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
    #expect(fonts.contains("Karla.ttf"))
    for name in ["Karla-Regular", "Karla-Regular_Medium", "Karla-Regular_SemiBold", "Karla-Regular_Bold"] {
      let font = try #require(UIFont(name: name, size: 17))
      #expect(font.familyName == "Karla")
    }
  }

  @Test
  func semanticStylesKeepTheirNativeBaseSizes() {
    let styles: [(Font.TextStyle, CGFloat)] = [
      (.largeTitle, 34), (.title, 28), (.title2, 22), (.title3, 20),
      (.headline, 17), (.body, 17), (.callout, 16), (.subheadline, 15),
      (.footnote, 13), (.caption, 12), (.caption2, 11),
    ]
    for (style, size) in styles {
      #expect(KarlaTypography.style(style).size == size)
    }
    #expect(KarlaTypography.style(.headline).weight == .semibold)
    #expect(KarlaTypography.style(.body).weight == .regular)
  }

  @Test
  func caveatNavigationTitlesIncludeTheirFinalStroke() {
    UINavigationBar.applyCaveatLargeTitles()
    let appearance = UINavigationBar.appearance().standardAppearance
    let attributes = appearance.largeTitleTextAttributes
    for title in ["Home", "Library", "Account"] {
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: title, attributes: attributes))
      let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
      let strokes = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
      #expect(strokes.maxX <= advance)
    }
    #expect(appearance.titleTextAttributes[.kern] == nil)
  }

  @Test
  func nativeTextScalesThroughAccessibilitySizes() {
    for style in [UIFont.TextStyle.body, .headline, .caption1] {
      let standard = KarlaTypography.nativeFont(
        size: 17, relativeTo: style,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
      let enlarged = KarlaTypography.nativeFont(
        size: 17, relativeTo: style,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
      #expect(standard.familyName == "Karla")
      #expect(enlarged.familyName == "Karla")
      #expect(enlarged.pointSize > standard.pointSize)
    }
  }
}
