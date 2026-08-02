// FINAL BROADCAST — shared painting plumbing.
//
// Everything the canvas port needs that dart:ui does not hand you directly:
// offscreen baking, globalCompositeOperation, JS-style radial gradients with an
// inner radius, fillText, and the replacement for the per-frame getImageData()
// the HTML used to bend the raster.
//
// Portable: dart:ui + package:flutter/painting only.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'consts.dart';

// ---------------------------------------------------------------------------
// 1. BAKING — the offscreen canvases
// ---------------------------------------------------------------------------

/// The JS `document.createElement("canvas")` + draw-once + drawImage-forever
/// pattern. Records `draw` into a picture and rasterises it to a ui.Image of
/// exactly [width] x [height] device pixels.
///
/// Call these once from an async init() and hold the ui.Image for the life of
/// the app. Never bake per frame.
Future<ui.Image> bakeImage(
    int width, int height, void Function(ui.Canvas c) draw) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(
      rec, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  draw(c);
  final pic = rec.endRecording();
  final img = await pic.toImage(width, height);
  pic.dispose();
  return img;
}

/// Synchronous bake. Handy when you need a plate inside a constructor or a
/// first frame; rasterisation is deferred by the engine but the handle is
/// usable immediately. Prefer [bakeImage] for bulk startup work.
ui.Image bakeImageSync(
    int width, int height, void Function(ui.Canvas c) draw) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(
      rec, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  draw(c);
  final pic = rec.endRecording();
  final img = pic.toImageSync(width, height);
  pic.dispose();
  return img;
}

/// Bakes into a ui.Picture instead of a raster. Cheaper than an image for pure
/// vector plates that are always drawn at the same scale.
ui.Picture bakePicture(
    double width, double height, void Function(ui.Canvas c) draw) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, width, height));
  draw(c);
  return rec.endRecording();
}

// ---------------------------------------------------------------------------
// 2. BLEND MODES — globalCompositeOperation
// ---------------------------------------------------------------------------

/// The canvas2d -> dart:ui blend-mode table. Use this rather than guessing.
///
///   "lighter"        -> BlendMode.plus
///   "multiply"       -> BlendMode.multiply
///   "screen"         -> BlendMode.screen
///   "overlay"        -> BlendMode.overlay
///   "soft-light"     -> BlendMode.softLight
///   "hard-light"     -> BlendMode.hardLight
///   "difference"     -> BlendMode.difference
///   "color-dodge"    -> BlendMode.colorDodge
///   "destination-in" -> BlendMode.dstIn
///   "destination-out"-> BlendMode.dstOut
///   "destination-over"->BlendMode.dstOver
///   "source-atop"    -> BlendMode.srcATop
///   "source-in"      -> BlendMode.srcIn
///   "source-over"    -> BlendMode.srcOver   (the default; no layer needed)
const Map<String, ui.BlendMode> kCompositeOps = <String, ui.BlendMode>{
  'source-over': ui.BlendMode.srcOver,
  'lighter': ui.BlendMode.plus,
  'multiply': ui.BlendMode.multiply,
  'screen': ui.BlendMode.screen,
  'overlay': ui.BlendMode.overlay,
  'soft-light': ui.BlendMode.softLight,
  'hard-light': ui.BlendMode.hardLight,
  'difference': ui.BlendMode.difference,
  'color-dodge': ui.BlendMode.colorDodge,
  'color-burn': ui.BlendMode.colorBurn,
  'destination-in': ui.BlendMode.dstIn,
  'destination-out': ui.BlendMode.dstOut,
  'destination-over': ui.BlendMode.dstOver,
  'destination-atop': ui.BlendMode.dstATop,
  'source-atop': ui.BlendMode.srcATop,
  'source-in': ui.BlendMode.srcIn,
  'source-out': ui.BlendMode.srcOut,
  'xor': ui.BlendMode.xor,
};

