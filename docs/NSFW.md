# NSFW sounds in SlapMe

SlapMe does **not** sniff filenames or audio content for “NSFW.”  
A pack is NSFW only because of **where you put the folder**.

---

## How labeling works

| Pack type | How it’s labeled | Shown when |
|---|---|---|
| **User NSFW** | Lives under `~/Library/Application Support/SlapMe/Packs/nsfw/<pack-name>/` | Folder has audio files |
| **Default / SFW** | Bundled `sfw/default/slap.wav` plus optional `…/Packs/sfw/<pack>/` | Always |
| **Custom** | Any other folder under `…/Packs/` (e.g. `my-pack/`) | Always |

In the popover, NSFW packs appear as **`NSFW: <pack-name>`**. Hit the refresh icon after adding files.

Individual files are not tagged. The **whole folder** is the pack; every `.mp3` / `.wav` / `.aiff` / `.m4a` / `.caf` inside it inherits that pack’s category.

---

## Folder layout (user packs)

```text
~/Library/Application Support/SlapMe/Packs/
├── nsfw/                    ← NSFW
│   └── ahegao/              ← shows as “NSFW: ahegao”
│       ├── clip1.mp3
│       └── clip2.mp3
├── sfw/                     ← optional extra SFW packs
│   └── soft/
│       └── ow.mp3
├── soundboard/              ← Custom
│   └── …
└── misc.mp3                 ← Custom: Drop folder (loose files)
```

### Create an NSFW pack

```bash
mkdir -p "$HOME/Library/Application Support/SlapMe/Packs/nsfw/my-pack"
# copy your clips into that folder, then in SlapMe: refresh packs → select “NSFW: my-pack”
```

Or open the folder from the app (folder icon), then create `nsfw/<pack-name>/` yourself.

### Move MyInstants downloads into NSFW

Download into any pack with **Add**, then move files into `Packs/nsfw/<pack>/`, or create that folder first and copy clips in:

```bash
mkdir -p "$HOME/Library/Application Support/SlapMe/Packs/nsfw/my-pack"
# copy mp3/wav files in, then refresh packs
```

## Bundled audio

SlapMe ships **one** default slap clip only:

```text
Sources/SlapMe/Resources/Packs/sfw/default/slap.wav
```

There is **no** default NSFW pack in the repo or app. NSFW is entirely user-provided under Application Support.

Developers who want a bundled NSFW pack for testing can add:

```text
Sources/SlapMe/Resources/Packs/nsfw/<pack-name>/*.wav
```

…then rebuild. Folder name under `nsfw/` becomes the pack name.

---

## What is *not* a label

- Filename keywords (`owo`, `yamete`, etc.) — **ignored** for category  
- MyInstants search text — **does not** auto-tag NSFW  
- Metadata inside the audio file — **not read**

Only the folder path under `Packs/nsfw/` matters.
