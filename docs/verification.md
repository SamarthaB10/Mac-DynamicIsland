# Verification

## Restore on open: 2026-10-23

The app process was running while the saved `islandHidden` preference was true. Opening the existing app had no restore handler. The app now handles a reopen request by showing and opening the island. This keeps the saved hide choice for normal startup and provides a direct way to restore it from Finder or Launchpad.

`./scripts/build.sh`, `cargo fmt --manifest-path core/Cargo.toml -- --check`, `zsh -n scripts/build.sh`, and `git diff --check` passed. The fresh bundle passed signature verification before replacement. The installed bundle passed `codesign --verify --deep --strict` and its executable matched the fresh build with `cmp`. Opening the app changed `islandHidden` from 1 to 0. Native UI inspection showed Hub controls, and a screenshot showed the compact island. The on-screen window list reported one Mac Island window at x=493, y=-24, width=528, height=440. Its 24-point content inset places the widget at the screen top. The running executable was `/Applications/Mac Island.app/Contents/MacOS/MacIsland`, SHA-256 `c93f1d1c983deee9c631bb89852513977977c2361dce4535a46ac6a45adb491b`.

The build includes the reviewed native playback changes from PR #2, which was merged into the Hub branch. No account, saved text, or authentication setting was changed. No tests were added. Build caches were removed after installation. No app backup was kept, as requested. PR monitoring remains off.

## Hub update: 2026-10-23

Work why: Keep files and saved text in one native Hub, with safe file actions and a standalone installed app.

The sections below this update describe the earlier release. They do not establish that the new Hub file actions passed manual checks.

The host release build passed with `./scripts/build.sh`. These checks also passed:

- `cargo fmt --manifest-path core/Cargo.toml -- --check`
- `cargo clippy --manifest-path core/Cargo.toml -- -D warnings`
- `zsh -n scripts/build.sh scripts/package.sh`
- `bash -n scripts/setup-google-drive.sh`
- `plutil -lint scripts/Info.plist scripts/MacIsland.entitlements`
- `git diff --check`
- `codesign --verify --deep --strict` for the fresh and installed bundles
- `cmp 'dist/Mac Island.app/Contents/MacOS/MacIsland' '/Applications/Mac Island.app/Contents/MacOS/MacIsland'`

The app was built and its signature was checked before the old process was stopped. The old app was backed up at `~/Library/Application Support/Mac Island Backups/20261023-003418/Mac Island.app`. The update was installed and launched from `/Applications/Mac Island.app`. `ps` confirmed that executable path. `otool -L` showed only Apple system frameworks and Swift libraries. The source folder and build tools are not needed to run the installed app. No dependency was added to the application.

The final bundle contained 3,261,216 bytes (3192 KiB of disk blocks). Its executable SHA-256 was `93ab7483d2f8cfd991cefaa39075dee9d31671a7ec87d203fd9ad8261ddee8d0`. Before the final upload/paste source fixes, `/usr/bin/sample 6784 3` reported a 16.6 MB physical footprint and 17.0 MB peak, with the main thread waiting for events throughout that sample. Process CPU-time differences over 15 and 30 seconds gave averages of 2.07% and 2.77% of one core. Individual `ps` readings were 0.0%. These observations do not confirm the requested 1% CPU during music playback: playback state could not be read with the failed UI tool. The target remains open. Playback bars now use Core Animation instead of a repeating SwiftUI animation. No status-polling loop was added.

Observed through the running app during this task: Hub navigation, plain multiline paste, automatic save after explicit paste, Copy retaining an item, Remove, whitespace rejection, repeated items, complete-link Open, and saved-text persistence after Quit and relaunch. Removed sample entries stayed removed. The native file chooser opened. The Drive account and its first 100 items were observed after sign-in; the user also confirmed authentication. Drive authentication code and Keychain entries were not changed. The upload adapter now retains Hub source references until upload ends. Remove and outward drag are blocked for those sources during upload. Ardia was set to open external links in a new tab in its last-used window.

Later updates added titles, up/down order buttons, horizontal file-action buttons, native text-input focus fixes, and temporary online-file delivery. Those final paths have not completed a full manual pass. Native UI automation first returned `AXError.notImplemented` for panel drags, then timeouts. Its final failure was `Sky Computer Use native pipe startup failed`, including after a reset.

