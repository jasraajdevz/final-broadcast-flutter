// FINAL BROADCAST — the window onto the frozen field.
//
// A 1:1 port of the HTML's WIN block: bakeField(), conifer(), bakeFrost(),
// tickLurkers(), figure() and drawWindow(t).
//
// The landscape and the frost are BAKED ONCE at 2x (200x664 = WIN.w*2 x
// WIN.h*2) and blitted every frame; only weather, the figures, the frost
// opacity and the glass reflection are live. That is what buys the budget for
// real trees, drifts and atmospheric perspective.
//
// LUMINANCE WARNING — do not brighten the snowfield. The HTML carries an
// explicit measurement in its comments: at #a3b1bf the field ran 3.4x brighter
// than the CRT during DEAD AIR and pulled the eye out of the window at exactly
// the moment the game wants you staring into a black screen. The gradient
// #414c5c -> #56616f -> #6e7a88 is deliberate and is reproduced verbatim.
//
// Portable: dart:math + dart:ui only. Nothing web-only lives here.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/bake.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

// ---------------------------------------------------------------------------
// Particle / actor records — the JS SNOW, TREES and LURK arrays
// ---------------------------------------------------------------------------

/// One flake of falling snow. JS: `{x,y,s,d,w}`.
class SnowFlake {
  SnowFlake(this.x, this.y, this.s, this.d, this.w);

  /// 0..1 across the pane.
  final double x;

  /// 0..1 down the pane (the phase; the flake falls forever).
  final double y;

  /// Size / brightness, 0.4..1.5.
  final double s;

  /// Fall speed, 0.10..0.52.
  final double d;

  /// Sway phase, 0..TAU.
  final double w;
}

/// A treeline entry. JS `TREES`.
///
/// PORT NOTE: this array is built and sorted by the original and then never
/// read — bakeField() clumps its own trees from the `bands` table instead. It
/// is reproduced here for fidelity (and because it consumes 26 draws from the
/// same RNG stream at startup in the original). Do not "fix" it.
class FieldTree {
  FieldTree(this.x, this.h, this.w, this.z);
  final double x, h, w, z;
}

/// One of the things standing in the field.
/// `z`: 0 = at the treeline, 1 = pressed against the glass.
class Lurker {
  Lurker(this.x, this.z, this.seed);
  double x, z, seed;
}

// ---------------------------------------------------------------------------
// conifer() and figure() — the two shape routines, kept top-level like the JS
// ---------------------------------------------------------------------------

void _ellipse(
    ui.Canvas g, double cx, double cy, double rx, double ry, ui.Paint p) {
  g.drawOval(
      ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2),
      p);
}

/// A spruce: a trunk plus nine drooping branch tiers, optionally with snow
/// sitting on the upper face of each tier. `base` is the ground line.
///
/// The tier outline is deliberately self-intersecting (it doubles back through
/// the axis) — canvas2d fills nonzero, and so does ui.Path by default, so the
/// droop reads the same.
void conifer(ui.Canvas g, double x, double base, double h, double w,
    ui.Color body, ui.Color? load) {
  final bodyPaint = fill(body);
  // trunk
  g.drawRect(
      ui.Rect.fromLTWH(x - w * 0.055, base - h * 0.16, w * 0.11, h * 0.17),
      bodyPaint);

  const int tiers = 9;
  for (var i = 0; i < tiers; i++) {
    final f = i / (tiers - 1);
    final y = base - h * 0.13 - h * 0.84 * f;
    final ww = w * (1 - f * 0.80) * (0.55 + 0.45 * (1 - f * 0.3));

    final branch = ui.Path()
      ..moveTo(x, y - h * 0.10)
      ..lineTo(x + ww * 0.98, y + h * 0.016)
      ..lineTo(x + ww * 0.42, y + h * 0.008)
      ..lineTo(x + ww * 0.70, y + h * 0.040)
      ..lineTo(x, y + h * 0.022)
      ..lineTo(x - ww * 0.70, y + h * 0.040)
      ..lineTo(x - ww * 0.42, y + h * 0.008)
      ..lineTo(x - ww * 0.98, y + h * 0.016)
      ..close();
    g.drawPath(branch, bodyPaint);

    if (load != null) {
      // snow sitting on the branch
      final cap = ui.Path()
        ..moveTo(x, y - h * 0.10)
        ..lineTo(x + ww * 0.62, y + h * 0.006)
        ..lineTo(x + ww * 0.30, y - h * 0.006)
        ..lineTo(x, y - h * 0.020)
        ..lineTo(x - ww * 0.30, y - h * 0.006)
        ..lineTo(x - ww * 0.62, y + h * 0.006)
        ..close();
      g.drawPath(cap, fill(load));
    }
  }
}

