import SwiftUI

struct SavedTextView: View {
  @ObservedObject var model: IslandModel
  @State private var inputHeight: CGFloat = 36
  @State private var selectedID: UUID?
  @State private var title = ""
  @State private var actionsID: UUID?
  @State private var editedText = ""
  @State private var editHeight: CGFloat = 36

  private var selected: SavedItem? {
    model.savedItems.first { $0.id == selectedID } ?? model.savedItems.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.savedTextComposing {
        TextField("Title (optional)", text: $model.textTitle).textFieldStyle(.plain)
          .font(.system(size: 12, weight: .medium)).accessibilityLabel("Title for new saved text")
        HubTextInput(text: $model.textInput, height: $inputHeight, save: saveDraft)
          .frame(height: inputHeight)
          .overlay(alignment: .topLeading) {
            if model.textInput.isEmpty {
              Text("Text to save").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                .padding(.top, 6).padding(.leading, 5).allowsHitTesting(false)
            }
          }
        HStack {
          Spacer()
          Button("Cancel") {
            model.textInput = ""
            model.textTitle = ""
            model.savedTextComposing = false
          }
          Button("Save", action: saveDraft)
            .disabled(model.textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.font(.system(size: 11)).controlSize(.small)
      } else if model.savedItems.isEmpty {
        Text("Saved text stays on this Mac until you remove it.")
          .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let item = selected {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: SavedTextLayout.rowSpacing) {
            ForEach(model.savedItems) { entry in
              SavedTextRow(model: model, item: entry, selected: entry.id == item.id,
                showingActions: actionsPresented(for: entry.id),
                select: { select(entry) }, editTitle: {
                  select(entry)
                  title = entry.title ?? ""
                  model.savedTextEditingTitle = true
                }, editText: { beginEditing(entry) })
            }
          }
        }.frame(height: SavedTextLayout.listHeight(count: model.savedItems.count))
        Divider().overlay(.white.opacity(0.15))
        if model.savedTextEditingTitle {
          HStack {
            TextField("Title", text: $title).textFieldStyle(.plain)
              .accessibilityLabel("Saved text title").onSubmit { saveTitle(item) }
            Button("Save title") { saveTitle(item) }.controlSize(.small)
          }.font(.system(size: 12))
        }
        if model.savedTextEditingContent {
          VStack(alignment: .leading, spacing: 8) {
            HubTextInput(text: $editedText, height: $editHeight, save: {})
              .frame(height: editHeight)
            HStack {
              Spacer()
              Button("Cancel") { model.savedTextEditingContent = false }
              Button("Save text") {
                if model.setTextContent(item.id, text: editedText) {
                  model.savedTextEditingContent = false
                }
              }.disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.system(size: 11)).controlSize(.small)
          }
        } else {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.webURL == nil ? "text.alignleft" : "link")
              .foregroundStyle(.white.opacity(0.75)).padding(.top, 3)
              .accessibilityHidden(true)
            ScrollView {
              Text(item.text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: model.savedTextDetailExpanded ? 81 : 36)
              .accessibilityLabel("Selected saved text preview")
            Button { beginEditing(item) } label: {
              Image(systemName: "pencil").frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit selected saved text").help("Edit saved text")
            Button { model.copyText(item) } label: {
              Image(systemName: "doc.on.doc").frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Copy selected saved text").help("Copy selected saved text")
          }.padding(.horizontal, 8)
        }
        Divider().overlay(.white.opacity(0.15))
      }
      if let error = model.textError {
        Text(error).font(.system(size: 11)).textSelection(.enabled)
      }
    }
    .contextMenu { Button("Paste") { model.pasteText() } }
    .onChange(of: actionsID) { _, id in model.menuOpen = id != nil }
    .onDisappear {
      actionsID = nil
      model.menuOpen = false
      model.savedTextEditingTitle = false
      model.savedTextEditingContent = false
      model.savedTextDetailExpanded = false
    }
  }

  private func actionsPresented(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { actionsID == id },
      set: { open in
        if open { actionsID = id }
        else if actionsID == id { actionsID = nil }
      })
  }

