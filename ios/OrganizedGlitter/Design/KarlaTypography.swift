import SwiftUI
import UIKit

extension Font {
  static func karla(_ textStyle: Font.TextStyle = .body) -> Font {
    let style = KarlaTypography.style(textStyle)
    return .custom("Karla-Regular", size: style.size, relativeTo: textStyle)
      .weight(style.weight)
  }
}

enum KarlaTypography {
  static func style(_ textStyle: Font.TextStyle) -> (size: CGFloat, weight: Font.Weight) {
    switch textStyle {
    case .largeTitle: (34, .regular)
    case .title: (28, .regular)
    case .title2: (22, .regular)
    case .title3: (20, .regular)
    case .headline: (17, .semibold)
    case .body: (17, .regular)
    case .callout: (16, .regular)
    case .subheadline: (15, .regular)
    case .footnote: (13, .regular)
    case .caption: (12, .regular)
    case .caption2: (11, .regular)
    @unknown default: (17, .regular)
    }
  }

  static func nativeFont(
    size: CGFloat, relativeTo textStyle: UIFont.TextStyle,
    compatibleWith traits: UITraitCollection? = nil
  ) -> UIFont {
    let font = UIFont(name: "Karla-Regular", size: size) ?? .systemFont(ofSize: size)
    return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font, compatibleWith: traits)
  }

  @MainActor
  static func applyControlFonts() {
    UIBarButtonItem.appearance().setTitleTextAttributes(
      [.font: nativeFont(size: 17, relativeTo: .body)], for: .normal)
    UITabBarItem.appearance().setTitleTextAttributes(
      [.font: nativeFont(size: 10, relativeTo: .caption2)], for: .normal)
    UITabBarItem.appearance().setTitleTextAttributes(
      [.font: nativeFont(size: 10, relativeTo: .caption2)], for: .selected)
    UISegmentedControl.appearance().setTitleTextAttributes(
      [.font: nativeFont(size: 13, relativeTo: .footnote)], for: .normal)
  }
}
