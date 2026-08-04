// FINAL BROADCAST — THE EIGHT, and the face-plate system they are built on.
//
// Straight port of the HTML's "FACE PLATES" block (bakeHead / bakeRim / bakeSSS
// / tintPlate / wetSpec / drawShroud / drawHair / mottle / FOLD / SHOULDER), the
// pre-baked noise tiles, bodySil(), seedNum() and drawAnom() for all eight
// anomalies.
//
// Everything here draws into the 320x240 FEED canvas coordinate space, which in
// the HTML has imageSmoothingEnabled = false — so every drawImage on the feed
// goes through nearestPaint(). The plates themselves are baked on smoothing-on
// contexts, so their internal MOTTLE pass uses smoothPaint(). That asymmetry is
// in the original and is load-bearing: it is what makes the 0.52x head downscale
// crunchy instead of soft.
//
// canvas2d applies globalCompositeOperation PER DRAW, not per group, so every
// separable blend ("lighter" / "multiply" / "screen" / "soft-light") is ported
// as a blendMode on that draw's Paint. Only the Porter-Duff ops
// (destination-in / destination-out / source-in / source-atop) get a saveLayer,
// because only those need the "whole surface" fenced to an offscreen — that is
// the bakers and tintPlate.
//
// Portable: dart:ui + package:flutter/painting only.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:final_broadcast/src/bake.dart';
import 'package:final_broadcast/src/consts.dart';

// ---------------------------------------------------------------------------
// 0. SMALL CANVAS2D SHIMS
// ---------------------------------------------------------------------------

/// `ctx.fillRect(x,y,w,h)`.
void fillRect(ui.Canvas g, double x, double y, double w, double h, ui.Color c,
    {ui.BlendMode mode = ui.BlendMode.srcOver}) {
  g.drawRect(ui.Rect.fromLTWH(x, y, w, h), fill(c, mode: mode));
}

/// `ctx.fillRect` with a shader instead of a colour.
void fillRectShader(
    ui.Canvas g, double x, double y, double w, double h, ui.Shader sh,
    {ui.BlendMode mode = ui.BlendMode.srcOver}) {
  g.drawRect(
      ui.Rect.fromLTWH(x, y, w, h),
      ui.Paint()
        ..shader = sh
        ..blendMode = mode
        ..isAntiAlias = true);
}

/// `ctx.ellipse(cx,cy,rx,ry,rot,0,TAU)` + fill/stroke.
void drawEllipse(ui.Canvas g, double cx, double cy, double rx, double ry,
    double rot, ui.Paint p) {
  if (rot == 0) {
    g.drawOval(ui.Rect.fromLTRB(cx - rx, cy - ry, cx + rx, cy + ry), p);
    return;
  }
  g.save();
  g.translate(cx, cy);
  g.rotate(rot);
  g.drawOval(ui.Rect.fromLTRB(-rx, -ry, rx, ry), p);
  g.restore();
}

/// The same colour with `globalAlpha` folded in, the way canvas2d does it.
ui.Color withGlobalAlpha(ui.Color c, double ga) =>
    c.withValues(alpha: clampD(c.a * ga, 0, 1));

/// JS `seedNum(n)` — the hash behind THE NIELSEN MAN's number field.
/// Reproduces `(n*2654435761)>>>0` exactly on both the VM and the web.
int seedNum(int n) => ((n * 2654435761) & 0xFFFFFFFF) % 10000;

/// Text drawn on the feed is mostly static, but a few labels pulse their alpha,
/// which would grow an unbounded TextPainter cache. This one is capped.
final TextCache feedText = TextCache();

/// Drops [feedText] once it has grown past what one frame can possibly need.
/// Called at the end of every feed frame.
void trimFeedText() {
  // THE NIELSEN MAN alone puts 144 fresh strings on screen every half second.
  if (feedText.length > 600) feedText.clear();
}

// ---------------------------------------------------------------------------
// 1. BAKED PLATES
// ---------------------------------------------------------------------------

/// The eight 180x135 grain tiles the whole game shuffles through.
/// Empty until [initEntities] completes; every user must tolerate that.
List<ui.Image> noiseTiles = const <ui.Image>[];

/// JS `noiseTiles[(t*rate|0)%8]`.
ui.Image? noiseTile(double t, double rate) {
  if (noiseTiles.isEmpty) return null;
  final i = (t * rate).toInt() % noiseTiles.length;
  return noiseTiles[i < 0 ? i + noiseTiles.length : i];
}

/// 5-octave value noise, 192x192. NOT one of the [noiseTiles].
ui.Image? mottleImage;

/// One cloth fold: shadow / core / shadow, 64x1.
ui.Image? foldImage;

/// The lit top of a shoulder, 64x32.
ui.Image? shoulderImage;

/// bakeHead()'s landmark record — JS `plate.lm`.
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

  /// lm.CX
  final double cx;

  /// lm.W
  final double w;
  final double brow, eye, nose, mouth, jaw, chin;
}

/// A baked 256x320 grayscale face: the plate itself, its silhouette (used as a
/// mask by every derived plate) and the landmarks the puppet furniture is
/// painted against.
class FacePlate {
  const FacePlate(this.img, this.sil, this.lm);
  final ui.Image img;
  final ui.Image sil;
  final HeadLandmarks lm;
}

/// JS HEADS{} — keyed by anomaly id.
Map<String, FacePlate> heads = const <String, FacePlate>{};

/// JS RIMS{} — the rim-light crescent baked out of each silhouette.
Map<String, ui.Image> rims = const <String, ui.Image>{};

/// JS SSSs{} — light bleeding through thin flesh.
Map<String, ui.Image> sss = const <String, ui.Image>{};

bool _ready = false;

/// True once every plate exists. Painters draw their backgrounds regardless and
/// simply skip the plate layers until this flips.
bool get entitiesReady => _ready;

/// bakeHead()'s option bag.
class HeadOpts {
  const HeadOpts({
    this.gaunt = 0,
    this.wide = 1,
    this.child = 0,
    this.hollow = false,
    this.frown = false,
    this.gaze = 0,
    this.key = -1,
  });
  final double gaunt, wide, child, gaze;
  final bool hollow, frown;

  /// JS `o.key === undefined ? -1 : o.key` — which side the key light is on.
  final double key;
}

/// JS `HEADS = {...}`.
const Map<String, HeadOpts> kHeadOpts = <String, HeadOpts>{
  'snow': HeadOpts(gaunt: 1.0, wide: 0.92, hollow: true),
  'sleep': HeadOpts(gaunt: 0.10, wide: 1.12, gaze: 0.35),
  'vert': HeadOpts(gaunt: 0.75, wide: 0.78, hollow: true),
  'dead': HeadOpts(gaunt: 0.55, wide: 1.00, hollow: true, frown: true),
  'card': HeadOpts(child: 1, wide: 0.94, frown: true),
  'rerun': HeadOpts(gaunt: 0.35, wide: 1.00, gaze: -0.4),
  'niel': HeadOpts(gaunt: 0.55, wide: 0.90, frown: true, key: 1),
  'call': HeadOpts(gaunt: 0.80, wide: 0.86, hollow: true),
};

const double _hw = 256; // HW
const double _hh = 320; // HH

/// Bakes everything in this file. Call once, await it, before the first frame.
/// Safe to call twice.
Future<void> initEntities() async {
  if (_ready) return;

  // --- pre-baked noise tiles -------------------------------------------------
  final tiles = <ui.Image>[];
  for (var k = 0; k < kNoiseTileCount; k++) {
    tiles.add(await _grayNoise(kNoiseTileW, kNoiseTileH));
  }
  noiseTiles = tiles;

  // --- MOTTLE: 5-octave value noise, the upscale IS the blur -----------------
  const octs = <List<double>>[
    [5, 0.50],
    [11, 0.34],
    [24, 0.22],
    [56, 0.14],
    [120, 0.09],
  ];
  final octImgs = <ui.Image>[];
  for (final o in octs) {
    final n = o[0].toInt();
    octImgs.add(await _grayNoise(n, n));
  }
  const double ms = kMottleSize * 1.0;
  mottleImage = await bakeImage(kMottleSize, kMottleSize, (c) {
    fillRect(c, 0, 0, ms, ms, const ui.Color(0xFF808080));
    for (var i = 0; i < octImgs.length; i++) {
      drawImageStretch(c, octImgs[i], const ui.Rect.fromLTWH(0, 0, ms, ms),
          smoothPaint(alpha: octs[i][1]));
    }
  });
  for (final im in octImgs) {
    im.dispose();
  }

  // --- FOLD / SHOULDER -------------------------------------------------------
  foldImage = await bakeImage(kFoldW, kFoldH, (c) {
    fillRectShader(
      c,
      0,
      0,
      kFoldW.toDouble(),
      kFoldH.toDouble(),
      linear(
        ui.Offset.zero,
        const ui.Offset(64, 0),
        <ui.Color>[
          rgba(0, 0, 0, 0),
          rgba(0, 0, 0, 0.60),
          rgba(255, 255, 255, 0.20),
          rgba(255, 255, 255, 0.05),
          rgba(0, 0, 0, 0.44),
          rgba(0, 0, 0, 0),
        ],
        <double>[0.00, 0.26, 0.48, 0.62, 0.80, 1.00],
      ),
    );
  });

  shoulderImage = await bakeImage(kShoulderW, kShoulderH, (c) {
    fillRectShader(
      c,
      0,
      0,
      64,
      32,
      linear(ui.Offset.zero, const ui.Offset(0, 32),
          <ui.Color>[rgba(255, 255, 255, 0.26), rgba(255, 255, 255, 0)],
          <double>[0, 1]),
    );
    fillRectShader(
      c,
      0,
      0,
      64,
      32,
      radialR0(const ui.Offset(32, 1), 1, 17,
          <ui.Color>[rgba(0, 0, 0, 0.80), rgba(0, 0, 0, 0)], <double>[0, 1]),
    );
  });

  // --- the eight faces, their rims and their subsurface ----------------------
  final h = <String, FacePlate>{};
  final r = <String, ui.Image>{};
  final ss = <String, ui.Image>{};
  for (final e in kHeadOpts.entries) {
    final plate = await bakeHead(e.value);
    h[e.key] = plate;
    r[e.key] = await bakeRim(plate.sil, -9, -7, rgba(190, 235, 255, 0.95),
        rgba(70, 120, 150, 0.25), 3);
    ss[e.key] = await bakeSSS(plate.sil, _hw * 0.5, _hh * 0.62, _hw * 0.42,
        rgba(255, 90, 60, 0.55));
  }
  heads = h;
  rims = r;
  sss = ss;

  _ready = true;
}

