# SlapMe

Slap your Apple Silicon MacBook — it yells back with anime/weeb (or any) sound packs.

Menu bar app + privileged accelerometer helper. Color / **Pride** icon, MyInstants import with preview, pack folders under Application Support, Ko-fi tip link.

**Tip jar:** [ko-fi.com/633games](https://ko-fi.com/633games)

---

## Download (prebuilt)

Grab the latest **SlapMe.app.zip** from:

**[github.com/633Games/SlapMe/releases](https://github.com/633Games/SlapMe/releases/latest)**

1. Unzip → drag **SlapMe.app** somewhere convenient (e.g. `/Applications` or `~/Applications`).
2. Open it (right-click → **Open** the first time if Gatekeeper complains — unsigned / ad-hoc signed).
3. Click the **hand** in the menu bar → gear → **Grant access & start helper…** and enter your Mac password once.
4. Slap the lid/case (gently!).

Requires an Apple Silicon **MacBook** on **macOS 14+** with a working SPU accelerometer (see [Prerequisites](#prerequisites)).

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Mac** | Apple Silicon **MacBook** (Air/Pro) with SPU accelerometer |
| **Chip** | Most **M2 / M3 / M4+**; among M1 class, **M1 Pro** is the usual one that works |
| **OS** | **macOS 14** Sonoma or newer |
| **Tools** (from source only) | [Xcode Command Line Tools](https://developer.apple.com/xcode/) (`xcode-select --install`) |
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
git clone https://github.com/633Games/SlapMe.git
cd SlapMe
chmod +x Scripts/*.sh
./Scripts/build.sh
./Scripts/start.sh
```

You should see a **raised hand** in the menu bar. Click it for the popover.

### First-run permissions

1. Click the hand icon.
2. If the helper is offline: open **Settings** (gear) → **Grant access & start helper…** (Mac password)  
   **or** run `./Scripts/start.sh` in Terminal.
3. That one admin approval can install a **LaunchDaemon** so the sensor helper starts at boot.
4. **Start SlapMe at login** is on by default. Settings persist in UserDefaults.
5. Tap **Listening for slaps** on the main screen so it shows **On**, then slap gently.

Defaults (overridden once you change them): sensitivity **0.20**, cooldown **0.65**, volume **0.7**, scale volume with slap force **on**.

### Optional: helper on login

```bash
./Scripts/install-launchd.sh
```

---

## Using SlapMe

### Main popover

| Control | What it does |
|---|---|
| **Listening for slaps** | Big On/Off button on the main screen |
| **Gear** | Settings — helper status, setup, sensitivity / cooldown / volume, launch at login |
| **Paintbrush** | Customise menu bar icon (solid color or Pride) |
| **Download** | Sound Downloader (open by default) — MyInstants search |
| **Folder / refresh** | Open packs folder / reload packs |
| Tip / Quit | Next to the title |

Only one of gear / paintbrush / download can be open at a time.

### Sound packs

- Bundled pack shows as **Default** (single slap SFX).
- Add your own under Application Support (including NSFW — see [docs/NSFW.md](docs/NSFW.md)).
- Drop `.mp3` / `.wav` / `.aiff` / `.m4a` into:

```text
~/Library/Application Support/SlapMe/Packs/
```

Then hit the refresh icon. Prefer packs you own or have rights to use.

NSFW is **folder-based** under `Packs/nsfw/<name>/` — no filename sniffing. Full guide: **[docs/NSFW.md](docs/NSFW.md)**. There is **no** bundled NSFW pack.

### Soundboard import (MyInstants)

1. Open the **download** icon (already open by default).
2. Search (e.g. `anime ow`, `yamete`, `slap`).
3. **Preview** a clip (tap **Stop** on that row to stop).
4. **Add** → pick a pack from the menu (**Default** first) or **+ New pack…**.
5. Browse with **prev / next** — **5 clips per page**.

Files land under `~/Library/Application Support/SlapMe/Packs/…` (or `Packs/nsfw/<name>/` if you put them there yourself).

### Menu bar icon

- **Solid** — color swatches / picker  
- **Pride** — rainbow cycle on the hand icon  

### Tips

- Lower **Sensitivity** if typing triggers sounds; raise if hard slaps do nothing.
- Increase **Cooldown** to cut repeat triggers from reverberation.
- Turn **Listening** off to stop reacting without quitting.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No hand icon | `pkill -x SlapMe; open -g -a /path/to/SlapMe.app` |
| `open` error `-1712` | Launch `SlapMe.app/Contents/MacOS/SlapMe` directly, or use `./Scripts/start.sh` |
| `sudo: Input/output error` | Don’t background `sudo`; use `start.sh` so the password is asked first |
| Helper offline | Gear → grant access, or `./Scripts/start.sh` |
| No slap detected | Confirm sensor `ioreg` check; slap the body; lower sensitivity slightly |
| Preview silent | Check Listening isn’t required for preview; system volume unmuted |
| Gatekeeper blocks unsigned app | Right-click → **Open**, or: `xattr -dr com.apple.quarantine SlapMe.app` |

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
./Scripts/build.sh release          # → dist/SlapMe.app + dist/slapme-helper
./Scripts/package-release.sh        # → dist/SlapMe-1.1.0-macOS.zip
swift build                         # debug under .build/
```

```text
Sources/SPUAccel/       accelerometer + slap detector
Sources/SlapMeHelper/   privileged socket server
Sources/SlapMe/         menu bar app, packs, soundboard, icons
Scripts/                build, start, launchd, package-release
```

---

## Attribution

- Accelerometer HID approach adapted from [AppleSPUAccelerometer](https://github.com/section9-lab/AppleSPUAccelerometer) (MIT)
- Soundboard search uses public MyInstants HTML/CDN (unofficial; site may change)

## Disclaimer

Undocumented Apple Silicon HID access may break after OS updates. Slap gently — don’t damage your laptop. You’re responsible for audio rights on imported clips.
