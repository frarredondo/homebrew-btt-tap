# homebrew-btt-tap

A [Homebrew](https://brew.sh) tap for installing **specific, pinned versions of
[BetterTouchTool](https://folivora.ai/)** (BTT) — useful for downgrading to the exact build your
license covered.

> **Note on licensing.** BetterTouchTool is proprietary software, © folivora.ai. This repository
> ships **only Homebrew cask metadata** (version strings, the vendor's own public download URLs, and
> SHA-256 checksums) — no BetterTouchTool binaries are redistributed here. The MIT license in this
> repo covers the cask files and `generate.sh` only, **not** BetterTouchTool itself. A valid BTT
> license is required to use the app beyond its trial.

## Install

```sh
brew tap frarredondo/btt-tap
brew install --cask frarredondo/btt-tap/btt@4.363
```

(After tapping, the short form `brew install --cask btt@4.363` also works.)

To upgrade/downgrade to a different version, see [Add another version](#add-another-version) below.

## Available versions

```sh
ls Casks/                       # versions shipped in this tap
brew search frarredondo/btt-tap/
```

Currently shipped:

| Version | Build  | Cask token                |
| ------- | ------ | ------------------------- |
| 4.363   | 43630  | `btt@4.363`   |

Every version ever published is listed at <https://folivora.ai/releases/>, or run
`./generate.sh --list`.

## Why pin / downgrade a version?

A BetterTouchTool license includes roughly two years of updates. After that window the app keeps
working, but newer builds prompt you to renew. To stay on the **last version your license covered**,
install that exact build from this tap. BTT itself hints at this when it sends you to
`https://folivora.ai/releases/?yourPreviouslyInstalledVersionWas` — that page lists the historical
builds, and this tap turns any of them into a one-line `brew install`.

## Add another version

The included `generate.sh` looks a version up in the live folivora.ai index (so it never guesses a
dead URL), verifies the download exists, reads the app's minimum macOS, hashes the zip, and writes
the cask.

### Interactive (TUI)

Run it with no arguments in a terminal to browse, filter, and **multi-select** versions:

```sh
./generate.sh
```

A pure-bash interactive list (no dependencies) opens — newest first, with each version's release
date and build, and a `*` next to versions already in this tap:

```
 BetterTouchTool - select versions to add   (frarredondo/btt-tap)
 filter: 4.36                         shown 12/2875   marked 2   (* = already a cask)
 [ ] * 4.363     2023-12-23   43630
 [x]   4.362     2023-12-21   43620
 [x]   4.361     2023-12-20   43610
 ...
 j/k up/down  g/G top/bottom  space mark  a mark-all  c clear  enter generate  0-9 filter  q quit
```

| Key | Action |
| --- | --- |
| `j` / `k` (or `↑` / `↓`) | move the cursor |
| `g` / `G` | jump to top / bottom |
| digits and `.` | filter by version (e.g. type `4.36`); `Backspace` edits |
| `space` | mark / unmark the highlighted version |
| `a` / `c` | mark all (currently filtered, not-yet-installed) / clear all marks |
| `Enter` | download + generate casks for all marked versions (or the highlighted one) |
| `q` | quit |

### Non-interactive

```sh
./generate.sh 5.612            # add one specific version
./generate.sh --latest         # add the newest published version
./generate.sh --list           # print every available version (no download)
```

Either way, install the result (and optionally commit + push the new cask to share it):

```sh
brew install --cask ./Casks/btt@5.612.rb
```

## Caveats

- **One version at a time.** Every cask installs the same `/Applications/BetterTouchTool.app`, so the
  versions are mutually exclusive by design. Homebrew will refuse to install a second version over an
  existing one. To switch:

  ```sh
  brew uninstall --cask btt@4.363
  brew install --cask frarredondo/btt-tap/btt@5.612
  # …or force an in-place swap:
  brew install --cask --force frarredondo/btt-tap/btt@5.612
  ```

- **Staying pinned.** The cask sets `auto_updates true` (accurate: BTT can update itself). If you are
  pinning to avoid a newer build, disable automatic updates inside BetterTouchTool's own preferences.

- **Clean removal.** `brew uninstall --zap --cask btt@4.363` also removes BTT's
  preferences, application-support, and cache files.

## License

MIT — see [LICENSE](LICENSE). Applies to this repository's scripts and cask metadata only.
