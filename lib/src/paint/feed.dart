// FINAL BROADCAST — THE FEED.
//
// The 320x240 offscreen the station is actually transmitting. Everything the
// operator sees on the tube comes through here: the normal programme
// (transmitter silhouette, output waveform, station ident, ticker, the STRIKE
// THE SET prompt), the eight anomalies, the masked-carrier overlay, the
// jumpscare frame and the dead-air frame.
//
// Straight port of the HTML's `renderFeed(t)` and `drawFeedNormal(t)`.
//
// TWO THINGS DELIBERATELY LEFT OUT, because they belong to the tube pass and
// not to the feed content:
//   * `tickTube()` — the persistence and bloom buffers. renderFeed() called it
//     as its last line; here the scene painter calls its own equivalent after
//     taking this frame.
//   * the scanline loop the HTML already deleted in favour of the screen-space
//     interlace comb in glassPass().
//
// Portable: dart:ui + package:flutter/painting only.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/bake.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/paint/entities.dart';
import 'package:final_broadcast/src/state.dart';

const double _fw = 320; // FW
const double _fh = 240; // FH
const ui.Rect _feedRect = ui.Rect.fromLTWH(0, 0, _fw, _fh);

// ---------------------------------------------------------------------------
// Static text styles. Anything whose colour is constant is built once.
// ---------------------------------------------------------------------------

final TextStyle _identStyle =
    mono(15, rgba(190, 255, 215, 0.92), weight: FontWeight.bold);
final TextStyle _subIdentStyle = mono(8, rgba(150, 220, 180, 0.7));
final TextStyle _hintStyle = mono(9, rgba(150, 220, 185, 0.8));
final TextStyle _manualStyle = mono(9, rgba(150, 220, 185, 0.75));
final TextStyle _tickerStyle = mono(9, rgba(190, 255, 215, 0.85));
final TextStyle _sponsorStyle =
    mono(9, rgba(255, 179, 71, 0.9), weight: FontWeight.bold);
final TextStyle _maskedStyle =
    mono(12, rgba(255, 255, 255, 0.75), weight: FontWeight.bold);
final TextStyle _cutStyle = mono(9, rgba(255, 180, 180, 0.8));

// ---------------------------------------------------------------------------
// drawFeedNormal — what KBLK-7 is putting out when nothing is wrong
// ---------------------------------------------------------------------------

