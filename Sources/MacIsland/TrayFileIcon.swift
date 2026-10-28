import AppKit
import SwiftUI

enum HubFileDragResult {
  case kept
  case discarded
  case delivered
}

struct TrayFileIcon: NSViewRepresentable {
  let url: URL
  let preview: () -> Void
  let began: () -> Void
  let ended: (HubFileDragResult) -> Void
  let writer: () -> NSPasteboardWriting
  let islandFrame: () -> NSRect
  let enabled: Bool

  func makeNSView(context: Context) -> TrayFileIconView { TrayFileIconView() }

  func updateNSView(_ view: TrayFileIconView, context: Context) {
    view.url = url
    view.icon.image = NSWorkspace.shared.icon(forFile: url.path)
    view.filename.stringValue = url.lastPathComponent
    view.preview = preview
    view.began = began
    view.ended = ended
    view.writer = writer
    view.islandFrame = islandFrame
    view.isEnabled = enabled
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.button)
    view.setAccessibilityLabel("Preview \(url.lastPathComponent)")
    view.setAccessibilityHelp("Drag outside the island to remove this file from the Hub.")
  }
}

final class TrayFileIconView: NSView, NSDraggingSource {
  let icon = NSImageView()
  let filename = NSTextField(labelWithString: "")
  var url: URL?
  var preview: (() -> Void)?
  var began: (() -> Void)?
  var ended: ((HubFileDragResult) -> Void)?
  var writer: (() -> NSPasteboardWriting)?
  var islandFrame: (() -> NSRect)?
  var isEnabled = true
  private var mouseOrigin: NSPoint?
  private var dragging = false
  private var sourceFrame = NSRect.zero
  private var canceled = false
  private var keyMonitor: Any?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    icon.imageScaling = .scaleProportionallyUpOrDown
    filename.font = .systemFont(ofSize: 10)
    filename.textColor = .white
    filename.lineBreakMode = .byTruncatingMiddle
    filename.alignment = .center
    addSubview(icon)
    addSubview(filename)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    icon.frame = NSRect(x: (bounds.width - 36) / 2, y: bounds.height - 36, width: 36, height: 36)
    filename.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 14)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(point) == nil ? nil : self
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    mouseOrigin = event.locationInWindow
    dragging = false
    window?.makeFirstResponder(self)
  }

  override func mouseDragged(with event: NSEvent) {
    guard isEnabled, !dragging, let mouseOrigin, let url,
      hypot(event.locationInWindow.x - mouseOrigin.x, event.locationInWindow.y - mouseOrigin.y) >= 4
    else { return }
    dragging = true
    canceled = false
    sourceFrame = islandFrame?() ?? window?.frame ?? .zero
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { self?.canceled = true }
      return event
    }
    began?()
    let item = NSDraggingItem(pasteboardWriter: writer?() ?? url as NSURL)
    item.setDraggingFrame(icon.frame, contents: icon.image)
    let session = beginDraggingSession(with: [item], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = false
  }

  override func mouseUp(with event: NSEvent) {
    guard isEnabled else { return }
    if !dragging && bounds.contains(convert(event.locationInWindow, from: nil)) { preview?() }
    mouseOrigin = nil
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation { .copy }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    mouseOrigin = nil
    let result: HubFileDragResult
    if canceled || sourceFrame.contains(screenPoint) { result = .kept }
    else { result = operation.isEmpty ? .discarded : .delivered }
    dragging = false
    ended?(result)
  }

  override func cancelOperation(_ sender: Any?) { canceled = true }

  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    preview?()
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard isEnabled else { return }
    if [36, 49, 76].contains(event.keyCode) { preview?() } else { super.keyDown(with: event) }
  }
}
