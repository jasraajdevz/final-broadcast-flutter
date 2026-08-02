// FINAL BROADCAST — FACE PLATES.
//
// A 1:1 port of the HTML's "anatomy by VALUE, not by outline" section.
//
// The old entities were an ellipse plus two circles plus an arc, i.e. a smiley.
// A 256x320 grayscale plate is baked once per entity: brow ridge throwing a
// hard shadow into the orbital sockets, eyeballs as spheres, lit nasal dorsum
// casting onto the philtrum, malar shelf, buccal hollow, mandible, submental
// shadow. Per frame it is ONE drawImageRect. Because it is all value and no
// line work, it survives the 0.52x downscale that eats hairlines.
//
// Everything here is baked ONCE. Call [ensureFaces] (or await [initFaces])
// before the first frame; every public entry point calls it defensively.
//
// Portable: dart:ui only. Nothing web-specific.

import 'dart:math' as math;
import 'dart:ui' as ui;

import '../bake.dart';
import '../consts.dart';

// HW / HH in the HTML.
final double _hw = kHeadW.toDouble();
final double _hh = kHeadH.toDouble();
final ui.Rect _plateRect = ui.Rect.fromLTWH(0, 0, _hw, _hh);

// ---------------------------------------------------------------------------
// Plate types
// ---------------------------------------------------------------------------

/// The `c.lm` the HTML hangs off each baked head: where the features actually
/// landed, in PLATE space, so puppet furniture (hinges, rouge, speculars) can
/// be painted on the real cheek line instead of guessed at.
class HeadLandmarks {
  const HeadLandmarks({
    required this.cx,
    required this.w,
    required this.brow,
    required this.eye,
    required this.nose,
    required this.mouth,
    required this.jaw,
    required this.chin,
  });

  /// JS `L.CX` — the plate's horizontal centre.
  final double cx;

  /// JS `L.W` — the half-width unit every feature is measured in.
  final double w;

  final double brow;
  final double eye;
  final double nose;
  final double mouth;
  final double jaw;
  final double chin;
}

/// One baked entity: the shaded value plate, its silhouette (used for rim
/// light, subsurface and tinting) and its landmarks.
///
/// The HTML hung `.sil` and `.lm` straight off the canvas element; this is the
/// same three things in a class.
class HeadPlate {
  HeadPlate(this.image, this.sil, this.lm);

  /// The shaded plate, already masked to [sil] and vignetted.
  final ui.Image image;

  /// White silhouette on transparent, [kHeadW] x [kHeadH].
  final ui.Image sil;

  final HeadLandmarks lm;
}

// ---------------------------------------------------------------------------
// MOTTLE — 5-octave value noise (NOT the noiseTiles)
// ---------------------------------------------------------------------------

const List<List<double>> _mottleOctaves = <List<double>>[
  <double>[5, 0.50],
  <double>[11, 0.34],
  <double>[24, 0.22],
  <double>[56, 0.14],
  <double>[120, 0.09],
];

ui.Image _bakeMottle() {
  final double s = kMottleSize.toDouble();
  final ui.Rect r = ui.Rect.fromLTWH(0, 0, s, s);

  // The tiles have to outlive the outer recording — the outer picture is not
  // rasterised until bakeImageSync returns, so they cannot be disposed inside
  // the draw callback.
  final List<ui.Image> tiles = <ui.Image>[];
  for (final List<double> oct in _mottleOctaves) {
    final int n = oct[0].toInt();
    tiles.add(bakeImageSync(n, n, (ui.Canvas q) {
      final ui.Paint p = ui.Paint()..isAntiAlias = false;
      for (int yy = 0; yy < n; yy++) {
        for (int xx = 0; xx < n; xx++) {
          final int v = (rand() * 255).floor();
          p.color = ui.Color.fromARGB(255, v, v, v);
          q.drawRect(
              ui.Rect.fromLTWH(xx.toDouble(), yy.toDouble(), 1, 1), p);
        }
      }
    }));
  }

  final ui.Image out = bakeImageSync(kMottleSize, kMottleSize, (ui.Canvas x) {
    x.drawRect(r, fill(const ui.Color(0xFF808080)));
    for (int i = 0; i < tiles.length; i++) {
      // the upscale IS the blur
      drawImageStretch(x, tiles[i], r, smoothPaint(alpha: _mottleOctaves[i][1]));
    }
  });

  for (final ui.Image t in tiles) {
    t.dispose();
  }
  return out;
}

// ---------------------------------------------------------------------------
// vblob — the soft value blob every feature is made of
// ---------------------------------------------------------------------------

