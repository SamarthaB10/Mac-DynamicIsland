import AppKit
import QuickLookUI

@MainActor
final class HubFilePreview {
  private var window: NSWindow?
  private var previewView: QLPreviewView?

  func show(_ url: URL) {
    if window == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let preview = QLPreviewView(frame: window.contentView!.bounds, style: .normal)!
      preview.autoresizingMask = [.width, .height]
      preview.autostarts = true
      window.contentView = preview
      window.center()
      self.window = window
      previewView = preview
    }
    previewView?.previewItem = url as NSURL
    window?.title = url.lastPathComponent
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func close(_ url: URL) {
    guard previewView?.previewItem?.previewItemURL == url else { return }
    previewView?.previewItem = nil
    window?.close()
  }
}
