import SwiftUI

enum HubSection: String, CaseIterable {
  case files = "Files"
  case savedText = "Saved Text"
}

struct HubView: View {
  @ObservedObject var model: IslandModel

  var body: some View {
    VStack(spacing: 12) {
      Picker("Hub view", selection: $model.hubView) {
        ForEach(HubSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).labelsHidden()
      if model.hubView == .files {
        HubFilesView(model: model)
      } else {
        SavedTextView(model: model)
      }
    }
    .onChange(of: model.hubView) { _, section in
      if section == .savedText { model.openForKeyboard?() }
    }
    .alert("File action", isPresented: Binding(
      get: { model.actionReport != nil }, set: { if !$0 { model.actionReport = nil } })
    ) {
      Button("OK") { model.actionReport = nil }
    } message: { Text(model.actionReport ?? "") }
  }
}

private struct SavedTextView: View {
  @ObservedObject var model: IslandModel
  @State private var inputHeight: CGFloat = 36

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Paste to save").foregroundStyle(.white.opacity(0.7))
        Spacer()
        Button { model.pasteText() } label: {
          Image(systemName: "clipboard").frame(width: 24, height: 24)
        }.buttonStyle(.plain).accessibilityLabel("Paste and save").help("Paste and save")
      }
      HStack(alignment: .bottom, spacing: 10) {
        HubTextInput(text: $model.textInput, height: $inputHeight, save: { model.saveText() })
          .frame(height: inputHeight)
          .overlay(alignment: .topLeading) {
            if model.textInput.isEmpty {
              Text("Type here").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                .padding(.top, 6).padding(.leading, 5).allowsHitTesting(false)
            }
          }
        if !model.textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button("Save") { model.saveText() }.buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium)).padding(6)
        }
      }
      if let error = model.textError {
        Text(error).font(.system(size: 11)).textSelection(.enabled)
      }
      if model.savedItems.isEmpty {
        Text("Saved text stays on this Mac until you remove it.")
          .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(model.savedItems) { item in
              VStack(alignment: .leading, spacing: 6) {
                Text(item.text).font(.system(size: 12)).textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 16) {
                  Button { model.copyText(item) } label: {
                    Image(systemName: "doc.on.doc").frame(width: 24, height: 24)
                  }.accessibilityLabel("Copy saved text").help("Copy")
                  if item.webURL != nil {
                    Button("Open") { model.openText(item) }
                  }
                  Spacer()
                  Button { model.removeText(item) } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                  }.accessibilityLabel("Remove saved text").help("Remove")
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
              }.padding(.vertical, 6)
              Divider().overlay(.white.opacity(0.15))
            }
          }
        }
      }
    }
    .contextMenu { Button("Paste") { model.pasteText() } }
  }
}