Still unverified in the final UI: typed Save and title editing, up/down ordering and its restart persistence, browser and Finder drag delivery, ZIP entries, image output formats and dimensions, PDF output and text retention, compression size, output cancellation, naming conflicts, and partial failures. Temporary source files and existing-output sentinels matched all 14 recorded hashes before cleanup. This confirms they stayed unchanged during the checks; it does not establish that the file actions ran.

The physical-top placement was checked through the window list: canvas y=-24 with 24-point top padding, on the built-in 1512×982-point display with a 32-point notch. A native lock-screen player already exists. Secure lock-screen display remains unverified. The user chose music controls only; no lyrics service was added.

Local before and after UI images were captured during the task. Final source review fixes reject an empty Paste, always offer Expand for saved text, and protect temporary sources during Drive upload. The final host build and installed signature and executable comparison passed after these fixes. The user later requested removal of temporary check files and did not require images on GitHub. Cleanup removed 378,710,171 bytes of temporary samples, outputs, tools, evidence, duplicate verification bundles, and build caches. The installed application and one original app backup were kept. The known disposable example.com sample link was absent from Saved Text at cleanup. No unit or integration tests were added or run. Intel and older-macOS runtime checks were not run for this update. There was no database use or public release deployment. GitHub publication and local application installation were authorized.

Work why: Deliver a standalone Mac app with a small notch interface, and record what was directly checked.

Checked on 2026-10-22 with an Apple silicon MacBook Pro, macOS 26.6.2, Apple Swift 6.3.3, and Rust 1.99.0. No unit or integration tests were added or run, as requested.

## Build and package

- `./scripts/build.sh`: passed for the host Mac.
- `./scripts/package.sh`: passed for the final universal app, DMG, ZIP, and checksums.
- `lipo -archs 'dist/Mac Island.app/Contents/MacOS/MacIsland'`: reported `x86_64 arm64`.
- `hdiutil verify dist/Mac-Island.dmg`: reported a valid checksum.
- `(cd dist && shasum -a 256 -c SHA256SUMS.txt)`: both download files passed.
- `cargo fmt --manifest-path core/Cargo.toml -- --check`: passed.
- `cargo clippy --manifest-path core/Cargo.toml -- -D warnings`: passed.
- `bash -n scripts/setup-google-drive.sh`: passed. The wizard was not run; its steps require the user's Google Cloud project.
- `zsh -n scripts/build.sh scripts/package.sh`: passed.
- `plutil -lint scripts/Info.plist scripts/MacIsland.entitlements`: passed.
- `codesign --verify --strict --verbose=2 '/Applications/Mac Island.app'`: passed.
- `otool -L '/Applications/Mac Island.app/Contents/MacOS/MacIsland'`: showed only Apple system frameworks and Swift system libraries. No source-checkout or Rust archive path is needed at runtime.

The first multi-architecture SwiftPM command required an unavailable XCBuild executable. The package script now builds each target triple separately and uses `lipo` to combine them. Both the Apple silicon and Intel compilation and link steps passed. `hdiutil` created the disk image. ZIP and SHA-256 files were also generated. See the release assets for the final package.

## Direct UI evidence

The app was copied to `/Applications/Mac Island.app` and started from that path. Its compact notch view and expanded controls were read through the native accessibility tree and screenshots.

Observed in this task:

- The black compact island and color Spotify cover.
- A live Spotify title and artist, plus playing and paused states, in native app screenshots. The user also supplied a screenshot with the playing indicator visible.
- A song-title button, song-position control, previous/play/next buttons, and device action in the revised player.
- Three sections: Now Playing, File Tray, and Devices.
- Explicit pin and collapse controls. Opening did not select the pin. After an unpinned opening, a later accessibility snapshot showed the compact state again.
- The Google Drive button in File Tray opened the installed app's native Google Drive setup window. The window showed client JSON import, setup instructions, and Connect Account. No credentials were imported.
- The native file chooser added the repository README to the tray in the earlier build. Remove cleared its tray reference, and `test -f README.md` confirmed that the source file remained.
- The user's weather screenshot showed a current temperature and condition. The badge was then moved to the top right. Coordinates were not written to the repository.
- Screen inspection reported the built-in display as 1512 × 982 points, with a 32-point notch area. The left and right safe areas placed the camera gap at x=665…850. The app uses these values and checks `CGDisplayIsBuiltin`.
- A window-list inspection showed the animation canvas at y=-24. Its top padding places the visible island at the physical top edge.

