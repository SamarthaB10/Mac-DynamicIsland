# Mac Island

A small Dynamic Island for the MacBook notch. It has Spotify controls, a file tray, connected devices, and local weather. The interface uses the macOS system font, black and white controls, and color album covers.

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

### File Tray

Drag files or folders from Finder onto the island. It opens File Tray during a drag. You can also use **Add Files**. Drag a file icon out to another app to use it. After that app accepts the drop, the entry leaves the tray. A canceled drag keeps it in the tray. The original file stays in place. Select an icon to reveal the file in Finder. **Remove** clears only the tray reference. It does not delete the file.

Tray references last until the app quits. Files stay in place. Cloud downloads added from Google Drive are stored in `~/Library/Application Support/Mac Island/Drive Downloads/`.

### Google Drive

Select **Google Drive** in File Tray or in the menu bar. Connect Google accounts, browse folders, search for files, and download files into the tray. Use an upload button for a tray file, or drop local files onto the Drive window's upload area. Uploads go into the folder shown in that window. Files are not uploaded when you add them to File Tray.

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
