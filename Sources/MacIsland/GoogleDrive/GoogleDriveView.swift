import SwiftUI
import UniformTypeIdentifiers

struct GoogleDriveView: View {
  @ObservedObject var drive: GoogleDriveController
  @ObservedObject var files: HubFileStore
  @State private var search = ""
  @State private var dropTarget = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "externaldrive.badge.icloud").font(.title2)
        Text("Google Drive").font(.headline)
        Spacer()
        if !drive.accounts.isEmpty {
          Picker("Account", selection: $drive.selectedAccount) {
            ForEach(drive.accounts) { account in Text(account.email).tag(Optional(account.id)) }
          }.labelsHidden().frame(maxWidth: 240).disabled(drive.busy)
            .onChange(of: drive.selectedAccount) { _, _ in drive.changeAccount() }
        }
        Button("Connect Account") { drive.connect() }.disabled(drive.busy)
        Menu {
          Button("Import OAuth Client JSON…") { drive.importConfiguration() }.disabled(drive.busy)
          Link("Google Setup Instructions", destination: setupURL)
          Divider()
          Button("Disconnect Selected Account") { drive.disconnect() }.disabled(
            drive.busy || drive.selectedAccount == nil)
        } label: {
          Image(systemName: "gearshape")
        }.menuStyle(.borderlessButton).fixedSize()
      }.padding(16)
      Divider()
      if drive.accounts.isEmpty {
        VStack(spacing: 14) {
          Image(systemName: "externaldrive.badge.person.crop").font(
            .system(size: 38, weight: .light))
          Text(drive.configured ? "Connect your Google account" : "Set up Google sign-in").font(
            .title3.weight(.semibold))
          Text(
            drive.configured
              ? "Browse Drive files, add downloads to Hub, and upload local files."
              : "Import a Desktop app OAuth client from Google Cloud. Google account access is stored in this Mac's Keychain."
          )
          .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
          if !drive.configured {
            HStack {
              Link("Setup Instructions", destination: setupURL)
              Button("Import OAuth JSON…") { drive.importConfiguration() }
            }
          } else {
            Button("Sign in with Google") { drive.connect() }.disabled(drive.busy)
          }
          if drive.busy { Button("Cancel Sign-In") { drive.cancelSignIn() } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(spacing: 10) {
          Button {
            drive.back()
          } label: {
            Image(systemName: "chevron.left")
          }
          .disabled(drive.folders.count < 2 || drive.busy).accessibilityLabel("Parent folder")
          Text(drive.folders.last?.name ?? "My Drive").fontWeight(.medium).lineLimit(1)
          Spacer()
          TextField("Search Drive", text: $search).textFieldStyle(.roundedBorder).frame(width: 190)
            .onSubmit { drive.list(search: search) }.disabled(drive.busy)
          Button {
            drive.list(search: search)
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(drive.busy).accessibilityLabel("Refresh Drive files")
        }.padding(.horizontal, 16).padding(.vertical, 10)
        List {
          ForEach(drive.files) { file in
            HStack {
              Image(systemName: file.folder ? "folder" : "doc").frame(width: 22)
              Text(file.name).lineLimit(1)
              Spacer()
              if file.folder {
                Button("Open") { drive.open(file) }.disabled(drive.busy)
              } else {
                Button(file.export.map { "Add \($0.suffix.uppercased()) to Hub" } ?? "Add to Hub")
                { drive.download(file) }
                .disabled(drive.busy || file.capabilities?.canDownload == false)
              }
            }.padding(.vertical, 3)
          }
          if drive.nextPage != nil {
            Button("Load More") { drive.list(search: search, more: true) }.disabled(drive.busy)
          }
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Upload to \(drive.folders.last?.name ?? "My Drive")").font(
              .subheadline.weight(.medium))
            Spacer()
            Text("Drop files here").font(.caption).foregroundStyle(.secondary)
          }
          if files.files.isEmpty {
            Text("Drag files here from Finder, or add files to Hub first.").font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ScrollView(.horizontal) {
              HStack(spacing: 10) {
                ForEach(files.files, id: \.self) { file in
                  Button {
                    drive.upload([file])
                  } label: {
                    Label(file.lastPathComponent, systemImage: "arrow.up.doc").lineLimit(1)
                  }.disabled(drive.busy).help(
                    "Upload \(file.lastPathComponent) to the current Drive folder")
                }
              }
            }
          }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(dropTarget ? Color.primary.opacity(0.08) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
          guard !drive.busy else { return false }
          Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
              let data: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) {
                  data, _ in
                  continuation.resume(returning: data)
                }
              }
              if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                urls.append(url)
              }
            }
            drive.upload(urls)
          }
          return true
        }
      }
      Divider()
      HStack {
        if drive.busy { ProgressView().controlSize(.small) }
        Text(drive.error ?? drive.status).font(.caption).lineLimit(2).foregroundStyle(
          drive.error == nil ? .secondary : .primary)
        Spacer()
      }.padding(12)
    }
    .frame(minWidth: 640, minHeight: 470)
    .task { if drive.selectedAccount != nil { drive.list() } }
  }

  private var setupURL: URL {
    URL(
      string:
        "https://github.com/SamarthaB10/Mac-DynamicIsland/blob/main/docs/google-drive-setup.md")!
  }
}
