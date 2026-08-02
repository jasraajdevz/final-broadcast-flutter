// FINAL BROADCAST — THE EIGHT, and the face-plate system two of them are built
// on.
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
// 5. FIGURES
// ---------------------------------------------------------------------------

/// JS `bodySil(g,x,y,s,col)` — generic standing figure; [y] is the ground line.
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

// ---------------------------------------------------------------------------
// 6. drawAnom — THE EIGHT
// ---------------------------------------------------------------------------

const double _fw = 320; // FW
const double _fh = 240; // FH

/// JS `drawAnom(g,def,t,prog)`. [g] is the 320x240 feed canvas.
void drawAnom(ui.Canvas g, Anom def, double t, double prog) {
  switch (def.id) {
    case 'snow':
      _drawSnow(g, t, prog);
    case 'sleep':
      _drawSleep(g, t, prog);
    case 'vert':
      _drawVert(g, t, prog);
    case 'dead':
      _drawDead(g, t, prog);
    case 'card':
      _drawCard(g, t, prog);
    case 'rerun':
      _drawRerun(g, t, prog);
    case 'niel':
      _drawNiel(g, t, prog);
    case 'call':
      _drawCall(g, t, prog);
  }
  trimFeedText();
}

// --- 1. THE SNOW ------------------------------------------------------------
// The face is NEVER drawn. It is only a modulation of the grain — the plate
// multiplies the noise where the skull occludes and lifts it where the skull is
// lit, so no outline exists anywhere in the frame and it ASSEMBLES.
void _drawSnow(ui.Canvas g, double t, double prog) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF000000));
  final n = noiseTile(t, 24);
  if (n != null) {
    drawImageStretch(g, n, const ui.Rect.fromLTWH(0, 0, _fw, _fh),
        nearestPaint(alpha: 0.95));
  }

  final s = 1.00 + prog * 0.30, hw = _hw * 0.62 * s, hh = _hh * 0.62 * s;
  final hx = _fw / 2 + math.sin(t * 0.31) * 4,
      hy = _fh * 0.50 + math.sin(t * 0.23) * 3;
  final head = heads['snow'], rim = rims['snow'];
  if (head != null && rim != null) {
    final dst = ui.Rect.fromLTWH(-hw / 2, -hh / 2, hw, hh);
    g.save();
    g.translate(hx, hy);
    drawImageStretch(g, head.img, dst,
        nearestPaint(alpha: clampD(prog * 1.5, 0, 0.97), mode: ui.BlendMode.multiply));
    drawImageStretch(g, head.img, dst,
        nearestPaint(alpha: clampD(prog * 1.0, 0, 0.62), mode: ui.BlendMode.plus));
    drawImageStretch(g, rim, dst,
        nearestPaint(
            alpha: clampD((prog - 0.30) * 1.6, 0, 0.85), mode: ui.BlendMode.plus));
    g.restore();
  }

  fillRectShader(
    g,
    0,
    0,
    _fw,
    _fh,
    radialR0(ui.Offset(hx, hy), 50, 150,
        <ui.Color>[rgba(255, 255, 255, 1), rgba(46, 46, 46, 1)], <double>[0, 1]),
    mode: ui.BlendMode.multiply,
  );
}