/// A figure, not a stick man: hunched, long-armed, wrong in the proportions.
/// `ground` is the contact line; `h` is total height; `seed` drives the sway.
void figure(ui.Canvas g, double x, double ground, double h, ui.Color col,
    double seed) {
  final sway = math.sin(seed * 10) * 0.5;
  final p = fill(col);
  final hipY = ground - h * 0.46;
  final shY = ground - h * 0.80;
  final headY = ground - h * 0.925;

  // legs, slightly apart
  final legs = ui.Path()
    ..moveTo(x - h * 0.075, ground)
    ..lineTo(x - h * 0.052, hipY)
    ..lineTo(x + h * 0.052, hipY)
    ..lineTo(x + h * 0.075, ground)
    ..lineTo(x + h * 0.030, ground)
    ..lineTo(x + h * 0.012, hipY + h * 0.03)
    ..lineTo(x - h * 0.012, hipY + h * 0.03)
    ..lineTo(x - h * 0.030, ground)
    ..close();
  g.drawPath(legs, p);

  // torso, tapering up to narrow shoulders
  final torso = ui.Path()
    ..moveTo(x - h * 0.058, hipY + h * 0.02)
    ..lineTo(x - h * 0.070, shY)
    ..lineTo(x + h * 0.070, shY)
    ..lineTo(x + h * 0.058, hipY + h * 0.02)
    ..close();
  g.drawPath(torso, p);

  // head, pitched forward
  g.save();
  g.translate(x + h * 0.012 * sway, headY);
  g.rotate(sway * 0.10);
  g.drawOval(
      ui.Rect.fromCenter(
          center: ui.Offset.zero, width: h * 0.096, height: h * 0.124),
      p);
  g.restore();
  // neck
  g.drawRect(
      ui.Rect.fromLTWH(x - h * 0.016, headY + h * 0.045, h * 0.032, h * 0.035),
      p);

  // arms hanging past the knee
  for (final s in const <double>[-1, 1]) {
    final arm = ui.Path()
      ..moveTo(x + s * h * 0.062, shY + h * 0.010)
      ..lineTo(x + s * h * 0.098, shY + h * 0.020)
      ..lineTo(x + s * h * 0.086, hipY + h * 0.16)
      ..lineTo(x + s * h * 0.052, hipY + h * 0.15)
      ..close();
    g.drawPath(arm, p);
  }
}

// ---------------------------------------------------------------------------
// The window scene
// ---------------------------------------------------------------------------

/// Owns the two baked plates (FIELD, FROST), the weather particles and the
/// lurkers, and draws the whole window — pane, frame, sill and the cold
/// spilling onto the back wall.
///
/// Usage from the scene painter:
/// ```dart
/// await windowScene.init();                       // startup (optional)
/// windowScene.tickLurkers(dt, runtime);           // once per frame
/// windowScene.drawWindow(canvas, runtime.tGlobal, state);   // in paint()
/// ```
/// If [init] was never awaited the plates are baked synchronously on the first
/// paint, so a caller that forgets still gets a correct (if slightly late)
/// first frame.
class WindowScene {
  WindowScene() {
    for (var i = 0; i < kSnowCount; i++) {
      snow.add(SnowFlake(rand(), rand(), 0.4 + rand() * 1.1,
          0.10 + rand() * 0.42, rand() * tau));
    }
    for (var i = 0; i < kTreeCount; i++) {
      trees.add(FieldTree(rand(), 0.30 + rand() * 0.46, 0.030 + rand() * 0.055,
          rand()));
    }
    trees.sort((a, b) => a.z.compareTo(b.z));
  }

  /// 110 flakes, three depths.
  final List<SnowFlake> snow = <SnowFlake>[];

  /// 26 entries, sorted by z. Unused by the original — see [FieldTree].
  final List<FieldTree> trees = <FieldTree>[];

