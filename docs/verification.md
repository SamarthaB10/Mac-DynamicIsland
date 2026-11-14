## Quiet native UI states: 2026-11-13

Work why: Reduce competing controls in music and keep the playing island small at the notch.

The normal player, centered artwork, and activity list are states of one native interface. Feature navigation uses SF Symbols with help and accessibility names. The artwork state has no side columns. Activity keeps an observed music strip. More provides less frequent controls; Hide and Collapse remain direct actions. Picker, drag, sign-in, and menu protection remain in use. Pointer exit uses the rounded visible surface and a 700 ms grace interval.

The first source reviews found a stale music strip and possible menu protection after its view was removed. The correction observes the media controller in the strip and clears menu protection when the controls disappear or the island hides/closes. A Spec review also identified transparent-corner hover and uncertain content/shape timing. The correction uses the rounded surface and removes the delayed content task. Shape motion uses no extra bounce. These changes still require native verification below; source does not prove smooth motion.

The host build and all seven existing public ActivityStore checks pass. Controlled-clock countdown checks pass for start, pause, resume, cancel and expiry. No new UI or Rust test boundary was added. One concurrent build failed because a shared source file changed during compilation; the final build was run after source changes and passed.

Final source reviews found missing close protection in Saved Text More and a missing music strip in the combined tray. The correction uses a protected popover for saved-item actions and adds the observed music strip above live work. The timer review found a queued cancel/restart race, unbounded duration conversion, and a remaining-versus-completed progress mismatch. Timer callbacks now run synchronously, accepted duration is bounded, time formatting is shared, and activity progress means elapsed work. The public countdown checks were run after these corrections.

The latest Saved Text shelf keeps Copy, Remove and More outside its scrolling list. The composer can hide without clearing its draft; explicit Cancel clears it. The artwork content panel changed from 360 by 300 to 272 by 208 points (about 52 percent of the former area). Audio output is directly available from Music. Files and live activities now share one navigation icon.

The corrected bundle was installed at `/Applications/Mac Island.app` after an explicit user request. A backup is at `~/Library/Application Support/Mac Island Backups/tray-shelf-20261113-221816/Mac Island.app`. Built and installed bundle signature checks pass. Their executables compare equal. The installed executable SHA-256 is `127f0ea62ad1654494d8fbbbbd8936ff28d918a768b32df6161f7976556476d1`.

The installed process was observed. A native accessibility read showed the selected Saved Text row, separate preview scroll area, fixed Copy/More/Remove controls, and the protected More popover. No saved user entry was removed for verification. Native reads and capture remain unreliable: launch reads returned `Computer Use server error -10005: timeoutReached`, and a screenshot call timed out and reset the kernel. These results prevent final screenshots and a complete pointer/motion/keyboard/accessibility check. They do not prove smooth motion, notch fit, drag/drop delivery, cloud transfer behavior, VoiceOver speech, or reduced motion in the running app. No cloud test upload, new permission, merge or release was performed.

# Verification

## Native activity engine: 2026-11-13

