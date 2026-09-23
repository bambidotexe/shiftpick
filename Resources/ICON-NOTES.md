# The icon

Four icons in a grid, three of them selected and the fourth not: a range picked out of a folder, which is
what ShiftPick does. The menu-bar mark is the same drawing at 18 pt.

| File | What it is |
|---|---|
| `AppIcon.icon/` | The Icon Composer document. `actool` compiles it into the `Assets.car` macOS renders with Liquid Glass. **Never hand-edit `icon.json`**; re-export it. |
| `AppIcon.icon/Assets/0_background.png` | The background layer, without glass. |
| `AppIcon.icon/Assets/1_selected 2.svg` | The three selected tiles, at 1024, in overlay. |
| `AppIcon.icon/Assets/2_unselected.svg` | The fourth tile, a ring, at 1024, in overlay. |
| `previews/ShiftPick-preview-1024.png` | The flat 1024 px master `scripts/make-app.sh` rasterises `AppIcon.icns` from, with `sips` and `iconutil`. `actool`'s own `.icns` carries 16 px and 128 px only. |
| `../docs/assets/icon.png` | The master at 256 px, which the README shows. |
| `../Sources/ShiftPickApp/MenuBarController.swift` | The menu-bar mark, `icon()`: the grid drawn in code as a template image, from the numbers of an 18 pt SVG with the same tiles, gaps and corners. |

The accent of the onboarding wizard, `OnboardingWindow.brand`, is the document's fill colour.

## Replacing it

Export over `AppIcon.icon/` from **Icon Composer**, then render the master with Icon Composer's own renderer
and resize a copy for the README:

```sh
ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" Resources/AppIcon.icon --export-image --output-file Resources/previews/ShiftPick-preview-1024.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
sips -z 256 256 Resources/previews/ShiftPick-preview-1024.png --out docs/assets/icon.png
```

If the drawing changes, redraw `MenuBarController.icon()` to match it and set `OnboardingWindow.brand` to
the new fill colour.

`make-app.sh` needs full Xcode for `actool`. With the Command Line Tools alone the app still builds and
still has an icon; it just loses the glass on macOS 26+, and the script says so.