  /// There is never a moment when the field is empty — one is already out
  /// there at sign-on. JS: `LURK={list:[{x:0.30,z:0.12,seed:0.5}],next:3.2,…}`.
  final List<Lurker> lurk = <Lurker>[Lurker(0.30, 0.12, 0.5)];
  double lurkNext = 3.2;
  double lurkClose = 0;
  double lurkCloseT = 0;

  ui.Image? _field;
  ui.Image? _frost;
  bool _baking = false;

  bool get ready => _field != null && _frost != null;

  /// Bakes FIELD and FROST off the raster thread. Call once at startup.
  Future<void> init() async {
    if (ready || _baking) return;
    _baking = true;
    final f = await bakeImage(kFieldW, kFieldH, _drawField);
    final r = await bakeImage(kFieldW, kFieldH, _drawFrost);
    _field = f;
    _frost = r;
    _baking = false;
  }

  /// Same plates, baked inline. Used as the lazy fallback from [drawWindow].
  void initSync() {
    if (ready) return;
    _field ??= bakeImageSync(kFieldW, kFieldH, _drawField);
    _frost ??= bakeImageSync(kFieldW, kFieldH, _drawFrost);
    _baking = false;
  }

  void dispose() {
    _field?.dispose();
    _frost?.dispose();
    _field = null;
    _frost = null;
  }

  // -------------------------------------------------------------------------
  // bakeField — the landscape, at 2x
  // -------------------------------------------------------------------------