/// JS `vblob(x,cx,cy,rx,ry,rot,col,soft)`.
///
/// A radial gradient from [col] to the same colour at zero alpha, squashed to
/// an ellipse. [soft] is the inner-radius fraction: 0 = feathered from the
/// centre, 0.2 = a hard-ish core.
///
/// [mode] is the extra the port needs: the HTML sets
/// `ctx.globalCompositeOperation` around some vblob calls (the rouge is
/// multiply, the brow catchlight is lighter), which a Dart caller cannot do
/// from outside the function.
void vblob(
  ui.Canvas x,
  double cx,
  double cy,
  double rx,
  double ry,
  double rot,
  ui.Color col,
  double soft, {
  ui.BlendMode mode = ui.BlendMode.srcOver,
}) {
  if (rx <= 0) return;
  x.save();
  x.translate(cx, cy);
  if (rot != 0) x.rotate(rot);
  x.scale(1, ry / rx);
  final ui.Paint p = ui.Paint()
    ..isAntiAlias = true
    ..blendMode = mode
    ..shader = radialR0(ui.Offset.zero, rx * soft, rx,
        <ui.Color>[col, col.withAlpha(0)], const <double>[0, 1]);
  x.drawCircle(ui.Offset.zero, rx, p);
  x.restore();
}

// ---------------------------------------------------------------------------
// headPath — cranium -> temple -> zygomatic -> gonion -> chin
// ---------------------------------------------------------------------------

/// JS `headPath(x,o)`, as a reusable [ui.Path] in plate space.
ui.Path headPath({double wide = 1, double child = 0}) {
  final double cx = _hw / 2, w = _hw * 0.33 * wide;
  final double top = _hh * (0.13 - child * 0.02);
  final double chin = _hh * (0.93 - child * 0.05);
  final double eye = _hh * (0.44 + child * 0.03);
  final double jaw = _hh * (0.74 - child * 0.03);

  final ui.Path p = ui.Path()..moveTo(cx, top);
  p.cubicTo(cx + w * 0.92, top + _hh * 0.005, cx + w * 1.08, eye - _hh * 0.10,
      cx + w * 1.02, eye);
  p.cubicTo(cx + w * (1.00 - child * 0.06), eye + _hh * 0.06, cx + w * 0.88,
      jaw - _hh * 0.07, cx + w * (0.72 + child * 0.10), jaw);
  p.cubicTo(cx + w * (0.56 + child * 0.12), jaw + _hh * 0.10, cx + w * 0.26,
      chin - _hh * 0.005, cx, chin);
  p.cubicTo(cx - w * 0.26, chin - _hh * 0.005, cx - w * (0.56 + child * 0.12),
      jaw + _hh * 0.10, cx - w * (0.72 + child * 0.10), jaw);
  p.cubicTo(cx - w * 0.88, jaw - _hh * 0.07, cx - w * (1.00 - child * 0.06),
      eye + _hh * 0.06, cx - w * 1.02, eye);
  p.cubicTo(cx - w * 1.08, eye - _hh * 0.10, cx - w * 0.92, top + _hh * 0.005,
      cx, top);
  p.close();
  return p;
}

// ---------------------------------------------------------------------------
// bakeHead — the anatomy value plate
// ---------------------------------------------------------------------------

