// FINAL BROADCAST — THE TUBE.
//
// A 1:1 port of the HTML's CRT section. The picture was a pasted axis-aligned
// texture. Now it is glass: barrel distortion in 26 slices so vertical edges
// bow and the corners get eaten by the mask, half-res channel copies pushed
// apart and masked to the RIM so misconvergence only appears where a real
// shadow mask misconverges, P22 phosphor persistence, a genuine highlight
// bloom, and an interlace comb in SCREEN space so it cannot moire against the
// 240->278 stretch.
//
// NOTE: the interlace field counter is [_ifield] — the baked landscape called
// FIELD in the HTML belongs to the scene, not here.
//
// ROWLUMA: the HTML called getImageData() on the 40x26 bloom buffer every
// frame and bent each raster slice by the row luminance it read back. Flutter
// has no synchronous pixel readback, so per the port contract that readback is
// DROPPED and [syntheticRowLuma] (bake.dart) synthesises the same two bright
// bands from known game state instead. [drawMainCRT] feeds it into [blitTube]
// at exactly the point the HTML fed ROWL: bend = L*3.0 px, k += L*0.012.
//
// FRAME ORDER, matching the HTML:
//     final feed = <scene renders the 320x240 feed to a ui.Image>;
//     tickTube(feed);              // end of renderFeed()
//     ... room, window, small monitors ...
//     drawMainCRT(canvas, s, runtime, feed, runtime.tGlobal);
//
// Portable: dart:ui only. Nothing web-specific.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../anomalies.dart';
import '../bake.dart';
import '../consts.dart';
import '../state.dart';

// ---------------------------------------------------------------------------
// Baked plates + per-frame buffers
// ---------------------------------------------------------------------------

ui.Image? _edgeMask; // chW x chH radial mask: transparent centre, opaque rim
ui.Image? _comb; // 4x4 interlace tile
ui.Image? _persist; // FW x FH P22 persistence
ui.Image? _bloom; // BLW x BLH highlight bloom
int _ifield = 0;
bool _ready = false;

final ui.Rect _feedRect =
    ui.Rect.fromLTWH(0, 0, kFeedW.toDouble(), kFeedH.toDouble());
final ui.Rect _bloomRect =
    ui.Rect.fromLTWH(0, 0, kBloomW.toDouble(), kBloomH.toDouble());

/// Bakes EDGEMASK and the interlace comb tile. Idempotent.
void ensureTube() {
  if (_ready) return;
  _ready = true;

  // EDGEMASK — misconvergence only where a real shadow mask misconverges.
  final double cw = kChW.toDouble(), ch = kChH.toDouble();
  _edgeMask = bakeImageSync(kChW, kChH, (ui.Canvas x) {
    x.drawRect(
        ui.Rect.fromLTWH(0, 0, cw, ch),
        ui.Paint()
          ..shader = radialR0(
              ui.Offset(cw / 2, ch / 2),
              ch * 0.34,
              ch * 0.86,
              <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 1)],
              const <double>[0, 1]));
  });

  // combPattern() — two darkened scanlines in a 4px cell.
  _comb = bakeImageSync(4, 4, (ui.Canvas x) {
    x.drawRect(const ui.Rect.fromLTWH(0, 0, 4, 1), fill(rgba(0, 0, 0, 0.42)));
    x.drawRect(const ui.Rect.fromLTWH(0, 2, 4, 1), fill(rgba(0, 0, 0, 0.20)));
  });
}

/// Async wrapper for a boot sequence that wants to await its assets.
Future<void> initTube() async => ensureTube();

/// The P22 persistence buffer (FW x FH), or null before the first [tickTube].
ui.Image? get persistImage => _persist;

/// The highlight bloom buffer (BLW x BLH), or null before the first [tickTube].
ui.Image? get bloomImage => _bloom;

/// Frees the ping-pong buffers. Only needed by tests.
void disposeTubeBuffers() {
  _persist?.dispose();
  _persist = null;
  _bloom?.dispose();
  _bloom = null;
  for (final ui.Image i in _retired) {
    i.dispose();
  }
  _retired.clear();
}

// The persistence buffers ping-pong, so last frame's image is still referenced
// by a picture that may not have rasterised yet. Retiring them two frames deep
// costs a few hundred KB and removes the question entirely.
final List<ui.Image> _retired = <ui.Image>[];

void _retire(ui.Image? img) {
  if (img != null) _retired.add(img);
  while (_retired.length > 4) {
    _retired.removeAt(0).dispose();
  }
}

