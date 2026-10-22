# Canopy artifact evidence

Work why: Use Canopy as a checked reference for a native Mac Dynamic Island. This report records what the public package establishes and where the reconstruction must use its own design.

Inspected on 2026-10-22. The analysis was static. Canopy was not installed, started, or activated. No trial, license service, weather service, database, or deployment was used. The public website and its public release endpoint were used.

## Target identity

The public page is [getcanopy.pro/download](https://getcanopy.pro/download). Its shipped JavaScript gives this release path: `/functions/downloadRelease?file=Canopy-1.1.zip`.

The downloaded ZIP has SHA-256 `fbf4885b191c13ccef96acd96cd12c53ee8096af4fc09c76a647d89a297176d6`. It contains `Canopy 2.app`. The main executable is `Contents/MacOS/Canopy v2`, with SHA-256 `fef42b33eae1493dc654fb626771515f34df19f69ece1e587e8925d1458550ef`. The bundle identifier is `com.CanopyV2.canopy`, its short version is `1.1`, and its build number is `2`. The filename, app name, and version labels differ; this report uses the digest to identify the inspected release. [E1, E2, E3]

## Evidence ledger

Each identifier below came from REA 6.3.0 CLI. Complete CLI results are retained in `docs/evidence/`. The table also records their original temporary paths. These JSON records contain analysis data, not app assets or source.

| Label | REA Evidence ID | Operation | Local result |
| --- | --- | --- | --- |
| E1 | `ev_050d8516284cd3cd0243086c70708ea778054f09f472372eb983e2ade7358896` | `inspect_artifact` | `/tmp/canopy-artifact-evidence.json` |
| E1a | `ev_9e951ef6b5598250b46653162f27fc9579c5b5e86e97eded3fd5fdc739e2526d` | `inventory_artifact` | Nested in E1 |
| E2 | `ev_07ba0f637e7372aee0820d2d9b179733424222389196e4f06a2cdffb21bb50d5` | `inspect_macho` | `/tmp/canopy-macho-evidence.json` |
| E3 | `ev_cc18f9cba2655eb6745751749465a0944b53e2a074172de319c163ef7a748957` | `inspect_plist` | `/tmp/canopy-plist-evidence.json` |
| E4 | `ev_5a9fda5bf208dcda95a397d83e25af2c91520acc4c506c1427504c9ca3aa689d` | `inspect_signature` | `/tmp/canopy-signature-evidence.json` |
| E5 | `ev_4ccd551399f7686fbf00acc8bebd1966f5aa41425542946a5733fdf081bb643f` | `extract_artifact` | `/tmp/canopy-extraction-evidence.json` |

Artifact graph manifest: `agm_312066ed8834b31286fc75bca44663627992c2da436289a036aef7be396ee055`. The graph reports 110 nodes, 146 occurrences, and 136 edges. [E1]

## Observed facts

- The main executable is a universal Mach-O with `x86_64` and `arm64` slices. The focused load/import analysis selected `arm64`. Its build metadata declares macOS 26.0 as the minimum and macOS 27.0 as the SDK. The plist also declares minimum macOS `26`. [E2, E3]
- The executable imports SwiftUI and AppKit. Named imports include `NSHostingView`, `NSPanel`, `NSWindow`, `NSScreen`, `auxiliaryTopLeftArea`, and `auxiliaryTopRightArea`. These are static references. They do not establish which window handles the island. [E2]
- `LSUIElement` is `true`. The bundle registers the `canopy` URL scheme. [E3]
- The main image links `WeatherKit`, `CoreLocation`, `IOKit`, `CoreBluetooth`, `IOBluetooth`, `ScriptingBridge`, `AVFoundation`, `AVFAudio`, `CoreAudio`, `Metal`, `MetalKit`, `QuartzCore`, `QuickLookThumbnailing`, and private `Wallpaper.framework`, among other system libraries. [E2]
- Battery-related imports include `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription`, and `IOPSNotificationCreateRunLoopSource`. Accessibility-related imports include `AXIsProcessTrusted` and `AXIsProcessTrustedWithOptions`. Event-related imports include `CGEventTapCreate`. Imports do not prove when these functions run. [E2]
- WeatherKit imports include current weather, hourly and daily forecasts, temperature, wind, and UV data. This supports a native weather integration, but its refresh rules and error behavior remain unknown. [E2]
- The plist declares purposes for location access to show weather, Apple Events to show Apple Music artwork, audio capture to show a waveform, and Bluetooth to read AirPods battery levels. These are declarations, not successful access checks. [E3]
- Signing metadata identifies a Developer ID signature and hardened runtime. Entitlements declare WeatherKit, network client access, location, and Apple Events. Temporary Apple Events exceptions name Spotify and Apple Music. The app sandbox value is `false`. Signature trust and notarization were not validated. [E4]
- The package contains `MediaRemoteAdapter.framework` and a `mediaremote-adapter.pl` resource. The extracted script accepts `stream`, `get`, `send`, and `test`, then loads corresponding adapter symbols. This is a code observation; the script was read but was not run. [E1a, E5]
- Packaged resources include AirPods `.mov` files, an asset catalog, a Metal library, click audio, lock audio, unlock audio, and localization directories. Their presence does not establish how or when the app uses them. No Canopy asset was copied into the reconstruction. [E1a]

## Inferences and build decisions

A SwiftUI view hosted by an AppKit panel is a well-supported reconstruction choice. The imports provide evidence for both systems and for native notch geometry. Exact panel style masks, window levels, screen selection, hover rules, and animation timing were not recovered. Those settings must be treated as our design choices. [E2]

Battery monitoring can use the system power-source APIs found in E2. This is a direct native route for our app. Its exact presentation and polling behavior need their own implementation checks.

Media support appears to have more than one route: the package includes a MediaRemote adapter and declares Apple Events access for music apps. This report does not establish which route is primary or which works on each macOS version. A first version can use a narrow, explicit integration and report unavailable media clearly. [E1a, E3, E4]

The reference uses private frameworks and broad local capabilities. They are not required to copy its visual model. A small reconstruction can use public AppKit/SwiftUI APIs and add each integration only when it has a clear need.

## Coverage and limits

| Question | Status | Boundary |
| --- | --- | --- |
| Is the downloadable app native, and what is its identity? | Answered | ZIP, plist, Mach-O, and signing metadata |
| Which UI systems and notch APIs are referenced? | Answered for static imports | `arm64` import table; no call graph |
| Which integrations does the package indicate? | Partly answered | Linkage, permissions, entitlements, packaged adapter |
| What is the exact island behavior? | Unresolved | No Canopy runtime observation |
| What are the exact animations and state rules? | Unresolved | No decompilation engine or runtime execution |
| Does every advertised integration work? | Unresolved | No runtime or service checks |

REA MCP tools were not exposed in this session. The CLI completed the package, Mach-O, plist, extraction, and signature operations without a decompilation engine. No configuration or engine was installed. The exported symbol list is small. REA warns that stripped or hidden symbols can make import and export coverage incomplete. The native inspection does not recover the original Swift source or prove execution.

## Commands and results

The following completed with exit code 0:

```sh
curl -L --fail --output /tmp/Canopy-1.1.zip 'https://getcanopy.pro/functions/downloadRelease?file=Canopy-1.1.zip'
npx -y rea-agents@6.3.0 inspect-artifact /tmp/Canopy-1.1.zip --format json
npx -y rea-agents@6.3.0 extract-artifact /tmp/Canopy-1.1.zip --format json
npx -y rea-agents@6.3.0 inspect-macho '<extracted>/Canopy 2.app' --format json
npx -y rea-agents@6.3.0 inspect-plist '<extracted>/Canopy 2.app' --format json
npx -y rea-agents@6.3.0 inspect-signature '<extracted>/Canopy 2.app' --format json
```

`<extracted>` is the REA-owned temporary output directory recorded in E5. No native analysis session was opened, so no session needs to be closed.