Future<ui.Image> _grayNoise(int w, int h) {
  final rnd = math.Random();
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < px.length; i += 4) {
    final v = (rnd.nextDouble() * 255).toInt();
    px[i] = v;
    px[i + 1] = v;
    px[i + 2] = v;
    px[i + 3] = 255;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

// ---------------------------------------------------------------------------
// 2. THE BAKERS
// ---------------------------------------------------------------------------

/// JS `vblob(x,cx,cy,rx,ry,rot,col,soft)` — a soft value blob. Anatomy in this
/// file is value, not line work, and this is the brush that paints it.
void vblob(ui.Canvas x, double cx, double cy, double rx, double ry, double rot,
    ui.Color col, double soft,
    {ui.BlendMode mode = ui.BlendMode.srcOver}) {
  x.save();
  x.translate(cx, cy);
  if (rot != 0) x.rotate(rot);
  x.scale(1, ry / rx);
  final p = ui.Paint()
    ..isAntiAlias = true
    ..blendMode = mode
    ..shader = radialR0(ui.Offset.zero, rx * soft, rx,
        <ui.Color>[col, col.withValues(alpha: 0)], <double>[0, 1]);
  x.drawCircle(ui.Offset.zero, rx, p);
  x.restore();
}

/// JS `headPath()` — cranium -> temple -> zygomatic -> gonion -> chin.
ui.Path headPath(HeadOpts o) {
  final wide = o.wide, child = o.child;
  const cx = _hw / 2;
  final w = _hw * 0.33 * wide;
  final top = _hh * (0.13 - child * 0.02), chin = _hh * (0.93 - child * 0.05);
  final eye = _hh * (0.44 + child * 0.03), jaw = _hh * (0.74 - child * 0.03);
  final p = ui.Path()..moveTo(cx, top);
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

/// JS `bakeHead(o)`.
Future<FacePlate> bakeHead(HeadOpts o) async {
  final gaunt = o.gaunt, child = o.child, wide = o.wide;
  final key = o.key;
  final path = headPath(o);

  final sil = await bakeImage(kHeadW, kHeadH, (s) {
    s.drawPath(path, fill(const ui.Color(0xFFFFFFFF)));
  });

  const cx = _hw / 2;
  final w = _hw * 0.33 * wide;
  final brow = _hh * (0.42 + child * 0.04), eye = brow + _hh * 0.045;
  final nose = eye + _hh * (child != 0 ? 0.100 : 0.130);
  final mouth = nose + _hh * (child != 0 ? 0.075 : 0.085);
  final jaw = _hh * (0.74 - child * 0.03), chin = _hh * (0.93 - child * 0.05);

  const b = ui.Rect.fromLTWH(0, 0, _hw, _hh);

  final img = await bakeImage(kHeadW, kHeadH, (c) {
    // Everything is fenced in one group so the destination-in below eats this
    // plate and nothing else.
    groupLayer(c, b, (x) {
      x.drawPath(path, fill(const ui.Color(0xFF6E6E6E)));
      vblob(x, cx + key * w * 0.10, brow - _hh * 0.105, w * 1.02, _hh * 0.155, 0,
          rgba(255, 255, 255, 0.30), 0.05);
      vblob(x, cx, nose + _hh * 0.015, w * 0.68, _hh * 0.120, 0,
          rgba(255, 255, 255, 0.18), 0);
      vblob(x, cx - w * 0.94, brow - _hh * 0.010, w * 0.34, _hh * 0.105, 0,
          rgba(0, 0, 0, 0.50), 0);
      vblob(x, cx + w * 0.94, brow - _hh * 0.010, w * 0.34, _hh * 0.105, 0,
          rgba(0, 0, 0, 0.50), 0);

      // BROW RIDGE — do not soften
      final ridge = ui.Path()..moveTo(cx - w * 0.88, brow - _hh * 0.026);
      ridge.quadraticBezierTo(
          cx, brow - _hh * 0.080, cx + w * 0.88, brow - _hh * 0.026);
      ridge.quadraticBezierTo(
          cx, brow - _hh * 0.046, cx - w * 0.88, brow - _hh * 0.026);
      x.drawPath(ridge, fill(rgba(255, 255, 255, 0.26)));
      vblob(x, cx - w * 0.46, brow + _hh * 0.014, w * 0.46, _hh * 0.046, -0.12,
          rgba(0, 0, 0, 0.70), 0.20);
      vblob(x, cx + w * 0.46, brow + _hh * 0.014, w * 0.46, _hh * 0.046, 0.12,
          rgba(0, 0, 0, 0.70), 0.20);

      for (final sg in const <double>[-1, 1]) {
        final ox = cx + sg * w * 0.46;
        vblob(x, ox, eye - _hh * 0.004, w * 0.42, _hh * 0.064, 0,
            rgba(0, 0, 0, 0.48 + gaunt * 0.44), 0.10);
        vblob(x, ox + sg * w * 0.18, eye - _hh * 0.022, w * 0.20, _hh * 0.036, 0,
            rgba(0, 0, 0, 0.55), 0);
        if (o.hollow) continue;
        vblob(x, ox, eye + _hh * 0.002, w * 0.21, _hh * 0.038, 0,
            rgba(255, 255, 255, 0.50), 0.10);
        vblob(x, ox - sg * w * 0.05, eye + _hh * 0.012, w * 0.12, _hh * 0.018, 0,
            rgba(255, 255, 255, 0.34), 0);
        vblob(x, ox, eye - _hh * 0.026, w * 0.25, _hh * 0.024, 0,
            rgba(0, 0, 0, 0.62), 0.10);
        drawEllipse(x, ox, eye + _hh * 0.026, w * 0.19, _hh * 0.005, 0,
            fill(rgba(255, 255, 255, 0.42)));
        drawEllipse(x, ox + o.gaze * w * 0.07, eye + _hh * 0.004, w * 0.085,
            _hh * 0.019, 0, fill(rgba(0, 0, 0, 0.88)));
      }

      vblob(x, cx - key * w * 0.09, (brow + nose) / 2, w * 0.11, _hh * 0.078, 0,
          rgba(255, 255, 255, 0.32), 0.15);
      vblob(x, cx + key * w * 0.17, (brow + nose) / 2 + _hh * 0.010, w * 0.14,
          _hh * 0.072, 0, rgba(0, 0, 0, 0.40), 0);
      vblob(x, cx, nose - _hh * 0.006, w * 0.22, _hh * 0.030, 0,
          rgba(255, 255, 255, 0.24), 0.05);
      for (final sg in const <double>[-1, 1]) {
        vblob(x, cx + sg * w * 0.25, nose - _hh * 0.002, w * 0.10, _hh * 0.020,
            0, rgba(0, 0, 0, 0.52), 0);
      }
      for (final sg in const <double>[-1, 1]) {
        drawEllipse(x, cx + sg * w * 0.115, nose + _hh * 0.008, w * 0.055,
            _hh * 0.012, sg * 0.35, fill(rgba(0, 0, 0, 0.85)));
      }
      vblob(x, cx, nose + _hh * 0.030, w * 0.30, _hh * 0.024, 0,
          rgba(0, 0, 0, 0.38), 0);

      final dr = o.frown ? 1.0 : 0.0;
      final lips = ui.Path()..moveTo(cx - w * 0.34, mouth);
      lips.quadraticBezierTo(
          cx, mouth + _hh * (0.012 + dr * 0.012), cx + w * 0.34, mouth);
      lips.quadraticBezierTo(
          cx, mouth + _hh * (0.024 + dr * 0.014), cx - w * 0.34, mouth);
      x.drawPath(lips, fill(rgba(0, 0, 0, 0.80)));
      vblob(x, cx, mouth - _hh * 0.015, w * 0.26, _hh * 0.012, 0,
          rgba(255, 255, 255, 0.20), 0);
      vblob(x, cx, mouth + _hh * 0.032, w * 0.22, _hh * 0.016, 0,
          rgba(0, 0, 0, 0.40), 0);

      for (final sg in const <double>[-1, 1]) {
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

      final mo = mottleImage;
      if (mo != null) {
        drawImageStretch(x, mo, b,
            smoothPaint(alpha: 0.45 + gaunt * 0.25, mode: ui.BlendMode.softLight));
      }

      withBlend(x, b, ui.BlendMode.dstIn,
          (m) => drawImageStretch(m, sil, b, smoothPaint()));

      withBlend(x, b, ui.BlendMode.srcATop, (m) {
        fillRectShader(
          m,
          0,
          0,
          _hw,
          _hh,
          radialFocal(
            ui.Offset(cx + key * w * 0.25, brow),
            w * 0.55,
            const ui.Offset(cx, _hh * 0.55),
            w * 1.65,
            <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.58)],
            <double>[0, 1],
          ),
        );
      });
    });
  });

  return FacePlate(
    img,
    sil,
    HeadLandmarks(
      cx: cx,
      w: w,
      brow: brow,
      eye: eye,
      nose: nose,
      mouth: mouth,
      jaw: jaw,
      chin: chin,
    ),
  );
}

/// JS `bakeRim(sil,dx,dy,c0,c1,blur)` — draw the silhouette, knock out a copy
/// shifted toward the light, keep the crescent. This is what stops a dark shape
/// reading as a hole cut in the background.
Future<ui.Image> bakeRim(ui.Image sil, double dx, double dy, ui.Color c0,
    ui.Color c1, double blur) {
  final w = sil.width.toDouble(), h = sil.height.toDouble();
  final b = ui.Rect.fromLTWH(0, 0, w, h);
  void body(ui.Canvas g) {
    groupLayer(g, b, (x) {
      drawImageStretch(x, sil, b, smoothPaint());
      withBlend(x, b, ui.BlendMode.dstOut,
          (m) => drawImageStretch(m, sil, ui.Rect.fromLTWH(dx, dy, w, h),
              smoothPaint()));
      withBlend(x, b, ui.BlendMode.srcIn, (m) {
        fillRectShader(m, 0, 0, w, h,
            linear(ui.Offset.zero, ui.Offset(0, h), <ui.Color>[c0, c1], <double>[0, 1]));
      });
    });
  }

  return bakeImage(sil.width, sil.height, (c) {
    if (blur <= 0) {
      body(c);
    } else {
      // CSS `filter: blur(Npx)` is a Gaussian with standard deviation N.
      withBlur(c, b.inflate(blur * 3), blur, body);
    }
  });
}

/// JS `bakeSSS(sil,cx,cy,r,col)` — light bleeding through thin flesh.
Future<ui.Image> bakeSSS(
    ui.Image sil, double cx, double cy, double r, ui.Color col) {
  final w = sil.width.toDouble(), h = sil.height.toDouble();
  final b = ui.Rect.fromLTWH(0, 0, w, h);
  return bakeImage(sil.width, sil.height, (c) {
    groupLayer(c, b, (x) {
      fillRectShader(
          x,
          0,
          0,
          w,
          h,
          radialR0(ui.Offset(cx, cy), 0, r,
              <ui.Color>[col, col.withValues(alpha: 0)], <double>[0, 1]));
      withBlend(x, b, ui.BlendMode.dstIn,
          (m) => drawImageStretch(m, sil, b, smoothPaint()));
    });
  });
}

/// JS `tintPlate(plate,col,mode)` + the drawImage that always followed it.
/// The HTML tinted into a scratch canvas and drew the result immediately; here
/// the same three ops happen in destination space inside one layer.
void drawTintedPlate(
    ui.Canvas g, FacePlate plate, ui.Color col, ui.Rect dst,
    {ui.BlendMode mode = ui.BlendMode.multiply, double alpha = 1.0}) {
  groupLayer(g, dst, (c) {
    drawImageStretch(c, plate.img, dst, nearestPaint());
    c.drawRect(dst, fill(col, mode: mode));
    withBlend(c, dst, ui.BlendMode.dstIn,
        (m) => drawImageStretch(m, plate.sil, dst, nearestPaint()));
  }, alpha: alpha);
}

// ---------------------------------------------------------------------------
// 3. SURFACE DETAIL
// ---------------------------------------------------------------------------

/// One hard specular on a real ridge. A single hard highlight on a dark form is
/// what the eye reads as WET, and it is the cheapest fright in the file.
class WetPt {
  const WetPt(this.x, this.y, this.rx, this.ry, this.rot, this.a);
  final double x, y, rx, ry, rot, a;
}

/// JS `wetSetFor(lm)`.
List<WetPt> wetSetFor(HeadLandmarks lm) {
  final w = lm.w;
  return <WetPt>[
    WetPt(lm.cx - w * 0.46, lm.eye + _hh * 0.024, w * 0.15, _hh * 0.0045, 0.05,
        0.55),
    WetPt(lm.cx + w * 0.46, lm.eye + _hh * 0.024, w * 0.15, _hh * 0.0045, -0.05,
        0.55),
    WetPt(lm.cx - w * 0.52, lm.eye - _hh * 0.004, w * 0.030, _hh * 0.008, 0.00,
        0.85),
    WetPt(lm.cx + w * 0.40, lm.eye - _hh * 0.004, w * 0.030, _hh * 0.008, 0.00,
        0.85),
    WetPt(lm.cx, lm.mouth + _hh * 0.006, w * 0.20, _hh * 0.005, 0.00, 0.40),
    WetPt(lm.cx - w * 0.10, lm.nose + _hh * 0.006, w * 0.035, _hh * 0.006, 0.30,
        0.30),
  ];
}

/// JS `wetSpec(g,plate,ox,oy,w,h,pts,t)`. The `plate` argument was unused in the
/// original — the points are already in plate space — so it is not taken here.
void wetSpec(ui.Canvas g, double ox, double oy, double w, double h,
    List<WetPt> pts, double t) {
  g.save();
  g.translate(ox, oy);
  g.scale(w / _hw, h / _hh);
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final fl = 0.72 + 0.28 * math.sin(t * (2.1 + i * 0.7) + i);
    g.save();
    g.translate(p.x, p.y);
    g.rotate(p.rot);
    drawEllipse(g, 0, 0, p.rx, p.ry, 0,
        fill(rgba(255, 252, 244, clampD(p.a * fl, 0, 1)), mode: ui.BlendMode.plus));
    g.restore();
  }
  g.restore();
}

/// JS `mottle(g,x,y,w,h,alpha,mode)`.
void mottle(ui.Canvas g, double x, double y, double w, double h, double alpha,
    [ui.BlendMode mode = ui.BlendMode.softLight]) {
  final mo = mottleImage;
  if (mo == null) return;
  drawImageStretch(g, mo, ui.Rect.fromLTWH(x, y, w, h),
      nearestPaint(alpha: alpha, mode: mode));
}