  void _drawField(ui.Canvas g) {
    const double s2 = 2;
    final double w = kFieldW.toDouble(); // WIN.w * 2 = 200
    final double h = kFieldH.toDouble(); // WIN.h * 2 = 664
    final double hz = h * 0.575;

    // --- sky: overcast, brighter at the horizon so everything silhouettes
    g.drawRect(
        ui.Rect.fromLTWH(0, 0, w, hz),
        ui.Paint()
          ..shader = linear(
              const ui.Offset(0, 0),
              ui.Offset(0, hz),
              const <ui.Color>[
                ui.Color(0xFF080F1C),
                ui.Color(0xFF172233),
                ui.Color(0xFF3D4D63),
              ],
              const <double>[0, 0.55, 1]));

    // stars through thin cloud
    final star = ui.Paint();
    for (var i = 0; i < 40; i++) {
      final y = rand() * hz * 0.6;
      star.color =
          rgba(220, 232, 248, (0.05 + rand() * 0.22) * (1 - y / (hz * 0.6)));
      g.drawRect(
          ui.Rect.fromLTWH(rand() * w, y, s2 * 0.8, s2 * 0.8), star);
    }

    // moon behind cloud
    final mx = w * 0.68, my = hz * 0.24;
    g.drawRect(
        ui.Rect.fromLTWH(0, 0, w, hz),
        ui.Paint()
          ..shader = radialR0(
              ui.Offset(mx, my),
              2,
              w * 0.85,
              <ui.Color>[
                rgba(214, 228, 248, 0.34),
                rgba(190, 208, 236, 0.10),
                rgba(190, 208, 236, 0),
              ],
              const <double>[0, 0.25, 1]));
    g.drawCircle(ui.Offset(mx, my), w * 0.055, fill(rgba(226, 238, 252, 0.30)));

    // cloud banding
    for (var i = 0; i < 7; i++) {
      final y = hz * (0.10 + i * 0.12);
      final a = 0.05 + rand() * 0.07;
      final band = ui.Path()..moveTo(0, y);
      for (double x = 0; x <= w; x += w / 8) {
        band.lineTo(x, y + math.sin(x * 0.02 + i) * h * 0.012);
      }
      band
        ..lineTo(w, y + h * 0.05)
        ..lineTo(0, y + h * 0.05)
        ..close();
      g.drawPath(band, fill(rgba(24, 34, 50, a)));
    }

    // --- snowfield first (trees sit on it), drifts carved by wind
    //
    // Kept below the tube on purpose. Measured by the original author: at
    // #a3b1bf the snowfield ran 3.4x brighter than the CRT during DEAD AIR —
    // the eye was dragged out of the window at exactly the moment the game
    // wants you staring into a black screen.
    g.drawRect(
        ui.Rect.fromLTWH(0, hz - 1, w, h - hz + 1),
        ui.Paint()
          ..shader = linear(
              ui.Offset(0, hz),
              ui.Offset(0, h),
              const <ui.Color>[
                ui.Color(0xFF414C5C),
                ui.Color(0xFF56616F),
                ui.Color(0xFF6E7A88),
              ],
              const <double>[0, 0.30, 1]));

    // dunes: lit crest, dark lee
    for (var i = 0; i < 9; i++) {
      final y = hz + (h - hz) * (0.06 + i * 0.11);
      final amp = h * (0.006 + i * 0.0035);
      final ph = i * 1.7;
      double crest(double x) =>
          y +
          math.sin(x * 0.021 + ph) * amp +
          math.sin(x * 0.007 + ph) * amp * 1.6;

      final body = ui.Path()..moveTo(0, y);
      for (double x = 0; x <= w; x += 6) {
        body.lineTo(x, crest(x));
      }
      body
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      // a real shadowed lee, not a second lighten — drifts need a dark side
      g.drawPath(body, fill(rgba(18, 26, 38, 0.10 + i * 0.022)));

      final line = ui.Path()..moveTo(0, y);
      for (double x = 0; x <= w; x += 6) {
        line.lineTo(x, crest(x));
      }
      g.drawPath(line, stroke(rgba(228, 240, 250, 0.10 + i * 0.02), s2 * 0.9));
    }

    // tracks, coming toward the glass and converging with distance.
    // JS wrapped these in globalAlpha=0.5; canvas2d applies globalAlpha per
    // draw op, so folding it into each colour is exact.
    final track = ui.Paint();
    for (var s = -1; s <= 1; s += 2) {
      for (var k = 0; k < 16; k++) {
        final f = k / 15;
        final y = hz + (h - hz) * (0.04 + f * 0.94);
        final sp = w * (0.012 + f * 0.075);
        track.color = rgba(58, 72, 90, (0.20 + f * 0.5) * 0.5);
        _ellipse(g, w * 0.42 + s * sp, y, s2 * (0.9 + f * 2.6),
            s2 * (0.5 + f * 1.5), track);
      }
    }

    // --- three treelines, far ones lifted toward sky value (aerial perspective)
    final bands = <_Band>[
      _Band(17, 0.150, 0.075, 0.030, rgba(52, 66, 86, 0.60), null, 0.000),
      _Band(10, 0.250, 0.130, 0.052, rgba(26, 36, 50, 0.88),
          rgba(150, 168, 190, 0.26), 0.022),
      _Band(5, 0.430, 0.230, 0.100, rgba(8, 12, 18, 1),
          rgba(196, 212, 232, 0.50), 0.058),
    ];
    for (final b in bands) {
      // clumped, not evenly spaced — even spacing read as wallpaper
      final clumps = <double>[
        for (var c = 0; c < 3; c++) 0.14 + rand() * 0.72,
      ];
      for (var i = 0; i < b.n; i++) {
        final c = clumps[(rand() * clumps.length).floor()];
        final x = w * clampD(c + rr(-0.26, 0.26), -0.05, 1.05);
        final hh =
            h * (b.lo + math.pow(rand(), 0.7).toDouble() * (b.hi - b.lo));
        conifer(g, x, hz + h * b.dy + rand() * h * 0.014, hh,
            w * b.w * (0.7 + rand() * 0.7), b.body, b.load);
      }
    }

    // a few bare broken trunks at the very front — the closest thing to glass
    final trunk = stroke(const ui.Color(0xFF06090D), w * 0.020,
        cap: ui.StrokeCap.round);
    final limb = stroke(const ui.Color(0xFF06090D), w * 0.009,
        cap: ui.StrokeCap.round);
    for (var i = 0; i < 3; i++) {
      final x = w * (0.10 + i * 0.38 + rand() * 0.10);
      final base = hz + h * 0.10 + rand() * h * 0.06;
      final hh = h * (0.22 + rand() * 0.16);
      g.drawLine(ui.Offset(x, base), ui.Offset(x + w * 0.012, base - hh), trunk);
      for (var k = 0; k < 4; k++) {
        final y = base - hh * (0.35 + k * 0.19);
        final d = (k % 2 != 0) ? 1.0 : -1.0;
        g.drawLine(
            ui.Offset(x + w * 0.008, y),
            ui.Offset(x + d * w * (0.035 + rand() * 0.03),
                y - h * (0.02 + rand() * 0.03)),
            limb);
      }
    }

    // distance haze over everything far
    g.drawRect(
        ui.Rect.fromLTWH(0, hz - h * 0.16, w, h * 0.22),
        ui.Paint()
          ..shader = linear(
              ui.Offset(0, hz - h * 0.16),
              ui.Offset(0, hz + h * 0.06),
              <ui.Color>[
                rgba(120, 140, 168, 0),
                rgba(120, 140, 168, 0.22),
              ],
              const <double>[0, 1]));
  }