/// JS `bakeHead(o)`.
///
/// [key] is the light direction, -1 by default (light from screen-left);
/// MR. NIELSEN is the one entity lit from the other side.
HeadPlate bakeHead({
  double gaunt = 0,
  double child = 0,
  double wide = 1,
  bool hollow = false,
  bool frown = false,
  double gaze = 0,
  double key = -1,
}) {
  final ui.Path path = headPath(wide: wide, child: child);

  final ui.Image sil = bakeImageSync(kHeadW, kHeadH, (ui.Canvas s) {
    s.drawPath(path, fill(const ui.Color(0xFFFFFFFF)));
  });

  final double cx = _hw / 2, w = _hw * 0.33 * wide;
  final double brow = _hh * (0.42 + child * 0.04);
  final double eye = brow + _hh * 0.045;
  final double nose = eye + _hh * (child != 0 ? 0.100 : 0.130);
  final double mouth = nose + _hh * (child != 0 ? 0.075 : 0.085);
  final double jaw = _hh * (0.74 - child * 0.03);
  final double chin = _hh * (0.93 - child * 0.05);

  final ui.Image plate = bakeImageSync(kHeadW, kHeadH, (ui.Canvas root) {
    groupLayer(root, _plateRect, (ui.Canvas x) {
      x.drawPath(path, fill(const ui.Color(0xFF6E6E6E)));

      // cranial mass: lit forehead, lit dorsum, temples falling away
      vblob(x, cx + key * w * 0.10, brow - _hh * 0.105, w * 1.02, _hh * 0.155,
          0, rgba(255, 255, 255, 0.30), 0.05);
      vblob(x, cx, nose + _hh * 0.015, w * 0.68, _hh * 0.120, 0,
          rgba(255, 255, 255, 0.18), 0);
      vblob(x, cx - w * 0.94, brow - _hh * 0.010, w * 0.34, _hh * 0.105, 0,
          rgba(0, 0, 0, 0.50), 0);
      vblob(x, cx + w * 0.94, brow - _hh * 0.010, w * 0.34, _hh * 0.105, 0,
          rgba(0, 0, 0, 0.50), 0);

      // BROW RIDGE — do not soften
      final ui.Path ridge = ui.Path()
        ..moveTo(cx - w * 0.88, brow - _hh * 0.026)
        ..quadraticBezierTo(
            cx, brow - _hh * 0.080, cx + w * 0.88, brow - _hh * 0.026)
        ..quadraticBezierTo(
            cx, brow - _hh * 0.046, cx - w * 0.88, brow - _hh * 0.026);
      x.drawPath(ridge, fill(rgba(255, 255, 255, 0.26)));
      vblob(x, cx - w * 0.46, brow + _hh * 0.014, w * 0.46, _hh * 0.046, -0.12,
          rgba(0, 0, 0, 0.70), 0.20);
      vblob(x, cx + w * 0.46, brow + _hh * 0.014, w * 0.46, _hh * 0.046, 0.12,
          rgba(0, 0, 0, 0.70), 0.20);

      // sphere in a hole, not a disc
      for (final double sg in const <double>[-1, 1]) {
        final double ox = cx + sg * w * 0.46;
        vblob(x, ox, eye - _hh * 0.004, w * 0.42, _hh * 0.064, 0,
            rgba(0, 0, 0, 0.48 + gaunt * 0.44), 0.10);
        vblob(x, ox + sg * w * 0.18, eye - _hh * 0.022, w * 0.20, _hh * 0.036,
            0, rgba(0, 0, 0, 0.55), 0);
        if (hollow) continue;
        vblob(x, ox, eye + _hh * 0.002, w * 0.21, _hh * 0.038, 0,
            rgba(255, 255, 255, 0.50), 0.10);
        vblob(x, ox - sg * w * 0.05, eye + _hh * 0.012, w * 0.12, _hh * 0.018,
            0, rgba(255, 255, 255, 0.34), 0);
        vblob(x, ox, eye - _hh * 0.026, w * 0.25, _hh * 0.024, 0,
            rgba(0, 0, 0, 0.62), 0.10);
        x.drawOval(
            ui.Rect.fromCenter(
                center: ui.Offset(ox, eye + _hh * 0.026),
                width: w * 0.19 * 2,
                height: _hh * 0.005 * 2),
            fill(rgba(255, 255, 255, 0.42)));
        x.drawOval(
            ui.Rect.fromCenter(
                center: ui.Offset(ox + gaze * w * 0.07, eye + _hh * 0.004),
                width: w * 0.085 * 2,
                height: _hh * 0.019 * 2),
            fill(rgba(0, 0, 0, 0.88)));
      }

      // nasal dorsum, alar shadow, nostrils, philtrum
      vblob(x, cx - key * w * 0.09, (brow + nose) / 2, w * 0.11, _hh * 0.078, 0,
          rgba(255, 255, 255, 0.32), 0.15);
      vblob(x, cx + key * w * 0.17, (brow + nose) / 2 + _hh * 0.010, w * 0.14,
          _hh * 0.072, 0, rgba(0, 0, 0, 0.40), 0);
      vblob(x, cx, nose - _hh * 0.006, w * 0.22, _hh * 0.030, 0,
          rgba(255, 255, 255, 0.24), 0.05);
      for (final double sg in const <double>[-1, 1]) {
        vblob(x, cx + sg * w * 0.25, nose - _hh * 0.002, w * 0.10, _hh * 0.020,
            0, rgba(0, 0, 0, 0.52), 0);
      }
      for (final double sg in const <double>[-1, 1]) {
        x.save();
        x.translate(cx + sg * w * 0.115, nose + _hh * 0.008);
        x.rotate(sg * 0.35);
        x.drawOval(
            ui.Rect.fromCenter(
                center: ui.Offset.zero,
                width: w * 0.055 * 2,
                height: _hh * 0.012 * 2),
            fill(rgba(0, 0, 0, 0.85)));
        x.restore();
      }
      vblob(x, cx, nose + _hh * 0.030, w * 0.30, _hh * 0.024, 0,
          rgba(0, 0, 0, 0.38), 0);

      // mouth line, vermilion, submental
      final double dr = frown ? 1 : 0;
      final ui.Path lips = ui.Path()
        ..moveTo(cx - w * 0.34, mouth)
        ..quadraticBezierTo(
            cx, mouth + _hh * (0.012 + dr * 0.012), cx + w * 0.34, mouth)
        ..quadraticBezierTo(cx, mouth + _hh * (0.024 + dr * 0.014),
            cx - w * 0.34, mouth);
      x.drawPath(lips, fill(rgba(0, 0, 0, 0.80)));
      vblob(x, cx, mouth - _hh * 0.015, w * 0.26, _hh * 0.012, 0,
          rgba(255, 255, 255, 0.20), 0);
      vblob(x, cx, mouth + _hh * 0.032, w * 0.22, _hh * 0.016, 0,
          rgba(0, 0, 0, 0.40), 0);

      // malar shelf, buccal hollow, mandible
      for (final double sg in const <double>[-1, 1]) {
        vblob(x, cx + sg * w * 0.36, mouth + _hh * 0.004, w * 0.09, _hh * 0.016,
            0, rgba(0, 0, 0, 0.58), 0);
        vblob(x, cx + sg * w * 0.36, (nose + mouth) / 2, w * 0.09, _hh * 0.048,
            sg * 0.25, rgba(0, 0, 0, 0.22 + gaunt * 0.30), 0);
        vblob(x, cx + sg * w * 0.66, eye + _hh * 0.058, w * 0.30, _hh * 0.055,
            sg * 0.20, rgba(255, 255, 255, 0.20 + gaunt * 0.18), 0.05);
        vblob(x, cx + sg * w * 0.60, mouth - _hh * 0.006, w * 0.24, _hh * 0.062,
            0, rgba(0, 0, 0, 0.16 + gaunt * 0.52), 0);
        vblob(x, cx + sg * w * 0.70, jaw + _hh * 0.012, w * 0.28, _hh * 0.030,
            sg * 0.35, rgba(255, 255, 255, 0.16), 0);
      }
      vblob(x, cx, chin - _hh * 0.058, w * 0.22, _hh * 0.028, 0,
          rgba(255, 255, 255, 0.26), 0);
      vblob(x, cx, chin - _hh * 0.014, w * 0.44, _hh * 0.030, 0,
          rgba(0, 0, 0, 0.55), 0);

      // skin grain
      drawImageStretch(x, mottleImage, _plateRect,
          smoothPaint(alpha: 0.45 + gaunt * 0.25, mode: ui.BlendMode.softLight));

      // cut to the silhouette, then vignette what is left
      withBlend(x, _plateRect, ui.BlendMode.dstIn, (ui.Canvas m) {
        m.drawImage(sil, ui.Offset.zero, nearestPaint());
      });
      withBlend(x, _plateRect, ui.BlendMode.srcATop, (ui.Canvas m) {
        m.drawRect(
            _plateRect,
            ui.Paint()
              ..shader = radialFocal(
                  ui.Offset(cx + key * w * 0.25, brow),
                  w * 0.55,
                  ui.Offset(cx, _hh * 0.55),
                  w * 1.65,
                  <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.58)],
                  const <double>[0, 1]));
      });
    });
  });

  return HeadPlate(
      plate,
      sil,
      HeadLandmarks(
          cx: cx,
          w: w,
          brow: brow,
          eye: eye,
          nose: nose,
          mouth: mouth,
          jaw: jaw,
          chin: chin));
}

