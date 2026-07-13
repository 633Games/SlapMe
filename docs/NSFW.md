# NSFW sounds in SlapMe

SlapMe does **not** sniff filenames or audio content for “NSFW.”  
A pack is NSFW only because of **where you put the folder**.

---

## How labeling works

| Pack type | How it’s labeled | Shown when |
|---|---|---|
| **Bundled NSFW** | Lives under `…/Packs/nsfw/<pack-name>/` in the app resources | **Enable NSFW packs** is on |
| **User NSFW** | Lives under `~/Library/Application Support/SlapMe/Packs/nsfw/<pack-name>/` | **Enable NSFW packs** is on |
| **SFW** | Under `…/Packs/sfw/<pack-name>/` (bundled or in Application Support) | Always |
| **Custom** | Any other folder under `…/Packs/` (e.g. `soundboard/`) | Always (not gated) |

In the popover, NSFW packs appear as **`NSFW: <pack-name>`**.  
The gate is the **Enable NSFW packs** toggle (off by default).

Individual files are not tagged. The **whole folder** is the pack; every `.mp3` / `.wav` / `.aiff` / `.m4a` / `.caf` inside it inherits that pack’s category.

---

## Folder layout (user packs)

```text
~/Library/Application Support/SlapMe/Packs/
├── nsfw/                    ← NSFW (gated)
│   └── ahegao/              ← shows as “NSFW: ahegao”
│       ├── clip1.mp3
│       └── clip2.mp3
├── sfw/                     ← optional extra SFW packs
│   └── soft/
│       └── ow.mp3
├── soundboard/              ← Custom (from MyInstants import; always visible)
│   └── …
└── misc.mp3                 ← Custom: Drop folder (loose files)
```

### Create an NSFW pack

```bash
mkdir -p "$HOME/Library/Application Support/SlapMe/Packs/nsfw/my-pack"
# copy your clips into that folder, then in SlapMe:
# Enable NSFW packs → Reload packs → select “NSFW: my-pack”
```

Or open the folder from the app: **Open custom folder**, then create `nsfw/<pack-name>/` yourself.

### Move MyInstants downloads into NSFW

Imports default to **Custom: soundboard** (not gated). To label them NSFW:

```bash
mkdir -p "$HOME/Library/Application Support/SlapMe/Packs/nsfw/soundboard"
mv "$HOME/Library/Application Support/SlapMe/Packs/soundboard/"*.mp3 \
   "$HOME/Library/Application Support/SlapMe/Packs/nsfw/soundboard/"
```

Then **Enable NSFW packs** → **Reload packs**.

---

## Bundled NSFW (developers)

Shipped placeholders live here before build:

```text
Sources/SlapMe/Resources/Packs/nsfw/default/*.wav
Sources/SlapMe/Resources/Packs/sfw/default/*.wav
```

Folder name under `nsfw/` or `sfw/` becomes the pack name (`default` → `NSFW: Default`).

---

## What is *not* a label

- Filename keywords (`owo`, `yamete`, etc.) — **ignored** for category  
- MyInstants search text — **does not** auto-tag NSFW  
- Metadata inside the audio file — **not read**

If it isn’t under an `nsfw/` directory, SlapMe treats it as SFW or Custom and will show it even with NSFW disabled.

---

## Rights & responsibility

You must own or have permission for any NSFW (or SFW) clips you add. SlapMe only organizes folders; it doesn’t grant a license to third-party voice/meme audio.

See the main [README](README.md) for install and general soundboard import / preview.