/// JS `shroudPath()` — the hem is a wave, never a line.
ui.Path shroudPath(
    double x0, double y0, double w, double h, double t, double seed) {
  final top = w * 0.40;
  final p = ui.Path()..moveTo(x0 - top, y0);
  p.cubicTo(x0 - top - w * 0.12, y0 + h * 0.20, x0 - w * 0.44, y0 + h * 0.58,
      x0 - w * 0.52, y0 + h);
  for (var i = 0; i <= 12; i++) {
    final u = i / 12, hx = x0 - w * 0.52 + u * w * 1.04;
    final hy = y0 +
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

/// JS `drawShroud()`.
void drawShroud(ui.Canvas g, double x0, double y0, double w, double h, double t,
    ui.Color col, double seed) {
  g.save();
  final path = shroudPath(x0, y0, w, h, t, seed);
  g.drawPath(path, fill(col));
  g.clipPath(path);
  final fo = foldImage;
  for (var i = 0; i < 6; i++) {
    final ph = seed * 3 + i * 1.93;
    final fx = x0 + (i / 5 - 0.5) * w * 0.94 + math.sin(t * 0.5 + ph) * w * 0.03;
    final fw = w * (0.16 + 0.13 * math.sin(ph).abs());
    final a = 0.26 + 0.30 * math.sin(ph * 1.7).abs();
    if (fo != null) {
      drawImageStretch(g, fo,
          ui.Rect.fromLTWH(fx - fw / 2, y0 - h * 0.10, fw, h * 1.25),
          nearestPaint(alpha: a));
    }
  }
  final so = shoulderImage;
  if (so != null) {
    drawImageStretch(g, so,
        ui.Rect.fromLTWH(x0 - w * 0.58, y0 - h * 0.09, w * 1.16, h * 0.46),
        nearestPaint());
  }
  mottle(g, x0 - w * 0.6, y0 - h * 0.1, w * 1.2, h * 1.2, 0.30);
  g.restore();
}

/// JS `drawHair()`. MASS first (survives the downscale), then sheen, then
/// strands. Layer 0 goes behind the head, layer 1 in front. Roots lag the head
/// by [lag], which is the cue that says this is attached to something that just
/// moved.
void drawHair(ui.Canvas g, double cx, double cy, double hw, double hh, double t,
    double lag, ui.Color? col, ui.Color? strandCol, int layer) {
  final sw = math.sin(t * 1.05) * hw * 0.05 + lag;
  if (layer == 0) {
    if (col == null) return;
    g.save();
    final p = ui.Path()..moveTo(cx - hw * 0.42, cy - hh * 0.02);
    p.cubicTo(cx - hw * 0.48, cy - hh * 0.40, cx + hw * 0.48, cy - hh * 0.40,
        cx + hw * 0.42, cy - hh * 0.02);
    p.cubicTo(cx + hw * 0.52, cy + hh * 0.26, cx + hw * 0.46 + sw,
        cy + hh * 0.52, cx + hw * 0.34 + sw * 1.8, cy + hh * 0.74);
    for (var i = 1; i <= 9; i++) {
      final u = i / 9;
      final x0 = cx + hw * 0.34 + sw * 1.8, x1 = cx - hw * 0.34 + sw * 1.8;
      final hy = cy +
          hh * 0.74 -
          math.sin(u * 9.3 + t * 0.6) * hh * 0.035 -
          math.sin(u * 3.7 + 1.4) * hh * 0.065;
      p.lineTo(x0 + (x1 - x0) * u, hy);
    }
    p.cubicTo(cx - hw * 0.46 + sw, cy + hh * 0.50, cx - hw * 0.52,
        cy + hh * 0.24, cx - hw * 0.42, cy - hh * 0.02);
    p.close();
    g.drawPath(p, fill(col));
    g.clipPath(p);
    fillRectShader(
      g,
      cx - hw,
      cy - hh,
      hw * 2,
      hh * 2.4,
      linear(
        ui.Offset(0, cy - hh * 0.36),
        ui.Offset(0, cy + hh * 0.16),
        <ui.Color>[
          rgba(255, 255, 255, 0),
          rgba(255, 255, 255, 0.14),
          rgba(255, 255, 255, 0),
        ],
        <double>[0, 0.52, 1],
      ),
    );
    fillRectShader(
      g,
      cx - hw,
      cy + hh * 0.20,
      hw * 2,
      hh,
      linear(ui.Offset(0, cy + hh * 0.20), ui.Offset(0, cy + hh * 0.76),
          <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.60)], <double>[0, 1]),
    );
    g.restore();
    return;
  }
  if (strandCol == null) return;
  g.save();
  final lw = math.max(0.9, hw * 0.020);
  for (var i = 0; i < 13; i++) {
    final u = i / 12, a = -math.pi * 0.94 + u * math.pi * 0.88;
    final x0 = cx + math.cos(a) * hw * 0.38,
        y0 = cy + math.sin(a) * hh * 0.30 - hh * 0.02;
    final dl = lag * (0.3 + u * 1.1) + math.sin(t * 1.3 + i * 2.3) * hw * 0.025;
    final len = hh * (0.28 + math.sin(i * 2.1).abs() * 0.30);
    final ga = 0.45 + 0.45 * math.sin(i * 1.7).abs();
    final p = ui.Path()..moveTo(x0, y0);
    p.quadraticBezierTo(x0 + dl * 0.7, y0 + len * 0.6,
        x0 + dl * 2.0 + (u - 0.5) * hw * 0.12, y0 + len);
    g.drawPath(
        p,
        stroke(withGlobalAlpha(strandCol, ga), lw,
            cap: ui.StrokeCap.round));
  }
  g.restore();
}

// ---------------------------------------------------------------------------
// 4. THE REPEAT'S TRAIL BUFFER
// ---------------------------------------------------------------------------
//
// THE REPEAT accumulates into a persistent 320x240 canvas with a slow decay, so
// the smear actually reads. There is no persistent drawing surface in dart:ui,
// so the buffer is re-baked each frame from the previous frame's image. One
// small offscreen per frame, and only while THE REPEAT is on the tube.

ui.Image? _trail;

/// Throws the trail buffer away. Call when the tube goes dark.
void resetAnomTrail() {
  _trail?.dispose();
  _trail = null;
}

// ---------------------------------------------------------------------------
// 5. FIGURES AND FRAMING HELPERS
// ---------------------------------------------------------------------------

const double _fw = 320; // FW
const double _fh = 240; // FH
const ui.Rect _feedRect = ui.Rect.fromLTWH(0, 0, _fw, _fh);

/// JS `bodySil(g,x,y,s,col)` — generic standing figure; [y] is the ground line.
/// Kept as the file's generic figure primitive; the anomalies each author their
/// own now, because a shared body is exactly what made them look alike.
void bodySil(ui.Canvas g, double x, double y, double s, ui.Color col) {
  final p = fill(col);
  drawEllipse(g, x, y - 64 * s, 11 * s, 13 * s, 0, p); // head
  final torso = ui.Path()..moveTo(x - 15 * s, y - 14 * s);
  torso.lineTo(x - 11 * s, y - 50 * s);
  torso.lineTo(x + 11 * s, y - 50 * s);
  torso.lineTo(x + 15 * s, y - 14 * s);
  torso.close();
  g.drawPath(torso, p);
  g.drawRect(ui.Rect.fromLTWH(x - 12 * s, y - 16 * s, 8 * s, 16 * s), p); // legs
  g.drawRect(ui.Rect.fromLTWH(x + 4 * s, y - 16 * s, 8 * s, 16 * s), p);
  g.drawRect(ui.Rect.fromLTWH(x - 20 * s, y - 46 * s, 6 * s, 26 * s), p); // arms
  g.drawRect(ui.Rect.fromLTWH(x + 14 * s, y - 46 * s, 6 * s, 26 * s), p);
}

/// Places a baked 256x320 plate so the plate-normalised point ([ux],[uy]) lands
/// on ([sx],[sy]) with the plate [w] wide. Height follows the plate's own 4:5
/// aspect, so a face is never stretched no matter how it is framed.
ui.Rect _plateRect(double sx, double sy, double w, double ux, double uy) {
  final h = w * (_hh / _hw);
  return ui.Rect.fromLTWH(sx - ux * w, sy - uy * h, w, h);
}

/// Runs [body] in PLATE space (0..256 x 0..320) over a plate already placed at
/// [dst], so landmark coordinates can be written down directly.
void _inPlate(ui.Canvas g, ui.Rect dst, void Function(ui.Canvas c) body) {
  g.save();
  g.translate(dst.left, dst.top);
  g.scale(dst.width / _hw, dst.height / _hh);
  body(g);
  g.restore();
}

/// Where a plate-space point ends up on the feed, for a plate placed at [dst].
ui.Offset _plateToScreen(ui.Rect dst, double px, double py) => ui.Offset(
    dst.left + px / _hw * dst.width, dst.top + py / _hh * dst.height);

/// One grain tile over [rect].
void _grain(ui.Canvas g, double t, double rate, double alpha,
    {ui.Rect rect = _feedRect, ui.BlendMode? mode}) {
  final n = noiseTile(t, rate);
  if (n == null) return;
  drawImageStretch(g, n, rect, nearestPaint(alpha: alpha, mode: mode));
}

/// A multiply vignette. [at] is where the picture is brightest, which is also
/// where the composition wants the eye to land.
void _vignette(
    ui.Canvas g, ui.Offset at, double r0, double r1, ui.Color edge) {
  fillRectShader(
    g,
    0,
    0,
    _fw,
    _fh,
    radialR0(at, r0, r1, <ui.Color>[const ui.Color(0xFFFFFFFF), edge],
        <double>[0, 1]),
    mode: ui.BlendMode.multiply,
  );
}

/// A spike that is near zero most of the time and 1 for an instant — for
/// discharges, ring flashes and reveals that must not read as a pulse.
double _spike(double t, double rate, double sharpness) =>
    math.pow(clampD(math.sin(t * rate), 0, 1), sharpness).toDouble();

// ---------------------------------------------------------------------------
// 6. drawAnom — THE EIGHT
// ---------------------------------------------------------------------------
//
// EIGHT COMPOSITIONS, not eight skins on one composition. The axes that are
// deliberately different across the set:
//
//   id     framing                       camera      looks at you   motion
//   snow   extreme CU, overflows frame    eye level   yes, always    advances
//   sleep  medium, entering frame RIGHT   from below  yes, down      leans in
//   vert   extreme long shot, sliced      worm's eye  no (head off)  rolls
//   dead   no subject at all              —           —             collapses
//   card   flat tableau, subject small    from above  no (the doll)  static
//   rerun  long shot, back to camera      eye level   never          loops
//   niel   low 3/4, cropped at frame LEFT worm's eye  no (clipboard) steps in
//   call   deep focus, fg + far doorway   desk height late           approaches
//
// DEAD AIR and THE REPEAT never show a face. Every one of the eight gets
// visibly worse the longer `prog` runs.

/// JS `drawAnom(g,def,t,prog)`. [g] is the 320x240 feed canvas.
///
/// Clipped to the feed rect here rather than at the call site, because the
/// manual's preview plate and the jumpscare zoom both call in without a clip of
/// their own and several of these compositions run figures off the edge.
void drawAnom(ui.Canvas g, Anom def, double t, double prog) {
  final p = clampD(prog, 0, 1);
  g.save();
  g.clipRect(_feedRect);
  switch (def.id) {
    case 'snow':
      _drawSnow(g, t, p);
    case 'sleep':
      _drawSleep(g, t, p);
    case 'vert':
      _drawVert(g, t, p);
    case 'dead':
      _drawDead(g, t, p);
    case 'card':
      _drawCard(g, t, p);
    case 'rerun':
      _drawRerun(g, t, p);
    case 'niel':
      _drawNiel(g, t, p);
    case 'call':
      _drawCall(g, t, p);
  }
  g.restore();
  trimFeedText();
}