// --- 2. THE SLEEPER ---------------------------------------------------------
// Full stack: shroud, hair behind, subsurface through the latex, tinted plate,
// puppet furniture painted in PLATE space so the hinge lands on the real cheek
// line and the rouge on the real malar, wet speculars, fringe.
void _drawSleep(ui.Canvas g, double t, double prog) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF0B0806));
  fillRectShader(
    g,
    0,
    0,
    _fw,
    _fh,
    radialFocal(
      const ui.Offset(_fw * 0.5, _fh * 0.36),
      10,
      const ui.Offset(_fw * 0.5, _fh * 0.5),
      190,
      <ui.Color>[rgba(190, 172, 138, 0.45), rgba(16, 11, 8, 0)],
      <double>[0, 1],
    ),
  );

  final sway = math.sin(t * 1.15) * 7, lean = prog * 22;
  final hs = 0.62 + prog * 0.20;
  final hw = _hw * hs * 0.52, hh = _hh * hs * 0.52;
  final hx = _fw / 2 + sway, hy = _fh * 0.40 + lean;
  final lag = math.cos(t * 1.15) * 3.0;

  drawShroud(g, hx, hy + hh * 0.42, hw * 2.0, _fh * 0.60, t,
      const ui.Color(0xFF1B1426), 0.7);

  final head = heads['sleep'], rim = rims['sleep'], sub = sss['sleep'];
  g.save();
  g.translate(hx, hy);
  g.rotate(math.sin(t * 0.5) * 0.05);
  drawHair(g, 0, -hh * 0.16, hw, hh, t, lag, rgba(14, 8, 12, 0.97), null, 0);

  if (head != null && rim != null && sub != null) {
    final dst = ui.Rect.fromLTWH(-hw / 2, -hh / 2, hw, hh);
    drawImageStretch(
        g, sub, dst, nearestPaint(alpha: 0.45, mode: ui.BlendMode.plus));
    drawTintedPlate(g, head, const ui.Color(0xFFE9CFA4), dst);

    final l = head.lm;
    g.save();
    g.translate(-hw / 2, -hh / 2);
    g.scale(hw / _hw, hh / _hh);
    final hinge = ui.Path()..moveTo(l.cx - l.w * 0.96, l.eye + _hh * 0.03);
    hinge.quadraticBezierTo(
        l.cx, l.mouth - _hh * 0.02, l.cx + l.w * 0.96, l.eye + _hh * 0.03);
    g.drawPath(hinge, stroke(rgba(20, 10, 8, 0.55), 3));
    for (final sg in const <double>[-1, 1]) {
      vblob(g, l.cx + sg * l.w * 0.62, l.mouth - _hh * 0.02, l.w * 0.30,
          _hh * 0.045, 0, rgba(210, 60, 60, 0.55), 0,
          mode: ui.BlendMode.multiply);
    }
    vblob(g, l.cx - l.w * 0.22, l.brow - _hh * 0.09, l.w * 0.30, _hh * 0.035,
        -0.3, rgba(255, 240, 215, 0.40), 0,
        mode: ui.BlendMode.plus);
    g.restore();

    wetSpec(g, -hw / 2, -hh / 2, hw, hh, wetSetFor(l), t);
    drawHair(g, 0, -hh * 0.16, hw, hh, t, lag, null, rgba(30, 16, 20, 0.85), 1);
    drawImageStretch(
        g, rim, dst, nearestPaint(alpha: 0.70, mode: ui.BlendMode.plus));
  } else {
    drawHair(g, 0, -hh * 0.16, hw, hh, t, lag, null, rgba(30, 16, 20, 0.85), 1);
  }
  g.restore();

  fillText(
    g,
    'GOODNIGHT, OPERATOR',
    const ui.Offset(_fw / 2, 30),
    mono(17, rgba(60, 30, 60, clampD(0.5 + math.sin(t * 4) * 0.3, 0, 1)),
        weight: FontWeight.bold),
    anchor: TextAnchor.center,
    cache: feedText,
  );
}

