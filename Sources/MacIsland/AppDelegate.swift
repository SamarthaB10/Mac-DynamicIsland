import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
  var closeIsland: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { closeIsland?() }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
  var dragState: ((Bool) -> Void)?
  var dropFiles: (([URL]) -> Void)?

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard !(sender.draggingSource is TrayFileIconView),
      sender.draggingPasteboard.canReadObject(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    else { return [] }
    dragState?(true)
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    sender.draggingSource is TrayFileIconView ? [] : .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) { dragState?(false) }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard !(sender.draggingSource is TrayFileIconView) else { return false }
    let files = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    dragState?(false)
    guard !files.isEmpty else { return false }
    dropFiles?(files)
    return true
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = IslandModel()
  private var driveWindow: NSWindow?
  private var driveController: GoogleDriveController?
  private var lockScreen: LockScreenController!
  private var panel: IslandPanel!
  private var statusItem: NSStatusItem!
  private var subscriptions = Set<AnyCancellable>()
  private var hovering = false
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var visibilityTask: Task<Void, Never>?
  private var horizontalScroll: CGFloat = 0
  private var gestureHandled = false
  private var dragOrigin: NSPoint?
  private var externalFileDrag = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureEditMenu()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "capsule.fill", accessibilityDescription: "Mac Island")
    panel = IslandPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isFloatingPanel = true
    panel.acceptsMouseMovedEvents = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    model.islandWindow = panel
    panel.closeIsland = { [weak self] in self?.model.collapse(force: true) }
    let hostingView = IslandHostingView(rootView: IslandView(model: model).preferredColorScheme(.dark))
    hostingView.registerForDraggedTypes([.fileURL])
    hostingView.dragState = { [weak self] targeted in
      self?.model.setDropTarget(targeted)
    }
    hostingView.dropFiles = { [weak self] in self?.model.addFiles($0) }
    hostingView.sizingOptions = []
    panel.contentView = hostingView
    model.updateInteraction = { [weak self] in
      guard let self else { return }
      self.visibilityTask?.cancel()
      if self.model.visible && self.screen != nil {
        self.panel.orderFrontRegardless()
      } else {
        self.visibilityTask = Task { [weak self] in
          try? await Task.sleep(for: .milliseconds(220))
          guard !Task.isCancelled, let self, !self.model.visible else { return }
          self.panel.orderOut(nil)
        }
      }
      self.updatePointer()
      if !self.model.expanded { self.panel.resignKey() }
    }
    model.openGoogleDrive = { [weak self] in self?.showGoogleDrive() }
    model.openForKeyboard = { [weak self] in self?.openIsland() }
    NotificationCenter.default.addObserver(
      self, selector: #selector(displaysChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(displaysChanged), name: NSWorkspace.didWakeNotification, object: nil
    )
    model.$pinned.combineLatest(model.$visible).sink { [weak self] _ in
      DispatchQueue.main.async { self?.updateMenu() }
    }.store(in: &subscriptions)
    let events: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel,
      .swipe,
    ]
    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
      MainActor.assumeIsolated { self?.handleMouse(event) }
    }
    localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
      MainActor.assumeIsolated { self?.handleMouse(event) }
      return event
    }
    lockScreen = LockScreenController(media: model.media)
    layout()
    updateMenu()
    if model.visible && screen != nil { panel.orderFrontRegardless() }
    model.media.refreshRunningPlayer()
    model.weather.refreshIfNeeded()
  }

  private func configureEditMenu() {
    let main = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu()
    applicationMenu.addItem(item("Open Island", action: #selector(openIsland), key: "o"))
    applicationMenu.addItem(item("Keep Island Open", action: #selector(togglePin), key: "p"))
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(item("Quit Mac Island", action: #selector(quit), key: "q"))
    applicationItem.submenu = applicationMenu
    main.addItem(applicationItem)
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
    ] {
      if action == "paste:" {
        edit.addItem(item(title, action: #selector(pasteIntoHub), key: key))
      } else {
        edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
      }
    }
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
  }

  @objc private func pasteIntoHub(_ sender: Any?) {
    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
      editor.paste(sender)
    } else if !model.pasteText() {
      NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.saveText()
    if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
  }

  private var screen: NSScreen? {
    NSScreen.screens.first { id(for: $0).map { CGDisplayIsBuiltin($0) != 0 } ?? false }
  }

  private func id(for screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  private func layout() {
    guard let screen else {
      panel.orderOut(nil)
      return
    }
    model.notchHeight = screen.safeAreaInsets.top
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      model.notchWidth = max(0, right.minX - left.maxX)
    } else {
      model.notchWidth = 0
    }
    let size = model.canvasSize
    let islandTop = screen.frame.maxY
    let centerX =
      screen.auxiliaryTopLeftArea.flatMap { left in
        screen.auxiliaryTopRightArea.map { right in (left.maxX + right.minX) / 2 }
      } ?? screen.frame.midX
    panel.setFrame(
      NSRect(
        x: centerX - size.width / 2,
        y: islandTop + IslandModel.canvasInset - size.height,
        width: size.width, height: size.height), display: true)
    updatePointer()
    if model.visible { panel.orderFrontRegardless() }
  }

  private var islandFrame: NSRect {
    let size = model.panelSize
    return NSRect(
      x: panel.frame.midX - size.width / 2,
      y: panel.frame.maxY - IslandModel.canvasInset - size.height,
      width: size.width, height: size.height)
  }

  // The transparent animation canvas must not block the apps behind it.
  private func updatePointer() {
    guard model.visible, screen != nil else {
      panel.ignoresMouseEvents = true
      hovering = false
      return
    }
    let inside = islandFrame.contains(NSEvent.mouseLocation)
    let acceptsPointer = inside || (externalFileDrag && NSEvent.pressedMouseButtons & 1 != 0)
    if panel.ignoresMouseEvents != !acceptsPointer { panel.ignoresMouseEvents = !acceptsPointer }
    let notchWidth = model.compactSize.width
    let notchTrigger = NSRect(
      x: panel.frame.midX - notchWidth / 2,
      y: islandFrame.maxY, width: notchWidth,
      height: max(0, (screen?.frame.maxY ?? islandFrame.maxY) - islandFrame.maxY))
    let nextHover = inside || notchTrigger.contains(NSEvent.mouseLocation)
    if nextHover != hovering {
      hovering = nextHover
      model.hover(nextHover)
    }
  }

  private func handleMouse(_ event: NSEvent) {
    if event.type == .leftMouseDragged, !model.draggingFile {
      externalFileDrag = NSPasteboard(name: .drag).canReadObject(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    } else if event.type == .leftMouseUp { externalFileDrag = false }
    if handleSwipe(event) { return }
    updatePointer()
    if event.type == .leftMouseDown || event.type == .rightMouseDown {
      if !islandFrame.contains(NSEvent.mouseLocation), !model.isChoosingFiles {
        model.collapse()
      }
    }
  }

  // A hidden island still accepts a restore gesture over the notch, without blocking other apps.
  private func handleSwipe(_ event: NSEvent) -> Bool {
    let size = model.visible ? model.panelSize : model.compactSize
    let region = NSRect(
      x: panel.frame.midX - size.width / 2,
      y: panel.frame.maxY - IslandModel.canvasInset - size.height,
      width: size.width, height: size.height)
    let nearIsland = region.contains(NSEvent.mouseLocation)
    if event.type == .leftMouseDown {
      dragOrigin = nearIsland && (!model.expanded || !model.visible) ? NSEvent.mouseLocation : nil
    } else if event.type == .leftMouseUp {
      dragOrigin = nil
    } else if event.type == .leftMouseDragged, let origin = dragOrigin {
      let delta = NSEvent.mouseLocation.x - origin.x
      if abs(delta) > 60, abs(NSEvent.mouseLocation.y - origin.y) < 35 {
        if (delta > 0 && model.visible) || (delta < 0 && !model.visible) {
          dragOrigin = nil
          model.setVisible(delta < 0)
          return true
        }
      }
    }
    guard event.type == .scrollWheel || event.type == .swipe else { return false }
    if event.phase == .began || event.phase == .mayBegin {
      horizontalScroll = 0
      gestureHandled = false
    }
    if event.phase == .ended || event.phase == .cancelled {
      horizontalScroll = 0
      gestureHandled = false
      return false
    }
    guard nearIsland, !gestureHandled, event.momentumPhase == [] else { return false }
    let delta = event.type == .swipe ? event.deltaX * 60 : event.scrollingDeltaX
    let vertical = event.type == .swipe ? event.deltaY * 60 : event.scrollingDeltaY
    guard abs(delta) > abs(vertical) else { return false }
    horizontalScroll += delta * (event.isDirectionInvertedFromDevice ? 1 : -1)
    if horizontalScroll > 45 && model.visible {
      gestureHandled = true
      model.setVisible(false)
      return true
    }
    if horizontalScroll < -45 && !model.visible {
      gestureHandled = true
      model.setVisible(true)
      return true
    }
    return false
  }

  private func updateMenu() {
    let menu = NSMenu()
    let visibility = item("Show Island", action: #selector(toggleVisibility), key: "")
    visibility.state = model.visible ? .on : .off
    menu.addItem(visibility)
    menu.addItem(item("Open Island", action: #selector(openIsland), key: "o"))
    menu.addItem(item("Collapse Island", action: #selector(collapseIsland), key: ""))
    let pin = item("Keep Island Open", action: #selector(togglePin), key: "p")
    pin.state = model.pinned ? .on : .off
    menu.addItem(pin)
    menu.addItem(item("Add Files…", action: #selector(addFiles), key: ""))
    menu.addItem(item("Google Drive…", action: #selector(showGoogleDrive), key: ""))
    menu.addItem(.separator())
    let lock = item("Show Player on Lock Screen", action: #selector(toggleLockScreen), key: "")
    lock.state = lockScreen?.enabled == true ? .on : .off
    menu.addItem(lock)
    menu.addItem(item("Preview Lock-Screen Player", action: #selector(previewLockScreen), key: ""))
    menu.addItem(.separator())
    menu.addItem(item("Quit Mac Island", action: #selector(quit), key: "q"))
    statusItem.menu = menu
  }

  private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  @objc private func displaysChanged() {
    model.audio.refresh()
    layout()
    updateMenu()
  }
  @objc private func openIsland() {
    guard screen != nil else { return }
    model.setVisible(true)
    model.expand()
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func toggleVisibility() {
    model.setVisible(!model.visible)
    updateMenu()
  }
  @objc private func collapseIsland() { model.collapse(force: true) }
  @objc private func togglePin() {
    model.togglePin()
    if model.pinned { openIsland() }
  }
  @objc private func addFiles() {
    openIsland()
    model.chooseFiles()
  }
  @objc private func showGoogleDrive() {
    model.collapse(force: true)
    if driveWindow == nil {
      let drive = driveController ?? GoogleDriveController()
      drive.receivedFile = { [weak self] url in self?.model.addFiles([url]) }
      driveController = drive
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = "Google Drive — Mac Island"
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: GoogleDriveView(drive: drive, model: model))
      window.center()
      driveWindow = window
    }
    driveWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func toggleLockScreen() {
    lockScreen.enabled.toggle()
    if !lockScreen.enabled { lockScreen.hide() }
    updateMenu()
  }
  @objc private func previewLockScreen() { lockScreen.show(locked: false) }
  @objc private func quit() { NSApp.terminate(nil) }
}
