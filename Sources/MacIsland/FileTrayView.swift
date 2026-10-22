import SwiftUI

struct FileTrayView: View {
  @ObservedObject var model: IslandModel

  var body: some View {
    VStack(spacing: 10) {
      if model.files.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: "tray.and.arrow.down").font(.system(size: 24, weight: .light))
          Text("Drop files here").font(.system(size: 14, weight: .medium))
          Text("Drag them out when you need them.").font(.system(size: 11)).foregroundStyle(
            .white.opacity(0.6))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: 12) {
            ForEach(model.files, id: \.self) { url in
              VStack(spacing: 4) {
                Button {
                  model.reveal(url)
                } label: {
                  Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().saturation(0).frame(width: 36, height: 36)
                }.buttonStyle(.plain).help("Show in Finder")
                  .accessibilityLabel("Show \(url.lastPathComponent) in Finder")
                  .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).truncationMode(
                  .middle)
                Button("Remove") { model.files.removeAll { $0 == url } }
                  .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                  .accessibilityLabel("Remove \(url.lastPathComponent) from tray")
              }.frame(width: 72)
            }
          }.padding(.vertical, 3)
        }.frame(height: 88)
      }
      if let error = model.fileError { Text(error).font(.system(size: 10)).lineLimit(1) }
      HStack {
        Button {
          model.openGoogleDrive?()
        } label: {
          Label("Google Drive", systemImage: "externaldrive.badge.icloud")
        }
        .buttonStyle(.plain).font(.system(size: 10))
        Spacer()
        Button {
          model.chooseFiles()
        } label: {
          Label("Add Files", systemImage: "plus")
        }
        .buttonStyle(.plain).font(.system(size: 11))
      }
    }
  }
}