/// JS `drawFeedNormal(t)`. [f] is the 320x240 feed canvas.
void drawFeedNormal(ui.Canvas f, GameState s, AnomalyRuntime a, double t) {
  fillRect(f, 0, 0, _fw, _fh, const ui.Color(0xFF04120A));

  // horizon glow
  fillRectShader(
    f,
    0,
    0,
    _fw,
    _fh,
    radialR0(const ui.Offset(_fw / 2, _fh * 0.55), 10, 190,
        <ui.Color>[rgba(20, 90, 50, 0.55), rgba(2, 10, 6, 0)], <double>[0, 1]),
  );

  // slow-panning transmitter silhouette
  final px = (t * 7) % (_fw + 140) - 70;
  final ridge = ui.Path()
    ..moveTo(0, _fh)
    ..lineTo(0, 168);
  for (var i = 0.0; i <= _fw; i += 16) {
    ridge.lineTo(
        i,
        168 +
            math.sin((i + t * 8) * 0.05) * 7 +
            math.sin(i * 0.013) * 10);
  }
  ridge.lineTo(_fw, _fh);
  ridge.close();
  f.drawPath(ridge, fill(const ui.Color(0xFF02170D)));

  final mast = ui.Path()
    ..moveTo(px, 176)
    ..lineTo(px - 9, _fh - 24)
    ..moveTo(px, 176)
    ..lineTo(px + 9, _fh - 24);
  for (var y = 190.0; y < _fh - 24; y += 16) {
    final sp = (y - 176) / (_fh - 200) * 9;
    mast.moveTo(px - sp, y);
    mast.lineTo(px + sp, y);
  }
  f.drawPath(mast, stroke(rgba(80, 200, 130, 0.5), 1));

  final bl = math.sin(t * 3) * 0.5 + 0.5;
  fillRect(f, px - 2, 172, 4, 4,
      rgba(255, 60, 40, clampD(0.35 + bl * 0.65, 0, 1)));

  // waveform of current output
  final rate = sigRate(s, a);
  final wave = ui.Path();
  for (var i = 0; i < _fw; i++) {
    final amp = math.sin(i * 0.09 + t * 4) * 10 +
        math.sin(i * 0.31 + t * 7) * 4 * math.min(1.0, rate / 50 + 0.2);
    if (i == 0) {
      wave.moveTo(i.toDouble(), 52 + amp);
    } else {
      wave.lineTo(i.toDouble(), 52 + amp);
    }
  }
  f.drawPath(wave, stroke(rgba(120, 255, 170, 0.8), 1));

  // station ident text
  fillText(f, 'KBLK-7', const ui.Offset(_fw / 2, 26), _identStyle,
      anchor: TextAnchor.center, cache: feedText);
  fillText(f, 'NOW BROADCASTING · NIGHT ${s.night}',
      const ui.Offset(_fw / 2, 38), _subIdentStyle,
      anchor: TextAnchor.center, cache: feedText);

  // the carrier needs holding by hand until the transmitters can do it
  var owned = 0;
  for (final p in kProducers) {
    owned += s.prod[p.id] ?? 0;
  }
  if (owned < 3) {
    final pulse = 0.55 + math.sin(t * 4) * 0.45;
    fillRect(f, 28, _fh * 0.38, _fw - 56, 44, rgba(0, 0, 0, 0.55));
    f.drawRect(
        ui.Rect.fromLTWH(28.5, _fh * 0.38 + 0.5, _fw - 57, 43),
        stroke(rgba(140, 255, 200, clampD(0.35 + pulse * 0.4, 0, 1)), 1));
    fillText(
      f,
      'STRIKE THE SET TO HOLD THE CARRIER',
      ui.Offset(_fw / 2, _fh * 0.38 + 20),
      mono(13, rgba(200, 255, 225, clampD(0.6 + pulse * 0.4, 0, 1)),
          weight: FontWeight.bold),
      anchor: TextAnchor.center,
      cache: feedText,
    );
    fillText(
      f,
      s.tune.strikes < 1
          ? '>> CLICK ANYWHERE ON THIS SCREEN <<'
          : 'BUY A TRANSMITTER AND IT HOLDS ITSELF',
      ui.Offset(_fw / 2, _fh * 0.38 + 35),
      _hintStyle,
      anchor: TextAnchor.center,
      cache: feedText,
    );
  } else if (s.tune.rate > 0) {
    fillText(f, 'MANUAL HOLD  ${s.tune.rate}/s',
        ui.Offset(_fw / 2, _fh * 0.38 + 8), _manualStyle,
        anchor: TextAnchor.center, cache: feedText);
  }

  // ticker
  final tick = '  SIGNAL ${fmt(s.sig)}   THIS SEGMENT ${fmt(s.segSig)}'
      '   OUTPUT ${fmt(rate)}/s   STREAK ${s.stats.streak} ';
  final tw = measureText(tick, _tickerStyle, cache: feedText);
  final off = -((t * 34) % tw);
  fillRect(f, 0, _fh - 20, _fw, 14, rgba(0, 0, 0, 0.55));
  for (var i = 0; i < 3; i++) {
    fillText(f, tick, ui.Offset(off + i * tw, _fh - 10), _tickerStyle,
        cache: feedText);
  }

  if (s.sponsorEnd > 0) {
    fillText(f, '+ SPONSORED ×3  ${s.sponsorEnd.ceil()}s',
        const ui.Offset(_fw - 6, _fh - 40), _sponsorStyle,
        anchor: TextAnchor.right, cache: feedText);
  }
}

// ---------------------------------------------------------------------------
// renderFeed — the compositor
// ---------------------------------------------------------------------------