// --- 3. THE VERTICAL MAN ----------------------------------------------------
void _drawVert(ui.Canvas g, double t, double prog) {
  final roll = (t * 150) % _fh;
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF050807));

  // rolled programme — a lit studio floor, so the roll is obvious
  for (final oy in const <double>[-_fh, 0]) {
    g.save();
    g.translate(0, roll + oy);
    fillRectShader(
      g,
      0,
      0,
      _fw,
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
    final line = stroke(rgba(120, 220, 170, 0.20), 1);
    for (var i = 0.0; i < _fw; i += 24) {
      g.drawLine(ui.Offset(i, 0), ui.Offset(i, _fh), line);
    }
    for (var j = 140.0; j < _fh; j += 26) {
      g.drawLine(ui.Offset(0, j), ui.Offset(_fw, j), line);
    }
    fillRect(g, 30, 96, 54, 44, rgba(140, 240, 190, 0.30));
    fillRect(g, 232, 104, 50, 36, rgba(140, 240, 190, 0.30));
    g.restore();
  }

  // tear band — blown-out white, he stands inside the seam
  final bandH = 18 + prog * 46, bandY = roll - bandH * 0.5;
  final hx = _fw / 2 + math.sin(t * 0.7) * 30;
  final hr = math.min(15.0, bandH * 0.30), hy = bandY + bandH * 0.40;
  g.save();
  g.clipRect(ui.Rect.fromLTWH(0, bandY, _fw, bandH));
  fillRect(g, 0, bandY, _fw, bandH, const ui.Color(0xFFD8E4DE));
  final n = noiseTile(t, 30);
  if (n != null) {
    drawImageStretch(g, n, ui.Rect.fromLTWH(0, bandY, _fw, bandH),
        nearestPaint(alpha: 0.45));
  }
  final dark = fill(const ui.Color(0xFF040705));
  drawEllipse(g, hx, hy, hr * 0.78, hr, 0, dark); // head, inside the seam
  g.drawRect(
      ui.Rect.fromLTWH(hx - hr * 0.55, hy + hr * 0.7, hr * 1.1, 340), dark);
  g.drawRect(ui.Rect.fromLTWH(hx - 58, hy + hr * 1.5, 52, 5), dark);
  g.drawRect(ui.Rect.fromLTWH(hx + 6, hy + hr * 1.5, 52, 5), dark);
  final eyes = fill(rgba(255, 250, 235, 0.95));
  g.drawRect(ui.Rect.fromLTWH(hx - hr * 0.42, hy - hr * 0.18, 2.4, 3), eyes);
  g.drawRect(ui.Rect.fromLTWH(hx + hr * 0.16, hy - hr * 0.18, 2.4, 3), eyes);
  g.restore();

  // seam edges
  final seam = stroke(rgba(255, 255, 255, clampD(0.5 + prog * 0.4, 0, 1)), 1.5);
  g.drawLine(ui.Offset(0, bandY), ui.Offset(_fw, bandY), seam);
  g.drawLine(ui.Offset(0, bandY + bandH), ui.Offset(_fw, bandY + bandH), seam);

  // faint after-image of him outside the seam
  fillRect(g, hx - 10, bandY + 12, 20, 320,
      rgba(0, 0, 0, clampD(0.10 + prog * 0.12, 0, 1)));
}

// --- 4. THE DEAD AIR --------------------------------------------------------
void _drawDead(ui.Canvas g, double t, double prog) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF000000));
  g.drawLine(const ui.Offset(0, _fh / 2), const ui.Offset(_fw, _fh / 2),
      stroke(rgba(80, 255, 140, clampD(0.75 - prog * 0.3, 0, 1)), 1.6));

  // faint face emerging
  const cx = _fw / 2, cy = _fh / 2;
  final ga = clampD(prog * 0.5, 0, 1);
  final ln = stroke(rgba(140, 200, 170, ga), 1);
  drawEllipse(g, cx, cy - 4, 54, 68, 0, ln);
  drawEllipse(g, cx - 20, cy - 16, 9, 5, 0, ln);
  drawEllipse(g, cx + 20, cy - 16, 9, 5, 0, ln);
  g.drawLine(const ui.Offset(cx - 16, cy + 30), const ui.Offset(cx + 16, cy + 30), ln);

  fillText(
    g,
    '— NO CARRIER —',
    const ui.Offset(_fw / 2, _fh - 30),
    mono(9, rgba(90, 140, 110, clampD(0.3 + math.sin(t * 2) * 0.15, 0, 1))),
    anchor: TextAnchor.center,
    cache: feedText,
  );
}