// ---------------------------------------------------------------------------
// blitTube — the 26-slice barrel
// ---------------------------------------------------------------------------

/// JS `blitTube(g,src,x,y,w,h,KH,KV,OS,rowLum,n)`.
///
/// [kh]/[kv] are the horizontal/vertical barrel coefficients, [os] the
/// overscan. [rowLum] is the per-row luminance (see [syntheticRowLuma]); when
/// it is non-null each slice is bent left by `L*3.0` px and widened by
/// `L*0.012`. [n] is the slice count — 26 for the picture, 8 for the chroma.
void blitTube(
  ui.Canvas g,
  ui.Image src,
  double x,
  double y,
  double w,
  double h,
  double kh,
  double kv,
  double os,
  Float32List? rowLum, [
  int n = 26,
  ui.Paint? paint,
]) {
  final ui.Paint p = paint ?? nearestPaint();
  final double srcW = src.width.toDouble(), srcH = src.height.toDouble();
  final double bw = w * os, bx = x + (w - bw) / 2;
  final double bh = h * os, by = y + (h - bh) / 2;
  for (int i = 0; i < n; i++) {
    final double u0 = i / n, u1 = (i + 1) / n;
    final double dy0 =
        by + bh * (0.5 + (u0 - 0.5) * (1 + kv * (1 - (2 * u0 - 1) * (2 * u0 - 1))));
    final double dy1 =
        by + bh * (0.5 + (u1 - 0.5) * (1 + kv * (1 - (2 * u1 - 1) * (2 * u1 - 1))));
    final double v = (u0 + u1) - 1;
    double k = 1 + kh * (1 - v * v);
    double bend = 0;
    if (rowLum != null && rowLum.isNotEmpty) {
      final double l = rowLum[(i * rowLum.length ~/ n).clamp(0, rowLum.length - 1)];
      k += l * 0.012;
      bend = l * 3.0;
    }
    final double dw = bw * k, dx = bx + (bw - dw) / 2 - bend;
    g.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, u0 * srcH, srcW, (u1 - u0) * srcH),
      ui.Rect.fromLTWH(dx, dy0, dw, math.max(1, dy1 - dy0) + 0.6),
      p,
    );
  }
}

/// The rectangle [blitTube] actually covers once overscan is applied.
ui.Rect _overscan(double x, double y, double w, double h, double os) =>
    ui.Rect.fromLTWH(x + (w - w * os) / 2, y + (h - h * os) / 2, w * os, h * os);

// ---------------------------------------------------------------------------
// tickTube — P22 persistence + bloom
// ---------------------------------------------------------------------------

/// JS `tickTube()`. Call once per frame with the freshly rendered feed, at the
/// end of the feed pass and BEFORE [drawMainCRT].
///
/// persist' = persist*0.66 + feed*0.26 (a black veil at 0.34 alpha, then the
/// feed added). bloom = the feed crushed to 40x26 and multiplied into itself
/// twice, i.e. v^4, which keeps only the highlights.
void tickTube(ui.Image feed) {
  ensureTube();

  final ui.Image? old = _persist;
  final ui.Image next = bakeImageSync(kFeedW, kFeedH, (ui.Canvas p) {
    if (old != null) p.drawImage(old, ui.Offset.zero, nearestPaint());
    p.drawRect(_feedRect, fill(rgba(0, 0, 0, 0.34)));
    drawImageStretch(p, feed, _feedRect,
        nearestPaint(alpha: 0.26, mode: ui.BlendMode.plus));
  });
  _retire(old);
  _persist = next;

  // 320x240 -> 40x26 is an 8x reduction; mipmapped sampling is what canvas2d's
  // smoothing does there, and plain bilinear would just alias.
  final ui.Paint down = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint mul = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..blendMode = ui.BlendMode.multiply;
  final ui.Image? oldBloom = _bloom;
  _bloom = bakeImageSync(kBloomW, kBloomH, (ui.Canvas b) {
    drawImageStretch(b, feed, _bloomRect, down);
    // The HTML drew the bloom canvas into itself twice under "multiply", which
    // squares and then squares again: v^4. Three multiplies by the same source
    // is the same product without needing a readback of the intermediate.
    drawImageStretch(b, feed, _bloomRect, mul);
    drawImageStretch(b, feed, _bloomRect, mul);
    drawImageStretch(b, feed, _bloomRect, mul);
  });
  _retire(oldBloom);
}

// ---------------------------------------------------------------------------
// chanCopy + paintTube
// ---------------------------------------------------------------------------

