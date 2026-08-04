// FINAL BROADCAST — THE BOOTH.
//
// A 1:1 port of the room half of the HTML canvas scene:
//
//   bakeWall()          -> [bakeWallTex]        (WALLTEX, 700x486, baked once)
//   drawRoom(t)         -> [RoomScene.drawRoom]
//   wallPt(u,v)         -> [wallPt]
//   drawWallProps(t)    -> [RoomScene.drawWallProps]
//   drawSmallMonitors(t)-> [RoomScene.drawSmallMonitors]
//   drawDesk(t)         -> [RoomScene.drawDesk]
//   the DUST loop in render() -> [RoomScene.drawDust]
//
// Every coordinate, colour and magic number is the number from index.html.
// Nothing here has been retuned. Where the original is odd, the oddity is
// preserved and flagged with a PORT NOTE.
//
// Canvas2d is a state machine and the HTML leans on that: `lineCap`, `lineWidth`
// and `textAlign` set in one draw function leak into the next. Where a leaked
// value is actually visible the port hard-codes the leaked value and says so.
//
// Portable: dart:ui + package:flutter/rendering.dart. Nothing web-only.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../anomalies.dart';
import '../bake.dart';
import '../consts.dart';
import '../economy.dart';
import '../state.dart';

// ---------------------------------------------------------------------------
// local helpers
// ---------------------------------------------------------------------------

/// `"#rrggbb"` written as an int, opaque.
ui.Color _hex(int rgb) => ui.Color(0xFF000000 | rgb);

double _hypot(double x, double y) => math.sqrt(x * x + y * y);

/// `ctx.beginPath(); moveTo(p0); lineTo(p1..pn); fill()` — canvas2d closes an
/// open subpath implicitly when filling, so this always closes.
void _fillPoly(ui.Canvas g, List<ui.Offset> pts, ui.Paint paint) {
  final p = ui.Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 1; i < pts.length; i++) {
    p.lineTo(pts[i].dx, pts[i].dy);
  }
  p.close();
  g.drawPath(p, paint);
}

/// The HTML's `roundRect(g,x,y,w,h,r)` helper.
ui.RRect _rr(double x, double y, double w, double h, double r) =>
    ui.RRect.fromRectXY(ui.Rect.fromLTWH(x, y, w, h), r, r);

/// `ctx.strokeRect(x,y,w,h)`.
void _strokeRect(
        ui.Canvas g, double x, double y, double w, double h, ui.Paint paint) =>
    g.drawRect(ui.Rect.fromLTWH(x, y, w, h), paint);

/// `ctx.fillRect(x,y,w,h)`.
void _fillRect(
        ui.Canvas g, double x, double y, double w, double h, ui.Paint paint) =>
    g.drawRect(ui.Rect.fromLTWH(x, y, w, h), paint);

/// `ctx.arc(x,y,r,0,TAU); ctx.fill()`.
void _fillCircle(
        ui.Canvas g, double x, double y, double r, ui.Paint paint) =>
    g.drawCircle(ui.Offset(x, y), r, paint);

/// JS `%` — truncated remainder, which keeps the sign of the dividend. Dart's
/// `%` is euclidean and would NOT match once a dust mote's drift goes negative.
double _jsMod(double a, double b) => a.remainder(b);

// ---------------------------------------------------------------------------
// WALLTEX — the back wall, baked once
// ---------------------------------------------------------------------------