  // -------------------------------------------------------------------------
  // bakeFrost — frost creeps in from the corners of the pane, never quite
  // leaves. Recursive fronds, four per corner, four generations.
  // -------------------------------------------------------------------------

  void _drawFrost(ui.Canvas g) {
    final double w = kFieldW.toDouble();
    final double h = kFieldH.toDouble();
    final col = rgba(226, 240, 252, 0.30);

    void frond(double x, double y, double a, double len, int gen) {
      if (gen <= 0 || len < 3) return;
      final nx = x + math.cos(a) * len, ny = y + math.sin(a) * len;
      g.drawLine(ui.Offset(x, y), ui.Offset(nx, ny),
          stroke(col, gen * 0.55, cap: ui.StrokeCap.round));
      frond(nx, ny, a + rr(-0.28, 0.28), len * 0.82, gen - 1);
      if (rand() < 0.75) {
        frond(x + math.cos(a) * len * 0.5, y + math.sin(a) * len * 0.5,
            a + rr(0.5, 1.2), len * 0.42, gen - 1);
      }
      if (rand() < 0.75) {
        frond(x + math.cos(a) * len * 0.5, y + math.sin(a) * len * 0.5,
            a - rr(0.5, 1.2), len * 0.42, gen - 1);
      }
    }

    final corners = <List<double>>[
      <double>[0, 0, 0.9],
      <double>[w, 0, math.pi - 0.9],
      <double>[0, h, -0.9],
      <double>[w, h, math.pi + 0.9],
    ];
    for (final c in corners) {
      for (var i = 0; i < 4; i++) {
        frond(c[0], c[1], c[2] + rr(-0.6, 0.6), h * 0.055, 4);
      }
    }
  }

  // -------------------------------------------------------------------------
  // tickLurkers — they never move ON screen; the scene is restaged between
  // glances. Runs every frame, including behind modals, the manual and the ad
  // break, exactly like the JS (which calls it outside the !adRun guard).
  // -------------------------------------------------------------------------

  void tickLurkers(double dt, AnomalyRuntime a) {
    if (dt > 0.1) dt = 0.1; // the JS loop clamps before it gets here
    final dread = a.s.dread / 100;
    // THE FIELD PUSHES BACK. AnomalyRuntime.lurkPressure existed, was
    // documented as "read from the window", and nothing ever wrote it — so
    // the figures outside were decoration with no cost. Crowd and proximity
    // both count, and one of them pressed against the glass counts double.
    double press = 0;
    for (final l in lurk) {
      press += 0.10 + l.z * 0.42; // z is 0 far .. 0.82 near
    }
    if (lurkCloseT > 0) press += 1.1;
    a.lurkPressure = (press / 3.2).clamp(0.0, 1.0);
    final live = a.active != null;
    final want =
        math.max(1, 1 + (dread * 3).floor() + (live ? 1 : 0)); // never fewer

    lurkNext -= dt;
    if (lurkNext <= 0) {
      lurkNext = rr(2.6, 6.4) - dread * 1.6;
      while (lurk.length > want) {
        lurk.removeAt((rand() * lurk.length).floor());
      }
      while (lurk.length < want) {
        lurk.add(Lurker(rand(), rand() * 0.35, rand()));
      }
      for (final l in lurk) {
        if (rand() < 0.55 + dread * 0.35) {
          l.x = clampD(l.x + rr(-0.34, 0.34), 0.04, 0.96);
          // mostly closer
          l.z = clampD(l.z + rr(-0.06, 0.13 + dread * 0.22), 0, 0.82);
          l.seed = rand();
        }
      }
      if (lurkCloseT <= 0 &&
          rand() < 0.05 + dread * 0.20 + (live ? 0.10 : 0)) {
        lurkCloseT = rr(0.9, 2.2);
        a.audio.env('sine', 41, 1.1, 0.05, 33);
      }
    }
    if (lurkCloseT > 0) {
      lurkCloseT -= dt;
      lurkClose = math.min(1, lurkClose + dt * 5);
    } else {
      lurkClose = math.max(0, lurkClose - dt * 1.6);
    }
  }

