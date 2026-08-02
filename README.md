# FINAL BROADCAST — Flutter

A Flutter web port of [FINAL BROADCAST](https://jasraajdevz.github.io/final-broadcast/),
a retro horror idle game. You run the night shift at KBLK-7, a station that lost its
licence in 1987 and never quite stopped transmitting.

The original is a single self-contained HTML file — procedural 2D canvas, synthesised
WebAudio, no assets. This is that game rebuilt on `CustomPainter` and `dart:ui`.

```bash
flutter run -d chrome
flutter build web --release --base-href /final-broadcast-flutter/
```

## How it is put together

    lib/src/consts.dart      geometry, colours, and the data tables
                             (10 producers, 12 upgrades, 8 counters, 8 anomalies,
                             the 7-segment run-down, the fake commercials)
    lib/src/state.dart       GameState (ChangeNotifier) + save/load, same
                             localStorage key and JSON shape as the HTML build
    lib/src/economy.dart     signal/subscriber rates, costs, prestige, sabotage hooks
    lib/src/anomalies.dart   the scheduler, banish/jumpscare, the sabotage rules
    lib/src/bake.dart        PictureRecorder -> ui.Image helper + blend-mode helpers
    lib/src/paint/           room, window, tube, faces, entities, feed, booth
    lib/src/ui/              status bar, rack, deck, manual, ad break, end sheet
    lib/src/audio.dart       WebAudio through dart:js_interop, behind an interface

## Notes from the port

**Everything static is baked once.** `PictureRecorder` -> `ui.Image`, then blitted:
the back wall (700x486), the field outside the window (200x664), frost, the eight
256x320 face plates with their rim and subsurface derivations, cloth, noise tiles.

**Blend modes.** Separable ops (`lighter`/`multiply`/`screen`/`soft-light`) are set
per `Paint`, which is what canvas2d actually does per draw. Only the Porter-Duff ops
(`dstIn`/`dstOut`/`srcATop`) get a `saveLayer`, because they need the surface fenced.

**There is no synchronous pixel readback in Flutter.** The HTML called `getImageData`
every frame to bend the CRT raster by row luminance; `Image.toByteData` is async, so
that is driven from game state instead (anomaly progress, tune heat, glitch, dread).

**Fonts.** CanvasKit does not resolve system font families, so `Courier New` silently
becomes Roboto and the whole game renders proportional. Courier Prime (OFL) ships
under the same family name — it is metric-compatible, so every hard-coded layout
number still lands. Box-drawing glyphs were replaced with ASCII, which a 1987
character generator would have used anyway.

## Licence

MIT, except `assets/fonts/` — Courier Prime is OFL, see `LICENSES-fonts.txt`.
