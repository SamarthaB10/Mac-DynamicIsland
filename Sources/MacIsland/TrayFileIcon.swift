import AppKit
import SwiftUI

struct TrayFileIcon: NSViewRepresentable {
  let url: URL
  let reveal: () -> Void
  let began: () -> Void
  let ended: (Bool) -> Void
  let writer: () -> NSPasteboardWriting

  func makeNSView(context: Context) -> TrayFileIconView { TrayFileIconView() }

  func updateNSView(_ view: TrayFileIconView, context: Context) {
    view.url = url
    view.image = NSWorkspace.shared.icon(forFile: url.path)
    view.imageScaling = .scaleProportionallyUpOrDown
    view.reveal = reveal
    view.began = began
    view.ended = ended
    view.writer = writer
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.button)
    view.setAccessibilityLabel("Show \(url.lastPathComponent) in Finder")
    view.setAccessibilityHelp("Drag to another app to take this file out of the Hub.")
  }
}

final class TrayFileIconView: NSImageView, NSDraggingSource {
  var url: URL?
  var reveal: (() -> Void)?
  var began: (() -> Void)?
  var ended: ((Bool) -> Void)?
  var writer: (() -> NSPasteboardWriting)?
  private var mouseOrigin: NSPoint?
  private var dragging = false
  private var sourceFrame = NSRect.zero

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    mouseOrigin = event.locationInWindow
    dragging = false
    window?.makeFirstResponder(self)
  }

  override func mouseDragged(with event: NSEvent) {
    guard !dragging, let mouseOrigin, let url,
      hypot(event.locationInWindow.x - mouseOrigin.x, event.locationInWindow.y - mouseOrigin.y) >= 4
    else { return }
    dragging = true
    sourceFrame = window?.frame ?? .zero
    began?()
    let item = NSDraggingItem(pasteboardWriter: writer?() ?? url as NSURL)
    item.setDraggingFrame(bounds, contents: image)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    if !dragging && bounds.contains(convert(event.locationInWindow, from: nil)) { reveal?() }
    mouseOrigin = nil
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation { .copy }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    mouseOrigin = nil
    // A canceled drag or a drop back on the island keeps the tray entry.
    ended?(!operation.isEmpty && !sourceFrame.contains(screenPoint))
    dragging = false
  }

  override func accessibilityPerformPress() -> Bool {
    reveal?()
    return true
  }

  override func keyDown(with event: NSEvent) {
    if [36, 49, 76].contains(event.keyCode) { reveal?() } else { super.keyDown(with: event) }
  }
}