/// JS `bakeWall()`.
///
/// "The back wall is baked once: acoustic tile with bevels, water damage,
/// nicotine staining, scuffs and patched-over holes. Per-frame cost is a single
/// drawImage."
///
/// Uses [rand] (Math.random), so every launch gets a different wall — exactly
/// like the original, which baked at script load.
void paintWallTex(ui.Canvas g) {
  const double w = 700; // kWallTexW
  const double h = 486; // kWallTexH
  assert(w == kWallTexW && h == kWallTexH);
  const plate = ui.Rect.fromLTWH(0, 0, w, h);

  // base gradient
  g.drawRect(
    plate,
    ui.Paint()
      ..shader = linear(
        ui.Offset.zero,
        const ui.Offset(0, h),
        <ui.Color>[_hex(0x161c1d), _hex(0x111718), _hex(0x0a0e0f)],
        <double>[0, 0.55, 1],
      ),
  );

  // acoustic tile: face, lit bevel, shadow bevel, right-hand shadow, perfs
  const t = kWallTilePitch; // 34
  final bevelLit = fill(rgba(255, 255, 255, .030));
  final bevelShadow = fill(rgba(0, 0, 0, .34));
  final bevelSide = fill(rgba(0, 0, 0, .22));
  final perf = fill(rgba(0, 0, 0, .30));
  for (double y = 0; y < h; y += t) {
    for (double x = 0; x < w; x += t) {
      final v = (rand() - 0.5) * 0.030;
      _fillRect(g, x + 1, y + 1, t - 2, t - 2,
          fill(rgba(255, 255, 255, math.max(0, 0.012 + v))));
      _fillRect(g, x + 1, y + 1, t - 2, 1, bevelLit);
      _fillRect(g, x + 1, y + t - 2, t - 2, 1, bevelShadow);
      _fillRect(g, x + t - 2, y + 1, 1, t - 2, bevelSide);
      if (rand() < 0.16) {
        for (var k = 0; k < 5; k++) {
          _fillRect(g, x + 5 + rand() * (t - 12), y + 5 + rand() * (t - 12),
              1.5, 1.5, perf);
        }
      }
    }
  }

  // water damage bleeding down from the ceiling line
  for (var i = 0; i < 5; i++) {
    final x = rand() * w, wdt = 40 + rand() * 90, hh = 50 + rand() * 140;
    final path = ui.Path()
      ..moveTo(x, 0)
      ..cubicTo(x - wdt * 0.6, hh * 0.4, x + wdt * 0.5, hh * 0.7,
          x + (rand() - 0.5) * 30, hh)
      ..cubicTo(x + wdt * 0.6, hh * 0.6, x + wdt * 0.7, hh * 0.3, x + wdt, 0)
      ..close();
    g.drawPath(
      path,
      ui.Paint()
        ..shader = linear(
          ui.Offset.zero,
          ui.Offset(0, hh),
          <ui.Color>[
            rgba(96, 80, 44, .16),
            rgba(80, 66, 38, .07),
            rgba(80, 66, 38, 0),
          ],
          <double>[0, 0.7, 1],
        ),
    );
  }

  // nicotine gradient — the room smoked for four decades
  g.drawRect(
    plate,
    ui.Paint()
      ..shader = linear(
        ui.Offset.zero,
        const ui.Offset(0, h),
        <ui.Color>[rgba(120, 96, 48, .10), rgba(120, 96, 48, 0)],
        <double>[0, 1],
      ),
  );

  // scuffs and gouges at hand height
  for (var i = 0; i < 40; i++) {
    final x = rand() * w, y = h * 0.45 + rand() * h * 0.5;
    g.drawLine(
      ui.Offset(x, y),
      ui.Offset(x + (rand() - 0.5) * 44, y + (rand() - 0.5) * 10),
      stroke(rgba(0, 0, 0, 0.10 + rand() * 0.18), 0.6 + rand() * 1.4),
    );
  }
  // patched holes
  final holeDark = fill(rgba(0, 0, 0, .42));
  final holeLit = fill(rgba(190, 200, 195, .05));
  for (var i = 0; i < 14; i++) {
    final x = rand() * w, y = rand() * h, r = 2 + rand() * 4;
    _fillCircle(g, x, y, r, holeDark);
    _fillCircle(g, x - 0.6, y - 0.6, r * 0.7, holeLit);
  }

  // grime settling into the bottom corners
  g.drawRect(
    plate,
    ui.Paint()
      ..shader = radialR0(
        const ui.Offset(w * 0.5, h * 1.05),
        h * 0.2,
        h * 0.95,
        <ui.Color>[rgba(0, 0, 0, .34), rgba(0, 0, 0, 0)],
        <double>[0, 1],
      ),
  );
}

/// Rasterises [paintWallTex] into the 700x486 plate the room blits every frame.
Future<ui.Image> bakeWallTex() =>
    bakeImage(kWallTexW, kWallTexH, paintWallTex);

// ---------------------------------------------------------------------------
// noise tiles — 8 x 180x135 grayscale
// ---------------------------------------------------------------------------
//
// The HTML bakes these once at the top of the CANVAS SCENE section and shares
// them between the small monitors, the room grain and the anomaly drawers. If
// the frame owner already has them, hand them to [RoomScene.initRoom]; if not,
// the scene bakes its own set so it works standalone.