// ---------------------------------------------------------------------------
// tintPlate / bakeRim / bakeSSS
// ---------------------------------------------------------------------------

final Map<String, ui.Image> _tintCache = <String, ui.Image>{};

/// JS `tintPlate(plate,col,mode)`.
///
/// The HTML re-composited a scratch 256x320 canvas on EVERY call and handed
/// back the same element; here the result is baked once per
/// (plate, colour, mode) and cached, which is the same picture without paying
/// for it 60 times a second. The game only ever asks for a handful of
/// combinations.
ui.Image tintPlate(HeadPlate plate, ui.Color col,
    [ui.BlendMode mode = ui.BlendMode.multiply]) {
  ensureFaces();
  final String key =
      '${identityHashCode(plate)}|${col.hashCode}|${mode.index}';
  final ui.Image? hit = _tintCache[key];
  if (hit != null) return hit;
  final ui.Image out = bakeImageSync(kHeadW, kHeadH, (ui.Canvas root) {
    groupLayer(root, _plateRect, (ui.Canvas ti) {
      ti.drawImage(plate.image, ui.Offset.zero, nearestPaint());
      withBlend(ti, _plateRect, mode, (ui.Canvas m) {
        m.drawRect(_plateRect, fill(col));
      });
      withBlend(ti, _plateRect, ui.BlendMode.dstIn, (ui.Canvas m) {
        m.drawImage(plate.sil, ui.Offset.zero, nearestPaint());
      });
    });
  });
  _tintCache[key] = out;
  return out;
}