// --- 5. THE TEST CARD GIRL --------------------------------------------------
void _drawCard(ui.Canvas g, double t, double prog) {
  const cols = <ui.Color>[
    ui.Color(0xFFC0C0C0),
    ui.Color(0xFFC0C000),
    ui.Color(0xFF00C0C0),
    ui.Color(0xFF00C000),
    ui.Color(0xFFC000C0),
    ui.Color(0xFFC00000),
    ui.Color(0xFF0000C0),
  ];
  const bw = _fw / 7;
  for (var i = 0; i < 7; i++) {
    fillRect(g, i * bw, 0, bw + 1, _fh * 0.72, cols[i]);
  }
  fillRect(g, 0, _fh * 0.72, _fw, _fh * 0.28, const ui.Color(0xFF101018));
  const sub = <ui.Color>[
    ui.Color(0xFF0000C0),
    ui.Color(0xFFFFFFFF),
    ui.Color(0xFFC000C0),
    ui.Color(0xFF101018),
  ];
  for (var i = 0; i < 4; i++) {
    fillRect(g, i * (_fw / 4), _fh * 0.72, _fw / 4 + 1, _fh * 0.10, sub[i]);
  }

  // bleed / oversaturate
  fillRect(g, 0, 0, _fw, _fh, rgba(255, 80, 140, clampD(0.06 + prog * 0.14, 0, 1)),
      mode: ui.BlendMode.screen);

  // the girl
  g.save();
  g.translate(_fw / 2, _fh * 0.52 + math.sin(t * 1.1) * 3);
  final dress = ui.Path()..moveTo(-34, 72);
  dress.lineTo(-22, -6);
  dress.lineTo(22, -6);
  dress.lineTo(34, 72);
  dress.close();
  g.drawPath(dress, fill(rgba(0, 0, 0, 0.72)));
  drawEllipse(g, 0, -32, 28, 32, 0, fill(const ui.Color(0xFFF2E6D8)));

  // chalk face
  final chalk = stroke(const ui.Color(0xFF3A3A3A), 2);
  final x1 = ui.Path()
    ..moveTo(-14, -40)
    ..lineTo(-4, -30)
    ..moveTo(-4, -40)
    ..lineTo(-14, -30);
  g.drawPath(x1, chalk);
  final x2 = ui.Path()
    ..moveTo(4, -40)
    ..lineTo(14, -30)
    ..moveTo(14, -40)
    ..lineTo(4, -30);
  g.drawPath(x2, chalk);
  g.drawArc(ui.Rect.fromCircle(center: const ui.Offset(0, -18), radius: 10),
      0.1 * math.pi, 0.8 * math.pi, false, chalk);

  // clown that is not a clown
  g.save();
  g.translate(30, 26);
  g.rotate(0.3 + math.sin(t * 2) * 0.05);
  g.drawCircle(ui.Offset.zero, 15, fill(const ui.Color(0xFFD84A4A)));
  g.drawCircle(const ui.Offset(-5, -3), 2.6, fill(const ui.Color(0xFF111111)));
  g.drawCircle(const ui.Offset(5, -3), 2.6, fill(const ui.Color(0xFF111111)));
  g.drawArc(ui.Rect.fromCircle(center: const ui.Offset(0, 4), radius: 7),
      math.pi, math.pi, false, stroke(const ui.Color(0xFF111111), 1.6));
  g.restore();
  g.restore();

  if (math.sin(t * 6) > 0.7) {
    fillRect(g, 0, 0, _fw, _fh, rgba(255, 255, 255, 0.12));
  }
}