/// The single most important helper in the port.
///
/// `ctx.globalCompositeOperation = mode; …draws…; ctx.globalCompositeOperation
/// = "source-over"` becomes:
///
///     withBlend(canvas, bounds, ui.BlendMode.plus, (c) { …draws… });
///
/// The draws go into an isolated layer which is then composited onto whatever
/// is already on the canvas using [mode]. dstIn / dstOut / srcATop ONLY behave
/// correctly this way — without the saveLayer they eat the whole surface.
///
/// [bounds] must enclose everything the mode is allowed to affect. For a
/// destination-* mode that means the region you want masked, not just the mask.
///
/// [alpha] is `ctx.globalAlpha` for the whole group.
void withBlend(
  ui.Canvas canvas,
  ui.Rect bounds,
  ui.BlendMode mode,
  void Function(ui.Canvas c) body, {
  double alpha = 1.0,
}) {
  final p = ui.Paint()..blendMode = mode;
  if (alpha < 1.0) {
    p.color = ui.Color.fromRGBO(0, 0, 0, clampD(alpha, 0, 1));
  }
  canvas.saveLayer(bounds, p);
  body(canvas);
  canvas.restore();
}

/// A plain isolated group. Use this to fence off content BEFORE applying a
/// destination-in / destination-out mask so the mask only eats this group.
///
///     groupLayer(canvas, bounds, (c) {
///       drawTheThing(c);
///       withBlend(c, bounds, ui.BlendMode.dstIn, drawTheMask);
///     });
void groupLayer(
  ui.Canvas canvas,
  ui.Rect bounds,
  void Function(ui.Canvas c) body, {
  double alpha = 1.0,
}) {
  final p = ui.Paint();
  if (alpha < 1.0) {
    p.color = ui.Color.fromRGBO(0, 0, 0, clampD(alpha, 0, 1));
  }
  canvas.saveLayer(bounds, p);
  body(canvas);
  canvas.restore();
}

/// `ctx.filter = "blur(Npx)"` for a whole group. [sigma] is the CSS px radius
/// divided by ~2; pass the value you actually want to see.
void withBlur(
  ui.Canvas canvas,
  ui.Rect bounds,
  double sigma,
  void Function(ui.Canvas c) body, {
  ui.BlendMode mode = ui.BlendMode.srcOver,
  double alpha = 1.0,
}) {
  final p = ui.Paint()
    ..blendMode = mode
    ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.decal);
  if (alpha < 1.0) {
    p.color = ui.Color.fromRGBO(0, 0, 0, clampD(alpha, 0, 1));
  }
  canvas.saveLayer(bounds, p);
  body(canvas);
  canvas.restore();
}

// ---------------------------------------------------------------------------
// 3. GRADIENTS — JS createRadialGradient / createLinearGradient
// ---------------------------------------------------------------------------

/// `ctx.createRadialGradient(cx,cy,r0,cx,cy,r1)` — the concentric case, which
/// is every radial gradient in the HTML.
///
/// JS stop 0 sits at radius r0, not at the centre; dart:ui has no inner radius,
/// so the stops are remapped onto [0,1] of r1 and everything inside r0 is left
/// as the first colour (TileMode.clamp does that for free).
ui.Gradient radialR0(
  ui.Offset center,
  double r0,
  double r1,
  List<ui.Color> colors,
  List<double> stops,
) {
  assert(colors.length == stops.length);
  final r = r1 <= 0 ? 1e-6 : r1;
  final mapped = <double>[
    for (final s in stops) clampD((r0 + s * (r1 - r0)) / r, 0, 1),
  ];
  // dart:ui requires strictly increasing stops.
  for (var i = 1; i < mapped.length; i++) {
    if (mapped[i] <= mapped[i - 1]) {
      mapped[i] = math.min(1.0, mapped[i - 1] + 1e-5);
    }
  }
  return ui.Gradient.radial(center, r, colors, mapped);
}

/// The offset-focus form, `createRadialGradient(fx,fy,r0, cx,cy,r1)`.
ui.Gradient radialFocal(
  ui.Offset focus,
  double r0,
  ui.Offset center,
  double r1,
  List<ui.Color> colors,
  List<double> stops,
) {
  assert(colors.length == stops.length);
  final r = r1 <= 0 ? 1e-6 : r1;
  final mapped = <double>[
    for (final s in stops) clampD((r0 + s * (r1 - r0)) / r, 0, 1),
  ];
  for (var i = 1; i < mapped.length; i++) {
    if (mapped[i] <= mapped[i - 1]) {
      mapped[i] = math.min(1.0, mapped[i - 1] + 1e-5);
    }
  }
  return ui.Gradient.radial(
      center, r, colors, mapped, ui.TileMode.clamp, null, focus, r0);
}

