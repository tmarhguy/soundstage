# SoundStage Architecture

A single Swift executable (~2 MB) built with SwiftUI + Core Audio. No Xcode
project — plain SwiftPM (`macos/Package.swift`) plus a bundling script.

```
macos/
├── Package.swift            SPM manifest (macOS 14.4+)
├── Info.plist               LSUIElement, audio + microphone usage strings
├── AppIcon.icns
├── make-app.sh              swift build → assemble .app → ad-hoc codesign
├── install.sh               optional: copy local build to /Applications
├── Sources/SoundStageCore/  testable policy (enable, clock, settings)
├── Sources/SoundStage/      app + Core Audio engine
└── Tests/SoundStageTests/   XCTest on SoundStageCore (no HAL / TCC)
```

## The audio path

### 1. Capturing system audio — process tap

`Engine.start()` creates a **global process tap** (macOS 14.4+ API):

```swift
let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObj])
desc.muteBehavior = .mutedWhenTapped
AudioHardwareCreateProcessTap(desc, &tapID)
```

Three properties matter:

- **Global with self excluded** — captures a stereo mixdown of every process
  except SoundStage itself (which prevents a feedback loop).
- **`.mutedWhenTapped`** — the tapped audio is muted *at the hardware*. Apps
  keep playing normally into Core Audio, but nothing reaches a physical device
  except through SoundStage's own render path. This is what prevents doubled
  audio when the user's default device is also one of the selected outputs.
- **Private** — the tap isn't visible to other processes.

**TCC gotcha:** without the *System Audio Recording* permission, tap creation
*succeeds* and buffers flow — but every sample is zero. SoundStage detects this
when other apps are playing and auto-stops (so `.mutedWhenTapped` doesn’t leave
the machine silent). Grants don’t apply mid-launch — quit and reopen after
allowing. A quarantined copy from Downloads can be **App Translocated**; the
app refuses to start until it’s in `/Applications` with quarantine cleared.

**Ad-hoc signing:** rebuilds change the CDHash and can orphan the Privacy
toggle (UI still ON, tap silent). Toggle SoundStage off/on in both Privacy
lists, then Quit and reopen. Notarization is the long-term fix.

**Gatekeeper:** quarantined ad-hoc downloads often fail to open
(`kLSNoExecutableErr`). Clear with `xattr -dr com.apple.quarantine`.

**Menu bar (macOS 26):** third-party status items can be hidden. SoundStage
opens a floating mixer on launch so the UI is always reachable.

**HDMI/DP aggregate gotcha (macOS 26):** including some DisplayPort/HDMI
outputs in the private aggregate makes `AudioDeviceStart` succeed while the
IO proc **never fires** (zero callbacks → total silence). SoundStage defaults
HDMI/DP devices to off; Built-in + Bluetooth still default on. Enable display
outputs one at a time if needed.

### 2. Fan-out — private aggregate device

The tap plus every selected output device go into one **aggregate device**:

```swift
let desc: [String: Any] = [
    kAudioAggregateDeviceSubDeviceListKey: subDevices,   // outputs, drift-comp on non-clock
    kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUUID, ...]],
    kAudioAggregateDeviceMainSubDeviceKey: clockUid,
    kAudioAggregateDeviceIsPrivateKey: 1,
    kAudioAggregateDeviceTapAutoStartKey: 1,
]
AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateID)
```

Every output device has its own hardware clock; they *will* drift apart.
`kAudioSubDeviceDriftCompensationKey: 1` makes Core Audio resample each
non-clock device against the **clock device** (the aggregate's "main"
sub-device). This is also why the clock should be a wired device: Bluetooth
clocks wander. Sample-rate mismatches (44.1 kHz Bluetooth vs 48 kHz wired) are
handled the same way; the engine additionally tries to set every device's
nominal rate to the clock's rate up front.

The aggregate is private, so it never appears in Sound settings or other apps.

### 3. Render — one realtime callback

`AudioDeviceCreateIOProcIDWithBlock` on the aggregate delivers, per cycle:

- **input buffers** — the tap's stereo mixdown
- **output buffers** — one per output-device stream, in sub-device list order