// --- 1. THE SNOW CRAWLER ----------------------------------------------------
//
// EXTREME CLOSE-UP. The plate is drawn at roughly twice the width of the frame
// and cropped on all four edges, so there is no outline anywhere — not even a
// jaw. The face is never painted, only used to modulate the grain: multiply
// where the skull occludes, lighten where it is lit. It ASSEMBLES.
//
// ESCALATION: it advances (the plate grows), the modulation deepens until the
// grain has visibly stopped being random, and past 40% two wet points appear in
// sockets that had nothing in them at all.
void _drawSnow(ui.Canvas g, double t, double p) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF000000));
  _grain(g, t, 24, 0.95);
  // a second, coarser tile at a different rate so the noise floor has depth
  // instead of being one flat fizz — a face can only hide in grain with depth
  final n2 = noiseTile(t + 3.7, 15);
  if (n2 != null) {
    drawImageStretch(g, n2,
        const ui.Rect.fromLTWH(-56, -42, _fw + 112, _fh + 84),
        nearestPaint(alpha: 0.38, mode: ui.BlendMode.screen));
  }

  final head = heads['snow'], rim = rims['snow'];
  var focus = const ui.Offset(_fw * 0.28, _fh * 0.40);

  if (head != null && rim != null) {
    final l = head.lm;
    final w = _fw * (1.95 + p * 0.80);
    final sx = _fw * 0.40 + math.sin(t * 0.27) * 3.5;
    final sy = _fh * 0.40 + math.sin(t * 0.19) * 2.5;
    final dst = _plateRect(sx, sy, w, l.cx / _hw, l.eye / _hh);

    // occlusion, then the lit side, then contrast: the grain organising
    drawImageStretch(
        g,
        head.img,
        dst,
        nearestPaint(
            alpha: clampD(0.32 + p * 0.65, 0, 0.90),
            mode: ui.BlendMode.multiply));
    drawImageStretch(
        g,
        head.img,
        dst,
        nearestPaint(
            alpha: clampD(0.16 + p * 0.50, 0, 0.66), mode: ui.BlendMode.plus));
    drawImageStretch(g, head.img, dst,
        nearestPaint(alpha: clampD(p * 0.52, 0, 0.52), mode: ui.BlendMode.overlay));
    drawImageStretch(
        g,
        rim,
        dst,
        nearestPaint(
            alpha: clampD((p - 0.28) * 1.7, 0, 0.90), mode: ui.BlendMode.plus));

    // it finds you: 'snow' is a hollow plate, so these sockets were empty
    final look = clampD((p - 0.40) / 0.34, 0, 1);
    if (look > 0) {
      final fl = 0.60 + 0.40 * math.sin(t * 7.3);
      _inPlate(g, dst, (c) {
        for (final sg in const <double>[-1, 1]) {
          final ex = l.cx + sg * l.w * 0.46;
          // a wet reflex, not a lamp: at this magnification anything bigger
          // than a couple of feed pixels reads as a light source
          vblob(c, ex, l.eye, l.w * 0.11, _hh * 0.014, 0,
              rgba(150, 195, 235, 0.10 * look), 0.10,
              mode: ui.BlendMode.plus);
          // rx/ry are RADII: at this magnification 0.024*w is a 13px lamp
          drawEllipse(
              c,
              ex - sg * l.w * 0.05,
              l.eye + _hh * 0.002,
              l.w * 0.009,
              _hh * 0.0020,
              0,
              fill(rgba(255, 253, 246, clampD(0.75 * look * fl, 0, 1)),
                  mode: ui.BlendMode.plus));
        }
      });
    }
    focus = _plateToScreen(dst, l.cx - l.w * 0.46, l.eye);
  }

  // the pool of light is on the near socket, not on the middle of the frame
  final ev = 24 + ((1 - p) * 26).round();
  _vignette(g, focus, 30 + (1 - p) * 36, 205,
      ui.Color.fromARGB(255, ev, ev, ev));
}

// --- 2. MR. SLEEPWELL -------------------------------------------------------
//
// The only BRIGHT frame in the game — "the picture whitens to a hospital
// brightness" — and he does not stand in it, he LEANS INTO it from the right
// edge, lit from below, looking down at the operator. Off-centre, tipped, and
// coming further in the whole time.
//
// Full plate stack: shroud, hair behind, subsurface through the latex, tinted
// plate, then the puppet furniture painted in PLATE space so the jaw hinge lands
// on the real cheek line and the rouge on the real malar.
//
// ESCALATION: he leans in and grows, the frame keeps whitening, the jaw hinge
// drops and the painted grin opens on more and more teeth.
void _drawSleep(ui.Canvas g, double t, double p) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFFDAD2C0));
  fillRectShader(
    g,
    0,
    0,
    _fw,
    _fh,
    radialFocal(
      const ui.Offset(_fw * 0.24, _fh * 0.14),
      6,
      const ui.Offset(_fw * 0.32, _fh * 0.30),
      250,
      <ui.Color>[rgba(255, 255, 252, 0.95), rgba(198, 190, 172, 0)],
      <double>[0, 1],
    ),
  );
  fillRect(g, 0, 0, _fw, _fh, rgba(255, 255, 255, clampD(p * 0.28, 0, 1)));
  _grain(g, t, 20, 0.13, mode: ui.BlendMode.overlay);

  final w = _fw * (0.56 + p * 0.30);
  final hh = w * (_hh / _hw);
  final hx = _fw * (0.84 - p * 0.28) + math.sin(t * 1.05) * 5;
  final hy = _fh * (0.34 + p * 0.10) + math.sin(t * 0.63) * 3;
  final lean = 0.30 + p * 0.34 + math.sin(t * 0.9) * 0.035;
  final lag = math.cos(t * 1.05) * 3.4;

  final head = heads['sleep'], rim = rims['sleep'], sub = sss['sleep'];

  g.save();
  g.translate(hx, hy);
  g.rotate(-lean);
  // the shroud hangs down-and-right out of the frame — he has come from there
  drawShroud(g, 0, hh * 0.44, w * 1.70, _fh * 0.82, t,
      const ui.Color(0xFF191324), 0.7);
  drawHair(g, 0, -hh * 0.16, w, hh, t, lag, rgba(16, 9, 14, 0.97), null, 0);

  if (head != null && rim != null && sub != null) {
    final dst = ui.Rect.fromLTWH(-w / 2, -hh / 2, w, hh);
    drawImageStretch(
        g, sub, dst, nearestPaint(alpha: 0.42, mode: ui.BlendMode.plus));
    drawTintedPlate(g, head, const ui.Color(0xFFEBD3AA), dst);

    final l = head.lm;
    _inPlate(g, dst, (c) {
      // KEY FROM BELOW — the camera is under him, which is the whole framing
      vblob(c, l.cx, l.chin - _hh * 0.050, l.w * 1.05, _hh * 0.150, 0,
          rgba(255, 246, 226, 0.36), 0.05, mode: ui.BlendMode.plus);
      vblob(c, l.cx, l.brow - _hh * 0.070, l.w * 1.15, _hh * 0.130, 0,
          rgba(26, 18, 24, 0.46), 0.10, mode: ui.BlendMode.multiply);

      // the jaw is hinged, and the hinge shows
      final drop = _hh * (0.004 + p * 0.052);
      final hinge = ui.Path()..moveTo(l.cx - l.w * 0.98, l.eye + _hh * 0.030);
      hinge.quadraticBezierTo(l.cx, l.mouth - _hh * 0.010 + drop,
          l.cx + l.w * 0.98, l.eye + _hh * 0.030);
      c.drawPath(hinge, stroke(rgba(24, 12, 10, 0.55), 3));

      // THE GRIN, opening on more teeth the longer he is allowed to stay
      final grin = ui.Path()..moveTo(l.cx - l.w * 0.56, l.mouth - _hh * 0.004);
      grin.quadraticBezierTo(l.cx, l.mouth + _hh * 0.030 + drop,
          l.cx + l.w * 0.56, l.mouth - _hh * 0.004);
      grin.quadraticBezierTo(l.cx, l.mouth + _hh * 0.008, l.cx - l.w * 0.56,
          l.mouth - _hh * 0.004);
      c.drawPath(grin, fill(rgba(14, 6, 9, 0.90)));
      c.save();
      c.clipPath(grin);
      final teeth = 3 + (p * 5).floor();
      for (var i = 0; i < teeth; i++) {
        final u = (i + 0.5) / teeth;
        final tx = l.cx + (u - 0.5) * l.w * 1.06;
        c.drawRect(
            ui.Rect.fromLTWH(tx - l.w * 0.036, l.mouth + drop * 0.35,
                l.w * 0.072, _hh * (0.014 + p * 0.016)),
            fill(rgba(238, 231, 210, 0.88)));
      }
      c.restore();

      // rouge, on the real malar
      for (final sg in const <double>[-1, 1]) {
        vblob(c, l.cx + sg * l.w * 0.64, l.mouth - _hh * 0.030, l.w * 0.32,
            _hh * 0.048, 0, rgba(206, 62, 62, 0.52), 0,
            mode: ui.BlendMode.multiply);
      }
    });

    wetSpec(g, -w / 2, -hh / 2, w, hh, wetSetFor(l), t);
    // FRINGE, not bars: short strands rooted on the cranium that stop at the
    // brow. Full-length strands at this magnification cross the whole face.
    drawHair(g, 0, -hh * 0.34, w * 0.86, hh * 0.46, t, lag, null,
        rgba(32, 17, 22, 0.72), 1);
    drawImageStretch(
        g, rim, dst, nearestPaint(alpha: 0.62, mode: ui.BlendMode.plus));
  } else {
    // FRINGE, not bars: short strands rooted on the cranium that stop at the
    // brow. Full-length strands at this magnification cross the whole face.
    drawHair(g, 0, -hh * 0.34, w * 0.86, hh * 0.46, t, lag, null,
        rgba(32, 17, 22, 0.72), 1);
  }
  g.restore();

  _vignette(g, const ui.Offset(_fw * 0.32, _fh * 0.32), 70, 250,
      const ui.Color(0xFFAFA796));

  // his sign-off, in the empty bright quarter he has not reached yet
  fillText(
    g,
    'GOODNIGHT,',
    const ui.Offset(12, 30),
    mono(15, rgba(58, 26, 50, clampD(0.62 + math.sin(t * 3.4) * 0.30, 0, 1)),
        weight: FontWeight.bold),
    cache: feedText,
  );
  fillText(
    g,
    'OPERATOR',
    const ui.Offset(12, 46),
    mono(15, rgba(58, 26, 50, clampD(0.62 + math.sin(t * 3.4 + 0.6) * 0.30, 0, 1)),
        weight: FontWeight.bold),
    cache: feedText,
  );
}

// --- 3. THE VERTICAL MAN ----------------------------------------------------
//
// EXTREME LONG SHOT from the floor. He is roughly one and a half frames tall,
// so his head starts ABOVE the top edge: there is no gaze in this composition at
// all, and the eye has nothing to land on except the seam sliding up the
// picture. Outside the tear he is only a stain; inside it he is a hard black
// cut in a blown-out white band.
//
// ESCALATION: the band grows and the roll slows, so the seam lingers on him;
// past 55% the picture tears in a second place at once; and past about half he
// begins to fold DOWN to bring his head into the frame — the only time you ever
// see it.
void _drawVert(ui.Canvas g, double t, double p) {
  final speed = 150 - p * 80;
  final roll = (t * speed) % _fh;
  final skew = math.sin(t * 17) * p * 3.5;

  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF040706));

  // the rolled programme: a lit studio floor, so the roll cannot be missed
  for (final oy in const <double>[-_fh, 0]) {
    g.save();
    g.translate(skew, roll + oy);
    fillRectShader(
      g,
      -8,
      0,
      _fw + 16,
      _fh,
      linear(
        ui.Offset.zero,
        const ui.Offset(0, _fh),
        const <ui.Color>[
          ui.Color(0xFF16281F),
          ui.Color(0xFF0D1C15),
          ui.Color(0xFF050D09),
        ],
        <double>[0, 0.55, 1],
      ),
    );
    final line = stroke(rgba(176, 198, 220, 0.20), 1);
    for (var i = 0.0; i < _fw; i += 24) {
      g.drawLine(ui.Offset(i, 0), ui.Offset(i, _fh), line);
    }
    for (var j = 140.0; j < _fh; j += 26) {
      g.drawLine(ui.Offset(0, j), ui.Offset(_fw, j), line);
    }
    fillRect(g, 30, 96, 54, 44, rgba(192, 216, 240, 0.30));
    fillRect(g, 232, 104, 50, 36, rgba(192, 216, 240, 0.30));
    g.restore();
  }

  // He is fixed in the studio, not in the seam. The seam just decides how much
  // of him the transmitter is honest about.
  const ground = _fh + 12.0;
  final headTop = -128 + p * p * 146;
  final hx = _fw / 2 + math.sin(t * 0.63) * 36;
  const sw = 11.0;

  _vertMan(g, hx, headTop, ground, sw,
      fill(rgba(0, 0, 0, clampD(0.13 + p * 0.26, 0, 1))));
  // a bare edge on the stain. Black on a black studio is not a silhouette, and
  // the operator has to be able to tell WHICH of the eight this is.
  _vertMan(g, hx, headTop, ground, sw,
      stroke(rgba(150, 220, 255, clampD(0.10 + p * 0.18, 0, 1)), 1));

  final bandH = 16 + p * 78;
  _vertSeam(g, t, p, roll - bandH * 0.5, bandH, hx, headTop, ground, sw, true);
  if (p > 0.55) {
    final b2h = 4 + (p - 0.55) * 34;
    _vertSeam(g, t, p, (roll + _fh * 0.42) % _fh - b2h * 0.5, b2h, hx, headTop,
        ground, sw, false);
  }
}

/// Draws one tear band, wrapped so a band straddling the top or bottom edge
/// appears at both.
void _vertSeam(ui.Canvas g, double t, double p, double y, double h, double hx,
    double headTop, double ground, double sw, bool primary) {
  for (final oy in const <double>[-_fh, 0, _fh]) {
    final by = y + oy;
    if (by + h < -1 || by > _fh + 1) continue;
    _vertBand(g, t, p, by, h, hx, headTop, ground, sw, primary);
  }
}

