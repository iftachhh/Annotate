<img src="docs/icon.png" width="128" alt="Annotate icon">

# Annotate

A macOS menu bar app for drawing on top of your screen.

- Press ⌘⌥P to cycle Disabled → Enabled → Interactive. The shortcut can be changed in Settings.
- Tools: pen (P), line (L), arrow (A), highlighter (H), rectangle (R), circle (O), text (T), counter (N), select (V), eraser (E).
- Number keys pick a color; `-` and `=` change the stroke width; ⌘Z undoes, ⌘⇧Z redoes; Esc exits.

## Install

Download the `.dmg` from [Releases](../../releases), open it and drag **Annotate** to **Applications**.

The app isn't notarized, so macOS blocks the first launch. Click **Open Anyway** in
**System Settings → Privacy & Security**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Annotate.app
```

Requires macOS 14 or later.

## Build

```sh
scripts/build-app.sh   # build/Annotate.app
scripts/release.sh     # build/Annotate-<version>.dmg (universal)
```

To publish a release, set the version in `Resources/Info.plist`, run `scripts/release.sh`, then upload the disk image:
`gh release create v1.0 build/Annotate-1.0.dmg --title "Annotate 1.0" --generate-notes`.

## License

Copyright © 2026 Iftach Dafni. All rights reserved.
Fonts in `Resources/Fonts` are under the SIL Open Font License (see the `OFL-*.txt` files).