Work why: Show Drive transfers and Hub file work beside music, with one native activity model and clear result states. Specification: [#12](https://github.com/SamarthaB10/Mac-DynamicIsland/issues/12).

Samartha also requested an explicit way to hide the island and restore it with a swipe. The expanded controls now include an eye-slash Hide button. Command-H uses the same hide action while Mac Island has keyboard focus. The menu names the available Hide or Show action. Returning the pointer to the notch restores the hidden island after the pointer has first left that area. This prevents immediate reopening when Hide is selected near the notch. The existing right-swipe hide and left-swipe restore handlers remain in use. Their runtime behavior is still unverified.

The activity store owns IDs, stable priority order, groups, progress, cancellation requests, and brief end states. SwiftUI supplies a progress ring, job control, and Activity list. Drive supplies byte counts through per-transfer URLSession delegates. Unknown totals and synchronous Hub work stay indeterminate. The native service adapters keep ownership of file work and confirm the final result.

Checks performed in this task:

- `swift build`: passed after the engine and adapters were added.
- `./scripts/check-activities.sh`: passed all seven public activity-store checks after the review fix.
- `./scripts/build.sh`: passed for the host Mac after the review fix.
- `codesign --verify --deep --strict`: passed for the fresh and installed bundles.
- `cmp` of the built and installed executables: passed.
- The first SwiftPM test attempt could not load `Testing`; this Command Line Tools installation also has no `xctest`. No framework or package was installed. The approved activity-store seam uses a standalone Swift check runner instead. It checks priority, groups, progress, cancellation, alert expiry, and late callbacks.

Native UI access returned `Computer Use server error -10005: timeoutReached` on each attempt to select the installed app. The optional launch function was also unavailable. App selection did launch the process. These errors prevented accessibility inspection and before/after screenshots. The build and store checks do not prove the visible UI.

Still unverified in the running UI: music beside a real job, live upload/download progress and cancellation, Hub success and failure, priority changes, rapid open/close, pin, picker and drag behavior, hide/restore, reduced motion, keyboard access, and VoiceOver. No cloud files were uploaded for verification. Exact islandcn motion matching is not established; its public source has no reference recordings. No React code or service demo data was copied.

### Standards review

One finding: the README claimed that results do not open or unhide the island, but existing Hub completion callbacks still did so. The fix adds a non-revealing path for background results. Explicit file choices and drops keep their reveal behavior. No other documented-standard or useful code-smell finding was reported.

### Spec review

One finding: Hub and Drive download completion could replace the selected tab or show a hidden island. Both now add results without invoking the reveal callback. Hub completion no longer invokes the keyboard-open callback. No scope creep was reported. The correction was checked directly in source and rebuilt; it is not a completed runtime UI check.

The final Spec review found one further issue: file work that ended while hidden could leave the Rust core with stale interaction flags. Restore now sends the current picker/drag and drop state after showing the island. This small correction was checked in source and rebuilt; no new test seam was added.

The initial reviews used the diff from `b1a8f4ff16e642fb94506d05fb826d6f4f2b88f3`. They found one issue per axis, with the same root cause. The code fix addresses both findings. A final Standards source review found no remaining findings after the correction and Hide control. Hover restore was added after that review; its source path was checked directly.

Samartha requested a PR and an installed-app update. [#13](https://github.com/SamarthaB10/Mac-DynamicIsland/pull/13) was merged by Samartha while this work was still in progress. Main then pointed to `4224aae7bfdfc3a1cc624f56ad23b543dd46caba`. The final documentation, compact audio notice width adjustment, completion correction, and explicit Hide control are in the follow-up work. Samartha approved opening its PR with screenshots and live UI checks still pending. Main had no check runs, commit statuses, or Actions runs at this read; checks were absent, not passing.

The corrected build was copied to `/Applications/Mac Island.app`. Its executable SHA-256 is `ef370037e372da92427811df5bffe077355ab96da515a13fdda33071b236a3b0`. A backup of the previous installed app is under `~/Library/Application Support/Mac Island Backups/activity-engine-_1ong2rn/`. No new dependency, permission, public release, or deployment was added. The repository has no checked-in workflow that builds or publishes a download on merge. Packaging and release upload still need an explicit action.

## Hub file lifetime and island controls: 2026-10-28

Work why: Keep Hub file safety rules in one module and make island controls respond separately.

`HubFileStore` now owns Hub references, temporary files, drag completion, upload protection, and removal decisions. Views use its removal decision instead of inspecting active-operation collections. Upload sources are protected before work is scheduled and released when the work ends. An outgoing temporary file is removed only after drop acceptance and copy completion. Native file promises and browser drop handling stay in their existing adapters.

In the large artwork view, Pin and Collapse appear below the left navigation tabs. Other views keep their existing control position. Icon buttons show press feedback separately. Startup reuses the first running app copy instead of creating a second widget.

Checks:

- `./scripts/build.sh`: passed for the host Mac after the final source changes.
- `codesign --verify --deep --strict 'dist/Mac Island.app'`: passed.
- `xcrun swift-format lint Sources/MacIsland/HubFileStore.swift Sources/MacIsland/IslandIconButtonStyle.swift Sources/MacIsland/MacIslandApp.swift`: passed.
- `git diff --check`: passed.
- `swift test`: compiled and linked the debug build, then reported `no tests found`. The package has no test target. No tests were added.
- Separate Standards and Spec reviews both found that upload protection initially started too late. This was corrected by protecting the source synchronously before scheduling work. No other findings were reported.

The user approved quitting the old development copy and checking the fresh build, then confirmed that everything works. The native accessibility tree showed the artwork layout and Pin, Collapse, and playback controls. A second executable launch returned successfully without creating another long-running copy. Native screenshot capture timed out; the user then said screenshots were not needed. File transfer failure cases were checked in source, not through live Google Drive uploads.

At the user's request, the fresh bundle was copied to `/Applications/Mac Island.app`. The installed bundle passed `codesign --verify --deep --strict`, and `cmp` confirmed that its executable matches the fresh build. `ps` confirmed that the installed path is running. No dependency was added. No database or cloud upload was used. Existing Spotify access was used by the running app. No release deployment was made.

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
