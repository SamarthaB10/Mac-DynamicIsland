import AppKit
import SwiftUI

// A plain, transparent editor that grows to six lines, then scrolls.
struct HubTextInput: NSViewRepresentable {
  @Binding var text: String
  @Binding var height: CGFloat
  let save: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = InputScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let editor = PasteTextView()
    editor.isRichText = false
    editor.importsGraphics = false
    editor.drawsBackground = false
    editor.textColor = .white
    editor.insertionPointColor = .white
    editor.selectedTextAttributes = [
      .backgroundColor: NSColor.white.withAlphaComponent(0.3), .foregroundColor: NSColor.white,
    ]
    editor.font = .systemFont(ofSize: 12)
    editor.textContainerInset = NSSize(width: 0, height: 6)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.delegate = context.coordinator
    editor.didPaste = { [weak coordinator = context.coordinator] in coordinator?.parent.save() }
    editor.unregisterDraggedTypes()
    editor.setAccessibilityLabel("Text to save")
    scroll.documentView = editor
    scroll.didLayout = { [weak coordinator = context.coordinator] in coordinator?.measure(editor) }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let editor = scroll.documentView as? NSTextView else { return }
    if editor.string != text { editor.string = text }
    context.coordinator.measure(editor)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: HubTextInput
    init(_ parent: HubTextInput) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let editor = notification.object as? NSTextView else { return }
      parent.text = editor.string
      measure(editor)
    }

    func measure(_ editor: NSTextView) {
      guard let container = editor.textContainer, let layout = editor.layoutManager else { return }
      layout.ensureLayout(for: container)
      let height = min(104, max(36, ceil(layout.usedRect(for: container).height) + 12))
      guard height != parent.height else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.parent.height != height else { return }
        self.parent.height = height
      }
    }
  }
}

private final class PasteTextView: NSTextView {
  var didPaste: (() -> Void)?

  override func mouseDown(with event: NSEvent) {
    window?.makeKey()
    NSApp.activate(ignoringOtherApps: true)
    super.mouseDown(with: event)
  }

  override func paste(_ sender: Any?) {
    super.pasteAsPlainText(sender)
    didPaste?()
  }

  override func pasteAsPlainText(_ sender: Any?) {
    super.pasteAsPlainText(sender)
    didPaste?()
  }
}

private final class InputScrollView: NSScrollView {
  var didLayout: (() -> Void)?
  override func layout() {
    super.layout()
    didLayout?()
  }
}