const ui.Color _chanRed = ui.Color(0xFFFF2020);
const ui.Color _chanBlue = ui.Color(0xFF2040FF);

/// JS `chanCopy()` + the chroma half of `paintTube()`, fused.
///
/// The HTML built a half-res canvas per channel (feed -> multiply tint ->
/// destination-in EDGEMASK) and then barrel-blitted it. Here the tint is a
/// modulate colour filter on the blit itself and the rim mask is applied to
/// the finished layer, which is the same picture with no per-frame offscreen
/// raster. The mask lands in destination space rather than source space; at
/// eight slices and KH=KV=0.045 the two are indistinguishable, and everything
/// outside the base rect is clipped by the screen well anyway.
void _chanPass(ui.Canvas g, ui.Image feed, double x, double y, double w,
    double h, ui.Color tint) {
  final ui.Rect bounds = ui.Rect.fromLTWH(x, y, w, h).inflate(24);
  withBlend(g, bounds, ui.BlendMode.plus, (ui.Canvas c) {
    final ui.Paint p = nearestPaint()
      ..colorFilter = ui.ColorFilter.mode(tint, ui.BlendMode.modulate);
    blitTube(c, feed, x, y, w, h, 0.045, 0.045, 1.04, null, 8, p);
    withBlend(c, bounds, ui.BlendMode.dstIn, (ui.Canvas m) {
      drawImageStretch(m, _edgeMask!, _overscan(x, y, w, h, 1.04),
          smoothPaint());
    });
  }, alpha: 0.55);
}

/// JS `paintTube(g,jx,jy,glitch)`.
///
/// [rowLum] replaces the HTML's per-frame `rowLuma()` readback; pass the
/// output of [syntheticRowLuma]. Null means no raster bend.
void paintTube(ui.Canvas g, ui.Image feed, double jx, double jy, double glitch,
    {Float32List? rowLum}) {
  ensureTube();
  blitTube(g, feed, kScr.left + jx, kScr.top + jy, kScr.width, kScr.height,
      0.045, 0.045, 1.04, rowLum, 26);
  final double sep = 1.4 + glitch * 3.2;
  _chanPass(g, feed, kScr.left + jx - sep, kScr.top + jy, kScr.width,
      kScr.height, _chanRed);
  _chanPass(g, feed, kScr.left + jx + sep, kScr.top + jy, kScr.width,
      kScr.height, _chanBlue);
}

// ---------------------------------------------------------------------------
// glassPass — persistence, bloom, interlace comb
// ---------------------------------------------------------------------------

Float64List _translation(double tx, double ty) => Float64List.fromList(
    <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);

ui.Paint? _combPaint;

/// JS `combPattern(g)` — cached, since the pattern never changes.
ui.Paint _comber() {
  ensureTube();
  return _combPaint ??= (ui.Paint()
    ..isAntiAlias = false
    ..shader = ui.ImageShader(_comb!, ui.TileMode.repeated, ui.TileMode.repeated,
        _translation(0, 0),
        filterQuality: ui.FilterQuality.none));
}

/// JS `glassPass(g)`. Draw it inside the screen-well clip, straight after
/// [paintTube] and the tear slices.
void glassPass(ui.Canvas g) {
  ensureTube();
  final ui.Image? per = _persist;
  if (per != null) {
    drawImageStretch(
        g, per, kScr, nearestPaint(alpha: 0.22, mode: ui.BlendMode.plus));
  }
  final ui.Image? bl = _bloom;
  if (bl != null) {
    drawImageStretch(g, bl, kScr.inflate(3),
        smoothPaint(alpha: 0.20, mode: ui.BlendMode.plus));
  }
  _ifield ^= 1;
  g.save();
  g.translate(0, _ifield.toDouble());
  g.drawRect(
      ui.Rect.fromLTWH(kScr.left, kScr.top - 1, kScr.width, kScr.height + 2),
      _comber());
  g.restore();
}

// ---------------------------------------------------------------------------
// drawMainCRT
// ---------------------------------------------------------------------------

ui.RRect _rr(double x, double y, double w, double h, double r) =>
    ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(x, y, w, h), ui.Radius.circular(r));

