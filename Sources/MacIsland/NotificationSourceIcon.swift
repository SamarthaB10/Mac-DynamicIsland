import AppKit
import SwiftUI

struct NotificationSourceIcon: View {
  let source: NotificationSource
  let size: CGFloat

  private var image: NSImage? {
    Bundle.main.url(forResource: source.rawValue, withExtension: "png", subdirectory: "NotificationIcons")
      .flatMap { NSImage(contentsOf: $0) }
  }

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFit()
          .padding(source == .gmail ? size * 0.14 : 0)
      } else {
        Image(systemName: source.symbol).font(.system(size: size * 0.5, weight: .semibold))
      }
    }
    .frame(width: size, height: size)
    .background(source == .gmail ? Color.white : (source == .youtube ? Color.red : Color.black),
      in: RoundedRectangle(cornerRadius: size * 0.2))
    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    .accessibilityHidden(true)
  }
}