void _vertBand(ui.Canvas g, double t, double p, double y, double h, double hx,
    double headTop, double ground, double sw, bool primary) {
  final rect = ui.Rect.fromLTWH(0, y, _fw, h);
  g.save();
  g.clipRect(rect);
  fillRect(g, 0, y, _fw, h,
      primary ? const ui.Color(0xFFDCE6E0) : const ui.Color(0xFF9DB2A8));
  _grain(g, t, 30, 0.42, rect: rect);
  _vertMan(g, hx, headTop, ground, sw, fill(const ui.Color(0xFF030605)));

  // the only eyes in this composition, and only while the seam is across them
  final hr = sw * 1.55;
  final eyeY = headTop + hr * 1.02;
  if (eyeY > y - 2 && eyeY < y + h + 2) {
    final e = fill(rgba(255, 252, 238, 0.95));
    g.drawRect(ui.Rect.fromLTWH(hx - sw * 0.54, eyeY, 2.6, 3.4), e);
    g.drawRect(ui.Rect.fromLTWH(hx + sw * 0.12, eyeY, 2.6, 3.4), e);
  }
  g.restore();

  // chroma-split seam edges: red leads, cyan trails
  final a = clampD((primary ? 0.52 : 0.30) + p * 0.40, 0, 1);
  g.drawLine(ui.Offset(0, y), ui.Offset(_fw, y),
      stroke(rgba(255, 120, 110, a), 1.4));
  g.drawLine(ui.Offset(0, y + h), ui.Offset(_fw, y + h),
      stroke(rgba(110, 200, 255, a), 1.4));
}

/// Nine frames tall and folding. [headTop] above 0 is the only reason his head
/// is ever in the picture.
void _vertMan(ui.Canvas g, double x, double headTop, double ground, double w,
    ui.Paint p) {
  final hr = w * 1.55;
  final shoulder = headTop + hr * 2.35;
  final hip = shoulder + (ground - shoulder) * 0.46;

  drawEllipse(g, x, headTop + hr, w * 0.86, hr, 0, p);
  g.drawRect(
      ui.Rect.fromLTWH(x - w * 0.26, headTop + hr * 1.75, w * 0.52, hr * 0.75),
      p);

  final torso = ui.Path()
    ..moveTo(x - w * 1.05, shoulder)
    ..lineTo(x + w * 1.05, shoulder)
    ..lineTo(x + w * 0.72, hip)
    ..lineTo(x - w * 0.72, hip)
    ..close();
  g.drawPath(torso, p);

  final armEnd = hip + (ground - hip) * 0.62;
  for (final sg in const <double>[-1, 1]) {
    final ax = x + sg * w * 0.98;
    final arm = ui.Path()
      ..moveTo(ax - w * 0.24, shoulder + hr * 0.15)
      ..lineTo(ax + w * 0.24, shoulder + hr * 0.15)
      ..lineTo(ax + sg * w * 0.30 + w * 0.16, armEnd)
      ..lineTo(ax + sg * w * 0.30 - w * 0.16, armEnd)
      ..close();
    g.drawPath(arm, p);
  }
  for (final sg in const <double>[-1, 1]) {
    final lx = x + sg * w * 0.36;
    final leg = ui.Path()
      ..moveTo(lx - w * 0.30, hip)
      ..lineTo(lx + w * 0.30, hip)
      ..lineTo(lx + w * 0.24, ground)
      ..lineTo(lx - w * 0.24, ground)
      ..close();
    g.drawPath(leg, p);
  }
}

// --- 4. DEAD AIR ------------------------------------------------------------
//
// NO SUBJECT. Nothing is ever drawn in this frame that could be a creature —
// Dead Air is an appetite, and the only way to photograph an appetite is to
// photograph the hole. So the composition is the frame itself: dead centre,
// perfectly symmetric (nothing else in the eight is), and getting emptier.
//
// ESCALATION: the ghost of the picture that should be here fades out, the flat
// line is bitten away in pieces, the caption loses letters, and the raster
// collapses to a slit like a set being killed.
void _drawDead(ui.Canvas g, double t, double p) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF000000));

  // what it has already taken
  final ghost = clampD(1 - p * 1.5, 0, 1);
  if (ghost > 0) {
    fillRectShader(
      g,
      0,
      0,
      _fw,
      _fh,
      radialR0(const ui.Offset(_fw / 2, _fh * 0.58), 6, 140,
          <ui.Color>[rgba(49, 55, 62, 0.55 * ghost), rgba(0, 0, 0, 0)],
          <double>[0, 1]),
    );
    final hz = stroke(rgba(120, 135, 150, 0.16 * ghost), 1);
    for (var k = 0; k < 3; k++) {
      final y = _fh * 0.62 + k * 9.0;
      g.drawLine(ui.Offset(0, y), ui.Offset(_fw, y), hz);
    }
  }

  // the one flat line, in pieces
  const ly = _fh / 2;
  const segs = 40;
  const segW = _fw / segs;
  final bright = clampD(0.88 - p * 0.34 + math.sin(t * 1.7) * 0.05, 0, 1);
  for (var i = 0; i < segs; i++) {
    final u = (i + 0.5) / segs;
    final bite = (math.sin(u * 21.7 + 1.3) * 0.5 + 0.5) * 0.55 +
        (math.sin(u * 7.1 - 0.6) * 0.5 + 0.5) * 0.45;
    if (bite < p * 0.82) continue;
    final wob = math.sin(u * 30 + t * 2.2) * (0.5 + p * 1.7);
    fillRect(g, i * segW, ly + wob - 0.8, segW + 0.6, 1.6,
        rgba(204, 229, 255, bright));
  }
  // the last of it, refusing
  fillRect(g, _fw / 2 - 3, ly - 1, 6, 2,
      rgba(204, 229, 255, clampD(0.50 + math.sin(t * 5) * 0.40, 0, 1)));

  const full = '— NO CARRIER —';
  final keep = clampD((1 - p * 0.95) * full.length, 0, full.length * 1.0).round();
  if (keep > 0) {
    fillText(
      g,
      full.substring(0, keep),
      const ui.Offset(_fw / 2, _fh - 34),
      mono(9, rgba(120, 135, 150, clampD(0.34 + math.sin(t * 2) * 0.14, 0, 1))),
      anchor: TextAnchor.center,
      cache: feedText,
    );
  }

  // THE COLLAPSE — the raster closes to a slit
  final sq = math.pow(p, 1.35).toDouble();
  final ix = 146 * sq, iy = 108 * sq;
  final black = fill(const ui.Color(0xFF000000));
  g.drawRect(ui.Rect.fromLTWH(0, 0, _fw, iy), black);
  g.drawRect(ui.Rect.fromLTWH(0, _fh - iy, _fw, iy), black);
  g.drawRect(ui.Rect.fromLTWH(0, 0, ix, _fh), black);
  g.drawRect(ui.Rect.fromLTWH(_fw - ix, 0, ix, _fh), black);
  if (sq > 0.02) {
    g.drawRect(ui.Rect.fromLTWH(ix, iy, _fw - ix * 2, _fh - iy * 2),
        stroke(rgba(176, 198, 220, clampD(0.08 + p * 0.26, 0, 1)), 1));
  }

  // and every so often the tube discharges across what is left
  final flash = _spike(t, 2.3, 26) * p;
  if (flash > 0.01) {
    fillRect(g, ix, ly - 1.5 - 6 * flash, _fw - ix * 2, 3 + 12 * flash,
        rgba(204, 229, 255, clampD(flash * 0.9, 0, 1)));
  }
}