/// JS `anomGlow(id)` — the phosphor colour each entity throws into the room.
ui.Color _anomGlow(String id) {
  switch (id) {
    case 'snow':
      return const ui.Color(0xFFC8C8D2);
    case 'sleep':
      return const ui.Color(0xFFFFDC96);
    case 'vert':
      return const ui.Color(0xFF78AAFF);
    case 'dead':
      return const ui.Color(0xFF3CFF8C);
    case 'card':
      return const ui.Color(0xFFFF5AA0);
    case 'rerun':
      return const ui.Color(0xFF78FFBE);
    case 'niel':
      return const ui.Color(0xFFFF5A46);
    case 'call':
      return const ui.Color(0xFF5ADCFF);
  }
  return const ui.Color(0xFFFFFFFF);
}

// Strings that change every frame (the countdown, the tuning pops) would grow
// the shared TextCache without bound, so they get their own cache with a lid.
final TextCache _dyn = TextCache();

TextCache _dynCache() {
  if (_dyn.length > 256) _dyn.clear();
  return _dyn;
}

final ui.Paint _bezelStroke = stroke(const ui.Color(0xFF3D4749), 1);
final ui.Paint _blackFill = fill(const ui.Color(0xFF000000));

/// JS `drawMainCRT(t)`.
///
/// Draws the bezel, the picture (barrel blit + chroma + tears + glass), the
/// tuning feedback, the phosphor spill into the room, the nameplate / SECOND
/// CAMERA readout, the power lamp and the banish ring.
///
/// [feed] is the 320x240 broadcast feed for this frame; [tickTube] must
/// already have been called with it.
void drawMainCRT(ui.Canvas g, GameState s, AnomalyRuntime a, ui.Image feed,
    double t) {
  ensureTube();
  final double cx = kCrt.left, cy = kCrt.top, cw = kCrt.width, chh = kCrt.height;

  // ---- bezel ----
  g.drawRRect(
      _rr(cx, cy + 8, cw, chh, 12),
      ui.Paint()
        ..color = rgba(0, 0, 0, 0.85)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14));
  g.drawRRect(
      _rr(cx, cy, cw, chh, 12),
      ui.Paint()
        ..isAntiAlias = true
        ..shader = linear(
            ui.Offset(0, cy),
            ui.Offset(0, cy + chh),
            const <ui.Color>[
              ui.Color(0xFF2B3234),
              ui.Color(0xFF1A2022),
              ui.Color(0xFF0E1213),
            ],
            const <double>[0, 0.5, 1]));
  g.drawRRect(_rr(cx + .5, cy + .5, cw - 1, chh - 1, 12), _bezelStroke);

  // ---- screen well ----
  g.drawRRect(
      _rr(kScr.left - 4, kScr.top - 4, kScr.width + 8, kScr.height + 8, 8),
      _blackFill);

  // ---- the picture ----
  g.save();
  g.clipRRect(_rr(kScr.left, kScr.top, kScr.width, kScr.height, 6));
  g.drawRect(kScr, _blackFill);

  final ActiveAnom? act = a.active;
  final double glitch =
      a.glitch * (act != null ? (0.3 + act.t / act.window * 0.7) : 0) +
          a.scare * 0.6;
  final double jx = glitch > 0 ? rr(-4, 4) * glitch : 0;
  final double jy = glitch > 0 ? rr(-2, 2) * glitch : 0;

  if (s.flash && glitch > 0.15 && rand() < 0.35) {
    // RGB split
    final ui.Paint p = nearestPaint(alpha: 0.55, mode: ui.BlendMode.plus);
    drawImageStretch(
        g,
        feed,
        ui.Rect.fromLTWH(kScr.left + jx - 3 * glitch, kScr.top + jy,
            kScr.width, kScr.height),
        p);
    drawImageStretch(
        g,
        feed,
        ui.Rect.fromLTWH(kScr.left + jx + 3 * glitch, kScr.top + jy,
            kScr.width, kScr.height),
        p);
  }

  paintTube(g, feed, jx, jy, glitch,
      rowLum: syntheticRowLuma(
        t: a.tGlobal,
        glitch: a.glitch,
        tuneHeat: s.tune.heat,
        anomProgress: act?.p ?? 0,
        dread: s.dread,
      ));

  // horizontal tear slices
  if (glitch > 0.25 && s.flash) {
    final int n = (glitch * 5).toInt();
    final ui.Paint p = nearestPaint();
    for (int i = 0; i < n; i++) {
      final double sy = rr(0, kScr.height - 6);
      final double sh = rr(3, 16);
      final double off = rr(-22, 22) * glitch;
      g.drawImageRect(
          feed,
          ui.Rect.fromLTWH(0, (sy / kScr.height) * kFeedH, kFeedW.toDouble(),
              (sh / kScr.height) * kFeedH),
          ui.Rect.fromLTWH(kScr.left + off, kScr.top + sy, kScr.width, sh),
          p);
    }
  }

  glassPass(g);

  // rolling brightness bar (CRT refresh)
  final double rb = ((t * 90) % (kScr.height + 120)) - 120;
  g.drawRect(
      ui.Rect.fromLTWH(kScr.left, kScr.top + rb, kScr.width, 120),
      ui.Paint()
        ..shader = linear(
            ui.Offset(0, kScr.top + rb),
            ui.Offset(0, kScr.top + rb + 120),
            <ui.Color>[
              rgba(255, 255, 255, 0),
              rgba(255, 255, 255, .035),
              rgba(255, 255, 255, 0),
            ],
            const <double>[0, 0.5, 1]));

  // glass curvature vignette + reflection
  g.drawRect(
      kScr,
      ui.Paint()
        ..shader = radialR0(
            kScr.center,
            kScr.height * 0.28,
            kScr.height * 0.85,
            <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, .72)],
            const <double>[0, 1]));
  g.drawRect(
      kScr,
      ui.Paint()
        ..shader = linear(
            ui.Offset(kScr.left, kScr.top),
            ui.Offset(kScr.left + kScr.width * 0.6, kScr.top + kScr.height * 0.6),
            <ui.Color>[rgba(255, 255, 255, .045), rgba(255, 255, 255, 0)],
            const <double>[0, 0.35]));

  // tuning feedback — struck-glass rings and the signal you knocked loose
  // CARRIER LOCK tiers the feedback: the rings get wider and the numbers get
  // bigger, hotter and eventually white, so the rhythm you are holding is
  // legible at a glance instead of being a hidden multiplier.
  final int lockTier = s.tune.tier.clamp(0, 4);
  const List<ui.Color> lockInk = <ui.Color>[
    ui.Color(0xFFB4FFD7),
    ui.Color(0xFF8FF0FF),
    ui.Color(0xFF7FD8FF),
    ui.Color(0xFFFFC46B),
    ui.Color(0xFFFFFFFF),
  ];
  final double lockSize = 15 + lockTier * 2.6;
  for (final TuneRipple r in s.tune.ripples) {
    final double p = r.t / 0.55;
    if (p > 1) continue;
    final ui.Color rc = lockInk[lockTier];
    g.drawCircle(ui.Offset(r.x, r.y), 8 + p * (54 + lockTier * 16),
        stroke(rc.withValues(alpha: 0.5 * (1 - p)), 2 * (1 - p) + 0.5));
    if (lockTier >= 2) {
      g.drawCircle(ui.Offset(r.x, r.y), 8 + p * (30 + lockTier * 10),
          stroke(rc.withValues(alpha: 0.26 * (1 - p)), 1.2 * (1 - p) + 0.4));
    }
  }
  for (final TunePop p in s.tune.pops) {
    final double k = p.t / 0.9;
    if (k > 1) continue;
    groupLayer(g, ui.Rect.fromLTWH(p.x - 90, p.y - 70, 180, 70), (ui.Canvas c) {
      fillText(c, p.v, ui.Offset(p.x, p.y - k * (34 + lockTier * 6)),
          mono(lockSize, lockInk[lockTier], weight: ui.FontWeight.bold),
          anchor: TextAnchor.center, cache: _dynCache());
    }, alpha: clampD(1 - k, 0, 1));
  }
  // the lock meter, on the tube's lower strap where the eye already is
  if (s.tune.tier > 0 || s.tune.lockP > 0.02) {
    final double mw = kScr.width * 0.42;
    final double mx = kScr.left + (kScr.width - mw) / 2;
    final double my = kScr.bottom - 16;
    g.drawRect(ui.Rect.fromLTWH(mx, my, mw, 5), fill(rgba(0, 0, 0, 0.55)));
    final double fillW =
        s.tune.tier >= 4 ? mw : mw * clampD(s.tune.lockP, 0, 1);
    g.drawRect(ui.Rect.fromLTWH(mx, my, fillW, 5),
        fill(lockInk[lockTier].withValues(alpha: 0.85)));
    if (s.tune.tier > 0) {
      fillText(
          g,
          '${s.tune.tierName}  x${s.tune.tierMult.toStringAsFixed(1)}',
          ui.Offset(kScr.left + kScr.width / 2, my - 6),
          mono(11, lockInk[lockTier], weight: ui.FontWeight.bold),
          anchor: TextAnchor.center,
          cache: _dynCache());
    }
  }
  g.restore();

  // ---- phosphor bloom around the tube ----
  if (act != null || a.scare > 0) {
    final ui.Color c =
        act != null ? _anomGlow(act.def.id) : const ui.Color(0xFFFF281E);
    final double inten = (act != null ? (0.10 + act.t / act.window * 0.18) : 0.3) *
        (act != null && act.def.id == 'dead' ? 0.4 : 1);
    g.drawRect(
        kRoom,
        ui.Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = radialR0(
              kScr.center,
              kScr.height * 0.4,
              kScr.height * 1.5,
              <ui.Color>[
                c.withValues(alpha: clampD(inten, 0, 1)),
                c.withAlpha(0)
              ],
              const <double>[0, 1]));
  }

  // ---- bezel furniture ----
  g.drawRect(ui.Rect.fromLTWH(cx + 18, cy + chh - 26, cw - 36, 14),
      fill(const ui.Color(0xFF0A0D0E)));
  final Counter? hint = a.cam2Hint;
  if (hint != null) {
    fillText(
        g,
        'SECOND CAMERA READS -> ${hint.nm}  [KEY ${hint.key}]',
        ui.Offset(cx + 24, cy + chh - 16),
        mono(9, rgba(109, 255, 154, .9), weight: ui.FontWeight.bold));
  } else {
    fillText(g, 'MERIDIAN CATHODE  ·  MODEL 7',
        ui.Offset(cx + 24, cy + chh - 16), mono(11, rgba(180, 220, 215, .35)));
  }

  // power lamp
  g.drawCircle(
      ui.Offset(cx + cw - 30, cy + chh - 19),
      3.5,
      fill(a.lost ? rgba(255, 50, 40, .9) : rgba(90, 255, 150, .9)));

  // ---- banish window ring around the bezel ----
  if (act != null) {
    final double p = 1 - act.t / act.window;
    final ui.RRect ring = _rr(cx - 6, cy - 6, cw + 12, chh + 12, 14);
    g.drawRRect(ring, stroke(rgba(0, 0, 0, .6), 6));

    final double per = 2 * ((cw + 12) + (chh + 12));
    final ui.Color ringCol =
        p < 0.3 ? K.red : (p < 0.6 ? K.amber : K.green);
    final ui.Path full = ui.Path()..addRRect(ring);
    ui.Path arc = ui.Path();
    for (final ui.PathMetric m in full.computeMetrics()) {
      arc = m.extractPath(0, math.min(per * p, m.length));
      break;
    }
    // shadowBlur 14 -> a blurred understroke of the same colour
    g.drawPath(
        arc,
        stroke(ringCol, 6)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7));
    g.drawPath(arc, stroke(ringCol, 6));

    // name + countdown
    g.drawRect(
        ui.Rect.fromLTWH(cx, cy - 42, cw, 26), fill(rgba(0, 0, 0, .75)));
    final String label = (act.masked && act.stage == 0)
        ? '## MASKED SIGNAL'
        : act.def.nm;
    fillText(
        g,
        '$label   ${(act.window - act.t).toStringAsFixed(1)}s',
        ui.Offset(cx + cw / 2, cy - 24),
        mono(15, p < 0.3 ? K.onAirLive : const ui.Color(0xFFFFD9A0),
            weight: ui.FontWeight.bold),
        anchor: TextAnchor.center,
        cache: _dynCache());
  } else if (a.warn > 0) {
    g.drawRect(ui.Rect.fromLTWH(cx, cy - 42, cw, 26), fill(rgba(0, 0, 0, .7)));
    fillText(
        g,
        '!!  CARRIER DISTURBANCE  !!',
        ui.Offset(cx + cw / 2, cy - 24),
        mono(
            14,
            math.sin(a.tGlobal * 22) > 0
                ? K.onAirLive
                : const ui.Color(0xFF7A2A24),
            weight: ui.FontWeight.bold),
        anchor: TextAnchor.center);
  } else if (a.allClear) {
    // A green ring that drains is the clearest possible reading of "you are safe,
    // and this is exactly how long for".
    g.drawRect(ui.Rect.fromLTWH(cx, cy - 42, cw, 26), fill(rgba(0, 0, 0, .6)));
    fillText(
        g,
        'ALL CLEAR   ${a.calmSeconds}s',
        ui.Offset(cx + cw / 2, cy - 24),
        mono(14, K.green, weight: ui.FontWeight.bold),
        anchor: TextAnchor.center);
  }
}