// --- 6. THE REPEAT ----------------------------------------------------------
void _drawRerun(ui.Canvas g, double t, double prog) {
  final loop = (t * 0.9) % 4;
  final fx = 26 + (loop / 4) * (_fw - 52);
  final fy = _fh * 0.66 + math.sin(loop * math.pi * 2) * 5;

  // persistent trail buffer — slow decay so the smear actually reads
  final prev = _trail;
  final next = bakeImageSync(kFeedW, kFeedH, (tc) {
    if (prev != null) {
      drawImageStretch(tc, prev, const ui.Rect.fromLTWH(0, 0, _fw, _fh),
          nearestPaint());
    }
    fillRect(tc, 0, 0, _fw, _fh, rgba(2, 7, 5, 0.055));
    bodySil(tc, fx, fy, 0.95, rgba(170, 255, 210, 0.42));
    if (loop < 0.06) {
      fillRect(tc, 0, 0, _fw, _fh, rgba(2, 7, 5, 1)); // hard cut on loop point
    }
  });
  prev?.dispose();
  _trail = next;

  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF03100B));
  // floor line so it reads as a room, not a void
  g.drawLine(const ui.Offset(0, _fh * 0.70), const ui.Offset(_fw, _fh * 0.70),
      stroke(rgba(90, 190, 140, 0.25), 1));
  drawImageStretch(g, next, const ui.Rect.fromLTWH(0, 0, _fw, _fh), nearestPaint());
  // echoed heads — the same moment, three times
  drawImageStretch(g, next, const ui.Rect.fromLTWH(-14, 2, _fw, _fh),
      nearestPaint(alpha: 0.30));
  drawImageStretch(g, next, const ui.Rect.fromLTWH(13, -2, _fw, _fh),
      nearestPaint(alpha: 0.30));
  // the solid, current one
  bodySil(g, fx, fy, 0.95, rgba(200, 255, 225, 0.92));
  final hole = fill(const ui.Color(0xFF03100B));
  g.drawRect(ui.Rect.fromLTWH(fx - 6, fy - 66 * 0.95, 3, 3), hole);
  g.drawRect(ui.Rect.fromLTWH(fx + 3, fy - 66 * 0.95, 3, 3), hole);

  final secs = ((loop % 1) * 30).floor().toString().padLeft(2, '0');
  fillText(
    g,
    'REC  00:0${loop.floor()};$secs',
    const ui.Offset(8, 16),
    mono(11, rgba(120, 255, 180, 0.8)),
    cache: feedText,
  );
  g.drawCircle(const ui.Offset(_fw - 14, 13), 4, fill(rgba(255, 60, 40, 0.9)));
  if (loop < 0.15) {
    fillRect(g, 0, 0, _fw, _fh,
        rgba(255, 255, 255, clampD(0.22 + prog * 0.28, 0, 1)));
  }
}

// --- 7. THE NIELSEN MAN -----------------------------------------------------
//
// JS `((c+r)%3)` — c+r reaches -1 on the first row, and JS % keeps the sign, so
// the top row is DIMMER than the base shade, not brighter. Ported with
// remainder(), not %, so that stays true.
final List<TextStyle> _nielStyles = <TextStyle>[
  for (final rem in const <int>[-1, 0, 1, 2])
    mono(11, rgba(130, 255, 180, clampD(0.30 + rem * 0.22, 0, 1)),
        weight: FontWeight.bold),
];

void _drawNiel(ui.Canvas g, double t, double prog) {
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
  fillRect(g, 0, 0, _fw, _fh, rgba(0, 0, 0, 0.18));

  // auditor — a hole punched in the numbers
  g.save();
  g.translate(_fw / 2, _fh * 0.56 + math.sin(t * 0.8) * 2);
  final body = ui.Path()..moveTo(-40, 90);
  body.lineTo(-28, -10);
  body.lineTo(28, -10);
  body.lineTo(40, 90);
  body.close();
  g.drawPath(body, fill(const ui.Color(0xFF0A0B0E)));
  final open = ui.Path()
    ..moveTo(-40, 90)
    ..lineTo(-28, -10)
    ..lineTo(28, -10)
    ..lineTo(40, 90);
  g.drawPath(open, stroke(rgba(150, 255, 190, 0.30), 1));
  g.drawRect(const ui.Rect.fromLTWH(-5, -10, 10, 64),
      fill(const ui.Color(0xFF16181D)));
  // clipboard
  g.drawRect(
      const ui.Rect.fromLTWH(24, 10, 26, 34), fill(const ui.Color(0xFF8A7A52)));
  g.drawRect(
      const ui.Rect.fromLTWH(27, 14, 20, 26), fill(const ui.Color(0xFFE8E4D8)));
  // bar-chart head
  const bars = <double>[34, 28, 22, 15, 9, 4];
  for (var i = 0; i < bars.length; i++) {
    final bh = bars[i] * (1 - prog * 0.5);
    g.drawRect(ui.Rect.fromLTWH(-33 + i * 11, -14 - bh, 9, bh),
        fill(rgba(230, 226, 214, clampD(0.9 - i * 0.1, 0, 1))));
  }
  g.drawLine(const ui.Offset(-34, -46), const ui.Offset(32, -14),
      stroke(rgba(255, 70, 60, 0.9), 2));
  g.restore();

  fillText(
    g,
    'AUDIT IN PROGRESS',
    const ui.Offset(_fw / 2, 24),
    mono(11, rgba(255, 80, 70, 0.85), weight: FontWeight.bold),
    anchor: TextAnchor.center,
    cache: feedText,
  );
}