/// JS `bakeRim(sil,dx,dy,c0,c1,blur)`.
///
/// Rim light straight out of the silhouette: draw it, knock out a copy shifted
/// toward the light, and the crescent left over hugs the far edge. This is what
/// stops a dark shape being a hole cut in the background.
ui.Image bakeRim(ui.Image sil, double dx, double dy, ui.Color c0, ui.Color c1,
    double blur) {
  final int w = sil.width, h = sil.height;
  final ui.Rect b = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  final ui.Image crescent = bakeImageSync(w, h, (ui.Canvas root) {
    groupLayer(root, b, (ui.Canvas x) {
      x.drawImage(sil, ui.Offset.zero, nearestPaint());
      withBlend(x, b, ui.BlendMode.dstOut, (ui.Canvas m) {
        m.drawImage(sil, ui.Offset(dx, dy), nearestPaint());
      });
      withBlend(x, b, ui.BlendMode.srcIn, (ui.Canvas m) {
        m.drawRect(
            b,
            ui.Paint()
              ..shader = linear(ui.Offset(0, 0), ui.Offset(0, h.toDouble()),
                  <ui.Color>[c0, c1], const <double>[0, 1]));
      });
    });
  });
  if (blur <= 0) return crescent;
  // ctx.filter="blur(Npx)" — the CSS length IS the standard deviation.
  final ui.Image out = bakeImageSync(w, h, (ui.Canvas c) {
    withBlur(c, b, blur, (ui.Canvas q) {
      q.drawImage(crescent, ui.Offset.zero, smoothPaint());
    });
  });
  crescent.dispose();
  return out;
}

/// JS `bakeSSS(sil,cx,cy,r,col)` — light bleeding through thin flesh.
ui.Image bakeSSS(
    ui.Image sil, double cx, double cy, double r, ui.Color col) {
  final int w = sil.width, h = sil.height;
  final ui.Rect b = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  return bakeImageSync(w, h, (ui.Canvas root) {
    groupLayer(root, b, (ui.Canvas x) {
      x.drawRect(
          b,
          ui.Paint()
            ..shader = radialR0(ui.Offset(cx, cy), 0, r,
                <ui.Color>[col, col.withAlpha(0)], const <double>[0, 1]));
      withBlend(x, b, ui.BlendMode.dstIn, (ui.Canvas m) {
        m.drawImage(sil, ui.Offset.zero, nearestPaint());
      });
    });
  });
}

// ---------------------------------------------------------------------------
// The eight entities
// ---------------------------------------------------------------------------

ui.Image? _mottle;
final Map<String, HeadPlate> _heads = <String, HeadPlate>{};
final Map<String, ui.Image> _rims = <String, ui.Image>{};
final Map<String, ui.Image> _sss = <String, ui.Image>{};
ui.Image? _fold;
ui.Image? _shoulder;
bool _ready = false;

/// True once every plate is baked.
bool get facesReady => _ready;