/// JS `renderFeed(t)`, minus its trailing `tickTube()`.
///
/// [f] must be a canvas whose origin is the top-left of the 320x240 feed.
void paintFeed(ui.Canvas f, GameState s, AnomalyRuntime a, double t) {
  f.save();
  // The HTML's feed is a real 320x240 canvas, so everything is clipped to it.
  // THE VERTICAL MAN's impossible torso and THE REPEAT's echoes both rely on it.
  f.clipRect(_feedRect);

  final act = a.active;
  final scareDef = a.scareDef;
  final ui.Image? dyingNoise = noiseTile(t, 40);
  final ActiveAnom? corpse = a.dying;
  // PAINT THE KILL. The runtime leaves a body for 0.35s; without this the
  // thing you beat is deleted between two frames and being RIGHT looks like
  // nothing happened. Done in the compositor with a scale + additive blow-out
  // so none of the eight entity painters need to know about it.
  //
  // This used to run HERE, above the act/lost/normal branch — and `act` is
  // always null while a corpse exists, so the final `else` always ran, and
  // drawFeedNormal's first operation is an opaque fillRect over the whole
  // 320x240 feed. The body was painted and erased inside the same frame:
  // baking the feed with and without a corpse produced 0 of 307200 bytes
  // differing, at every phase of the animation. Nobody has ever seen it.
  //
  // It is now a closure, called from inside the else AFTER the picture is
  // restored, so it composites over the feed instead of under it.
  void paintCorpse() {
    if (corpse == null) return;
    final k = a.dyingP;
    final e = k * k;
    f.save();
    f.translate(_fw / 2, _fh / 2);
    f.scale(1 + e * 0.28, 1 + e * 0.28);
    f.translate(-_fw / 2, -_fh / 2);
    f.saveLayer(_feedRect, ui.Paint()..color = rgba(255, 255, 255, 1 - e));
    drawAnom(f, corpse.def, t, 1);
    f.restore();
    f.restore();
    // it goes to grain and light on the way out
    if (dyingNoise != null) {
      drawImageStretch(f, dyingNoise, _feedRect, nearestPaint(alpha: 0.25 + e * 0.5));
    }
    fillRect(f, 0, 0, _fw, _fh, rgba(190, 255, 215, (1 - e) * 0.34),
        mode: ui.BlendMode.plus);
  }
  if (act != null) {
    final prog = act.t / act.window;
    drawAnom(f, act.def, t, prog);
    if (act.masked && act.stage == 0) {
      fillRect(f, 0, 0, _fw, _fh, rgba(0, 0, 0, 0.55));
      final n = noiseTile(t, 30);
      if (n != null) {
        drawImageStretch(f, n, _feedRect, nearestPaint(alpha: 0.5));
      }
      fillText(f, '## MASKED CARRIER ##', const ui.Offset(_fw / 2, _fh / 2),
          _maskedStyle,
          anchor: TextAnchor.center, cache: feedText);
      fillText(f, 'CUT TO REVEAL', const ui.Offset(_fw / 2, _fh / 2 + 16),
          _cutStyle,
          anchor: TextAnchor.center, cache: feedText);
    }
    // rising static as the window closes
    if (act.def.id != 'dead') {
      final n = noiseTile(t, 26);
      if (n != null) {
        drawImageStretch(f, n, _feedRect,
            nearestPaint(alpha: clampD(0.06 + prog * 0.20, 0, 1)));
      }
    }
  } else if (a.scare > 0 && scareDef != null) {
    // THE JUMPSCARE FRAME.
    //
    // This used to be the entity's own sprite scaled up 2x on black, which
    // reads as a logo sting: a shape, centred, briefly. A face is not a shape.
    // It is too close, it is off-centre, it is WET, and the parts of it your
    // eye hunts for — the sockets, the mouth — are the parts that are wrong.
    fillRect(f, 0, 0, _fw, _fh, const ui.Color(0xFF000000));

    final double bite = clampD(1.5 - a.scare, 0, 1.5) / 1.5; // 0 -> 1
    f.save();
    // hard push in, and never centred — a face square in frame is a portrait
    final double z = 2.4 + bite * 1.5;
    final double ox = _fw * (0.5 + (scareDef.id.hashCode % 7 - 3) * 0.022);
    f.translate(ox, _fh * 0.40);
    f.scale(z, z);
    f.translate(-ox, -_fh * 0.40);
    drawAnom(f, scareDef, t, 1);
    f.restore();

    // --- the sockets ---
    // Two holes with nothing behind them, torn rather than drawn, sitting
    // where the eye is already looking for eyes.
    final double eyeY = _fh * 0.34;
    for (var s = -1; s <= 1; s += 2) {
      final double ex = ox + s * _fw * 0.13;
      final ui.Paint hole = ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(ex, eyeY),
          _fw * 0.085 * (1 + bite * 0.35),
          <ui.Color>[
            const ui.Color(0xFF000000),
            const ui.Color(0xFF000000),
            rgba(70, 6, 8, 0.75),
            rgba(70, 6, 8, 0),
          ],
          <double>[0, 0.42, 0.72, 1],
        );
      f.drawRect(_feedRect, hole);
      // the wet line under it
      f.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset(ex, eyeY + _fh * 0.055 + bite * 8),
          width: _fw * 0.020,
          height: _fh * 0.10 + bite * 26,
        ),
        fill(rgba(120, 12, 16, 0.55 + bite * 0.35)),
      );
    }

    // --- the mouth ---
    // Open far too wide, and the wrong shape for a scream.
    final double mw = _fw * (0.10 + bite * 0.16);
    final double mh = _fh * (0.05 + bite * 0.22);
    final ui.Rect mouth = ui.Rect.fromCenter(
        center: ui.Offset(ox, _fh * 0.62), width: mw, height: mh);
    f.drawOval(mouth, fill(const ui.Color(0xFF070203)));
    f.drawOval(mouth, stroke(rgba(110, 10, 14, 0.9), 2));
    // teeth, uneven, not all present
    final int teeth = 7;
    for (var i = 0; i < teeth; i++) {
      if ((scareDef.id.hashCode >> i) & 1 == 0) continue;
      final double tx = mouth.left + mouth.width * ((i + 0.5) / teeth);
      final double th = mouth.height * (0.20 + ((i * 37) % 11) / 11 * 0.24);
      fillRect(f, tx - mouth.width * 0.035, mouth.top, mouth.width * 0.07, th,
          rgba(196, 184, 158, 0.82));
      fillRect(f, tx - mouth.width * 0.035, mouth.bottom - th * 0.8,
          mouth.width * 0.07, th * 0.8, rgba(178, 166, 140, 0.7));
    }

    // --- and it is on the lens ---
    // The last thing between the player and it is a pane with something wet
    // on the near side.
    for (var i = 0; i < 5; i++) {
      final double sx = _fw * (0.12 + ((i * 53) % 79) / 79 * 0.78);
      final double sy = _fh * (0.10 + ((i * 31) % 67) / 67 * 0.72);
      final double sr = 3.0 + ((i * 17) % 13) / 13 * 9 * (0.4 + bite);
      f.drawOval(
        ui.Rect.fromCenter(center: ui.Offset(sx, sy), width: sr * 2, height: sr * 2.3),
        fill(rgba(126, 10, 14, 0.62)),
      );
      fillRect(f, sx - sr * 0.22, sy, sr * 0.44, sr * (2 + bite * 7),
          rgba(96, 8, 12, 0.5));
    }
    final n = noiseTile(t, 40);
    if (n != null) {
      drawImageStretch(f, n, _feedRect, nearestPaint(alpha: 0.42));
    }
    fillRectShader(
      f,
      0,
      0,
      _fw,
      _fh,
      radialR0(const ui.Offset(_fw / 2, _fh / 2), 40, 190,
          <ui.Color>[rgba(255, 255, 255, 1), rgba(255, 60, 50, 1)],
          <double>[0, 1]),
      mode: ui.BlendMode.multiply,
    );
    if (a.scare > 1.28) {
      fillRect(f, 0, 0, _fw, _fh,
          rgba(255, 255, 255, clampD((a.scare - 1.28) * 4, 0, 1)));
    }
  } else if (a.lost) {
    fillRect(f, 0, 0, _fw, _fh, const ui.Color(0xFF000000));
    final n = noiseTile(t, 40);
    if (n != null) {
      drawImageStretch(f, n, _feedRect, nearestPaint(alpha: 0.9));
    }
  } else {
    drawFeedNormal(f, s, a, t);
    // the body, over the restored picture rather than under an opaque fill
    if (act == null) paintCorpse();
    // AFTERIMAGE beat — the thing is gone and its face is still burned into
    // the phosphor. Drawn over the restored picture, decaying with a.burn.
    final Anom? ghost = a.afterimageDef;
    final double burn = a.burn;
    if (ghost != null && burn > 0.004) {
      f.saveLayer(const ui.Rect.fromLTWH(0, 0, 320, 240),
          ui.Paint()..color = rgba(255, 255, 255, burn * 0.42));
      drawAnom(f, ghost, t, 1);
      f.restore();
    }
    if (a.warn > 0) {
      final n = noiseTile(t, 30);
      if (n != null) {
        drawImageStretch(f, n, _feedRect,
            nearestPaint(alpha: clampD(0.10 + math.sin(t * 30) * 0.06, 0, 1)));
      }
      if (math.sin(t * 24) > 0.4) {
        fillRect(f, 0, rr(0, _fh), _fw, rr(2, 14), rgba(255, 255, 255, 0.10));
      }
    }
    if (a.banishFx > 0) {
      fillRect(f, 0, 0, _fw, _fh,
          rgba(140, 255, 190, clampD(a.banishFx * 0.35, 0, 1)));
    }
  }

  f.restore();
  trimFeedText();
}

// ---------------------------------------------------------------------------
// The offscreen itself
// ---------------------------------------------------------------------------

/// The JS `feed` canvas: a live 320x240 raster the tube pass samples.
///
/// Call [render] exactly once per frame, then hand [image] to the tube painter
/// (blitTube / chanCopy / the persistence and bloom buffers). The previous
/// frame's image is disposed for you.
class FeedRenderer {
  ui.Image? _img;

  /// The most recent feed frame, or null before the first [render].
  ui.Image? get image => _img;

  /// Bakes one 320x240 frame.
  void render(GameState s, AnomalyRuntime a, double t) {
    final next = bakeImageSync(kFeedW, kFeedH, (c) => paintFeed(c, s, a, t));
    _img?.dispose();
    _img = next;
  }

  void dispose() {
    _img?.dispose();
    _img = null;
  }
}