private struct HubFilesView: View {
  @ObservedObject var model: IslandModel
  @State private var imageAction: ImageActionConfiguration?
  @State private var pendingImageAction: FileAction?
  @State private var showingOptions = false

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Text("\(model.selectedFiles.count) selected").foregroundStyle(.white.opacity(0.7))
        Spacer()
        Button(model.selectedFiles.count == model.files.count ? "Clear Selection" : "Select All") {
          model.selectedFiles = model.selectedFiles.count == model.files.count ? [] : Set(model.files)
        }.disabled(model.files.isEmpty)
      }.font(.system(size: 11))
      if model.files.isEmpty {
        Button { model.chooseFiles() } label: {
          Image(systemName: "tray.and.arrow.down").font(.system(size: 24, weight: .light))
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Add Files").help("Add Files")
          .disabled(model.isChoosingFiles)
      } else {
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: 12) {
            ForEach(model.files, id: \.self) { url in
              VStack(spacing: 5) {
                Toggle(isOn: Binding(
                  get: { model.selectedFiles.contains(url) },
                  set: { if $0 { model.selectedFiles.insert(url) } else { model.selectedFiles.remove(url) } }
                )) { Text("Select \(url.lastPathComponent)") }
                  .labelsHidden().toggleStyle(.checkbox)
                  .accessibilityLabel("Select \(url.lastPathComponent)")
                TrayFileIcon(
                  url: url, reveal: { model.reveal(url) }, began: { model.beginFileDrag() },
                  ended: { model.endFileDrag(url, accepted: $0) }
                ).saturation(0).frame(width: 36, height: 36)
                  .help("Drag out, or click to show in Finder")
                Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                  .help(url.lastPathComponent)
                Button("Remove") { model.removeFile(url) }
                  .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                  .accessibilityLabel("Remove \(url.lastPathComponent) from Hub")
              }.frame(width: 84)
            }
            Button { model.chooseFiles() } label: {
              Image(systemName: "tray.and.arrow.down").font(.system(size: 24, weight: .light))
                .frame(width: 84, height: 100)
            }.buttonStyle(.plain).accessibilityLabel("Add Files").help("Add Files")
              .disabled(model.isChoosingFiles)
          }.padding(.vertical, 3)
        }.frame(maxHeight: .infinity)
      }
      if let error = model.fileError {
        Text(error).font(.system(size: 11)).textSelection(.enabled)
      }
      if model.processingFiles {
        HStack { ProgressView().controlSize(.small); Text("Creating result files…") }
      } else if showingOptions {
        HStack(spacing: 6) {
          actionButton("Create ZIP", symbol: "archivebox") { model.performFileAction(.zip) }
          actionButton("Resize Images", symbol: "arrow.up.left.and.arrow.down.right") { configure(.resize) }
          actionButton("Convert Images", symbol: "arrow.triangle.2.circlepath") { configure(.convert) }
          actionButton("Images to PDF", symbol: "doc.richtext") { model.performFileAction(.imagePDF) }
          actionButton("Compress Images", symbol: "arrow.down.right.and.arrow.up.left") { configure(.compress) }
          actionButton("Compress PDFs", symbol: "doc.zipper") { model.performFileAction(.compressPDF) }
        }.disabled(model.selectedFiles.isEmpty || model.isChoosingFiles)
      }
      HStack {
        Button { model.openGoogleDrive?() } label: {
          GoogleMark().frame(width: 16, height: 16).frame(width: 28, height: 28)
        }.accessibilityLabel("Google Drive").help("Google Drive")
        Spacer()
        Button { showingOptions.toggle() } label: {
          Label("Options", systemImage: showingOptions ? "chevron.up" : "ellipsis.circle")
        }.disabled(model.isChoosingFiles)
        Spacer()
        Color.clear.frame(width: 28, height: 28)
      }.buttonStyle(.plain).font(.system(size: 11))
    }
    .sheet(item: $imageAction, onDismiss: {
      model.configuringImages = false
      if let action = pendingImageAction {
        pendingImageAction = nil
        model.performFileAction(action)
      }
    }) { configuration in
      ImageActionView(kind: configuration.kind) { action in
        pendingImageAction = action
        imageAction = nil
      }
    }
  }

  private func configure(_ kind: ImageActionKind) {
    model.configuringImages = true
    imageAction = ImageActionConfiguration(kind: kind)
  }

  private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 7) {
        Image(systemName: symbol).font(.system(size: 16))
        Text(title).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }.frame(width: 66, height: 64)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }.buttonStyle(.plain).accessibilityLabel(title).help(title)
  }
}

private struct GoogleMark: View {
  private static let image = Bundle.main.url(forResource: "Google", withExtension: "png")
    .flatMap { NSImage(contentsOf: $0) }

  var body: some View {
    if let image = Self.image {
      Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
    } else { Text("G").font(.system(size: 16, weight: .semibold)) }
  }
}

private enum ImageActionKind: String {
  case resize = "Resize Images"
  case convert = "Convert Images"
  case compress = "Compress Images"
}

private struct ImageActionConfiguration: Identifiable {
  let id = UUID()
  let kind: ImageActionKind
}

private struct ImageActionView: View {
  let kind: ImageActionKind
  let perform: (FileAction) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var format = ImageOutput.png
  @State private var preset = 1024
  @State private var custom = ""
  @State private var targetMB = "10"

  private var maximum: Int? { preset == 0 ? Int(custom) : preset }
  private var maximumBytes: Int? {
    guard let value = Double(targetMB), value.isFinite, value > 0,
      value < Double(Int.max) / 1_000_000 else { return nil }
    let bytes = Int(value * 1_000_000)
    return bytes > 0 ? bytes : nil
  }
  private var valid: Bool {
    switch kind {
    case .resize: return maximum.map { $0 > 0 } ?? false
    case .convert: return true
    case .compress: return maximumBytes != nil
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(kind.rawValue).font(.headline)
      Picker("Output format", selection: $format) {
        ForEach(ImageOutput.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      if kind == .resize {
        Picker("Maximum long edge", selection: $preset) {
          Text("512 pixels").tag(512)
          Text("1024 pixels").tag(1024)
          Text("2048 pixels").tag(2048)
          Text("Custom").tag(0)
        }
        if preset == 0 {
          TextField("Pixels (positive whole number)", text: $custom)
            .accessibilityLabel("Custom maximum long edge in pixels")
        }
        Text("Keep proportions. Smaller images stay at their current size.").font(.caption)
      }
      if kind == .compress {
        TextField("Target size in MB", text: $targetMB)
          .accessibilityLabel("Target size in MB")
        Text("Quality or dimensions can be reduced to meet the target. Proportions stay the same.")
          .font(.caption)
      }
      Text("Source files stay unchanged. JPEG uses a white background.").font(.caption)
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Choose Output Folder…") {
          if kind == .compress, let maximumBytes {
            perform(.compressImage(format: format, maximumBytes: maximumBytes))
          } else {
            perform(.image(format: format, maximumLongEdge: kind == .resize ? maximum : nil))
          }
        }.disabled(!valid).keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 380)
      .onAppear { if kind == .compress { format = .jpeg } }
  }
}
