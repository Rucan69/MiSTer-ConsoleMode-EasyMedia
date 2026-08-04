# MiSTer-ConsoleMode-EasyMedia

Turn a Zaparoo artwork scrape into a console mode ready media library, without scraping anything twice.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Platform Windows](https://img.shields.io/badge/Platform-Windows-lightgrey)

[Report an issue](https://github.com/Rucan69/MiSTer-ConsoleMode-EasyMedia/issues) · [Changelog](CHANGELOG.md)

---

## ⚠ Before you start

**1. Unblock the scripts.** Windows flags anything downloaded from the web, and PowerShell refuses to run flagged scripts under the default `RemoteSigned` policy. Run this once, in the folder holding the scripts:

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
```

Moving the files does not help: the mark is an NTFS alternate data stream that follows the copy.

**2. Avoid network shares for large collections.** Both scripts work fine over SMB, but every file is a round trip. A library of ten thousand games means tens of thousands of round trips, and a run that takes minutes locally can take the better part of an hour over the network. Plug the drive in if you can.

**3. Back up first.** These scripts have been tested on real libraries — around 11 000 console ROMs across 40 systems, and 3 000 arcade MRA files — and carry deliberate safeguards: they never touch your ROMs, never modify a `gamelist.xml`, and never write inside the `box2d\` or `screenshot\` folders that hold your Zaparoo artwork. The clean script refuses to act on any folder not named `media`. That said, they do delete files. Make a backup before the first run.

---

## What problem this solves

1 /Taki's source for media is not Screenscraper !

2 /Zaparoo and the console mode frontend both want artwork, but they name it differently.

3/ Zaparoo stores artwork under the game's **catalogue title**, in a Recalbox style tree:

```
media/box2d/Lunch Time.png
media/screenshot/Lunch Time.png
```

4/ Console mode wants it under the **exact ROM file name**, flat, with a `-BG` suffix for the background:

```
media/Lunch Time (USA) (GameCube).png
media/Lunch Time (USA) (GameCube)-BG.png
```

Rebuilding that mapping by hand is impossible at scale, and a plain name match fails constantly. On arcade, **three quarters of MRA names differ from their artwork name** — nothing would ever guess that `280Z-ZZAP (US).mra` needs `Datsun 280 Zzzap.png`, or that `Gogetsuji Legends (US, Ver. 95.06.20).mra` needs `Power Instinct Legends.png`.

The answer is that the mapping already exists, sitting unused in `gamelist.xml`. This tool reads it.

---

## Requirements

- Windows with PowerShell 5.1 or later. No modules, no external tools.
- An existing Zaparoo scrape produced by **ZapScraper**, bundled with [MiSTer Companion](https://mistercompanion.org/) ([releases](https://github.com/Anime0t4ku/mister-companion/releases)).

### ZapScraper settings

When scraping, select at minimum:

| Setting | Value |
|---|---|
| Output format | **Zaparoo Companion** |
| Resolution preset | **HDTV** |
| Images | **Screenshot** and **2D Boxart** |
| Images, optional | 3D Boxart, Title Screen |

The two optional sources can then be selected at deploy time with `-BoxDir box3d` and `-ScreenDir titlescreen`.

> **A note on the optional sources.** ScreenScraper's coverage of 3D box art and title screens is usually thinner than for 2D box art and screenshots. This tool only copies what your scrape already contains: if a game has no 3D box art, none appears. Know what you scraped before you switch source.

---

## Workflow

### 1. Scrape with ZapScraper

Produce a normal Zaparoo scrape with the settings above. Do not rename or reorganise anything afterwards — the tool reads the `gamelist.xml` that ZapScraper wrote, and it expects the paths inside it to still be valid.

### 2. Unblock the scripts

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
```

### 3. Clean the target library

Console mode caches thumbnails, and a stale cache will keep showing old artwork forever. Cleaning removes both the deployed artwork and that cache.

```powershell
# dry run first, always
.\Clean-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -WhatIf -ReportCsv .\clean.csv

# for real, one confirmation per system
.\Clean-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games
```

Answer `A` at the first prompt to accept all, or pass `-Confirm:$false`.

### 4. Deploy

```powershell
# dry run
.\Deploy-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -WhatIf -ReportCsv .\console.csv

# for real
.\Deploy-ConsoleModeMedia.ps1 -Console -GamesRoot O:\games -ReportCsv .\console.csv
```

Read the report before the real run. Two figures matter: how many entries came out as `MISSING`, and how many were matched by a heuristic rather than by the gamelist.

### 5. Let console mode optimise

Console mode generates its own downscaled thumbnails into `media\optimized\`. It does this automatically as you browse systems, or you can trigger it from its own options menu. Nothing to do here — the deploy script has already emptied the stale cache.

### Arcade is the same, with two parameters

```powershell
.\Clean-ConsoleModeMedia.ps1  -Arcade -ArcadeRoot G:\_Arcade -WhatIf
.\Clean-ConsoleModeMedia.ps1  -Arcade -ArcadeRoot G:\_Arcade
.\Deploy-ConsoleModeMedia.ps1 -Arcade -ArcadeRoot G:\_Arcade -WhatIf -ReportCsv .\arcade.csv
.\Deploy-ConsoleModeMedia.ps1 -Arcade -ArcadeRoot G:\_Arcade -ReportCsv .\arcade.csv
```

> **Console and arcade cannot run together.** `-Console` and `-Arcade` belong to mutually exclusive parameter sets, so PowerShell rejects the call at parse time if you pass both, or neither. The two libraries usually live on different drives, and this makes it impossible to hit the wrong one by accident.

---

## Parameter reference

### Deploy-ConsoleModeMedia.ps1

| Parameter | Mode | Required | Default | Description |
|---|---|---|---|---|
| `-Console` | Console | yes | — | Console library mode |
| `-GamesRoot` | Console | yes | — | Folder holding one subfolder per system |
| `-Systems` | Console | no | all | White list, e.g. `-Systems psx,snes` |
| `-Arcade` | Arcade | yes | — | Arcade library mode |
| `-ArcadeRoot` | Arcade | yes | — | The `_Arcade` folder itself |
| `-BoxDir` | both | no | `box2d` | Source for the box art: `box2d` or `box3d` |
| `-ScreenDir` | both | no | `screenshot` | Source for the background: `screenshot` or `titlescreen` |
| `-NoOverwrite` | both | no | off | Incremental: skip games already covered, keep the thumbnail cache |
| `-ReportCsv` | both | no | — | Write a per-ROM report, plus `<name>-orphans.csv` |

`-WhatIf`, `-Confirm`, `-Verbose` and `-Debug` are available on both scripts.

Use `-NoOverwrite` after adding a handful of ROMs: it only writes what is missing, and leaves the cache alone since nothing already on screen has changed.

### Clean-ConsoleModeMedia.ps1

| Parameter | Mode | Required | Default | Description |
|---|---|---|---|---|
| `-Console` | Console | yes | — | Console library mode |
| `-GamesRoot` | Console | yes | — | Folder holding one subfolder per system |
| `-Systems` | Console | no | all | White list |
| `-Arcade` | Arcade | yes | — | Arcade library mode |
| `-ArcadeRoot` | Arcade | yes | — | The `_Arcade` folder itself |
| `-KeepOptimized` | both | no | off | Leave the thumbnail cache in place |
| `-ReportCsv` | both | no | — | Log every deleted file |

The clean script asks for confirmation once **per system**, never per file. It has `ConfirmImpact = 'High'`, so it always asks unless you pass `-Confirm:$false`.

---

## How it works

### Folder layouts

**Console mode.** Sources and output share the system's `media\` folder. Recursive, because multi-disc sets often live in subfolders.

```
<GamesRoot>\<system>\                 ROMs
<GamesRoot>\<system>\gamelist.xml
<GamesRoot>\<system>\media\box2d\     source artwork, never modified
<GamesRoot>\<system>\media\screenshot\
<GamesRoot>\<system>\media\           <-- output
<GamesRoot>\<system>\media\optimized\ frontend cache, emptied
```

**Arcade mode.** Output sits one level **above** `_Arcade`, which is the MiSTer layout. It is derived from `-ArcadeRoot` and printed before anything is written, so check that line on your first run.

```
<ArcadeRoot>\*.mra                    ROMs, recursive
<ArcadeRoot>\_alternatives\           included, regional and hacked variants
<ArcadeRoot>\_Organized\              skipped, duplicates the root set
<ArcadeRoot>\gamelist.xml
<ArcadeRoot>\media\box2d\             source artwork, never modified
<ArcadeRoot>\media\screenshot\
<parent>\media\                       <-- output
<parent>\media\optimized\             frontend cache, emptied
```

### Output naming

The target name is the **ROM base name plus the extension of the source image**. A JPEG source stays a JPEG, because console mode reads both formats and converts on the fly into its own cache. Roughly one arcade box art in eight is a JPEG, so this matters.

If a source switches format between two scrapes, the twin carrying the other extension is deleted before writing, so the frontend can never pick up a stale file.

### The resolution chain

Nine levels, first hit wins. Every match is tagged in the report with the level that produced it, so a heuristic result is always auditable.

| Level | Basis |
|---|---|
| `gamelist` | Explicit path to artwork mapping read from `gamelist.xml`. The source of truth |
| `manual` | Hard-coded exception table, see below |
| `glname` | The title declared in the gamelist, normalised |
| `folder` | Inheritance from a parent folder entry, for multi-disc sets |
| `norm` | Normalised ROM file name |
| `noplus` | Same, with plus signs dropped instead of spelled out |
| `prefix` | ROM key is a unique prefix of an artwork key |
| `rprefix` | An artwork key is a unique prefix of the ROM key |
| `fuzzy` | Normalised without articles |

Two formats of `gamelist.xml` are supported. Classic EmulationStation puts the ROM path and the artwork tags in the same `<game>`. ZapScraper splits them: a canonical entry carrying an `id` holds the title and the artwork, while child entries carrying a `parentid` hold only the ROM path. The tool resolves that join, which is what makes arcade work at all.

Artwork tags are never guessed by name. Any tag whose text points inside a `media` folder and ends with an image extension is considered, then classified by the folder it actually lives in. That survives `boxart2d`, `image`, `thumbnail`, and whatever a future scraper invents.

Normalisation strips region and version tags, rotates a trailing article back to the front, folds accents and superscripts through Unicode compatibility decomposition, then discards case and punctuation. So `Legend of Zelda, The - A Link to the Past (Europe)` and `The Legend of Zelda - A Link to the Past` produce one key, and so do `Bang2 Busters` and the same title spelled with a superscript.

The `prefix` levels require a **unique** match and a minimum key length, which is why `Metal Slug` cannot swallow `Metal Slug X`.

### What is not a ROM

MiSTer keeps support files next to the ROMs: palettes, borders, overlays, BIOS blobs. Left alone they would be counted as games, and the heuristic levels would cheerfully hand them the artwork of the real ROM. The following are excluded: `.pal`, `.gbp`, `.bor`, `.ovr`, `.sgb`, `.jce`, `.jmc`, `.sfix`, `.sp1`, `.lo`, `.drv`, `.inf`, `.exe`, plus BIOS name patterns such as `boot*.rom`, `*bios*.rom` and `Super Game Boy*.sfc`.

A `.bin` or `.img` is treated as a CD track only when a `.cue`, `.gdi`, `.toc` or `.m3u` sits in the same folder. Otherwise it is a real ROM, which is what makes Odyssey², Channel F, Arcadia, VC4000, Astrocade, CreatiVision, MyVision and the Atari 7800 work at all.

---

## Measured results

Real runs, on a curated collection.

### Console

| | |
|---|---|
| Systems | 40 |
| ROMs | 10 883 |
| Box art deployed | 10 829 |
| Backgrounds deployed | 10 831 |
| Not covered | 54 |
| **Coverage** | **99.5 %** |

Of those 10 829 matches, 10 792 came straight from the gamelist. Eight came from the manual table, four from `glname`, and 25 from the heuristic levels. Nothing reached `fuzzy`, and nothing reached `norm`.

### Arcade

| | |
|---|---|
| MRA files | 2 957 |
| Box art deployed | 2 757 |
| Backgrounds deployed | 2 759 |
| Not covered | 200 |
| **Coverage** | **93.2 %** |

Arcade coverage is lower because `_alternatives` is less thoroughly scraped than the root set. Of the 200 misses, 187 have a gamelist entry but no artwork on disk, and 13 are MRA files absent from the gamelist. None is a matching failure.

---

## Customising

### Adding your own exceptions

Some titles cannot be matched by any heuristic, because the ROM name is a suffix, an infix, or shares no word at all with the artwork name. `$ManualMap`, at the top of the deploy script, handles those.

```powershell
$ManualMap = @{
    'NEOGEO|kabukiklash'   = 'Far East of Eden- Kabuki Klash'
    'VC4000|superinv'      = 'Cassette 33 - Super Invaders'
}
```

The key is `"<SystemName>|<normalised ROM key>"`. The system name is the folder name, or `Arcade` in arcade mode. To find the normalised key of a stubborn ROM, run with `-ReportCsv` and read it from the report.

The value is the artwork file name **without extension**, exactly as it sits on disk. The same name is looked up in both source folders.

Entries are consulted after the gamelist, so if a future scrape fixes an entry properly, the gamelist wins and the exception becomes harmless dead weight.

### Reading the report

| Column | Meaning |
|---|---|
| `System` | Folder name, or `Arcade` |
| `Rom` | ROM file name |
| `SubFolder` | Subfolder, when the ROM is not at the system root |
| `GlName` | Title declared in the gamelist, empty if the ROM is absent from it |
| `BoxSource` / `BgSource` | Artwork file that was used |
| `BoxMatch` / `BgMatch` | Resolution level, or `MISSING` |

Sort on `BoxMatch` and review anything tagged `prefix`, `rprefix` or `fuzzy`. A `MISSING` row with a `GlName` filled in means the gamelist knows the game but no artwork was scraped for it, which is a scraping gap, not a tool problem.

The companion `-orphans.csv` lists artwork files that no ROM claimed. On a curated collection that is mostly leftovers from games you removed.

---

## Known limitations

- **Windows only** for now. A Python port able to run from the MiSTer's own `Scripts` folder is the obvious next step, since Python 3 is present on the device.
- **Case sensitivity.** On Windows a mismatch in case between a gamelist path and the real file name is forgiven. On the ext4 volume the MiSTer actually reads, it is not. If a system comes out with unexplained misses, check the case.
- **Flat output.** All artwork lands directly in `media\`, so two ROMs sharing a base name across different subfolders aim at the same target. The script warns when that happens.
- **Duplication.** Regional variants sharing one artwork file each get their own copy. Arcade `_alternatives` alone triples the source volume. Not a problem on ext4, worth knowing on a small card.
- **Normalisation collisions.** Two artwork files can reduce to the same key, for example `Burger Time.png` and `BurgerTime.png`. The script warns; the gamelist usually settles it anyway.

---

## Troubleshooting

**`File is not digitally signed`** — the web mark. Run `Get-ChildItem .\*.ps1 | Unblock-File`.

**`Parameter set cannot be resolved`** — you passed both `-Console` and `-Arcade`, or neither. Pick one.

**The report is empty after a dry run** — it should not be. Both scripts write their CSV even under `-WhatIf`, on purpose, because inspecting the report is the whole point of a dry run.

**A whole system produced nothing** — it has no `media\` folder, so it was skipped. Check with `-Verbose`.

**Old artwork still shows in the frontend** — the thumbnail cache. Run the clean script, or make sure you are not passing `-NoOverwrite`, which preserves it.

**The arcade output went to the wrong place** — the output folder is derived as the parent of `-ArcadeRoot` plus `media`. It is printed at the top of every run. Check that line.

---

## How this was built

This tool was designed, written and refactored in an ongoing dialogue with
Claude, Anthropic's AI assistant. The specification, the real-world testing and
every design decision came from the human side; the code, the gamelist analysis
and the reports came from the collaboration. It went through eight iterations
before this release, and most of them were driven by a test run failing on real
hardware rather than by anything either of us predicted in advance.

Worth saying plainly, because the topic tends to attract dogma: used well, an AI
assistant is a genuine accelerator. It does not replace knowing your own
hardware, reading your own reports, or catching the bug it just wrote — three
things that happened repeatedly here. What it does replace is the fifty hours
this would otherwise have taken. That time went back to my family, which is
reason enough.

## License

MIT. Use it, copy it, change it, ship it, sell it. Just keep the copyright notice.

See [LICENSE](LICENSE).

## Credits

Created by **Rucan** — [@Rucan69](https://github.com/Rucan69).

Built on top of the work of the MiSTer, Zaparoo and MiSTer Companion communities. This tool scrapes nothing and downloads nothing: it only rearranges artwork you already have.