  // -------------------------------------------------------------------------
  // drawWindow — the live layer
  // -------------------------------------------------------------------------

  /// [t] is the global animation clock (AnomalyRuntime.tGlobal).
  void drawWindow(ui.Canvas g, double t, GameState s) {
    if (!ready) initSync();
    const w = kWin;
    final wx = w.left, wy = w.top, ww = w.width, wh = w.height;

    g.save();
    g.clipRect(w);

    // the baked landscape (the main context runs with imageSmoothing off)
    final field = _field;
    if (field != null) drawImageStretch(g, field, w, nearestPaint());
    final hz = wy + wh * 0.575;

    // ground spindrift — wind dragging loose snow across the field
    final drift = ui.Paint();
    for (var i = 0; i < 26; i++) {
      final f = i / 26;
      final yy = hz + wh * 0.06 + f * wh * 0.36;
      final xx = ((t * (26 + f * 70) + i * 97) % (ww + 70)) - 35;
      drift.color = rgba(226, 238, 250, 0.05 + f * 0.14);
      g.drawRect(
          ui.Rect.fromLTWH(wx + xx, yy, 10 + f * 26, 0.8 + f * 1.6), drift);
    }

    // the ones standing out there
    for (final l in lurk) {
      final z = l.z;
      final px = wx + l.x * ww;
      final base = hz + wh * 0.03 + z * (wh * 0.38);
      final h = 13 + z * 86;
      // contact shadow on the snow
      _ellipse(g, px, base + h * 0.02, h * 0.16, h * 0.035,
          fill(rgba(24, 32, 44, 0.10 + z * 0.16)));
      figure(g, px, base, h, rgba(3, 5, 8, 0.62 + z * 0.38), l.seed);
      if (z > 0.42) {
        // eyeshine once they are close
        final a = (z - 0.42) * 1.4;
        final eye = fill(rgba(215, 232, 240, a));
        g.drawRect(
            ui.Rect.fromLTWH(
                px - h * 0.030, base - h * 0.945, h * 0.020, h * 0.014),
            eye);
        g.drawRect(
            ui.Rect.fromLTWH(
                px + h * 0.012, base - h * 0.945, h * 0.020, h * 0.014),
            eye);
      }
    }

    // one at the glass
    if (lurkClose > 0.01) {
      final a = lurkClose;
      final cx = wx + ww * 0.5, cy = wy + wh * 0.30;
      final headP = fill(rgba(3, 5, 7, 0.92 * a));
      g.drawRect(ui.Rect.fromLTWH(wx, wy + wh * 0.12, ww, wh), headP);
      _ellipse(g, cx, cy, ww * 0.40, wh * 0.20, headP);
      // shoulders filling the pane
      final sh = ui.Path()
        ..moveTo(wx - 10, wy + wh)
        ..lineTo(cx - ww * 0.52, cy + wh * 0.16)
        ..lineTo(cx + ww * 0.52, cy + wh * 0.16)
        ..lineTo(wx + ww + 10, wy + wh)
        ..close();
      g.drawPath(sh, fill(rgba(6, 10, 14, 0.92 * a)));
      final eyes = fill(rgba(228, 240, 246, 0.88 * a));
      g.drawRect(
          ui.Rect.fromLTWH(cx - ww * 0.17, cy - wh * 0.025, 7, 5), eyes);
      g.drawRect(
          ui.Rect.fromLTWH(cx + ww * 0.07, cy - wh * 0.025, 7, 5), eyes);
      // breath on the pane
      _ellipse(g, cx, cy + wh * 0.14, ww * 0.26, wh * 0.05,
          stroke(rgba(210, 228, 236, 0.30 * a), 1.6));
    }

    // falling snow, three depths
    final flakeP = ui.Paint();
    for (final f in snow) {
      final y = (f.y + t * f.d * 0.09) % 1;
      final x = (f.x + math.sin(t * 0.5 + f.w) * 0.03 + 1) % 1;
      flakeP.color = rgba(232, 242, 252, 0.16 + f.s * 0.46);
      final sz = f.s * 1.6;
      g.drawRect(ui.Rect.fromLTWH(wx + x * ww, wy + y * wh, sz, sz), flakeP);
    }

    // the pane itself: frost, condensation, and the lit room reflected in it
    final frost = _frost;
    if (frost != null) {
      drawImageStretch(g, frost, w,
          nearestPaint(alpha: 0.30 + math.min(0.30, s.dread / 330)));
    }
    g.drawRect(
        ui.Rect.fromLTWH(wx, wy + wh * 0.55, ww, wh * 0.45),
        ui.Paint()
          ..shader = linear(
              ui.Offset(0, wy + wh * 0.55),
              ui.Offset(0, wy + wh),
              <ui.Color>[
                rgba(198, 216, 232, 0),
                rgba(198, 216, 232, 0.16),
              ],
              const <double>[0, 1]));

    // the CRT, reflected
    withBlend(g, w, ui.BlendMode.screen, (c) {
      c.drawRect(
          w,
          ui.Paint()
            ..shader = linear(
                ui.Offset(wx, wy + wh * 0.30),
                ui.Offset(wx + ww, wy + wh * 0.62),
                <ui.Color>[
                  rgba(80, 150, 110, 0.10),
                  rgba(80, 150, 110, 0),
                ],
                const <double>[0, 0.45]));
    });

    // glancing sheen
    final sheen = ui.Path()
      ..moveTo(wx, wy + wh * 0.24)
      ..lineTo(wx + ww, wy - wh * 0.02)
      ..lineTo(wx + ww, wy + wh * 0.10)
      ..lineTo(wx, wy + wh * 0.36)
      ..close();
    g.drawPath(sheen, fill(rgba(140, 170, 200, 0.05)));

    g.restore();

    // frame, mullions, sill
    g.drawRect(ui.Rect.fromLTWH(wx - 4, wy - 4, ww + 8, wh + 8),
        stroke(const ui.Color(0xFF080B0C), 8));
    g.drawRect(ui.Rect.fromLTWH(wx - 8, wy - 8, ww + 16, wh + 16),
        stroke(const ui.Color(0xFF283335), 1));
    final mull = fill(const ui.Color(0xFF0C1012));
    g.drawRect(ui.Rect.fromLTWH(wx - 1, wy + wh * 0.5 - 3, ww + 2, 6), mull);
    g.drawRect(ui.Rect.fromLTWH(wx + ww * 0.5 - 3, wy, 6, wh), mull);
    final mullLit = fill(rgba(255, 255, 255, 0.05));
    g.drawRect(
        ui.Rect.fromLTWH(wx - 1, wy + wh * 0.5 - 3, ww + 2, 1.4), mullLit);
    g.drawRect(ui.Rect.fromLTWH(wx + ww * 0.5 - 3, wy, 1.4, wh), mullLit);
    // (the original sets fillStyle="#10151700" here and never uses it)
    fillText(g, 'EXT — FIELD', ui.Offset(wx, wy + wh + 16),
        mono(10, rgba(150, 190, 185, 0.6)));

    // cold spilling into the room
    withBlend(g, kWall, ui.BlendMode.plus, (c) {
      c.drawRect(
          kWall,
          ui.Paint()
            ..shader = radialR0(
                ui.Offset(wx + ww / 2, wy + wh / 2),
                10,
                260,
                <ui.Color>[
                  rgba(120, 160, 205, 0.07),
                  rgba(120, 160, 205, 0),
                ],
                const <double>[0, 1]));
    });
  }
}

/// One of the three treelines in bakeField.
class _Band {
  const _Band(this.n, this.hi, this.lo, this.w, this.body, this.load, this.dy);
  final int n;
  final double hi, lo, w, dy;
  final ui.Color body;
  final ui.Color? load;
}

/// The default instance — the JS module-level FIELD / FROST / SNOW / LURK.
final WindowScene windowScene = WindowScene();