/// Bakes MOTTLE, the eight HEADS, their RIMS and SSSs, FOLD and SHOULDER.
/// Idempotent and synchronous — roughly 45 small offscreen rasters.
void ensureFaces() {
  if (_ready) return;
  _ready = true; // set first: bakeHead reads mottleImage through this guard
  _mottle = _bakeMottle();

  _heads['snow'] = bakeHead(gaunt: 1.0, wide: 0.92, hollow: true);
  _heads['sleep'] = bakeHead(gaunt: 0.10, wide: 1.12, gaze: 0.35);
  _heads['vert'] = bakeHead(gaunt: 0.75, wide: 0.78, hollow: true);
  _heads['dead'] =
      bakeHead(gaunt: 0.55, wide: 1.00, hollow: true, frown: true);
  _heads['card'] = bakeHead(child: 1, wide: 0.94, frown: true);
  _heads['rerun'] = bakeHead(gaunt: 0.35, wide: 1.00, gaze: -0.4);
  _heads['niel'] = bakeHead(gaunt: 0.55, wide: 0.90, frown: true, key: 1);
  _heads['call'] = bakeHead(gaunt: 0.80, wide: 0.86, hollow: true);

  for (final MapEntry<String, HeadPlate> e in _heads.entries) {
    _rims[e.key] = bakeRim(e.value.sil, -9, -7, rgba(190, 235, 255, 0.95),
        rgba(70, 120, 150, 0.25), 3);
    _sss[e.key] = bakeSSS(e.value.sil, _hw * 0.5, _hh * 0.62, _hw * 0.42,
        rgba(255, 90, 60, 0.55));
  }

  // one cloth fold: shadow / core / shadow
  _fold = bakeImageSync(kFoldW, kFoldH, (ui.Canvas x) {
    x.drawRect(
        ui.Rect.fromLTWH(0, 0, kFoldW.toDouble(), kFoldH.toDouble()),
        ui.Paint()
          ..shader = linear(
              const ui.Offset(0, 0),
              ui.Offset(kFoldW.toDouble(), 0),
              <ui.Color>[
                rgba(0, 0, 0, 0),
                rgba(0, 0, 0, 0.60),
                rgba(255, 255, 255, 0.20),
                rgba(255, 255, 255, 0.05),
                rgba(0, 0, 0, 0.44),
                rgba(0, 0, 0, 0),
              ],
              const <double>[0.00, 0.26, 0.48, 0.62, 0.80, 1.00]));
  });

  _shoulder = bakeImageSync(kShoulderW, kShoulderH, (ui.Canvas x) {
    final ui.Rect b = ui.Rect.fromLTWH(
        0, 0, kShoulderW.toDouble(), kShoulderH.toDouble());
    x.drawRect(
        b,
        ui.Paint()
          ..shader = linear(
              const ui.Offset(0, 0),
              ui.Offset(0, kShoulderH.toDouble()),
              <ui.Color>[rgba(255, 255, 255, 0.26), rgba(255, 255, 255, 0)],
              const <double>[0, 1]));
    x.drawRect(
        b,
        ui.Paint()
          ..shader = radialR0(const ui.Offset(32, 1), 1, 17,
              <ui.Color>[rgba(0, 0, 0, 0.80), rgba(0, 0, 0, 0)],
              const <double>[0, 1]));
  });
}

/// Async wrapper for a boot sequence that wants to await its assets.
Future<void> initFaces() async => ensureFaces();

/// JS `MOTTLE` — the 192x192 value-noise plate.
ui.Image get mottleImage {
  ensureFaces();
  return _mottle!;
}

/// JS `HEADS` — keyed by anomaly id (snow, sleep, vert, dead, card, rerun,
/// niel, call).
Map<String, HeadPlate> get heads {
  ensureFaces();
  return _heads;
}

/// JS `RIMS`.
Map<String, ui.Image> get rims {
  ensureFaces();
  return _rims;
}

/// JS `SSSs`.
Map<String, ui.Image> get sssPlates {
  ensureFaces();
  return _sss;
}

/// JS `FOLD` — 64x1 cloth-fold gradient strip.
ui.Image get foldImage {
  ensureFaces();
  return _fold!;
}

/// JS `SHOULDER` — 64x32 shoulder plate.
ui.Image get shoulderImage {
  ensureFaces();
  return _shoulder!;
}

// ---------------------------------------------------------------------------
// wetSpec — a few HARD speculars on real ridges
// ---------------------------------------------------------------------------

/// JS `wetSpec(g,plate,ox,oy,w,h,pts,t)`.
///
/// A single hard highlight on a dark form is what the eye reads as WET, and it
/// is the cheapest fright in the file. Points are `[x, y, rx, ry, rot, alpha]`
/// in PLATE space; the call maps plate space onto the destination rect.
///
/// `plate` is unused, exactly as in the HTML — the scale comes from HW/HH.
void wetSpec(ui.Canvas g, HeadPlate? plate, double ox, double oy, double w,
    double h, List<List<double>> pts, double t) {
  g.save();
  g.translate(ox, oy);
  g.scale(w / _hw, h / _hh);
  for (int i = 0; i < pts.length; i++) {
    final List<double> p = pts[i];
    final double fl = 0.72 + 0.28 * math.sin(t * (2.1 + i * 0.7) + i);
    g.save();
    g.translate(p[0], p[1]);
    if (p.length > 4 && p[4] != 0) g.rotate(p[4]);
    g.drawOval(
        ui.Rect.fromCenter(
            center: ui.Offset.zero, width: p[2] * 2, height: p[3] * 2),
        fill(rgba(255, 252, 244, clampD(p[5] * fl, 0, 1)),
            mode: ui.BlendMode.plus));
    g.restore();
  }
  g.restore();
}