  private func beginEditing(_ item: SavedItem) {
    select(item)
    editedText = item.text
    editHeight = 36
    model.savedTextEditingContent = true
    model.openForKeyboard?()
  }

  private func select(_ item: SavedItem) {
    selectedID = item.id
    model.savedTextEditingContent = false
    model.savedTextEditingTitle = false
    model.savedTextDetailExpanded = false
  }

  private func saveDraft() {
    model.saveText()
    if model.textInput.isEmpty {
      model.savedTextComposing = false
      selectedID = model.savedItems.first?.id
    }
  }

  private func saveTitle(_ item: SavedItem) {
    model.setTextTitle(item.id, title: title)
    model.savedTextEditingTitle = false
  }
}

enum SavedTextLayout {
  static let rowHeight: CGFloat = 46
  static let rowSpacing: CGFloat = 6

  static func listHeight(count: Int) -> CGFloat {
    let rows = min(count, 3)
    return CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowSpacing
  }
}

private struct SavedTextRow: View {
  @ObservedObject var model: IslandModel
  let item: SavedItem
  let selected: Bool
  @Binding var showingActions: Bool
  let select: () -> Void
  let editTitle: () -> Void
  let editText: () -> Void

  private var name: String {
    item.title ?? item.webURL?.host ?? item.text
  }

  var body: some View {
    HStack(spacing: 2) {
      Button(action: select) {
        HStack(spacing: 10) {
          SavedTextIcon(url: item.webURL)
          VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(item.text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
              .lineLimit(1)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.leading, 10).frame(maxWidth: .infinity, minHeight: SavedTextLayout.rowHeight)
          .contentShape(Rectangle())
      }.accessibilityLabel(name).accessibilityValue(selected ? "Selected" : "")
        .help("Preview saved text")
      Button { model.copyText(item) } label: {
        Image(systemName: "doc.on.doc").frame(width: 28, height: 32).contentShape(Rectangle())
      }.accessibilityLabel("Copy \(name)").help("Copy saved text")
      Button { showingActions.toggle() } label: {
        Image(systemName: "ellipsis").frame(width: 28, height: 32).contentShape(Rectangle())
      }.accessibilityLabel("More actions for \(name)").help("More saved text actions")
        .popover(isPresented: $showingActions) {
          VStack(alignment: .leading, spacing: 8) {
            Button("Edit text") { editText(); showingActions = false }
            Button("Edit title") { editTitle(); showingActions = false }
            Button("Move up") { model.moveText(item.id, offset: -1); showingActions = false }
              .disabled(model.savedItems.first?.id == item.id)
            Button("Move down") { model.moveText(item.id, offset: 1); showingActions = false }
              .disabled(model.savedItems.last?.id == item.id)
            Button(selected && model.savedTextDetailExpanded ? "Collapse text" : "Expand text") {
              let expand = !selected || !model.savedTextDetailExpanded
              select()
              model.savedTextDetailExpanded = expand
              showingActions = false
            }
            if item.webURL != nil {
              Button("Open URL") { model.openText(item); showingActions = false }
            }
            Divider()
            Button("Remove", role: .destructive) {
              model.removeText(item)
              model.savedTextEditingContent = false
              model.savedTextEditingTitle = false
              showingActions = false
            }
          }.padding(12)
        }
        .onDisappear { if showingActions { showingActions = false } }
    }.buttonStyle(.plain).padding(.trailing, 6)
      .background(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.055),
        in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(selected ? Color.white.opacity(0.55) : Color.white.opacity(0.04), lineWidth: 1)
          .allowsHitTesting(false)
      }
  }
}

private struct SavedTextIcon: View {
  let url: URL?
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFit().padding(2)
          .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
      } else {
        Image(systemName: url == nil ? "text.alignleft" : "link")
          .font(.system(size: 18)).foregroundStyle(.white.opacity(0.85))
      }
    }.frame(width: 24, height: 24).accessibilityHidden(true)
      .task(id: url) {
        image = nil
        if let url {
          let loaded = await WebsiteIconLoader.shared.image(for: url)
          if !Task.isCancelled { image = loaded }
        }
      }
  }
}