// --- 8. THE CALLER ----------------------------------------------------------
void _drawCall(ui.Canvas g, double t, double prog) {
  fillRect(g, 0, 0, _fw, _fh, const ui.Color(0xFF04060A));
  // scope grid
  final grid = stroke(rgba(60, 120, 160, 0.2), 1);
  for (var i = 0.0; i <= _fw; i += 32) {
    g.drawLine(ui.Offset(i, 0), ui.Offset(i, _fh), grid);
  }
  for (var j = 0.0; j <= _fh; j += 30) {
    g.drawLine(ui.Offset(0, j), ui.Offset(_fw, j), grid);
  }

  // speaking waveform
  final wave = ui.Path();
  for (var i = 0; i < _fw; i++) {
    final env = math.sin(t * 2.1 + i * 0.004).abs() * (0.4 + prog * 0.8);
    final a = math.sin(i * 0.14 + t * 11) * 26 * env +
        math.sin(i * 0.42 + t * 23) * 9 * env;
    if (i != 0) {
      wave.lineTo(i.toDouble(), _fh * 0.36 + a);
    } else {
      wave.moveTo(i.toDouble(), _fh * 0.36 + a);
    }
  }
  g.drawPath(wave, stroke(rgba(90, 230, 255, 0.95), 1.6));

  // dial-head figure
  g.save();
  g.translate(_fw / 2, _fh * 0.70);
  final body = ui.Path()..moveTo(-34, 70);
  body.lineTo(-24, -8);
  body.lineTo(24, -8);
  body.lineTo(34, 70);
  body.close();
  g.drawPath(body, fill(const ui.Color(0xFF03080C)));
  final open = ui.Path()
    ..moveTo(-34, 70)
    ..lineTo(-24, -8)
    ..lineTo(24, -8)
    ..lineTo(34, 70);
  g.drawPath(open, stroke(rgba(90, 230, 255, 0.55), 1.6));

  // rotary dial head
  g.save();
  g.translate(0, -38);
  g.drawCircle(ui.Offset.zero, 28, fill(const ui.Color(0xFF0A1218)));
  g.drawCircle(ui.Offset.zero, 28, stroke(rgba(120, 240, 255, 0.8), 2));
  g.rotate(math.sin(t * 1.4) * 0.6);
  for (var i = 0; i < 10; i++) {
    final a = -1.9 + i * 0.42;
    g.drawCircle(
        ui.Offset(math.cos(a) * 18, math.sin(a) * 18),
        3.4,
        fill(rgba(120, 240, 255,
            clampD(0.35 + 0.5 * math.sin(t * 3 + i).abs(), 0, 1))));
  }
  g.restore();

  // receiver arm
  g.drawLine(const ui.Offset(22, 4), const ui.Offset(34, -30),
      stroke(rgba(90, 230, 255, 0.8), 5, cap: ui.StrokeCap.round));
  g.drawRect(
      const ui.Rect.fromLTWH(28, -42, 14, 16), fill(const ui.Color(0xFF0D1A22)));
  g.restore();

  if (math.sin(t * 7) > 0) {
    fillRect(g, 0, 0, _fw, _fh, rgba(90, 230, 255, 0.06));
  }
  fillText(
    g,
    'LINE 1 · LINE 2 · LINE 3 · ALL',
    const ui.Offset(_fw / 2, 20),
    mono(11, rgba(120, 240, 255, 0.9), weight: FontWeight.bold),
    anchor: TextAnchor.center,
    cache: feedText,
  );
}
