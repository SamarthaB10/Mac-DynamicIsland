# Mac Island

A small Dynamic Island for the MacBook notch. It has Spotify controls, a Hub for files and saved text, connected devices, and local weather. The interface uses the macOS system font, black and white controls, and color album covers.

## Download and install

**[Download Mac Island for Mac](https://github.com/SamarthaB10/Mac-DynamicIsland/releases/latest/download/Mac-Island.dmg)**

1. Open the disk image.
2. Drag **Mac Island.app** into **Applications**.
3. Open Mac Island from Applications.

The download supports **Apple silicon and Intel** on **macOS 14 or later**. You do not need the source code, Swift, Rust, or a terminal to run the app. There is no Dock icon. Use the capsule icon in the menu bar for settings and Quit.

This release has an ad hoc signature. It is not notarized by Apple. macOS can block the first launch. If you trust this download, use **System Settings > Privacy & Security > Open Anyway**. See [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper.

A [ZIP download](https://github.com/SamarthaB10/Mac-DynamicIsland/releases/latest/download/Mac-Island.zip) and [SHA-256 checksums](https://github.com/SamarthaB10/Mac-DynamicIsland/releases/latest/download/SHA256SUMS.txt) are also available.

## Use the island

- Move the pointer near the notch to open it. Move away to close it.
- Select the pin only when you want it to stay open. The chevron or Escape closes and unpins it.
- Swipe right over the island to hide it. Swipe left over the notch area to show it again. A horizontal two-finger trackpad gesture is supported. On the compact island, a mouse drag is also supported.
- The menu bar's **Show Island** option can hide or show it. This choice is saved on your Mac.
- The island stays on the built-in MacBook display. It does not move to an external monitor. With the lid closed and no built-in display available, it hides.

### Now Playing

Play music in Spotify. The cover and playing indicator appear beside the notch. Open the island for playback controls and the song progress bar. Select the song title to open Spotify. The heart opens Spotify so you can save the song there; it does not change your saved songs itself. The headphones button opens Devices.

Allow Automation access to Spotify when macOS asks. If access is denied, change it in **System Settings > Privacy & Security > Automation**. Apple Music is not supported.

### Hub

The Hub has **Files** and **Saved Text** views.

In Files, drag files or folders from Finder onto the island, or select the middle tray icon. Drag a file icon to another app to use it. An accepted drop removes the Hub reference. A canceled drag keeps it. Select an icon to show the file in Finder. **Remove** clears only the reference. Source files stay in place. File references last until the app quits. Browser drags can supply local files, promised files, image data, or HTTP/HTTPS download URLs. Online copies use a private session folder under the macOS temporary directory, named `Mac Island Online Drops`. They are removed after an accepted outward drag has delivered a copy, or when Mac Island quits normally. Canceled drags keep the temporary file. **Save to Downloads** in Options makes a permanent, uniquely named copy in Downloads. Local source files are never put in this temporary area or deleted by the Hub. Some protected website downloads require a browser sign-in and cannot be downloaded by the app. Partial download results are kept. The color Google G button opens the existing Drive window.

Select the checkboxes for the files you want to process. Open **Options** to show the horizontal action buttons. **Create ZIP** makes one archive from selected files and folders. **Resize Images** and **Convert Images** accept PNG, JPEG, and HEIC inputs and make PNG or JPEG outputs. Resize offers maximum long edges of 512, 1024, and 2048 pixels, or a positive custom value. It keeps proportions and does not enlarge smaller images. PNG keeps transparency. JPEG uses a white background. Image orientation is kept.

**Compress Images** accepts a target size in MB and PNG or JPEG output. It reduces quality or dimensions to meet the target, keeps proportions, and keeps a result only when it is smaller than the source and fits the target. Very small targets may not be possible. Large inputs are decoded at a maximum long edge of 8192 pixels for this action. JPEG uses a white background.

**Images to PDF** makes one PDF for each selected PNG, JPEG, or HEIC image. **Compress PDFs** uses balanced image compression and keeps text selectable. It keeps a result only when it is smaller and reports the before and after sizes. Some PDFs cannot be made smaller. ZIP compression also depends on the source content; already compressed files may not shrink.

Each action asks for an output folder. Cancel makes no files. Result files have new names when a name is already used. Completed results appear in Files. If part of an action fails, completed results are kept and the app lists the failures. Sources stay unchanged. Deselect unsupported items before an image action. Choose an output folder outside selected folders for ZIP creation.

In Saved Text, paste plain text or a link into the input area to save it automatically. Command-V also works anywhere in Saved Text; the clipboard button and context menu provide Paste. Line breaks are kept. Empty entries are not saved. Repeated saves make separate items. The copy icon keeps the saved item; the × icon removes it from Saved Text. **Open** is available only when the whole item is a complete HTTP or HTTPS link. It opens the default browser when selected.

You can give a new saved item an optional title, or use its pencil button to edit a title later. Use the up and down buttons at the top of an item to change its position. Titles and order stay saved across restarts.

Saved Text stays on this Mac across restarts until you remove it. It is stored in `~/Library/Application Support/Mac Island/Saved Text.json`. When you type text, a **Save** button appears. Select it to save. Unsaved typed text is not stored when the app quits. The app does not monitor the clipboard or sync saved text. Cloud downloads added from Google Drive are stored in `~/Library/Application Support/Mac Island/Drive Downloads/`.

### Google Drive

Select **Google Drive** in the Hub or in the menu bar. Connect Google accounts, browse folders, search for files, and download files into the Hub. Use an upload button for a Hub file, or drop local files onto the Drive window's upload area. Uploads go into the folder shown in that window. Files are not uploaded when you add them to the Hub.

**First-time setup is required:** import a Google Cloud **Desktop app OAuth client JSON**, then select **Connect Account**. See the [Google Drive setup guide](docs/google-drive-setup.md). No Google client credentials are included in the public app. Google passwords are entered in your browser. Access and refresh tokens are stored in macOS Keychain.

After an app update, macOS can ask to allow access to the saved Google credentials. Enter your Mac login password in the macOS Keychain dialog and select **Always Allow** if you trust this app. Do not enter that password in a website or chat.

Google Docs, Sheets, and Slides download as DOCX, XLSX, and PPTX files. Folder uploads and recursive folder downloads are not supported. Files are uploaded as new copies. Existing Drive files are not overwritten.

### Devices and weather

Devices is a compact scrolling list of audio outputs and external displays. Select an audio output to use it. Bluetooth headphones, USB audio, HDMI, and DisplayPort outputs appear when macOS exposes them. Device battery values appear only when macOS reports them. An unknown battery is not shown as a made-up percentage.

Weather is at the top right. Select it to enable or refresh weather at your precise location. macOS will ask for Location Services access. Location coordinates are sent to [Open-Meteo](https://open-meteo.com/) for weather. Right-click the badge for the data source and any error. No Mac battery indicator is shown.

The menu includes a lock-screen player switch and preview. Secure lock-screen display is experimental and has not been verified on this Mac. Synced lyrics are not implemented.

## Design and resource use

The SwiftUI interface uses AppKit for windows, CoreAudio for device changes, and Core Location for location. A small **Rust static library** controls open, close, pin, hide, restore, and dismissal deadlines. It runs inside the app; there is no backend server or helper process. Native macOS adapters and Google network access remain in Swift.

There is no repeating system polling loop. Playback indicators run only while music plays. The progress display updates while playing; it does not poll Spotify. Only the current album cover is retained, at a maximum of 160 pixels per side. Google Drive upload and download bodies use file transfers instead of loading whole files into memory.

See [verification](docs/verification.md) for measured resource use and checks that remain. These measurements do not guarantee a fixed memory or CPU limit on every Mac.

## Build from source

This section is for developers. It is not needed to install the download.

Requires macOS, Swift 6 tools, and Rust. To build for the current Mac:

```sh
./scripts/build.sh
open "dist/Mac Island.app"
```

To make the universal download:

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
./scripts/package.sh
```

The app, disk image, ZIP, and checksums are written to `dist/`. Google setup instructions are also available as `./scripts/setup-google-drive.sh`. The setup script guides you through Google Cloud and app import. It does not ask for secrets in a terminal or send them to GitHub.

This is an independent app based on the public Canopy reference. No Canopy code or artwork is included. The [reference evidence](docs/canopy-evidence.md) records the inspection and its limits.