// --- 5. THE TEST CARD GIRL --------------------------------------------------
//
// A FLAT GRAPHIC TABLEAU seen head-on: a real test card, with castellations, a
// graticule circle and a PLUGE strip. She is not the subject — she is a small
// photograph inset OFF-CENTRE LEFT, shot from above the way you photograph a
// child, and she is not looking at the camera. The clown is. It is bigger than
// she is, it is nearer the lens, and it is the only object in the frame with
// any depth at all, which is why the eye goes straight to it.
//
// ESCALATION: the print slips (chroma registration splits), she grows and rises
// out of her own inset until she breaks the border and crosses the colour bars,
// the chalk on her face is redrawn over and over, and the clown's stitched mouth
// comes open.
void _drawCard(ui.Canvas g, double t, double p) {
  const cols = <ui.Color>[
    ui.Color(0xFFC0C0C0),
    ui.Color(0xFFC0C000),
    ui.Color(0xFF00C0C0),
    ui.Color(0xFF99ACC0),
    ui.Color(0xFFC000C0),
    ui.Color(0xFFC00000),
    ui.Color(0xFF0000C0),
  ];
  const bw = _fw / 7;
  const barsH = 40.0;
  const cardTop = barsH, cardBot = 206.0;

  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF5C5C5C));
  for (var i = 0; i < 7; i++) {
    fillRect(g, i * bw, 0, bw + 1, barsH, cols[i]);
  }
  fillRect(g, 0, cardTop, _fw, cardBot - cardTop, const ui.Color(0xFF5E5E5E));

  // castellations
  for (var y = cardTop + 4; y < cardBot - 8; y += 16) {
    fillRect(g, 0, y, 8, 8, const ui.Color(0xFF2A2A2A));
    fillRect(g, _fw - 8, y + 8, 8, 8, const ui.Color(0xFF2A2A2A));
  }

  // the graticule, printed three times because the print is slipping
  final drift = p * 4.4 + math.sin(t * 0.8) * 0.7;
  const circ = ui.Offset(_fw * 0.5, 124);
  void graticule(double dx, ui.Paint pt) {
    g.drawCircle(circ.translate(dx, 0), 76, pt);
    g.drawCircle(circ.translate(dx, 0), 28, pt);
    g.drawLine(ui.Offset(circ.dx + dx, cardTop + 6),
        ui.Offset(circ.dx + dx, cardBot - 6), pt);
    g.drawLine(
        ui.Offset(10 + dx, circ.dy), ui.Offset(_fw - 10 + dx, circ.dy), pt);
    // a ruled frequency ladder, not a thicket of verticals
    for (var k = 1; k <= 3; k++) {
      final gy = circ.dy - k * 20.0;
      final half = 76 * math.sqrt(math.max(0.0, 1 - (k * 20.0 / 76) * (k * 20.0 / 76)));
      g.drawLine(ui.Offset(circ.dx + dx - half, gy),
          ui.Offset(circ.dx + dx + half, gy), pt);
    }
  }

  final split = clampD(0.30 + p * 0.42, 0, 1);
  graticule(-drift,
      stroke(rgba(255, 62, 52, split), 1.4, mode: ui.BlendMode.plus));
  graticule(drift,
      stroke(rgba(60, 190, 255, split), 1.4, mode: ui.BlendMode.plus));
  graticule(0, stroke(const ui.Color(0xFF1C1C1C), 1.6));

  // --- her inset. Off-centre left, and she does not fill it for long.
  const box = ui.Rect.fromLTWH(26, 62, 92, 116);
  fillRect(g, box.left, box.top, box.width, box.height,
      const ui.Color(0xFF1A1D1B));
  fillRectShader(
    g,
    box.left,
    box.top,
    box.width,
    box.height,
    radialR0(ui.Offset(box.center.dx, box.top + 40), 6, 96,
        <ui.Color>[rgba(120, 128, 118, 0.55), rgba(8, 10, 9, 0)],
        <double>[0, 1]),
  );
  g.drawRect(box, stroke(const ui.Color(0xFF121212), 3));

  final head = heads['card'];
  final gs = 1.0 + p * 0.52;
  final phw = 62 * gs, phh = phw * (_hh / _hw);
  final hcx = box.center.dx + 1;
  final hcy = box.top + 46 - p * 24 + math.sin(t * 1.4) * 1.2;
  final dst = ui.Rect.fromLTWH(hcx - phw / 2, hcy - phh / 2, phw, phh);

  // floor shadow inside the photograph, then the dress, then her
  drawEllipse(g, hcx, box.bottom - 8, 34 * gs, 7 * gs, 0,
      fill(rgba(0, 0, 0, 0.45)));
  final dress = ui.Path()
    ..moveTo(hcx - 13 * gs, hcy + phh * 0.30)
    ..lineTo(hcx + 13 * gs, hcy + phh * 0.30)
    ..lineTo(hcx + 30 * gs, box.bottom - 6 + p * 26)
    ..lineTo(hcx - 30 * gs, box.bottom - 6 + p * 26)
    ..close();
  g.drawPath(dress, fill(const ui.Color(0xFF16130F)));
  g.drawPath(dress, stroke(rgba(190, 186, 170, 0.22), 1));
  // A BOB, behind the head. The 'card' plate is bald, and a bald child on a
  // sign-off card reads as a mannequin instead of as a girl. The mass is scaled
  // down to 0.65 so it stops at the jaw — at full height it is a monk's cowl.
  drawHair(g, hcx, hcy - phh * 0.16, phw * 0.92, phh * 0.65, t,
      math.sin(t * 0.9) * 1.2, rgba(26, 18, 15, 0.96), null, 0);

  if (head != null) {
    drawTintedPlate(g, head, const ui.Color(0xFFF0E7D4), dst);
    drawImageStretch(
        g, head.img, dst, nearestPaint(alpha: 0.42, mode: ui.BlendMode.plus));
    final l = head.lm;
    _inPlate(g, dst, (c) {
      // shot from ABOVE: the crown is lit, the chin is in its own shadow
      vblob(c, l.cx, l.brow - _hh * 0.140, l.w * 1.10, _hh * 0.180, 0,
          rgba(255, 250, 235, 0.34), 0.05, mode: ui.BlendMode.plus);
      vblob(c, l.cx, l.chin - _hh * 0.010, l.w * 0.95, _hh * 0.090, 0,
          rgba(16, 14, 12, 0.45), 0.05, mode: ui.BlendMode.multiply);

      // CHALK, drawn on and drawn on again
      final ch = stroke(const ui.Color(0xFFDBD5C4), 8, cap: ui.StrokeCap.round);
      final marks = 1 + (p * 2).round();
      for (final sg in const <double>[-1, 1]) {
        final ex = l.cx + sg * l.w * 0.46, ey = l.eye;
        final r = l.w * 0.34, ry = _hh * 0.036;
        for (var k = 0; k < marks; k++) {
          final j = (k - (marks - 1) / 2) * l.w * 0.055;
          c.drawLine(ui.Offset(ex - r + j, ey - ry),
              ui.Offset(ex + r + j, ey + ry), ch);
          c.drawLine(ui.Offset(ex + r + j, ey - ry),
              ui.Offset(ex - r + j, ey + ry), ch);
        }
      }
      c.drawArc(
          ui.Rect.fromCircle(
              center: ui.Offset(l.cx, l.mouth - _hh * 0.030),
              radius: l.w * 0.42),
          0.18 * math.pi,
          0.64 * math.pi,
          false,
          ch);
      final o = clampD((p - 0.45) / 0.55, 0, 1);
      if (o > 0) {
        drawEllipse(c, l.cx, l.mouth + _hh * 0.012, l.w * 0.28,
            _hh * (0.026 + o * 0.048), 0, fill(rgba(10, 8, 10, 0.70 * o)));
        drawEllipse(c, l.cx, l.mouth + _hh * 0.012, l.w * 0.28,
            _hh * (0.026 + o * 0.048), 0,
            stroke(rgba(219, 213, 196, o), 7));
      }
    });
  }

  // --- the clown that is not a clown. Right of centre, ON the card.
  g.save();
  g.translate(224, 168);
  g.rotate(0.20 - p * 0.20 + math.sin(t * 2.1) * 0.03);
  const r = 26.0;
  final circle = ui.Path()..addOval(ui.Rect.fromCircle(center: ui.Offset.zero, radius: r));
  g.drawPath(circle, fill(const ui.Color(0xFFB33C3C)));
  g.save();
  g.clipPath(circle);
  vblob(g, -r * 0.34, -r * 0.42, r * 0.95, r * 0.95, 0,
      rgba(255, 186, 168, 0.42), 0.05);
  vblob(g, r * 0.32, r * 0.40, r * 1.00, r * 1.00, 0, rgba(0, 0, 0, 0.48), 0.05);
  mottle(g, -r, -r, r * 2, r * 2, 0.40);
  g.restore();
  g.drawPath(circle, stroke(rgba(60, 14, 14, 0.55), 1.2));
  // the seam it was sewn along
  g.drawLine(const ui.Offset(0, -r), const ui.Offset(0, -r * 0.35),
      stroke(rgba(230, 200, 190, 0.35), 1));

  // it turns to the lens as it is left alone
  final turn = -0.55 + p * 0.55;
  final ex = math.sin(turn) * r * 0.55;
  for (final sg in const <double>[-1, 1]) {
    final bx = ex + sg * r * 0.30;
    final br = r * (0.115 + (sg * math.cos(turn) > 0 ? 0.02 : 0));
    g.drawCircle(ui.Offset(bx, -r * 0.14), br, fill(const ui.Color(0xFF0C0C0C)));
    g.drawCircle(ui.Offset(bx - br * 0.30, -r * 0.14 - br * 0.30), br * 0.32,
        fill(rgba(255, 255, 250, 0.85)));
  }
  // no nose. A stitched mouth, and it opens.
  final gap = p * r * 0.30;
  if (gap > 0.8) {
    drawEllipse(g, ex * 0.6, r * 0.32, r * 0.40, gap, 0,
        fill(const ui.Color(0xFF0A0708)));
  }
  final st = stroke(rgba(226, 206, 196, 0.75), 1.2);
  for (var i = 0; i < 6; i++) {
    final sx = ex * 0.6 + (i / 5 - 0.5) * r * 0.78;
    final sy = r * 0.32 - math.cos((i / 5 - 0.5) * 2.4) * r * 0.05;
    g.drawLine(ui.Offset(sx, sy - gap - 2), ui.Offset(sx, sy - gap + 1), st);
    g.drawLine(ui.Offset(sx, sy + gap - 1), ui.Offset(sx, sy + gap + 2), st);
  }
  // a ruff, worn like a collar rather than scattered round its head
  for (var i = 0; i < 7; i++) {
    final u = i / 6;
    final cxr = (u - 0.5) * r * 1.9;
    g.drawCircle(
        ui.Offset(cxr, r * 0.86 + (0.5 - (u - 0.5).abs()) * r * 0.20),
        r * 0.24,
        fill(const ui.Color(0xFF6A5F96)));
  }
  g.drawRect(ui.Rect.fromLTWH(-r * 0.95, r * 0.94, r * 1.9, r * 0.34),
      fill(const ui.Color(0xFF4B4270)));
  g.restore();

  // --- PLUGE and the ident strip
  const sub = <ui.Color>[
    ui.Color(0xFF0000C0),
    ui.Color(0xFFFFFFFF),
    ui.Color(0xFFC000C0),
    ui.Color(0xFF101018),
  ];
  for (var i = 0; i < 4; i++) {
    fillRect(g, i * (_fw / 4), cardBot, _fw / 4 + 1, 16, sub[i]);
  }
  fillRect(g, 0, cardBot + 16, _fw, _fh - cardBot - 16,
      const ui.Color(0xFF0B0B0F));
  fillText(g, 'KBLK-7   TEST CARD F   1140 kHz',
      const ui.Offset(_fw / 2, _fh - 5), _cardIdent,
      anchor: TextAnchor.center, cache: feedText);

  // the whole print oversaturating
  fillRect(g, 0, 0, _fw, _fh, rgba(255, 74, 138, clampD(0.04 + p * 0.11, 0, 1)),
      mode: ui.BlendMode.screen);
  if (math.sin(t * 6) > 0.72) {
    fillRect(g, 0, 0, _fw, _fh,
        rgba(255, 255, 255, clampD(0.08 + p * 0.07, 0, 1)));
  }
}

final TextStyle _cardIdent = mono(9, rgba(214, 214, 204, 0.78));

// --- 6. THE REPEAT ----------------------------------------------------------
//
// A LONG SHOT down an empty studio: converging floor tape, a lighting grid, a
// boom hanging in from the top-left. The figure is SMALL and BACK TO CAMERA —
// there is no face in this composition and there never will be, because what is
// on the tape is four seconds of somebody walking away.
//
// ESCALATION: the loop tightens (four seconds down to about one), and the tape
// starts printing takes on top of each other until three or four of him are
// crossing the floor at once. One of them is not moving.
void _drawRerun(ui.Canvas g, double t, double p) {
  final loopLen = 4.0 - p * 2.7;
  final loop = (t * 0.95) % loopLen;
  final u = loop / loopLen;
  const horizon = _fh * 0.42;

  // He does not cross flat: he comes out of the far corner and walks toward the
  // near one, so the scale changes across the loop and the studio has depth.
  double walkX(double uu) => 44 + uu * (_fw - 96);
  double walkY(double uu) => horizon + (_fh - horizon) * (0.20 + uu * uu * 0.62);
  double walkS(double uu) => 0.24 + uu * uu * 0.30;

  // --- the room ---------------------------------------------------------
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF03100B));
  fillRectShader(
    g,
    0,
    0,
    _fw,
    horizon,
    linear(ui.Offset.zero, const ui.Offset(0, horizon),
        <ui.Color>[rgba(27, 30, 34, 1), rgba(4, 18, 12, 1)], <double>[0, 1]),
  );
  fillRectShader(
    g,
    0,
    horizon,
    _fw,
    _fh - horizon,
    linear(const ui.Offset(0, horizon), const ui.Offset(0, _fh),
        <ui.Color>[rgba(41, 46, 52, 1), rgba(3, 14, 9, 1)], <double>[0, 1]),
  );
  const vp = ui.Offset(_fw * 0.54, horizon);
  final fl = stroke(rgba(160, 180, 200, 0.14), 1);
  for (var i = -7; i <= 7; i++) {
    g.drawLine(vp, ui.Offset(_fw * 0.5 + i * 58.0, _fh), fl);
  }
  for (var k = 1; k <= 6; k++) {
    final uu = k / 7;
    final y = horizon + (_fh - horizon) * uu * uu;
    g.drawLine(ui.Offset(0, y), ui.Offset(_fw, y), fl);
  }
  // lighting grid and a boom hanging in from the top-left
  final rig = stroke(rgba(176, 198, 220, 0.16), 2);
  g.drawLine(const ui.Offset(0, 16), const ui.Offset(_fw, 22), rig);
  for (var i = 0; i < 5; i++) {
    final lx = 24 + i * 68.0;
    g.drawRect(ui.Rect.fromLTWH(lx - 5, 18, 10, 9),
        fill(rgba(192, 216, 240, 0.22)));
  }
  final boom = ui.Path()
    ..moveTo(-4, 2)
    ..lineTo(74, 40);
  g.drawPath(boom, stroke(rgba(192, 216, 240, 0.24), 2));
  drawEllipse(g, 76, 41, 4.5, 2.6, 0.5, fill(rgba(192, 216, 240, 0.26)));
  // the tape mark he snaps back to
  final markX = walkX(0), markY = walkY(0);
  final mk = stroke(rgba(204, 229, 255, 0.28), 1.2);
  g.drawLine(ui.Offset(markX - 5, markY), ui.Offset(markX + 5, markY), mk);
  g.drawLine(ui.Offset(markX, markY - 3), ui.Offset(markX, markY + 3), mk);

  // --- the printed-over takes ------------------------------------------
  final takes = 1 + (p * 2.6).floor();
  for (var k = takes - 1; k >= 1; k--) {
    final uu = (u + k / takes) % 1.0;
    _walker(g, walkX(uu), walkY(uu), walkS(uu),
        rgba(192, 216, 240, clampD(0.10 + p * 0.14, 0, 1)), uu * 5);
  }

  // --- the one that does not walk --------------------------------------
  final still = clampD((p - 0.16) / 0.55, 0, 1);
  if (still > 0) {
    const sy = horizon + (_fh - horizon) * 0.46;
    _walker(g, _fw * 0.74, sy, 0.40,
        rgba(3, 13, 9, clampD(0.40 + still * 0.55, 0, 1)), 0);
    if (still > 0.72) {
      // a sliver of cheek. Not a face — it has not turned that far yet.
      drawEllipse(g, _fw * 0.74 + 2.6, sy - 62 * 0.40, 1.6, 3.0, 0,
          fill(rgba(195, 219, 244, clampD((still - 0.72) * 3, 0, 0.60))));
    }
  }

  // --- the smear ---------------------------------------------------------
  final prev = _trail;
  final next = bakeImageSync(kFeedW, kFeedH, (tc) {
    if (prev != null) {
      drawImageStretch(tc, prev, _feedRect, nearestPaint());
    }
    fillRect(tc, 0, 0, _fw, _fh, rgba(2, 7, 5, 0.055 + p * 0.020));
    _walker(tc, walkX(u), walkY(u), walkS(u), rgba(204, 229, 255, 0.42), u * 5);
    if (u < 0.05) {
      fillRect(tc, 0, 0, _fw, _fh, rgba(2, 7, 5, 1)); // hard cut on the splice
    }
  });
  prev?.dispose();
  _trail = next;

  drawImageStretch(g, next, _feedRect,
      nearestPaint(alpha: 0.92, mode: ui.BlendMode.plus));
  drawImageStretch(g, next, const ui.Rect.fromLTWH(-13, 2, _fw, _fh),
      nearestPaint(alpha: 0.26, mode: ui.BlendMode.plus));
  drawImageStretch(g, next, const ui.Rect.fromLTWH(12, -2, _fw, _fh),
      nearestPaint(alpha: 0.26, mode: ui.BlendMode.plus));

  // the solid, current pass
  _walker(g, walkX(u), walkY(u), walkS(u), rgba(204, 229, 255, 0.94), u * 5);

  // --- the machine -------------------------------------------------------
  final secs = ((loop % 1) * 30).floor().toString().padLeft(2, '0');
  fillText(g, 'REC  00:0${loop.floor()};$secs', const ui.Offset(8, 16),
      _rerunTc, cache: feedText);
  g.drawCircle(const ui.Offset(_fw - 14, 13), 4,
      fill(rgba(255, 60, 40, clampD(0.35 + 0.6 * math.sin(t * 4).abs(), 0, 1))));
  if (u < 0.15) {
    fillRect(g, 0, 0, _fw, _fh,
        rgba(255, 255, 255, clampD(0.18 + p * 0.32, 0, 1)));
  }
  _vignette(g, const ui.Offset(_fw * 0.50, _fh * 0.60), 60, 210,
      const ui.Color(0xFF2E2E2E));
}