/// JS `wetSetFor(lm)` — the six speculars that read as a wet face.
List<List<double>> wetSetFor(HeadLandmarks lm) {
  final double w = lm.w;
  return <List<double>>[
    <double>[lm.cx - w * 0.46, lm.eye + _hh * 0.024, w * 0.15, _hh * 0.0045, 0.05, 0.55],
    <double>[lm.cx + w * 0.46, lm.eye + _hh * 0.024, w * 0.15, _hh * 0.0045, -0.05, 0.55],
    <double>[lm.cx - w * 0.52, lm.eye - _hh * 0.004, w * 0.030, _hh * 0.008, 0.00, 0.85],
    <double>[lm.cx + w * 0.40, lm.eye - _hh * 0.004, w * 0.030, _hh * 0.008, 0.00, 0.85],
    <double>[lm.cx, lm.mouth + _hh * 0.006, w * 0.20, _hh * 0.005, 0.00, 0.40],
    <double>[lm.cx - w * 0.10, lm.nose + _hh * 0.006, w * 0.035, _hh * 0.006, 0.30, 0.30],
  ];
}

// ---------------------------------------------------------------------------
// mottle / shroud / hair
// ---------------------------------------------------------------------------

/// JS `mottle(g,x,y,w,h,alpha,mode)`.
///
/// [smooth] is false by default because every caller in the HTML draws into a
/// context with `imageSmoothingEnabled = false` (the feed).
void mottle(ui.Canvas g, double x, double y, double w, double h, double alpha,
    [ui.BlendMode mode = ui.BlendMode.softLight, bool smooth = false]) {
  final ui.Rect dst = ui.Rect.fromLTWH(x, y, w, h);
  drawImageStretch(g, mottleImage, dst,
      smooth ? smoothPaint(alpha: alpha, mode: mode)
             : nearestPaint(alpha: alpha, mode: mode));
}

/// JS `shroudPath(g,x0,y0,w,h,t,seed)` — the hem is a wave, never a line.
ui.Path shroudPath(
    double x0, double y0, double w, double h, double t, double seed) {
  final double top = w * 0.40;
  final ui.Path p = ui.Path()..moveTo(x0 - top, y0);
  p.cubicTo(x0 - top - w * 0.12, y0 + h * 0.20, x0 - w * 0.44, y0 + h * 0.58,
      x0 - w * 0.52, y0 + h);
  for (int i = 0; i <= 12; i++) {
    final double u = i / 12, hx = x0 - w * 0.52 + u * w * 1.04;
    final double hy = y0 +
        h +
        math.sin(u * 7.1 + seed + t * 0.8) * h * 0.030 +
        math.sin(u * 3.0 - seed * 2 + t * 0.5) * h * 0.048;
    p.lineTo(hx, hy);
  }
  p.cubicTo(x0 + w * 0.44, y0 + h * 0.58, x0 + top + w * 0.12, y0 + h * 0.20,
      x0 + top, y0);
  p.quadraticBezierTo(x0, y0 - h * 0.07, x0 - top, y0);
  p.close();
  return p;
}

/// JS `drawShroud(g,x0,y0,w,h,t,col,seed)`.
void drawShroud(ui.Canvas g, double x0, double y0, double w, double h, double t,
    ui.Color col, double seed) {
  ensureFaces();
  g.save();
  final ui.Path p = shroudPath(x0, y0, w, h, t, seed);
  g.drawPath(p, fill(col));
  g.clipPath(p);
  for (int i = 0; i < 6; i++) {
    final double ph = seed * 3 + i * 1.93;
    final double fx =
        x0 + (i / 5 - 0.5) * w * 0.94 + math.sin(t * 0.5 + ph) * w * 0.03;
    final double fw = w * (0.16 + 0.13 * math.sin(ph).abs());
    final double alpha = 0.26 + 0.30 * math.sin(ph * 1.7).abs();
    drawImageStretch(g, foldImage,
        ui.Rect.fromLTWH(fx - fw / 2, y0 - h * 0.10, fw, h * 1.25),
        nearestPaint(alpha: clampD(alpha, 0, 1)));
  }
  drawImageStretch(
      g,
      shoulderImage,
      ui.Rect.fromLTWH(x0 - w * 0.58, y0 - h * 0.09, w * 1.16, h * 0.46),
      nearestPaint());
  mottle(g, x0 - w * 0.6, y0 - h * 0.1, w * 1.2, h * 1.2, 0.30);
  g.restore();
}