The Mac battery view was removed from the app. The compact notch height now follows the 32-point system notch area. Devices uses small scrolling rows. CoreAudio supplies output-device changes, connection type, and volume. The app does not put the island on an external display.

## Resource observations

`ps -axo pid,rss,%cpu,etime,comm` was used for direct process samples. An earlier revision used 47,984 KiB resident memory with a sampled 0.0% CPU. The standalone app installed in Applications later showed 29,952 KiB with a sampled 0.0% CPU while idle. These are individual samples, not a peak or long-term bound. Build compiler processes were separate and were not counted as app resource use.

The Rust core is a static library in the app process. It has no network client, polling thread, or unbounded cache. Swift schedules only requested close deadlines. Current album art is decoded to at most 160 pixels per side. Google transfer bodies use URLSession file uploads and file downloads. The progress display redraws while playing; it does not request Spotify state every second.

## Checks still needed

- Physical trackpad swipe direction and thresholds, including restore while hidden.
- Native Finder drag delivery into the notch in the final build, drag-out delivery, and multi-file drags. The app has native window drag registration and a SwiftUI drop fallback; delivery was not fully checked with Finder after the final change.
- Several connected headphones or HDMI/DisplayPort devices. Those hardware cases were not available for a direct check. Unknown device battery data remains unknown.
- Lid-close and external-monitor-only operation. The code hides without a built-in display; this was not checked by closing the user's lid.
- Secure lock-screen display. The menu preview and lock-event adapter are implemented, but the secure login window was not exercised.
- Google token refresh, export, download, and upload. Initial sign-in and listing were checked in the follow-up below; these transfer paths still need checks.
- Intel runtime and macOS 14 runtime. Both target architectures compile, but only Apple silicon on this Mac was available to run.
- VoiceOver, reduced motion, and a full keyboard-navigation pass.

## Follow-up: version 0.2.1

Work why: A file must leave File Tray after another app accepts its drop. The old SwiftUI drag provider did not receive a completion result, so the entry stayed in the tray.

The file icon now starts a native AppKit drag and offers a copy of the file URL. It clears the tray reference only after macOS reports an accepted drop outside the island. Canceled drags and drops back on the island keep the entry. No original file is deleted or moved. The island stays open during the drag without changing the pin setting. No dependency was added.

- `./scripts/build.sh` and `./scripts/package.sh`: passed.
- `lipo -archs 'dist/Mac Island.app/Contents/MacOS/MacIsland'`: reported `x86_64 arm64`.
- `codesign --verify --deep --strict '/Applications/Mac Island.app'`: passed after installation.
- The installed app displayed a temporary text file in File Tray with the native drag source and an accessible file label.
- Automated drag interaction returned `AXError.notImplemented` for the island panel. A Finder attempt was interrupted by user input. The user then confirmed that drag-out works. This is user confirmation, not a completed automated end-to-end check.
- A direct filesystem check found `Drag Sample.txt` in the temporary Finder destination and confirmed that the original sample remained in its source folder.
- The Google account connection was observed after an app restart. The app loaded the first 100 Drive items. After the update, macOS requested Keychain access again; the user confirmed that Google Drive works after approval. No credentials were committed to the repository.

The app is installed in `/Applications/Mac Island.app`. It does not need the source folder. The DMG, ZIP, checksums, source, and updated README are published as version 0.2.1. No unit or integration tests were added or run.

## Original release scope

The app installation and GitHub publication were requested by the user. The source folder started empty, with no existing changes. All new files serve the app, its build, setup, or evidence.

Public Canopy pages and its public release were used for the initial inspection. Apple, Google, and Open-Meteo documentation was read. GitHub stores the source and app download. No database was used. No Canopy code or artwork was copied. No production database, Google cloud file, sharing permission, or Google account credential was changed during development.