final TextStyle _rerunTc = mono(11, rgba(204, 229, 255, 0.8));

/// A figure walking AWAY: shoulders wider than the head, no features, legs and
/// arms out of phase with each other.
void _walker(
    ui.Canvas g, double x, double y, double s, ui.Color col, double ph) {
  final pt = fill(col);
  final sw = math.sin(ph * tau);

  drawEllipse(g, x, y - 61 * s, 8.0 * s, 10.0 * s, 0, pt);
  final torso = ui.Path()
    ..moveTo(x - 10.5 * s, y - 51 * s)
    ..lineTo(x + 10.5 * s, y - 51 * s)
    ..lineTo(x + 9 * s, y - 22 * s)
    ..lineTo(x - 9 * s, y - 22 * s)
    ..close();
  g.drawPath(torso, pt);

  for (final sg in const <double>[-1, 1]) {
    final sp = sw * sg * 7 * s;
    final lx = x + sg * 4.5 * s;
    final leg = ui.Path()
      ..moveTo(lx - 4.4 * s, y - 24 * s)
      ..lineTo(lx + 4.4 * s, y - 24 * s)
      ..lineTo(lx + 3.2 * s + sp, y)
      ..lineTo(lx - 3.2 * s + sp, y)
      ..close();
    g.drawPath(leg, pt);
  }
  for (final sg in const <double>[-1, 1]) {
    final sp = -sw * sg * 6 * s;
    final ax = x + sg * 11.5 * s;
    final arm = ui.Path()
      ..moveTo(ax - 2.6 * s, y - 48 * s)
      ..lineTo(ax + 2.6 * s, y - 48 * s)
      ..lineTo(ax + 2.3 * s + sp, y - 24 * s)
      ..lineTo(ax - 2.3 * s + sp, y - 24 * s)
      ..close();
    g.drawPath(arm, pt);
  }
}

// --- 7. THE NIELSEN ---------------------------------------------------------
//
// A WORM'S-EYE three-quarter, CROPPED BY THE LEFT EDGE. He is not centred and
// he never will be — the frame cannot hold him, and he steps in further every
// few seconds. He does not look at you: he looks at the clipboard, which is the
// brightest object in the picture and sits near the middle of it, so the eye
// goes to the thing he is taking rather than to him.
//
// ESCALATION: the audit cursor sweeps down the number wall and everything above
// it is already gone; his bar-chart head falls; the clipboard fills up a line at
// a time; and past 80% something behind the bars resolves, for single frames,
// into a face.

/// JS `((c+r)%3)` — c+r reaches -1 on the first row, and JS % keeps the sign, so
/// the top row is DIMMER than the base shade, not brighter. Ported with
/// remainder(), not %, so that stays true.
final List<TextStyle> _nielStyles = <TextStyle>[
  for (final rem in const <int>[-1, 0, 1, 2])
    mono(11, rgba(204, 229, 255, clampD(0.30 + rem * 0.22, 0, 1)),
        weight: FontWeight.bold),
];
final TextStyle _nielHead =
    mono(11, rgba(255, 80, 70, 0.85), weight: FontWeight.bold);
final TextStyle _nielSub = mono(8, rgba(255, 150, 130, 0.75));
final TextStyle _nielLedger = mono(6, const ui.Color(0xFF33333A));

void _drawNiel(ui.Canvas g, double t, double p) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF05060A));
  final tick = (t * 2).toInt();
  for (var c = 0; c < 8; c++) {
    final off = (t * (40 + c * 11)) % 16;
    for (var r = -1; r < 17; r++) {
      final y = r * 16 + off;
      fillText(
        g,
        (seedNum(c * 97 + r * 13 + tick) % 9000 + 1000).toString(),
        ui.Offset(c * 40 + 6, y),
        _nielStyles[(c + r).remainder(3) + 1],
        cache: feedText,
      );
    }
  }
  // the audit cursor. Everything above it has already been counted and taken.
  final cur = ((t * (0.22 + p * 0.55)) % 1.0) * _fh;
  fillRect(g, 0, 0, _fw, cur, rgba(0, 0, 0, clampD(0.28 + p * 0.42, 0, 1)));
  fillRect(g, 0, cur - 1.5, _fw, 3,
      rgba(255, 90, 70, clampD(0.45 + p * 0.40, 0, 1)));
  fillRect(g, 0, 0, _fw, _fh, rgba(0, 0, 0, 0.16));

  // --- the auditor. Cropped by the left edge, and closing.
  final s = 1.0 + p * 0.42;
  final bx = _fw * 0.19 - p * 14;
  final shoulderY = _fh * (0.36 - p * 0.16);
  const ground = _fh + 34.0;
  final halfTop = 46 * s, halfBot = 64 * s;
  final neckY = shoulderY - 11 * s;

  // square shoulders. A grey suit is a rectangle with a man in it.
  final suit = ui.Path()
    ..moveTo(bx - halfTop, shoulderY)
    ..cubicTo(bx - halfTop * 0.90, shoulderY - 5 * s, bx - 11 * s, neckY + 1 * s,
        bx - 7 * s, neckY - 3 * s)
    ..lineTo(bx + 7 * s, neckY - 3 * s)
    ..cubicTo(bx + 11 * s, neckY + 1 * s, bx + halfTop * 0.90, shoulderY - 5 * s,
        bx + halfTop, shoulderY)
    ..lineTo(bx + halfBot, ground)
    ..lineTo(bx - halfBot, ground)
    ..close();
  g.drawPath(suit, fill(const ui.Color(0xFF11141A)));
  g.save();
  g.clipPath(suit);
  fillRectShader(
    g,
    bx - halfBot,
    neckY - 10,
    halfBot * 2,
    ground - neckY + 10,
    linear(ui.Offset(0, neckY), const ui.Offset(0, ground),
        <ui.Color>[rgba(86, 100, 114, 0.42), rgba(0, 0, 0, 0)], <double>[0, 1]),
  );
  // shirt, collar and tie — without these he is a black polygon
  final shirt = ui.Path()
    ..moveTo(bx, neckY)
    ..lineTo(bx + 13 * s, shoulderY + 6 * s)
    ..lineTo(bx, shoulderY + 58 * s)
    ..lineTo(bx - 13 * s, shoulderY + 6 * s)
    ..close();
  g.drawPath(shirt, fill(const ui.Color(0xFFA9B0B6)));
  g.drawPath(shirt, fill(rgba(0, 0, 0, 0.18)));
  final tie = ui.Path()
    ..moveTo(bx - 3.4 * s, shoulderY + 1 * s)
    ..lineTo(bx + 3.4 * s, shoulderY + 1 * s)
    ..lineTo(bx + 5.0 * s, shoulderY + 56 * s)
    ..lineTo(bx, shoulderY + 64 * s)
    ..lineTo(bx - 5.0 * s, shoulderY + 56 * s)
    ..close();
  g.drawPath(tie, fill(const ui.Color(0xFF3E0F12)));
  // lapels, catching the light off the number wall
  for (final sg in const <double>[-1, 1]) {
    final lap = ui.Path()
      ..moveTo(bx + sg * 3 * s, neckY + 2 * s)
      ..lineTo(bx + sg * 21 * s, shoulderY - 2 * s)
      ..lineTo(bx + sg * 11 * s, shoulderY + 70 * s)
      ..close();
    g.drawPath(lap, fill(rgba(52, 62, 74, 0.9)));
    g.drawPath(lap, stroke(rgba(152, 171, 190, 0.22), 1));
  }
  g.restore();
  g.drawPath(
      suit, stroke(rgba(204, 229, 255, clampD(0.26 + p * 0.24, 0, 1)), 1.2));

  // the head. It is a bar chart, and it is falling.
  const barH = <double>[46, 38, 30, 21, 12, 5];
  final headBase = neckY - 2 * s;
  for (var i = 0; i < barH.length; i++) {
    final bh = barH[i] * s * (1 - p * 0.62);
    final bx0 = bx - 33 * s + i * 11.5 * s;
    g.drawRect(ui.Rect.fromLTWH(bx0, headBase - bh, 9.5 * s, bh),
        fill(rgba(232, 228, 216, clampD(0.94 - i * 0.09, 0, 1))));
    g.drawRect(ui.Rect.fromLTWH(bx0 + 7.6 * s, headBase - bh + 1.5, 1.9 * s, bh),
        fill(rgba(0, 0, 0, 0.32)));
  }
  // the baseline the head sits on, so it reads as attached
  g.drawRect(ui.Rect.fromLTWH(bx - 34 * s, headBase, 68 * s, 1.6 * s),
      fill(rgba(200, 198, 188, 0.75)));
  g.drawLine(
      ui.Offset(bx - 33 * s, headBase - 52 * s * (1 - p * 0.60)),
      ui.Offset(bx + 33 * s, headBase - 5 * s),
      stroke(rgba(255, 70, 60, 0.9), 2));

  // and past 80% the bars resolve, for a frame at a time, into a face
  final reveal = clampD((p - 0.80) / 0.20, 0, 1);
  if (reveal > 0) {
    final nh = heads['niel'];
    if (nh != null) {
      final fl = _spike(t, 9.1, 3);
      final fw = 96 * s;
      final fdst =
          _plateRect(bx, headBase - 20 * s, fw, nh.lm.cx / _hw, nh.lm.eye / _hh);
      drawImageStretch(
          g,
          nh.img,
          fdst,
          nearestPaint(
              alpha: clampD(reveal * fl * 0.85, 0, 1), mode: ui.BlendMode.plus));
    }
  }

  // --- the clipboard. The brightest thing in the frame, and near its centre.
  g.save();
  g.translate(bx + 56 * s, _fh * 0.56);
  g.rotate(-0.26 + math.sin(t * 0.7) * 0.02);
  g.drawRect(ui.Rect.fromLTWH(-17 * s, -23 * s, 34 * s, 46 * s),
      fill(const ui.Color(0xFF7C6C48)));
  g.drawRect(ui.Rect.fromLTWH(-14 * s, -20 * s, 28 * s, 40 * s),
      fill(const ui.Color(0xFFEFEADA)));
  g.drawRect(ui.Rect.fromLTWH(-7 * s, -26 * s, 14 * s, 5 * s),
      fill(const ui.Color(0xFF3A3A3E)));
  final rows = 1 + (p * 7).floor();
  for (var i = 0; i < rows; i++) {
    fillText(g, '${seedNum(i * 31 + 7) % 9000 + 1000}',
        ui.Offset(-11 * s, -12 * s + i * 4.6 * s), _nielLedger,
        cache: feedText);
  }
  // his hand on it
  drawEllipse(g, -15 * s, 6 * s, 6 * s, 9 * s, -0.3,
      fill(const ui.Color(0xFF9E9A8E)));
  g.restore();

  fillText(g, 'AUDIT IN PROGRESS', const ui.Offset(_fw - 8, 18), _nielHead,
      anchor: TextAnchor.right, cache: feedText);
  if (p > 0.5) {
    fillText(g, 'RESTATING SEGMENT OUTPUT', const ui.Offset(_fw - 8, 30),
        _nielSub,
        anchor: TextAnchor.right, cache: feedText);
  }

  _vignette(g, ui.Offset(bx + 56 * s, _fh * 0.56), 40, 230,
      const ui.Color(0xFF383838));
}