/// `ctx.createLinearGradient(x0,y0,x1,y1)`.
ui.Gradient linear(
  ui.Offset from,
  ui.Offset to,
  List<ui.Color> colors,
  List<double> stops,
) {
  assert(colors.length == stops.length);
  return ui.Gradient.linear(from, to, colors, stops);
}

/// `rgba(r,g,b,a)` written the JS way, for transcribing colour literals.
ui.Color rgba(int r, int g, int b, double a) =>
    ui.Color.fromRGBO(r, g, b, clampD(a, 0, 1));

/// A solid fill paint.
ui.Paint fill(ui.Color c, {ui.BlendMode mode = ui.BlendMode.srcOver}) =>
    ui.Paint()
      ..color = c
      ..blendMode = mode
      ..isAntiAlias = true;

/// A stroke paint. `lineWidth` is `ctx.lineWidth`.
ui.Paint stroke(ui.Color c, double lineWidth,
        {ui.BlendMode mode = ui.BlendMode.srcOver,
        ui.StrokeCap cap = ui.StrokeCap.butt}) =>
    ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = cap
      ..color = c
      ..blendMode = mode
      ..isAntiAlias = true;

// ---------------------------------------------------------------------------
// 4. IMAGES — drawImage
// ---------------------------------------------------------------------------

/// `ctx.imageSmoothingEnabled = false`.
ui.Paint nearestPaint({double alpha = 1.0, ui.BlendMode? mode}) {
  final p = ui.Paint()
    ..filterQuality = ui.FilterQuality.none
    ..isAntiAlias = false;
  if (alpha < 1.0) p.color = ui.Color.fromRGBO(0, 0, 0, clampD(alpha, 0, 1));
  if (mode != null) p.blendMode = mode;
  return p;
}

/// `ctx.imageSmoothingEnabled = true`.
ui.Paint smoothPaint({double alpha = 1.0, ui.BlendMode? mode}) {
  final p = ui.Paint()..filterQuality = ui.FilterQuality.low;
  if (alpha < 1.0) p.color = ui.Color.fromRGBO(0, 0, 0, clampD(alpha, 0, 1));
  if (mode != null) p.blendMode = mode;
  return p;
}

/// `ctx.drawImage(img, dx, dy, dw, dh)` — whole source stretched to [dst].
void drawImageStretch(ui.Canvas canvas, ui.Image img, ui.Rect dst,
    [ui.Paint? paint]) {
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    dst,
    paint ?? nearestPaint(),
  );
}

// ---------------------------------------------------------------------------
// 5. TEXT — fillText
// ---------------------------------------------------------------------------

/// The game's only font.
TextStyle mono(double size, ui.Color color,
        {FontWeight weight = FontWeight.normal,
        double? letterSpacing,
        double? height}) =>
    TextStyle(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );

/// `ctx.textAlign`.
enum TextAnchor { left, center, right }

/// TextPainters are expensive to build. Anything drawn every frame with static
/// text must come from here, not from a fresh TextPainter.
///
/// The cache is unbounded on purpose — the game has a fixed vocabulary of
/// labels. Call [clear] if you ever generate text from unbounded input.
class TextCache {
  final Map<String, TextPainter> _m = <String, TextPainter>{};

  TextPainter get(String text, TextStyle style, {double? maxWidth}) {
    final key = '${style.hashCode}|${maxWidth ?? -1}|$text';
    return _m.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: maxWidth == null ? 1 : null,
      )..layout(maxWidth: maxWidth ?? double.infinity);
      return tp;
    });
  }

  int get length => _m.length;

  void clear() => _m.clear();
}

/// Shared cache. Painters may keep their own if they prefer.
final TextCache textCache = TextCache();

