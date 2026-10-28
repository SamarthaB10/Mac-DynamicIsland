import SwiftUI

// Show press feedback on this button, without dimming the other controls.
struct IslandIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.55 : 1)
  }
}
