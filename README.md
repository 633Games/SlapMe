<p align="center">
  <img src="docs/slapme-banner.svg" alt="SLAPME — slap → anime sounds" width="780" />
</p>

# SlapMe

Slap your MacBook. It screams for you.

Apple Silicon MacBooks only · macOS 14+ · tip jar: [ko-fi.com/633games](https://ko-fi.com/633games)

---

## 1. Install (build from source)

```bash
git clone https://github.com/633Games/SlapMe.git
cd SlapMe
chmod +x Scripts/*.sh
./Scripts/build.sh
./Scripts/start.sh
```

Enter your Mac password when asked. Look for the **hand** in the menu bar → click it → grant helper access if needed → slap gently.

---

## 2. Download (zip)

Too scary? Grab the ready-made app:

**[Download SlapMe.app.zip](https://github.com/633Games/SlapMe/releases/latest)**

1. Unzip
2. Open **SlapMe.app** (right-click → **Open** if Mac complains)
3. Menu bar hand → gear → grant access (password once)
4. Slap!

---

## 3. Prerequisites

| Need | Detail |
|---|---|
| MacBook | Apple Silicon (M2 / M3 / M4… — M1 Pro often works) |
| OS | macOS 14 Sonoma or newer |
| Password | Once, so the slap sensor helper can start |
| From source | Xcode Command Line Tools (`xcode-select --install`) |

**Won’t work on:** Intel Macs, Mac mini / Studio / iMac, phones.

Check the sensor:

```bash
ioreg -l -w0 | grep AppleSPUHIDDevice
```

No output = this Mac can’t slap-detect. Sadge.

---

## 4. Troubleshooting

| Problem | Fix |
|---|---|
| No hand icon | Quit and reopen SlapMe.app |
| Helper offline | Gear → grant access, or run `./Scripts/start.sh` |
| No sound on slap | Tap **Listening for slaps** so it says **On**; slap the body (not the screen); lower Sensitivity in Settings |
| Mac blocks the app | Right-click → **Open**, or run: `xattr -dr com.apple.quarantine SlapMe.app` |
| Still broken | Check `/tmp/slapme-helper.log` |

Add your own sounds with the **download** icon (MyInstants), or drop files in:

`~/Library/Application Support/SlapMe/Packs/`

---

Slap gently. Don’t yeet your laptop.  
You’re responsible for the audio you import. ╰(✿´⌣`✿)╯♡