Future<ui.Image> _bakeNoiseTile(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < px.length; i += 4) {
    final v = (rand() * 255).floor();
    px[i] = v;
    px[i + 1] = v;
    px[i + 2] = v;
    px[i + 3] = 255;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// JS `noiseTiles` — 8 tiles of [kNoiseTileW] x [kNoiseTileH] white noise.
Future<List<ui.Image>> bakeNoiseTiles() async {
  final out = <ui.Image>[];
  for (var k = 0; k < kNoiseTileCount; k++) {
    out.add(await _bakeNoiseTile(kNoiseTileW, kNoiseTileH));
  }
  return out;
}

// ---------------------------------------------------------------------------
// wallPt — the left-wall perspective mapping
// ---------------------------------------------------------------------------

/// JS `wallPt(u,v)`. `u` is depth (0 = screen edge, 1 = back wall), `v` is
/// height (0 = ceiling line, 1 = floor line).
///
/// PORT NOTE: `tx` and `bx` are computed identically in the original, so the
/// horizontal lerp by `v` is a no-op. Transcribed as written.
ui.Offset wallPt(double u, double v) {
  final tx = lerpD(0, kWall.left, u), ty = lerpD(0, kWall.top, u);
  final bx = lerpD(0, kWall.left, u), by = lerpD(kRoom.height, kWall.bottom, u);
  return ui.Offset(lerpD(tx, bx, v), lerpD(ty, by, v));
}

// ---------------------------------------------------------------------------
// DUST
// ---------------------------------------------------------------------------

/// One mote of the 70 in JS `DUST`.
class DustMote {
  DustMote()
      : x = rand(),
        y = rand(),
        s = 0.5 + rand() * 1.4,
        vx = (rand() - 0.5) * 0.008,
        vy = -0.004 - rand() * 0.010,
        ph = rand() * tau;
  final double x, y, s, vx, vy, ph;
}

// ---------------------------------------------------------------------------
// the scene
// ---------------------------------------------------------------------------

/// The booth: walls, wall props, the two security monitors and the desk.
///
/// Draws in CABINET coordinates — the caller has already scaled 1280x720 to fit
/// and clipped to [kRoom]. Nothing here paints UI; the status bar, rack and deck
/// are real widgets stacked over the CustomPaint.
class RoomScene {
  RoomScene(this.runtime)
      : dust = List<DustMote>.generate(kDustCount, (_) => DustMote());

  final AnomalyRuntime runtime;
  GameState get s => runtime.s;

  /// JS `DUST`.
  final List<DustMote> dust;

  ui.Image? _wallTex;
  List<ui.Image> _noise = const <ui.Image>[];
  bool _ownsNoise = false;

  /// True once [initRoom] has finished baking WALLTEX.
  bool get ready => _wallTex != null;

  /// The baked back wall, or null before [initRoom] completes.
  ui.Image? get wallTex => _wallTex;

  /// The shared noise tiles this scene is using.
  List<ui.Image> get noiseTiles => _noise;

  /// Bakes WALLTEX. Pass [noiseTiles] if the frame owner already baked the
  /// shared set; otherwise the scene bakes its own (and disposes them).
  ///
  /// Both bakes complete on the engine's own queue, so inside `testWidgets`
  /// this must be awaited from `tester.runAsync(...)`; the FakeAsync clock will
  /// never resolve it. A plain `test()` with `TestWidgetsFlutterBinding
  /// .ensureInitialized()` works directly.
  ///
  /// Drawing before this resolves is safe — the wall image is simply skipped
  /// and the monitors show no grain.
  Future<void> initRoom({List<ui.Image>? noiseTiles}) async {
    _wallTex ??= await bakeWallTex();
    if (noiseTiles != null) {
      _noise = noiseTiles;
      _ownsNoise = false;
    } else if (_noise.isEmpty) {
      _noise = await bakeNoiseTiles();
      _ownsNoise = true;
    }
  }

  /// Adopt an externally owned noise set after construction.
  void useNoiseTiles(List<ui.Image> tiles) {
    if (_ownsNoise) {
      for (final img in _noise) {
        img.dispose();
      }
    }
    _noise = tiles;
    _ownsNoise = false;
  }

  void dispose() {
    _wallTex?.dispose();
    _wallTex = null;
    if (_ownsNoise) {
      for (final img in _noise) {
        img.dispose();
      }
    }
    _noise = const <ui.Image>[];
  }

  /// Everything this file owns, in the order render() calls it. The tube, the
  /// window and the room-wide tints are somebody else's; interleave as needed.
  void drawAll(ui.Canvas g, double t) {
    drawRoom(g, t);
    drawSmallMonitors(g, t);
    drawDesk(g, t);
    drawDust(g, t);
  }

  // -------------------------------------------------------------------------
  // drawRoom
  // -------------------------------------------------------------------------

  static final ui.Paint _floorPaint = fill(_hex(0x0a0d0e));
  static final ui.Paint _ceilPaint = fill(_hex(0x080a0b));
  static final ui.Paint _leftWallPaint = fill(_hex(0x0c1011));
  static final ui.Paint _rightWallPaint = fill(_hex(0x070a0b));
  static final ui.Paint _gridPaint = stroke(rgba(120, 180, 170, .05), 1);
  static final ui.Paint _cornerPaint = stroke(rgba(255, 255, 255, .05), 1);

  /// JS `drawRoom(t)`.
  void drawRoom(ui.Canvas g, double t) {
    const l = 0.0, tp = 0.0;
    final r = kRoom.width, b = kRoom.height;
    const w = kWall;

    // PORT NOTE: the original opens with `g.fillStyle="#05070700"` — an
    // eight-digit hex with zero alpha that is never used. Dropped; it is a dead
    // assignment, not a draw.

    // floor
    _fillPoly(g, <ui.Offset>[
      ui.Offset(l, b),
      ui.Offset(r, b),
      ui.Offset(w.right, w.bottom),
      ui.Offset(w.left, w.bottom),
    ], _floorPaint);
    // ceiling
    _fillPoly(g, <ui.Offset>[
      const ui.Offset(l, tp),
      ui.Offset(r, tp),
      ui.Offset(w.right, w.top),
      ui.Offset(w.left, w.top),
    ], _ceilPaint);
    // left / right walls
    _fillPoly(g, <ui.Offset>[
      const ui.Offset(l, tp),
      ui.Offset(w.left, w.top),
      ui.Offset(w.left, w.bottom),
      ui.Offset(l, b),
    ], _leftWallPaint);
    _fillPoly(g, <ui.Offset>[
      ui.Offset(r, tp),
      ui.Offset(w.right, w.top),
      ui.Offset(w.right, w.bottom),
      ui.Offset(r, b),
    ], _rightWallPaint);

    // back wall — forty years of acoustic tile, baked once
    final wt = _wallTex;
    if (wt != null) drawImageStretch(g, wt, w, nearestPaint());

    // floor grid receding
    for (var i = 1; i < 10; i++) {
      final p = i / 10;
      g.drawLine(
        ui.Offset(lerpD(l, w.left, p), lerpD(b, w.bottom, p)),
        ui.Offset(lerpD(r, w.right, p), lerpD(b, w.bottom, p)),
        _gridPaint,
      );
    }
    // corner edges
    _strokeRect(g, w.left + .5, w.top + .5, w.width, w.height, _cornerPaint);

    drawWallProps(g, t);

    // flickering ceiling tube
    final fl = (math.sin(t * 13) * 0.5 + 0.5) * (rand() < 0.03 ? 0.25 : 1);
    _fillPoly(
      g,
      const <ui.Offset>[
        ui.Offset(300, 0),
        ui.Offset(640, 0),
        ui.Offset(560, 300),
        ui.Offset(380, 300),
      ],
      ui.Paint()
        ..shader = linear(
          ui.Offset(kRoom.width / 2, 0),
          ui.Offset(kRoom.width / 2, 300),
          <ui.Color>[
            rgba(180, 220, 230, 0.05 * fl),
            rgba(180, 220, 230, 0),
          ],
          <double>[0, 1],
        ),
    );
    _fillRect(g, 392, 4, 156, 7, fill(rgba(200, 235, 240, 0.16 * fl)));
  }

  // -------------------------------------------------------------------------
  // drawWallProps
  // -------------------------------------------------------------------------

  static final ui.Paint _doorFill = fill(_hex(0x05080a));
  static final ui.Paint _doorEdge = stroke(rgba(160, 190, 190, .10), 2);
  static final ui.Paint _gapDark = fill(rgba(30, 6, 6, .95));
  static final ui.Paint _gapBlack = fill(rgba(0, 0, 0, .95));
  static final ui.Paint _handle = fill(rgba(200, 220, 215, .14));
  // lineCap = "round" is set here in the original and never unset.
  static final ui.Paint _cablePaint =
      stroke(rgba(0, 0, 0, .55), 3, cap: ui.StrokeCap.round);
  static final ui.Paint _panelFill = fill(_hex(0x0d1113));
  static final ui.Paint _panelEdge =
      stroke(_hex(0x222b2d), 1, cap: ui.StrokeCap.round);
  static final ui.Paint _jackDark = fill(_hex(0x05080a));
  static final ui.Paint _jackLit = fill(rgba(255, 180, 90, .5));
  static final ui.Paint _clockFace = fill(_hex(0x0b0f10));
  static final ui.Paint _clockEdge =
      stroke(_hex(0x2a3436), 2, cap: ui.StrokeCap.round);
  static final ui.Paint _clockTick = fill(rgba(180, 210, 205, .35));
  static final ui.Paint _minuteHand =
      stroke(rgba(200, 225, 220, .55), 2, cap: ui.StrokeCap.round);
  static final ui.Paint _secondHand =
      stroke(rgba(255, 90, 70, .8), 1, cap: ui.StrokeCap.round);
  static final ui.Paint _shelfFill = fill(_hex(0x0c1011));
  // PORT NOTE: lineWidth is still 2 here, left over from the ON AIR box stroke.
  static final ui.Paint _shelfEdge =
      stroke(_hex(0x222b2d), 2, cap: ui.StrokeCap.round);
  static final ui.Paint _spineLit = fill(rgba(200, 220, 215, .10));

  static final TextStyle _onAirHotStyle =
      mono(17, _hex(0xff5a46), weight: FontWeight.bold);
  static final TextStyle _onAirLiveStyle =
      mono(17, _hex(0xffbe6e), weight: FontWeight.bold);

  /// JS `drawWallProps(t)` — the left-wall door in perspective and the fittings
  /// band under the main monitor.
  void drawWallProps(ui.Canvas g, double t) {
    const w = kWall;

    // ---- the door in the left wall ----
    final d = <ui.Offset>[
      wallPt(0.34, 0.20),
      wallPt(0.70, 0.26),
      wallPt(0.70, 0.90),
      wallPt(0.34, 0.94),
    ];
    _fillPoly(g, d, _doorFill);
    final doorPath = ui.Path()..moveTo(d[0].dx, d[0].dy);
    for (var i = 1; i < 4; i++) {
      doorPath.lineTo(d[i].dx, d[i].dy);
    }
    doorPath.close();
    g.drawPath(doorPath, _doorEdge);

    // it is never quite shut
    final gap = <ui.Offset>[
      wallPt(0.62, 0.27),
      wallPt(0.70, 0.26),
      wallPt(0.70, 0.90),
      wallPt(0.62, 0.92),
    ];
    final dark = runtime.warn > 0 || s.dread > 55;
    _fillPoly(g, gap, dark ? _gapDark : _gapBlack);
    if (dark) {
      // two points of light in the gap, and they are at head height
      final e = wallPt(0.665, 0.44);
      final eyes = fill(rgba(255, 190, 180, 0.45 + math.sin(t * 3) * 0.25));
      _fillRect(g, e.dx - 3, e.dy, 2, 3, eyes);
      _fillRect(g, e.dx + 2, e.dy + 1, 2, 3, eyes);
    }
    final hp = wallPt(0.655, 0.60);
    _fillRect(g, hp.dx - 3, hp.dy, 5, 3, _handle);

    // ---- cable runs from the ceiling down behind the desk ----
    for (var i = 0; i < 5; i++) {
      final cx = w.left + 40 + i * 168, sag = 16 + i * 4;
      g.drawPath(
        ui.Path()
          ..moveTo(cx, w.top)
          ..cubicTo(cx + 10, w.top + 30 + sag, cx - 14, w.top + 52, cx - 6,
              w.top + 92),
        _cablePaint,
      );
    }

    // ---- fittings band under the main monitor ----
    const by = 470.0;

    // patch panel
    final panel = _rr(w.left + 34, by, 232, 52, 3);
    g.drawRRect(panel, _panelFill);
    g.drawRRect(panel, _panelEdge);
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 12; c++) {
        final jx = w.left + 50 + c * 18, jy = by + 16 + r * 22;
        _fillCircle(g, jx, jy, 4.2, _jackDark);
        if ((c * 3 + r * 7) % 5 == 0) {
          _fillCircle(g, jx, jy, 2, _jackLit);
        }
      }
    }

    // studio clock — hands actually run on airtime
    final cx = w.left + 318, cy = by + 26;
    _fillCircle(g, cx, cy, 23, _clockFace);
    g.drawCircle(ui.Offset(cx, cy), 23, _clockEdge);
    for (var i = 0; i < 12; i++) {
      final a = i * tau / 12;
      _fillRect(g, cx + math.cos(a) * 18 - 1, cy + math.sin(a) * 18 - 1, 2, 2,
          _clockTick);
    }
    final sec = (s.airtime % 60) / 60 * tau - math.pi / 2;
    final min = (s.airtime % 3600) / 3600 * tau - math.pi / 2;
    g.drawLine(ui.Offset(cx, cy),
        ui.Offset(cx + math.cos(min) * 13, cy + math.sin(min) * 13), _minuteHand);
    g.drawLine(ui.Offset(cx, cy),
        ui.Offset(cx + math.cos(sec) * 18, cy + math.sin(sec) * 18), _secondHand);

    // ON AIR wall lamp
    final live = !runtime.lost;
    final hot = runtime.active != null;
    final lampBox = _rr(w.left + 368, by + 2, 152, 46, 4);
    g.drawRRect(
      lampBox,
      fill(hot
          ? _hex(0x2a0806)
          : live
              ? _hex(0x1a0d06)
              : _hex(0x0c0e0f)),
    );
    g.drawRRect(
      lampBox,
      stroke(
        hot
            ? _hex(0x7a2018)
            : live
                ? _hex(0x4a3a18)
                : _hex(0x222b2d),
        2,
        cap: ui.StrokeCap.round,
      ),
    );
    final lampA = hot
        ? (0.7 + math.sin(t * 9) * 0.3)
        : live
            ? 0.5
            : 0.12;
    // The label colour carries the (continuously varying) lamp alpha in the
    // original. Applying it as a layer alpha instead keeps the TextStyle — and
    // therefore the TextPainter cache key — constant.
    groupLayer(
      g,
      ui.Rect.fromLTWH(w.left + 360, by - 4, 168, 56),
      (c) => fillText(c, hot ? 'INTRUSION' : 'ON AIR',
          ui.Offset(w.left + 444, by + 31), hot ? _onAirHotStyle : _onAirLiveStyle,
          anchor: TextAnchor.center),
      alpha: clampD(lampA, 0, 1),
    );
    if (live) {
      final glow = ui.Rect.fromLTWH(w.left + 280, by - 110, 340, 220);
      withBlend(g, glow, ui.BlendMode.plus, (c) {
        c.drawRect(
          glow,
          ui.Paint()
            ..shader = radialR0(
              ui.Offset(w.left + 444, by + 25),
              4,
              150,
              <ui.Color>[
                hot ? rgba(255, 60, 40, .22) : rgba(255, 160, 60, .10),
                hot ? rgba(255, 60, 40, 0) : rgba(255, 160, 60, 0),
              ],
              <double>[0, 1],
            ),
        );
      });
    }

    // tape shelf
    _fillRect(g, w.left + 548, by, 118, 52, _shelfFill);
    // PORT NOTE: the half-pixel offset with a 2px pen is in the original.
    _strokeRect(g, w.left + 548.5, by + .5, 118, 52, _shelfEdge);
    for (var i = 0; i < 9; i++) {
      final sx = w.left + 553 + i * 12;
      _fillRect(g, sx, by + 6, 9, 40,
          fill(i % 3 == 0 ? _hex(0x1c2426) : _hex(0x141a1b)));
      _fillRect(g, sx, by + 11, 9, 2, _spineLit);
    }
  }

  // -------------------------------------------------------------------------
  // drawSmallMonitors
  // -------------------------------------------------------------------------

  /// JS `feeds` — four labels for two monitors. See the PORT NOTE below.
  static const List<String> feedNames = <String>[
    'CAM 1 — HALLWAY',
    'CAM 2 — MAST',
    'CAM 3 — STUDIO B',
    'CAM 4 — VAULT',
  ];

  static final ui.Paint _monBody = fill(_hex(0x0b0e0f));
  static final ui.Paint _monEdge =
      stroke(_hex(0x1d2628), 1, cap: ui.StrokeCap.round);
  static final ui.Paint _monBlack = fill(_hex(0x040807));
  static final ui.Paint _monScan = fill(rgba(0, 0, 0, .3));
  static final ui.Paint _monSil = fill(rgba(0, 0, 0, .94));
  static final TextStyle _monLabelHot = mono(10, rgba(255, 140, 130, .95));
  static final TextStyle _monLabelCold = mono(10, rgba(150, 190, 185, .75));

  /// JS `drawSmallMonitors(t)` — the security cams to the left of the tube.
  ///
  /// PORT NOTE: `feeds` has four entries and the original has drawing branches
  /// for `i === 2` and `i === 3`, but `SIDE` (here [kSide]) only holds two
  /// monitors. CAM 3 and CAM 4 never render. Both branches are transcribed so
  /// the port stays line-for-line, and both are unreachable here too.
  void drawSmallMonitors(ui.Canvas g, double t) {
    const sw = kSideW, sh = kSideH;
    for (var i = 0; i < kSide.length; i++) {
      final m = kSide[i];
      final shell = _rr(m.dx - 5, m.dy - 5, sw + 10, sh + 16, 4);
      g.drawRRect(shell, _monBody);
      g.drawRRect(shell, _monEdge);

      g.save();
      g.clipRect(ui.Rect.fromLTWH(m.dx, m.dy, sw, sh));
      _fillRect(g, m.dx, m.dy, sw, sh, _monBlack);

      final warnHot = runtime.warn > 0 || runtime.active != null;
      // lineCap is still "round" here, leaked from the cable runs.
      final art = stroke(rgba(144, 162, 180, warnHot ? 0.35 : 0.22), 1,
          cap: ui.StrokeCap.round);

      if (i == 0) {
        g.drawPath(
          ui.Path()
            ..moveTo(m.dx, m.dy + sh)
            ..lineTo(m.dx + 38, m.dy + 26)
            ..lineTo(m.dx + 58, m.dy + 26)
            ..lineTo(m.dx + sw, m.dy + sh),
          art,
        );
      }
      if (i == 1) {
        final p = ui.Path()
          ..moveTo(m.dx + sw / 2, m.dy + 6)
          ..lineTo(m.dx + sw / 2 - 16, m.dy + sh)
          ..moveTo(m.dx + sw / 2, m.dy + 6)
          ..lineTo(m.dx + sw / 2 + 16, m.dy + sh);
        for (double y = 16; y < sh; y += 12) {
          final st = (y / sh) * 16;
          p
            ..moveTo(m.dx + sw / 2 - st, m.dy + y)
            ..lineTo(m.dx + sw / 2 + st, m.dy + y);
        }
        g.drawPath(p, art);
        _fillRect(g, m.dx + sw / 2 - 1, m.dy + 4, 3, 3,
            fill(rgba(255, 60, 40, 0.4 + math.sin(t * 3) * 0.4)));
      }
      if (i == 2) {
        _strokeRect(g, m.dx + 14, m.dy + 30, sw - 28, sh - 42, art);
        g.drawLine(ui.Offset(m.dx + 8, m.dy + 22),
            ui.Offset(m.dx + sw - 8, m.dy + 22), art);
      }
      if (i == 3) {
        for (var k = 0; k < 4; k++) {
          _strokeRect(g, m.dx + 8 + k * 20, m.dy + 14, 14, sh - 26, art);
        }
      }

      // THIS ROOM, ON A CAMERA THAT DOES NOT EXIST.
      //
      // The back of an operator's chair, a desk, the glow of a CRT — the shot
      // the player is sitting in. And somebody in the chair. It turns, slowly,
      // for as long as the feed lasts, and it never finishes turning.
      if (runtime.mirrorCam == i) {
        final double q = runtime.mirrorTurn;
        _fillRect(g, m.dx, m.dy + sh * 0.62, sw, sh * 0.38,
            fill(rgba(16, 22, 24, 0.9))); // the desk
        // the tube's glow, from behind
        g.drawOval(
          ui.Rect.fromCenter(
              center: ui.Offset(m.dx + sw * 0.5, m.dy + sh * 0.46),
              width: sw * 0.62,
              height: sh * 0.30),
          fill(rgba(72, 81, 90, 0.35)),
        );
        // the chair back
        _fillRect(g, m.dx + sw * 0.30, m.dy + sh * 0.44, sw * 0.40, sh * 0.34,
            fill(rgba(6, 8, 9, 0.95)));
        // and whoever is in it — head above the chair, turning
        final double hx = m.dx + sw * 0.5 + q * sw * 0.055;
        g.drawOval(
          ui.Rect.fromCenter(
              center: ui.Offset(hx, m.dy + sh * 0.40),
              width: 20 + q * 5,
              height: 24),
          fill(rgba(3, 4, 5, 0.97)),
        );
        // once it is far enough round, an eye catches the light
        if (q > 0.42) {
          final double e = ((q - 0.42) / 0.43).clamp(0.0, 1.0);
          _fillRect(g, hx + 3 + q * 3, m.dy + sh * 0.385, 2.5, 1.8,
              fill(rgba(255, 240, 225, 0.35 + e * 0.6)));
        }
      }

      // THE SCAR. A jumpscare leaves one of the corridor cameras occupied for
      // the rest of the night. It does not move, it is never mentioned, and
      // nothing in the UI acknowledges it — you are supposed to notice on your
      // own, later, that someone has been standing there for twenty minutes.
      if (runtime.ghostCam == i && runtime.warn <= 0) {
        final double gy = m.dy + sh - 6;
        bodySil(g, m.dx + sw * 0.5, gy, 0.62, _monSil);
        final ui.Paint eyes = ui.Paint()..color = rgba(255, 236, 210, 0.55);
        final double ey = gy - 64 * 0.62;
        _fillRect(g, m.dx + sw * 0.5 - 5, ey, 3, 2, eyes);
        _fillRect(g, m.dx + sw * 0.5 + 2, ey, 3, 2, eyes);
      }

      // --- THE THING IN THE HALLWAY ---
      //
      // This used to be `i == (t * 3).toInt() % kSide.length`: the figure
      // teleported between all four cameras three times a second, which the
      // eye reads as screen noise and dismisses. It is now in ONE camera, the
      // same one for the whole telegraph, and it does not move — it just
      // gets closer, and its eyes come up, and then it is on the tube.
      //
      // Stillness is the whole effect. Nothing here is allowed to jitter.
      if (runtime.warn > 0 && i == runtime.warnCam) {
        final double p = runtime.warnP;
        final double gy = m.dy + sh - 6;
        // 0.34 at the far end of the hall to 0.92 filling the frame
        final double sc = 0.34 + p * 0.58;
        // it walks up the frame as it approaches, so perspective reads
        final double y = gy - (1 - p) * sh * 0.16;
        bodySil(g, m.dx + sw / 2, y, sc, _monSil);
        // the eyes only open in the last third. Before that it is a shape;
        // after that it is looking at the camera.
        if (p > 0.62) {
          final double eo = ((p - 0.62) / 0.38).clamp(0.0, 1.0);
          final ui.Paint eyes = ui.Paint()
            ..color = rgba(255, 236, 210, 0.25 + eo * 0.75);
          final double ey = y - 64 * sc;
          _fillRect(g, m.dx + sw / 2 - 5 * sc, ey, 3 * sc + 1, 2 * sc + 1, eyes);
          _fillRect(g, m.dx + sw / 2 + 2 * sc, ey, 3 * sc + 1, 2 * sc + 1, eyes);
        }
      }

      if (_noise.isNotEmpty) {
        final tile = _noise[(t * 20 + i * 3).toInt() % _noise.length];
        drawImageStretch(g, tile, ui.Rect.fromLTWH(m.dx, m.dy, sw, sh),
            nearestPaint(alpha: warnHot ? 0.22 : 0.10));
      }
      for (double y = 0; y < sh; y += 2) {
        _fillRect(g, m.dx, m.dy + y, sw, 1, _monScan);
      }
      g.restore();

      fillText(g, feedNames[i], ui.Offset(m.dx, m.dy + sh + 11),
          warnHot ? _monLabelHot : _monLabelCold);
    }
  }

  /// JS `bodySil(g,x,y,s,col)` — generic standing figure; `y` is the ground
  /// line. Kept public because it is the only figure primitive in the file.
  static void bodySil(
      ui.Canvas g, double x, double y, double sc, ui.Paint paint) {
    // head
    g.drawOval(
      ui.Rect.fromCenter(
          center: ui.Offset(x, y - 64 * sc), width: 22 * sc, height: 26 * sc),
      paint,
    );
    // torso
    _fillPoly(g, <ui.Offset>[
      ui.Offset(x - 15 * sc, y - 14 * sc),
      ui.Offset(x - 11 * sc, y - 50 * sc),
      ui.Offset(x + 11 * sc, y - 50 * sc),
      ui.Offset(x + 15 * sc, y - 14 * sc),
    ], paint);
    // legs
    _fillRect(g, x - 12 * sc, y - 16 * sc, 8 * sc, 16 * sc, paint);
    _fillRect(g, x + 4 * sc, y - 16 * sc, 8 * sc, 16 * sc, paint);
    // arms
    _fillRect(g, x - 20 * sc, y - 46 * sc, 6 * sc, 26 * sc, paint);
    _fillRect(g, x + 14 * sc, y - 46 * sc, 6 * sc, 26 * sc, paint);
  }

  // -------------------------------------------------------------------------
  // drawDesk
  // -------------------------------------------------------------------------

  static final ui.Paint _deskLip = stroke(rgba(255, 255, 255, .06), 1);
  static final ui.Paint _vuBody = fill(_hex(0x0d1112));
  // PORT NOTE: lineWidth is 1 here — the last value drawMainCRT leaves behind.
  static final ui.Paint _vuEdge =
      stroke(_hex(0x28312f), 1, cap: ui.StrokeCap.round);
  static final ui.Paint _vuArc =
      stroke(rgba(255, 200, 120, .25), 1, cap: ui.StrokeCap.round);
  static final ui.Paint _needleHot =
      stroke(_hex(0xff5b50), 1.6, cap: ui.StrokeCap.round);
  static final ui.Paint _needleCold =
      stroke(_hex(0xffcc88), 1.6, cap: ui.StrokeCap.round);
  static final ui.Paint _reelRim =
      stroke(rgba(180, 210, 205, .35), 1.4, cap: ui.StrokeCap.round);
  static final ui.Paint _reelHub = fill(_hex(0x1a2122));
  static final TextStyle _vuLabel = mono(7, rgba(150, 180, 175, .4));

  /// JS `drawDesk(t)` — the foreground desk, the two VU meters that track
  /// [sigRate], and the reel-to-reel that spins faster during an intrusion.
  void drawDesk(ui.Canvas g, double t) {
    const dy = 534.0;

    // desk surface (foreground)
    _fillPoly(
      g,
      <ui.Offset>[
        ui.Offset(kWall.left - 30, dy),
        ui.Offset(kWall.right + 30, dy),
        ui.Offset(kRoom.width + 40, 720),
        const ui.Offset(-40, 720),
      ],
      ui.Paint()
        ..shader = linear(
          const ui.Offset(0, dy),
          const ui.Offset(0, 720),
          <ui.Color>[_hex(0x171d1e), _hex(0x232b2d), _hex(0x0b0e0f)],
          <double>[0, 0.16, 1],
        ),
    );
    g.drawLine(ui.Offset(kWall.left - 30, dy + .5),
        ui.Offset(kWall.right + 30, dy + .5), _deskLip);

    // VU meters on the desk lip
    final rate = sigRate(s, runtime);
    final rel = clampD(math.log(1 + rate) / math.ln10 / 7, 0, 1);
    for (var i = 0; i < 2; i++) {
      final vx = 40 + i * 112.0, vy = 548.0, vw = 96.0, vh = 44.0;
      final box = _rr(vx, vy, vw, vh, 3);
      g.drawRRect(box, _vuBody);
      g.drawRRect(box, _vuEdge);

      g.save();
      g.translate(vx + vw / 2, vy + vh - 6);
      g.drawArc(ui.Rect.fromCircle(center: ui.Offset.zero, radius: 30),
          math.pi * 1.15, math.pi * 0.7, false, _vuArc);
      final v = clampD(
          rel +
              math.sin(t * (7 + i * 3)) * 0.08 +
              (runtime.active != null ? 0.25 : 0),
          0,
          1);
      final ang = math.pi * 1.15 + v * (math.pi * 0.7);
      g.drawLine(
        ui.Offset.zero,
        ui.Offset(math.cos(ang) * 28, math.sin(ang) * 28),
        v > 0.82 ? _needleHot : _needleCold,
      );
      g.restore();

      fillText(g, i != 0 ? 'AUDIO' : 'CARRIER',
          ui.Offset(vx + vw / 2, vy + 11), _vuLabel,
          anchor: TextAnchor.center);
    }

    // reel-to-reel
    g.save();
    g.translate(790, 572);
    final deck = _rr(-84, -24, 168, 52, 4);
    g.drawRRect(deck, _vuBody);
    g.drawRRect(deck, _vuEdge);
    for (var i = 0; i < 2; i++) {
      final rx = -40 + i * 80.0;
      final spin =
          t * (runtime.active != null ? 5 : 1.6) * (i != 0 ? -1 : 1);
      g.save();
      g.translate(rx, 2);
      g.rotate(spin);
      g.drawCircle(ui.Offset.zero, 17, _reelRim);
      for (var k = 0; k < 3; k++) {
        g.rotate(tau / 3);
        g.drawLine(ui.Offset.zero, const ui.Offset(0, -15), _reelRim);
      }
      g.restore();
      _fillCircle(g, rx, 2, 4, _reelHub);
    }
    g.restore();
  }

  // -------------------------------------------------------------------------
  // DUST
  // -------------------------------------------------------------------------

  final ui.Paint _dustPaint = ui.Paint();

  /// The DUST loop out of JS `render(t)`.
  ///
  /// "dust in the air — lit only by the tube, so it reads as volume in front of
  /// the glow". Composited with `lighter`.
  ///
  /// PORT NOTE: uses JS-truncated modulo. Once a mote's horizontal drift carries
  /// `d.x + d.vx*t + 2` below zero (roughly ten minutes of airtime for the
  /// fastest leftward motes) the original wraps it to a NEGATIVE fraction and
  /// the mote leaves the room for good. Reproduced.
  void drawDust(ui.Canvas g, double t) {
    final lit = kScr.left + kScr.width / 2;
    final lity = kScr.top + kScr.height / 2;
    withBlend(g, kRoom, ui.BlendMode.plus, (c) {
      for (final d in dust) {
        final dx =
            _jsMod(d.x + d.vx * t + math.sin(t * 0.3 + d.ph) * 0.012 + 2, 1);
        final dy = _jsMod(d.y + d.vy * t + 1000, 1);
        final px = dx * kRoom.width, py = dy * kRoom.height;
        final dist = _hypot(px - lit, py - lity) / 460;
        final a = math.max(0.0, 1 - dist) *
            0.30 *
            (0.4 + 0.6 * math.sin(t * 1.7 + d.ph) * 0.5 + 0.3);
        if (a <= 0.004) continue;
        _dustPaint.color = rgba(190, 215, 205, a);
        c.drawRect(ui.Rect.fromLTWH(px, py, d.s, d.s), _dustPaint);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// CustomPainter wrapper
// ---------------------------------------------------------------------------

/// Paints just the booth, in cabinet coordinates, repainting off the runtime.
///
/// The full frame interleaves the window, the tube and the room-wide tints
/// between these calls; use [RoomScene] directly for that and keep this for
/// isolated previews and golden tests.
class RoomPainter extends CustomPainter {
  RoomPainter(this.scene) : super(repaint: scene.runtime);

  final RoomScene scene;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.save();
    canvas.clipRect(kRoom);
    scene.drawAll(canvas, scene.runtime.tGlobal);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RoomPainter oldDelegate) =>
      oldDelegate.scene != scene;
}