/// JS `drawHair(g,cx,cy,hw,hh,t,lag,col,strandCol,layer)`.
///
/// MASS first (survives downscale), then sheen, then strands. Layer 0 goes
/// behind the head, layer 1 in front. Roots lag the head by [lag], which is the
/// cue that says this is attached to something that just moved.
void drawHair(ui.Canvas g, double cx, double cy, double hw, double hh, double t,
    double lag, ui.Color? col, ui.Color? strandCol, int layer) {
  final double sw = math.sin(t * 1.05) * hw * 0.05 + lag;
  if (layer == 0) {
    g.save();
    final ui.Path p = ui.Path()..moveTo(cx - hw * 0.42, cy - hh * 0.02);
    p.cubicTo(cx - hw * 0.48, cy - hh * 0.40, cx + hw * 0.48, cy - hh * 0.40,
        cx + hw * 0.42, cy - hh * 0.02);
    p.cubicTo(cx + hw * 0.52, cy + hh * 0.26, cx + hw * 0.46 + sw,
        cy + hh * 0.52, cx + hw * 0.34 + sw * 1.8, cy + hh * 0.74);
    for (int i = 1; i <= 9; i++) {
      final double u = i / 9;
      final double x0 = cx + hw * 0.34 + sw * 1.8;
      final double x1 = cx - hw * 0.34 + sw * 1.8;
      final double hy = cy +
          hh * 0.74 -
          math.sin(u * 9.3 + t * 0.6) * hh * 0.035 -
          math.sin(u * 3.7 + 1.4) * hh * 0.065;
      p.lineTo(x0 + (x1 - x0) * u, hy);
    }
    p.cubicTo(cx - hw * 0.46 + sw, cy + hh * 0.50, cx - hw * 0.52,
        cy + hh * 0.24, cx - hw * 0.42, cy - hh * 0.02);
    p.close();
    g.drawPath(p, fill(col ?? const ui.Color(0xFF000000)));
    g.clipPath(p);
    g.drawRect(
        ui.Rect.fromLTWH(cx - hw, cy - hh, hw * 2, hh * 2.4),
        ui.Paint()
          ..shader = linear(
              ui.Offset(0, cy - hh * 0.36),
              ui.Offset(0, cy + hh * 0.16),
              <ui.Color>[
                rgba(255, 255, 255, 0),
                rgba(255, 255, 255, 0.14),
                rgba(255, 255, 255, 0),
              ],
              const <double>[0, 0.52, 1]));
    g.drawRect(
        ui.Rect.fromLTWH(cx - hw, cy + hh * 0.20, hw * 2, hh),
        ui.Paint()
          ..shader = linear(
              ui.Offset(0, cy + hh * 0.20),
              ui.Offset(0, cy + hh * 0.76),
              <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.60)],
              const <double>[0, 1]));
    g.restore();
    return;
  }
  g.save();
  final ui.Color sc = strandCol ?? const ui.Color(0xFF000000);
  final double lw = math.max(0.9, hw * 0.020);
  for (int i = 0; i < 13; i++) {
    final double u = i / 12, a = -math.pi * 0.94 + u * math.pi * 0.88;
    final double x0 = cx + math.cos(a) * hw * 0.38;
    final double y0 = cy + math.sin(a) * hh * 0.30 - hh * 0.02;
    final double dl =
        lag * (0.3 + u * 1.1) + math.sin(t * 1.3 + i * 2.3) * hw * 0.025;
    final double len = hh * (0.28 + math.sin(i * 2.1).abs() * 0.30);
    final double alpha = 0.45 + 0.45 * math.sin(i * 1.7).abs();
    final ui.Path p = ui.Path()..moveTo(x0, y0);
    p.quadraticBezierTo(x0 + dl * 0.7, y0 + len * 0.6,
        x0 + dl * 2.0 + (u - 0.5) * hw * 0.12, y0 + len);
    g.drawPath(
        p,
        stroke(
            sc.withValues(
                alpha: clampD(sc.a * alpha, 0, 1)),
            lw,
            cap: ui.StrokeCap.round));
  }
  g.restore();
}