/// `ctx.fillText(text, x, y)` — [at] is the BASELINE origin, matching canvas2d,
/// and [anchor] is `ctx.textAlign`.
void fillText(
  ui.Canvas canvas,
  String text,
  ui.Offset at,
  TextStyle style, {
  TextAnchor anchor = TextAnchor.left,
  TextCache? cache,
}) {
  final tp = (cache ?? textCache).get(text, style);
  final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  double dx = at.dx;
  if (anchor == TextAnchor.center) {
    dx -= tp.width / 2;
  } else if (anchor == TextAnchor.right) {
    dx -= tp.width;
  }
  tp.paint(canvas, ui.Offset(dx, at.dy - baseline));
}

/// Top-left origin variant, for laying out UI rather than transcribing
/// fillText calls.
void drawText(
  ui.Canvas canvas,
  String text,
  ui.Offset topLeft,
  TextStyle style, {
  TextAnchor anchor = TextAnchor.left,
  double? maxWidth,
  TextCache? cache,
}) {
  final tp = (cache ?? textCache).get(text, style, maxWidth: maxWidth);
  double dx = topLeft.dx;
  if (anchor == TextAnchor.center) {
    dx -= tp.width / 2;
  } else if (anchor == TextAnchor.right) {
    dx -= tp.width;
  }
  tp.paint(canvas, ui.Offset(dx, topLeft.dy));
}

/// Width of a string in the given style, `ctx.measureText(...).width`.
double measureText(String text, TextStyle style, {TextCache? cache}) =>
    (cache ?? textCache).get(text, style).width;

// ---------------------------------------------------------------------------
// 6. ROW LUMINANCE — the one thing that could not be ported
// ---------------------------------------------------------------------------
//
// The HTML called getImageData() on a 40x26 bloom buffer EVERY FRAME and fed
// the per-row luminance into blitTube(), which bent each raster slice
// horizontally by `L * 3.0` px and widened it by `L * 0.012`.
//
// Flutter has no synchronous pixel readback — Image.toByteData() is async — so
// the readback is DROPPED. The bend is instead synthesised from known game
// state, which is the substitute the original author's own cut-list suggested.
// It is not pixel-accurate; it is the same effect driven by the same causes
// (a bright band where the picture is, more bend during a glitch, more when the
// operator is hammering the tube).

final Float32List _rowl = Float32List(kBloomH);

/// Per-row luminance in 0..1 for the raster bend, [rows] long (defaults to the
/// HTML's 26). The returned buffer is REUSED — copy it if you need to keep it.
///
/// * [t]            — the global animation clock (tGlobal).
/// * [glitch]       — AnomalyRuntime.glitch, 0..1.
/// * [tuneHeat]     — GameState.tune.heat, 0..1.
/// * [anomProgress] — ActiveAnom.p, 0..1, or 0 when nothing is live.
/// * [dread]        — GameState.dread, 0..100.
Float32List syntheticRowLuma({
  required double t,
  double glitch = 0,
  double tuneHeat = 0,
  double anomProgress = 0,
  double dread = 0,
  int rows = kBloomH,
}) {
  final out = rows == kBloomH ? _rowl : Float32List(rows);
  // The feed's horizon glow sits at ~0.55 of the frame; the waveform trace at
  // ~0.22. Those are the two bright bands a real readback would have found.
  final agitation = clampD(glitch * 0.55 + anomProgress * 0.35 + dread / 400,
      0, 1);
  final hammer = clampD(tuneHeat, 0, 1);
  for (var r = 0; r < rows; r++) {
    final u = rows <= 1 ? 0.0 : r / (rows - 1);
    final horizon = math.exp(-math.pow((u - 0.55) / 0.30, 2).toDouble());
    final trace = 0.45 * math.exp(-math.pow((u - 0.22) / 0.06, 2).toDouble());
    var v = 0.16 + 0.30 * horizon + trace;
    // slow vertical roll, so the bend never sits still
    v += 0.05 * math.sin(u * 9.0 + t * 1.7);
    // agitation adds a fast tearing band that sweeps the frame
    if (agitation > 0) {
      final band = math.exp(
          -math.pow((u - (t * 0.63 % 1.0)) / 0.07, 2).toDouble());
      v += agitation * (0.34 * band + 0.06 * math.sin(u * 41.0 + t * 23.0));
    }
    // striking the set brightens the whole raster briefly
    v *= 1 + hammer * 0.35;
    out[r] = v < 0 ? 0 : (v > 1 ? 1 : v);
  }
  return out;
}
