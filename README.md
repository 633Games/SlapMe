# SlapMe

Slap your Apple Silicon MacBook — it yells back with anime/weeb (or any) sound packs.

Menu bar app + privileged accelerometer helper. Color / **Pride** icon, MyInstants import with **Preview** before download, NSFW packs (gated), Ko-fi tip link.

**Tip jar:** [ko-fi.com/633games](https://ko-fi.com/633games)

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Mac** | Apple Silicon **MacBook** (Air/Pro) with SPU accelerometer |
| **Chip** | Most **M2 / M3 / M4+**; among M1 class, **M1 Pro** is the usual one that works |
| **OS** | **macOS 14** Sonoma or newer |
| **Tools** | [Xcode Command Line Tools](https://developer.apple.com/xcode/) (`xcode-select --install`) so `swift` works |
| **Admin password** | Once, so `slapme-helper` can read the accelerometer via IOKit HID |

**Not supported:** Intel Macs, Mac mini / Studio / iMac (no usable laptop SPU path here), phones.

### Check your sensor

```bash
ioreg -l -w0 | grep AppleSPUHIDDevice
```

If that prints matches, you’re good. No output → this Mac likely can’t run the slap detector.

---

## Install (build from source)

```bash
# 1. Clone
git clone https://github.com/633Games/SlapMe.git
cd SlapMe

# 2. Build the app + helper
chmod +x Scripts/*.sh
./Scripts/build.sh

# 3. Start helper (password prompt) + menu bar app
./Scripts/start.sh
```

You should see a **raised hand** in the menu bar. Click it for settings.

### First-run permissions

1. Click the hand icon.
2. If it says **Helper offline**, press **Grant access & start helper…** and enter your Mac password  
   **or** use `./Scripts/start.sh` (password in Terminal, not backgrounded).
3. When the status shows **Helper online**, slap the laptop lid/case (not too hard!).

### Optional: helper on login

```bash
./Scripts/install-launchd.sh
```

Installs a LaunchDaemon so the sensor helper comes back after reboot (still runs as root).

---

## Using SlapMe

### Sound packs

- Bundled SFW placeholders ship in the app.
- Enable **NSFW packs** in the popover if you want those placeholders.
- Drop your own `.mp3` / `.wav` / `.aiff` / `.m4a` into:

```text
~/Library/Application Support/SlapMe/Packs/
```

Then **Reload packs**. Prefer packs you own or have rights to use.

NSFW is **folder-based** (not filename tags). Full guide: **[docs/NSFW.md](docs/NSFW.md)**.

### Soundboard import (MyInstants)

In the popover:

1. Search (e.g. `anime ow`, `yamete`, `slap`).
2. Hit **Preview** to hear a clip **without saving**.
3. Hit **Add** (or **Download top 5**) to save into `Custom: soundboard`.

Files land in:

```text
~/Library/Application Support/SlapMe/Packs/soundboard/
```

Many soundboard uploads are copyrighted. Preview/download only what you’re allowed to use.

### Menu bar icon

- **Solid** — color swatches / picker  
- **Pride** — rainbow cycle on the hand icon  

### Tips

- Lower **Sensitivity** if typing triggers sounds; raise if hard slaps do nothing.
- Increase **Cooldown** to cut repeat triggers from reverberation.
- **Mute** stops audio but can leave listening on.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No hand icon | `pkill -x SlapMe; open -g -a "$(pwd)/dist/SlapMe.app"` |
| `open` error `-1712` | Use `./Scripts/start.sh` (launches the binary) or the command above |
| `sudo: Input/output error` | Don’t background `sudo`; use the fixed `start.sh` so password is asked first |
| Helper offline | **Grant access & start helper…** or `./Scripts/start.sh` |
| No slap detected | Confirm sensor `ioreg` check; slap the body harder; lower threshold slightly |
| Preview silent | Unmute in the popover; check system volume |

Helper log: `/tmp/slapme-helper.log`

---

## Architecture

```text
Physical slap → Apple SPU accelerometer (IOKit HID)
                 → slapme-helper (root) → Unix socket
                 → SlapMe.app (menu bar) → play pack audio
```

Socket: `~/Library/Application Support/SlapMe/slapme.sock`

---

## Develop

```bash
./Scripts/build.sh release   # → dist/SlapMe.app + dist/slapme-helper
swift build                  # debug binaries under .build/
```

Project layout:

```text
Sources/SPUAccel/       accelerometer + slap detector
Sources/SlapMeHelper/   privileged socket server
Sources/SlapMe/         menu bar app, packs, soundboard, icons
Scripts/                build.sh, start.sh, install-launchd.sh
```

---

## Attribution

- Accelerometer HID approach adapted from [AppleSPUAccelerometer](https://github.com/section9-lab/AppleSPUAccelerometer) (MIT)
- Soundboard search uses public MyInstants HTML/CDN (unofficial; site may change)

## Disclaimer

Undocumented Apple Silicon HID access may break after OS updates. Slap gently — don’t damage your laptop. You’re responsible for audio rights on imported clips.
