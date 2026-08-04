# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Python port able to run from the MiSTer's own `Scripts` folder.
- Case insensitive artwork index, for correct behaviour on ext4.
- Relative path in the target collision warning, to tell the arcade root from `_alternatives`.

## [1.0.0] - 2026-08-04

First public release.

### Added

- `Deploy-ConsoleModeMedia.ps1` — copies a Zaparoo artwork scrape into the flat
  `media\` layout the console mode frontend expects, renaming each file after the
  exact ROM name and appending `-BG` to the background.
- `Clean-ConsoleModeMedia.ps1` — removes deployed artwork and empties the
  frontend thumbnail cache.
- Two mutually exclusive parameter sets, `-Console` and `-Arcade`, enforced at
  parameter binding time so the two libraries can never be processed in one run.
- Support for both `gamelist.xml` layouts: classic EmulationStation, and the
  ZapScraper parent and child split where a canonical entry holds the artwork
  while child entries hold the ROM paths.
- Nine level resolution chain: `gamelist`, `manual`, `glname`, `folder`, `norm`,
  `noplus`, `prefix`, `rprefix`, `fuzzy`. Every match is tagged in the report.
- Artwork tag detection by content rather than by tag name, so `boxart2d`,
  `image` and `thumbnail` are all handled without a white list.
- Name normalisation: region and version tags stripped, trailing article rotated
  back to the front, Unicode compatibility decomposition for accents and
  superscripts, case and punctuation discarded.
- `$ManualMap` exception table for titles no heuristic can reach.
- Source extension preserved on the target, so JPEG artwork stays JPEG. The twin
  carrying the other extension is deleted before writing.
- Conditional treatment of `.bin` and `.img`: a CD track only when a `.cue`,
  `.gdi`, `.toc` or `.m3u` sits in the same folder, a real ROM otherwise. This is
  what makes Odyssey², Channel F, Arcadia, VC4000, Astrocade, CreatiVision,
  MyVision and the Atari 7800 work.
- Exclusion of MiSTer support files and BIOS blobs from the ROM inventory.
- `-BoxDir` accepting `box2d` or `box3d`, and `-ScreenDir` accepting `screenshot`
  or `titlescreen`.
- `-NoOverwrite` for incremental runs, which also preserves the thumbnail cache.
- `-ReportCsv`, producing a per-ROM report and a companion orphan artwork list,
  written even under `-WhatIf`.
- Nested progress bars, throttled to one refresh per percent.
- Four safeguards on the clean script: no recursion, two extensions only, refusal
  to act on a folder whose name is not `media`, and a thumbnail cache that is
  emptied but never created nor removed.
- One confirmation per system rather than per file, with `ConfirmImpact = 'High'`.

[Unreleased]: https://github.com/Rucan69/MiSTer-ConsoleMode-EasyMedia/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Rucan69/MiSTer-ConsoleMode-EasyMedia/releases/tag/v1.0.0
