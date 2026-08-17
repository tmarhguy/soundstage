# Global hotkey

![chord-control-option-slash](https://img.shields.io/badge/chord-%E2%8C%83%E2%8C%A5%2F-blue)
![no-accessibility](https://img.shields.io/badge/Accessibility-not%20required-lightgrey)

SoundStage lives in the menu bar with **no Dock icon**, so finding the mixer again can be awkward — especially if macOS hides the menu-bar item.

The **global hotkey** toggles the floating mixer panel from any app with one chord: **⌃⌥/** (Control–Option–Slash). Routing and the menu-bar process keep running; you’re only showing or hiding the UI.

---

## What the hotkey is (and isn’t)

| The hotkey **is** | The hotkey **is not** |
|---|---|
| A **system-wide** chord that works while other apps are focused | Something that only works when the mixer is already key |
| A **show / hide** toggle for the mixer panel | Quit, Start/Stop, or Autosync |
| Available whenever SoundStage is **already running** | A cold launcher built into the app (macOS won’t listen after quit) |
| Free of Accessibility / Input Monitoring prompts | Customizable in-app (fixed chord in v1) |

The mixer footer shows `⌃⌥/ · toggle mixer` as a reminder.

---

## When to use it

Use the hotkey when:

- SoundStage is running and you want the mixer **without** hunting the tray icon
- You’re in another app and need volume, delay, Start/Stop, or Autosync quickly
- You want to **dismiss** the panel and keep audio routing in the background

Skip it (or open from Applications) when:

- SoundStage is **fully quit** — the in-app chord does nothing until you launch once (see [Cold start](#cold-start-when-the-app-is-quit))
- You only use the menu-bar panel and already have that item visible

---

## Quick start

1. Launch SoundStage once (from `/Applications`, or let **Login Items** start it at login).
2. From **any** app, press **⌃⌥/** (Control–Option–Slash).
3. The floating mixer appears (or comes to the front).
4. Press **⌃⌥/** again → the mixer **hides**; SoundStage stays running (meters, routing, menu bar).
5. Press **⌃⌥/** again anytime to bring it back.

**Tip:** Add SoundStage under **System Settings → General → Login Items** so it’s usually running and the hotkey stays useful after reboot.

---

## What you’ll see

| Mixer state | **⌃⌥/** does |
|---|---|
| Hidden / closed / not on screen | Shows and focuses the mixer |
| Already visible | Hides the mixer (`orderOut`) — app keeps running |

Quit still uses the panel’s **power** button (or Quit from the menu bar). Hiding with **⌃⌥/** does **not** stop routing.

---

## What’s actually happening

SoundStage registers a Carbon **`RegisterEventHotKey`** for Control–Option–Slash at launch and clears it on terminate.

<div align="center">
  <table>
    <thead>
      <tr>
        <th align="left">Trigger</th>
        <th align="left">Condition</th>
        <th align="left">Function</th>
        <th align="left">Result</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td rowspan="2"><kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>/</kbd> pressed</td>
        <td> Mixer visible</td>
        <td><code>orderOut</code></td>
        <td>Hide panel</td>
      </tr>
      <tr>
        <td> Mixer hidden</td>
        <td><code>showMixerPanel()</code></td>
        <td>Show / focus</td>
      </tr>
    </tbody>
  </table>
</div>

That API works while Safari, Finder, etc. are focused and does **not** require Accessibility or Input Monitoring. The app process must be running for the registration to exist.

Implementation: [`HotKey.swift`](../macos/Sources/SoundStage/HotKey.swift), [`App.swift`](../macos/Sources/SoundStage/App.swift) (`hotKeyAction()`).

---

## Cold start (when the app is quit)

**macOS does not keep listening for SoundStage’s chord after you quit.** There is no Info.plist “launch on ⌃⌥/” for third-party apps. When the process exits, Carbon’s registration dies with it.

### What works natively (no helper binary)

Use Apple’s **Shortcuts** app as the system-wide listener:

1. Open **Shortcuts**.
2. New shortcut → add **Open App** → choose **SoundStage**.
3. Click the shortcut’s info / details → **Add Keyboard Shortcut** → set **⌃⌥/** (or another free chord).
4. Run it once to grant any prompts.

After that, the chord can **launch** SoundStage from cold. Once the app is running, SoundStage’s own registration also wants **⌃⌥/** for show/hide — if both claim the same keys, behavior can conflict. Prefer either:

- **Same chord, Login Item always on** — keep SoundStage running; rely on in-app toggle day to day; Shortcuts is a backup, or  
- **Different chord for Shortcuts** (e.g. cold-start only) — e.g. keep **⌃⌥/** for toggle, use another chord in Shortcuts for “Open SoundStage”

**Automator → Quick Action** + **System Settings → Keyboard → Keyboard Shortcuts** is the same idea on an older path.

### What we don’t ship (yet)

A tiny always-on **LaunchAgent** / `SMAppService` helper that owns the hotkey and calls `open` would give a single productized cold-start chord. That’s extra install surface; Shortcuts covers the need with zero custom agent code.

---

## Permissions

| Permission | Needed for hotkey? |
|---|---|
| **Accessibility** | No |
| **Input Monitoring** | No |
| **System Audio Recording** | Only for routing audio (unchanged) |
| **Microphone** | Only for Autosync (unchanged) |

No extra privacy prompt for the in-app hotkey.

---

## Tips

- **Login Item** keeps SoundStage alive across reboots so in-app **⌃⌥/** stays available.
- **Hide ≠ quit** — audio keeps playing through SoundStage while the panel is hidden.
- For true cold start, use [Shortcuts](#cold-start-when-the-app-is-quit) or don’t quit the app.
- If another utility already stole **⌃⌥/**, the chord may do nothing — rare for this combo.

---

## Troubleshooting

| Symptom | What to try |
|---|---|
| Chord does nothing | Confirm SoundStage is running. Launch from `/Applications` once. |
| Wanted to quit, only hid the panel | Use the **power** button in the mixer (or Quit). Hotkey only toggles visibility. |
| Need launch when fully quit | Set up [Shortcuts cold start](#cold-start-when-the-app-is-quit); or add a Login Item and leave the app running. |
| Shortcuts and in-app fight over the same keys | Use different chords, or disable one of them. |
| Conflict with another app’s shortcut | Quit the other utility, or open an issue requesting a different default. |

---

## FAQ

**Why can’t the built-in hotkey launch SoundStage from cold?**  
It’s registered **inside** the running app. Quit → nothing is listening. macOS has no native “remember this app’s hotkey when dead” for third-party apps. Use **Shortcuts**, a Login Item, or (someday) a helper agent.

**Does hiding the mixer stop audio?**  
No. Only **Stop** or **Quit** tears down routing.

**Is this the same as the window close button?**  
Similar idea (panel goes away, app stays). Hotkey is global; the red button is only when the panel is up.

**Can I change the chord?**  
Not in the UI yet. Default is fixed: **⌃⌥/**. Shortcuts can use any chord for Open App.

**Do I need Accessibility?**  
No for the in-app Carbon hotkey.

---

## Related

- [README](../README.md) — install, Login Items, feature list
- [AUTOSYNC.md](AUTOSYNC.md) — mic-based delay calibration from the mixer
- [ARCHITECTURE.md](ARCHITECTURE.md) — overall audio path