The callback (realtime constraints: no allocation, no locks, no ObjC/Swift
runtime calls that can block):

1. Writes tap input into a **shared stereo interleaved ring buffer**
   (750 ms max delay + headroom).
2. For each output buffer, reads the ring at `writeIndex − delayFrames[device]`,
   applies `gain[device] × master`, and accumulates RMS for the meters.

Per-device parameters live in pre-allocated pointers written by the UI thread
and read by the audio thread. Aligned 32-bit loads/stores are atomic on
arm64; a one-buffer-stale gain value is inaudible, so no locking is needed.

Delaying a device just moves its read offset back. The UI exposes this as
"delay the *fast* (wired) devices to match the *slow* (Bluetooth) one" —
you can't time-travel Bluetooth forward.

### 3b. Autosync (one-shot mic calibration)

`AutoSyncRunner` drives a temporary **measure mode** on the engine:

1. **`beginLatencyMeasure(chirp:)`** — snapshot gains/delays/master, force
   delays to 0, mute tap passthrough into the ring, load a precomputed mono
   chirp buffer.
2. **`soloForMeasure(uid:)`** — DUT gain up, all other slots zero.
3. **`scheduleProbe()`** — audio thread writes chirp samples into the ring
   (L=R) instead of silence; only the soloed device reproduces them.
4. **`MicRecorder`** (`AVAudioEngine` input tap on the default mic) captures
   the room while each probe plays.
5. **`SoundStageCore.estimateDelayMs`** — normalized cross-correlation with
   earliest-strong-peak selection, parabolic sub-sample interpolation, then
   `relativeDelaysMs` (slowest → 0, others delayed, rounded to nearest ms).
6. **`endLatencyMeasure()`** — restore the mix; the model writes the new
   `delayMs` map into settings + live slot pointers.

Failures are all-or-nothing (mic denial, low confidence, too-short capture):
the snapshot is restored and no partial delay set is persisted. A second
attempt at higher probe gain runs automatically per device before giving up.

Pure math lives in `SoundStageCore/LatencyMeasure.swift` so XCTest can cover
chirps, reflections, noise rejection, and nearest-ms quantization without
touching Core Audio or TCC.

**User-facing guide:** [AUTOSYNC.md](AUTOSYNC.md).

### 4. Teardown

`stop()` destroys IOProc → aggregate → tap, in that order. Destroying the tap
un-mutes system audio; normal routing resumes instantly. The app also stops
the engine in `applicationWillTerminate`, and a killed process is cleaned up
by `coreaudiod`, so there's no way to leave the system muted.

## The app layer

- **`AppModel`** (`@MainActor ObservableObject`) owns settings
  (JSON-encoded in `UserDefaults`), listens for device hot-plug
  (`kAudioHardwarePropertyDevices`), polls meters at 8 Hz, and debounces
  engine restarts when the device set or clock changes.
- **Autosync:** `autosync()` runs `AutoSyncRunner` on a task; UI shows
  `Syncing Device…` and blocks Start/Stop/Quit/restart-while-measuring.
  Requires Microphone TCC (`NSMicrophoneUsageDescription`) in addition to
  System Audio Recording.
- **Auto-rejoin:** on every device-list change, if the engine is running and
  `enabled ∩ present` differs from what the engine is driving, it restarts
  with the current set — so a reconnecting Bluetooth speaker rejoins.
- **Auto-resume:** `wasRunning` is persisted; launch → engine starts.
- **`--capture out.png [--hero]`** renders `PanelView` via `ImageRenderer`
  with a deterministic fake model — the README screenshots are generated by
  the app itself (native `NSSwitch` doesn't render offscreen, so preview mode
  draws a lookalike).

## Why not a virtual audio driver?

The classic approach (BlackHole, Loopback) installs an `AudioServerPlugIn` —
an installer, admin rights, and for distribution Apple's audio-driver
entitlement. Process taps do the same job for this use case with **zero
install surface**: TCC prompts for system audio (and microphone only if you
use Autosync), and dragging the app to the Trash removes every trace.