// --- 8. THE CALLER ----------------------------------------------------------
//
// DEEP FOCUS. The switchboard is jammed against the lens along the bottom edge,
// soft and enormous; the room runs away from it; and the thing that is calling
// is a long way off, small, standing in the only lit doorway in the station,
// off-centre right. The patch cord runs from its receiver all the way into the
// foreground, which is what ties the two planes together.
//
// ESCALATION: it walks the length of the room toward the lens, every lamp on
// the board lights ("every line, at once"), the trace grows out of its own
// instrument and turns red, and past 62% the dial stops spinning and one finger
// hole is aimed straight down the barrel.
final TextStyle _callOn =
    mono(8, rgba(255, 210, 150, 0.92), weight: FontWeight.bold);
final TextStyle _callOff = mono(8, rgba(90, 130, 150, 0.55));

void _drawCall(ui.Canvas g, double t, double p) {
  const horizon = 150.0;
  const doorX = 206.0, doorW = 42.0, doorTop = 74.0;
  const boardY = 194.0;

  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF03060A));
  fillRectShader(
    g,
    0,
    0,
    _fw,
    horizon,
    linear(ui.Offset.zero, const ui.Offset(0, horizon),
        <ui.Color>[rgba(9, 20, 30, 1), rgba(4, 11, 17, 1)], <double>[0, 1]),
  );
  fillRectShader(
    g,
    0,
    horizon,
    _fw,
    _fh - horizon,
    linear(const ui.Offset(0, horizon), const ui.Offset(0, _fh),
        <ui.Color>[rgba(12, 26, 34, 1), rgba(3, 8, 12, 1)], <double>[0, 1]),
  );

  const vp = ui.Offset(doorX + doorW / 2, horizon);
  final fl = stroke(rgba(70, 160, 200, 0.13), 1);
  for (var i = -6; i <= 6; i++) {
    g.drawLine(vp, ui.Offset(_fw * 0.5 + i * 64.0, _fh), fl);
  }
  g.drawLine(const ui.Offset(0, horizon), const ui.Offset(_fw, horizon),
      stroke(rgba(80, 170, 205, 0.22), 1));

  // THE DOORWAY — the only warm thing in the building
  final glow = 0.55 + 0.45 * math.sin(t * 0.9);
  // its light on the back wall, so the far half of the room is not pure black.
  // Without this a dark coat above the horizon has nothing to be dark against
  // and the figure reads as a wireframe.
  fillRectShader(
    g,
    0,
    0,
    _fw,
    horizon,
    radialR0(const ui.Offset(doorX + doorW / 2, horizon - 34), 16, 200,
        <ui.Color>[rgba(206, 188, 150, 0.34), rgba(0, 0, 0, 0)],
        <double>[0, 1]),
  );
  fillRect(g, doorX, doorTop, doorW, horizon - doorTop,
      rgba(228, 214, 176, clampD(0.60 + glow * 0.18, 0, 1)));
  // The spill has to be strong: it is the only lit ground in the frame, and a
  // black coat against a black floor is not a silhouette, it is a wireframe.
  final spill = ui.Path()
    ..moveTo(doorX, horizon)
    ..lineTo(doorX + doorW, horizon)
    ..lineTo(doorX + doorW + 96, _fh)
    ..lineTo(doorX - 108, _fh)
    ..close();
  g.save();
  g.clipPath(spill);
  fillRectShader(
    g,
    0,
    horizon,
    _fw,
    _fh - horizon,
    linear(const ui.Offset(0, horizon), const ui.Offset(0, _fh),
        <ui.Color>[rgba(232, 218, 180, 0.34), rgba(226, 214, 178, 0.07)],
        <double>[0, 1]),
  );
  g.restore();
  g.drawRect(
      ui.Rect.fromLTWH(doorX - 3, doorTop - 3, doorW + 6, horizon - doorTop + 3),
      stroke(rgba(150, 200, 220, 0.28), 2));

  // --- it comes down the room --------------------------------------------
  final z = math.pow(p, 1.25).toDouble();
  final fh0 = 34 + z * 162;
  // it stays inside the spill as it comes, so it stays a silhouette
  final fx = vp.dx + (_fw * 0.52 - vp.dx) * z + math.sin(t * 0.6) * 3 * z;
  final fy = horizon + (_fh + 30 - horizon) * z;
  final rec = _dialMan(g, fx, fy, fh0, t, p);

  // the cord, from its receiver into the foreground. This is the spine of the
  // composition: it is the only thing that touches both planes.
  final cord = ui.Path()..moveTo(rec.dx, rec.dy);
  cord.cubicTo(rec.dx + 26 + z * 34, rec.dy + 40, _fw * 0.80,
      boardY - 34, _fw * 0.70, boardY + 16);
  g.drawPath(cord, stroke(rgba(90, 200, 235, clampD(0.30 + p * 0.35, 0, 1)), 1.4));

  // --- the switchboard, too close to the lens to be sharp -----------------
  fillRectShader(
    g,
    0,
    boardY - 20,
    _fw,
    _fh - boardY + 20,
    linear(const ui.Offset(0, boardY - 20), const ui.Offset(0, boardY + 6),
        <ui.Color>[rgba(4, 12, 16, 0), rgba(4, 11, 15, 1)], <double>[0, 1]),
  );
  fillRect(g, 0, boardY, _fw, _fh - boardY, const ui.Color(0xFF060E13));
  g.drawLine(const ui.Offset(0, boardY), const ui.Offset(_fw, boardY),
      stroke(rgba(90, 180, 210, 0.18), 2));
  for (var r = 0; r < 2; r++) {
    for (var c = 0; c < 12; c++) {
      final jx = 16 + c * 26.0, jy = boardY + 12 + r * 17.0;
      vblob(g, jx, jy, 6, 6, 0, rgba(0, 0, 0, 0.55), 0.2);
      if ((c + r * 12) / 24 < 0.06 + p * 0.98) {
        final lit = clampD(0.30 + 0.50 * math.sin(t * 6 + c * 1.3 + r).abs(),
            0, 1);
        vblob(g, jx, jy, 10, 10, 0, rgba(255, 190, 120, lit * 0.50), 0.1,
            mode: ui.BlendMode.plus);
        g.drawCircle(ui.Offset(jx, jy), 2.2, fill(rgba(255, 216, 162, 0.88)));
      }
    }
  }
  const labels = <String>['LINE 1', 'LINE 2', 'LINE 3', 'ALL'];
  for (var i = 0; i < 4; i++) {
    fillText(g, labels[i], ui.Offset(14 + i * 78.0, _fh - 5),
        p > i * 0.24 ? _callOn : _callOff,
        cache: feedText);
  }

  // --- the trace, which does not stay in its instrument -------------------
  final out = clampD((p - 0.55) / 0.45, 0, 1);
  final stripH = 54 + out * 96;
  final cy = 32 + out * 34;
  fillRect(g, 0, 0, _fw, stripH,
      rgba(2, 10, 16, clampD(0.88 - out * 0.34, 0, 1)));
  final grid = stroke(rgba(60, 130, 170, clampD(0.22 * (1 - out * 0.7), 0, 1)), 1);
  for (var i = 0.0; i <= _fw; i += 32) {
    g.drawLine(ui.Offset(i, 0), ui.Offset(i, stripH), grid);
  }
  for (var j = 0.0; j <= stripH; j += 14) {
    g.drawLine(ui.Offset(0, j), ui.Offset(_fw, j), grid);
  }
  // it gets louder, but it must never become the whole picture — the figure
  // behind it is the point
  final amp = 7 + p * 20 + out * 14;
  final freq = 0.14 - out * 0.075;
  final wave = ui.Path();
  for (var i = 0; i <= _fw; i += 2) {
    final env = math.sin(t * 2.1 + i * 0.004).abs() * 0.55 + 0.45;
    final a = (math.sin(i * freq + t * 11) * amp +
            math.sin(i * 0.42 + t * 23) * amp * 0.30) *
        env;
    if (i == 0) {
      wave.moveTo(0, cy + a);
    } else {
      wave.lineTo(i.toDouble(), cy + a);
    }
  }
  final trace = ui.Color.lerp(
      const ui.Color(0xFF5AE6FF), const ui.Color(0xFFFF4A3C), out)!;
  g.drawPath(wave, stroke(trace.withValues(alpha: 0.28), 4,
      mode: ui.BlendMode.plus));
  g.drawPath(wave, stroke(trace.withValues(alpha: 0.95), 1.6));

  final ring = _spike(t, 5.2, 8);
  if (ring > 0.02) {
    fillRect(g, 0, 0, _fw, _fh,
        rgba(120, 235, 255, clampD(ring * (0.05 + p * 0.10), 0, 1)));
  }
  _vignette(g, const ui.Offset(doorX + doorW / 2, horizon - 20), 46, 240,
      const ui.Color(0xFF2A2A2A));
}

/// Draws the figure whose head is a rotary dial. Returns the world position of
/// the receiver, so the caller can run the cord from it into the foreground.
ui.Offset _dialMan(
    ui.Canvas g, double x, double ground, double h, double t, double p) {
  final w = h * 0.24;
  final headR = h * 0.115;
  final headY = ground - h + headR;
  final dark = fill(const ui.Color(0xFF02070B));

  final shoulderY = headY + headR * 1.9;
  // neck, so the dial is not floating above the coat
  g.drawRect(
      ui.Rect.fromLTWH(x - w * 0.11, headY + headR * 0.7, w * 0.22,
          headR * 1.4),
      dark);
  // shoulders and a coat that falls, rather than a cone
  final coat = ui.Path()
    ..moveTo(x - w * 0.30, shoulderY - headR * 0.45)
    ..cubicTo(x - w * 0.62, shoulderY - headR * 0.35, x - w * 0.70, shoulderY,
        x - w * 0.72, shoulderY + headR * 0.5)
    ..lineTo(x - w * 0.86, ground)
    ..lineTo(x + w * 0.86, ground)
    ..lineTo(x + w * 0.72, shoulderY + headR * 0.5)
    ..cubicTo(x + w * 0.70, shoulderY, x + w * 0.62, shoulderY - headR * 0.35,
        x + w * 0.30, shoulderY - headR * 0.45)
    ..close();
  g.drawPath(coat, dark);
  g.drawPath(coat,
      stroke(rgba(110, 235, 255, clampD(0.30 + p * 0.30, 0, 1)), 1.3));
  // a lapel seam down the front so the coat has a front
  g.drawLine(ui.Offset(x, shoulderY - headR * 0.4), ui.Offset(x, ground),
      stroke(rgba(70, 160, 195, 0.35), 1));

  // the arm, bent at the elbow, holding the receiver up to where an ear
  // would be if it had one
  final elbowX = x + w * 0.74, elbowY = shoulderY + headR * 1.5;
  final rx = x + w * 0.86, ry = headY + headR * 0.30;
  final armW = clampD(h * 0.030, 1.4, 4.4);
  final arm = ui.Path()
    ..moveTo(x + w * 0.42, shoulderY)
    ..quadraticBezierTo(elbowX, elbowY, rx, ry + h * 0.03);
  g.drawPath(arm,
      stroke(const ui.Color(0xFF02070B), armW * 1.7, cap: ui.StrokeCap.round));
  g.drawPath(arm,
      stroke(rgba(90, 200, 235, 0.45), armW * 0.55, cap: ui.StrokeCap.round));
  g.drawRect(
      ui.Rect.fromLTWH(rx - h * 0.034, ry - h * 0.062, h * 0.068, h * 0.124),
      fill(const ui.Color(0xFF0C1B25)));
  g.drawRect(
      ui.Rect.fromLTWH(rx - h * 0.034, ry - h * 0.062, h * 0.068, h * 0.124),
      stroke(rgba(140, 245, 255, 0.80), 1.2));

  g.save();
  g.translate(x, headY);
  g.drawCircle(ui.Offset.zero, headR, fill(const ui.Color(0xFF06121A)));
  g.drawCircle(ui.Offset.zero, headR, stroke(rgba(120, 240, 255, 0.85), 1.5));
  final align = clampD((p - 0.62) / 0.38, 0, 1);
  g.rotate(math.sin(t * 1.3) * 0.55 * (1 - align));
  for (var i = 0; i < 10; i++) {
    final a = -1.95 + i * 0.42;
    g.drawCircle(
        ui.Offset(math.cos(a) * headR * 0.62, math.sin(a) * headR * 0.62),
        math.max(0.8, headR * 0.14),
        fill(rgba(120, 240, 255,
            clampD(0.28 + 0.48 * math.sin(t * 3 + i).abs(), 0, 1))));
  }
  g.restore();

  // and at the end one hole is pointed straight down the lens
  if (align > 0) {
    g.drawCircle(ui.Offset(x, headY), math.max(1.0, headR * 0.20),
        fill(rgba(4, 8, 12, align)));
    g.drawCircle(
        ui.Offset(x, headY),
        math.max(0.6, headR * 0.09),
        fill(
            rgba(220, 255, 255,
                clampD(align * (0.55 + 0.45 * math.sin(t * 6)), 0, 1)),
            mode: ui.BlendMode.plus));
  }

  return ui.Offset(rx, ry + h * 0.05);
}
