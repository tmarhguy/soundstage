# Open at login

![login-item](https://img.shields.io/badge/macOS-Login%20Item-blue)
![no-helper](https://img.shields.io/badge/helper-not%20required-lightgrey)

SoundStage has **no Dock icon**, so after a reboot it is easy to forget to launch it. **Open at login** starts the app when you log in. Combined with **auto-resume**, a reboot can bring the whole mix back with zero clicks — and **⌃⌥/** can show or hide the mixer anytime the app is running ([hotkey guide](HOTKEY.md)).

---

## What Open at login is (and isn’t)

| Open at login **is** | Open at login **is not** |
|---|---|
| A **Login Item** — macOS launches SoundStage after you log in | A way to start **routing** by itself |
| An in-app toggle (mixer **gear → Settings**) | Stored in mixer JSON / UserDefaults — the OS owns the item |
| The usual way to keep **⌃⌥/** available after reboot | A cold-start hotkey (the chord only works while the app is running) |

Two layers, independent:

| Layer | What it does | Where it lives |
|---|---|---|
| **Open at login** | Launch the SoundStage process | Settings toggle → macOS Login Items |
| **Auto-resume** | Start routing if it was live last time | Mixer Start/Stop (`wasRunning`) |

If you **Stop**, then reboot, the app comes back **stopped**. If you quit while **live**, the mix comes back.

---

## When to use it

Turn it on when:

- You want the mix (or just the app) waiting after every reboot / log in
- You rely on **⌃⌥/** and don’t want to hunt for SoundStage.app each morning
- SoundStage lives in `/Applications` and System Audio Recording is already allowed

Skip it (or leave it off) when:

- You only use SoundStage occasionally
- The copy you’re running is still in Downloads (move it to `/Applications` first)
- You’re running an unpackaged `swift run` build — Login Items need the real `.app`

---

## Quick start

1. Put **SoundStage.app** in `/Applications` and launch it from there.
2. Click the **gear** on the mixer header.
3. Turn on **Open at login**.
4. Leave routing **Start**ed if you want the mix to come back after reboot (auto-resume).
5. Restart or log out/in once to confirm: SoundStage appears, and if it was live, routing is live.

**Off:** same Settings page, toggle **Open at login** off. That unregisters the Login Item; it does not Stop or Quit the current session.

---

## Approval and System Settings

Sometimes macOS registers the item but leaves it pending. Settings then shows a caption and **Open Login Items…**.

1. Click **Open Login Items…** (or open **System Settings → General → Login Items**).
2. Enable **SoundStage**.
3. Return to Settings — the toggle should read on.

You can still manage the item from System Settings; SoundStage re-reads OS status whenever Settings appears. The in-app toggle is the usual path.

---

## What you’ll see

| Situation | Toggle | Caption / action |
|---|---|---|
| Registered | On, interactive | Login launches the app; routing follows auto-resume |
| Not registered | Off, interactive | Same caption |
| macOS blocked it | On, not interactive | **Open Login Items…** to approve |
| App Translocation (Downloads/Desktop) | Off, disabled | Move to `/Applications` first |
| Unpackaged `swift run` | Off, disabled | Needs `SoundStage.app` in `/Applications` |

The mixer still opens on login (same as a normal launch). Hide it with **⌃⌥/**; that does not quit the app.

---

## Troubleshooting

| Symptom | What to try |
|---|---|
| Toggle does nothing / stays off | Launch from `/Applications`, not Downloads. Clear quarantine: `xattr -dr com.apple.quarantine /Applications/SoundStage.app` |
| Caption about a translocated copy | Move the app to `/Applications`, quit, open it from there, then toggle again |
| Caption about unpackaged `swift run` | Build/install the `.app` (`./macos/make-app.sh && ./macos/install.sh`) |
| Toggle on, but macOS asks to allow it | **Open Login Items…** and enable SoundStage |
| App launches after reboot, mix is silent / stopped | You last **Stop**ped (or a capture-health stop cleared resume). Hit **Start**. Auto-resume only if it was live when you quit |
| App does not launch at login | Confirm the toggle is on; check Login Items; confirm the bundle is still at `/Applications/SoundStage.app` |
| Privacy / silent tap after a rebuild | Same as a normal launch — see [README](../README.md) (signature change can stale the TCC grant) |

---

## FAQ

**Does Open at login start the mix?**  
Only if auto-resume applies: routing was live when you last quit, and at least one enabled device is present.

**Where is this saved?**  
In macOS Login Items via `SMAppService`. Not in SoundStage’s mixer settings file.

**Do I need a helper app or LaunchAgent?**  
No. The main app registers itself.

**Will the mixer pop up every reboot?**  
Yes in this version. Use **⌃⌥/** to hide it; SoundStage keeps running.

**I turned it on in System Settings instead of the app. Is that OK?**  
Yes. Settings reads the OS the next time you open the page.

**Can I use this and Shortcuts cold start together?**  
Yes. Open at login covers reboot; [Shortcuts](HOTKEY.md#cold-start-when-the-app-is-quit) covers launching after you fully Quit. Prefer different chords if both claim **⌃⌥/**.

---

## Related

- [README — Start on boot](../README.md#start-on-boot) — short overview
- [HOTKEY.md](HOTKEY.md) — why the app needs to be running for **⌃⌥/**
- [ARCHITECTURE.md](ARCHITECTURE.md) — `SMAppService`, presentation policy, auto-resume
