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
    mono(15, rgba(204, 229, 255, 0.92), weight: FontWeight.bold);
final TextStyle _subIdentStyle = mono(8, rgba(176, 198, 220, 0.7));
final TextStyle _tickerStyle = mono(9, rgba(204, 229, 255, 0.85));
final TextStyle _sponsorStyle =
    mono(9, rgba(255, 179, 71, 0.9), weight: FontWeight.bold);
final TextStyle _maskedStyle =
    mono(12, rgba(255, 255, 255, 0.75), weight: FontWeight.bold);
final TextStyle _cutStyle = mono(9, rgba(255, 180, 180, 0.8));

// ---------------------------------------------------------------------------
// drawFeedNormal — what KBLK-7 is putting out when nothing is wrong
// ---------------------------------------------------------------------------

/// JS `drawFeedNormal(t)`. [f] is the 320x240 feed canvas.
// ---------------------------------------------------------------------------
// WHAT KBLK-7 IS PUTTING OUT
//
// This is the picture the player looks at for ninety percent of a night, and
// it was PRETTY: a soft green horizon glow, rolling hills, a transmitter mast
// panning gently across, a beacon blinking on a sine. A calm nighttime
// landscape with a nice waveform over it — a screensaver.
//
// It is the same failure the audio had. The most-looked-at thing in a horror
// game was soothing, and no amount of jumpscare fixes that, because the
// jumpscare is two seconds and this is eight minutes.
//
// The replacement is not louder or gorier. It is a picture that is quietly
// WRONG, and gets more wrong the longer the night runs:
//
//   THE MAST does not pan. It stands still, because a thing that drifts is
//   scenery and a thing that stands still is a landmark you keep checking.
//
//   SOMETHING IS ON IT. The archive says there are handholds worn into the
//   ladder above the two hundred foot mark, on the inside face, where nobody
//   climbing would put their hands. It is on the mast, it is a little higher
//   every time an anomaly is dealt with, and it is NEVER seen moving.
//
//   THE TOWN GOES OUT. A row of lit windows on the horizon. One goes dark
//   every couple of minutes and never comes back on. By 06:00 the field is
//   black, and nothing in the game ever mentions it.
//
//   THE WAVEFORM LIES. Almost always an honest trace of your output. Rarely,
//   for about a second, it resolves into the profile of a face and then goes
//   back to being a waveform.
// ---------------------------------------------------------------------------

/// Windows still lit on the horizon, 12 down to 0 across a night.
int _townLit(GameState s) {
  final double p = (s.shiftMin / kShiftMinutes).clamp(0.0, 1.0);
  return (12 * (1 - p)).round();
}

/// How far up the mast it has got, 0..1. Driven by how much of the night has
/// been survived rather than by time, so it is progress and not a clock.
double _climb(GameState s) =>
    ((s.stats.banished + s.stats.scared) / 26.0).clamp(0.0, 0.92);

void drawFeedNormal(ui.Canvas f, GameState s, AnomalyRuntime a, double t) {
  fillRect(f, 0, 0, _fw, _fh, const ui.Color(0xFF0A0F13));

  // A low, dirty glow on the horizon — sodium lamps in a town that is going
  // out, not a sunrise. Sits under the treeline so it silhouettes rather than
  // illuminates.
  fillRectShader(
    f,
    0,
    0,
    _fw,
    _fh,
    radialR0(const ui.Offset(_fw / 2, _fh * 0.72), 8, 150,
        <ui.Color>[rgba(56, 63, 70, 0.42), rgba(6, 8, 11, 0)], <double>[0, 1]),
  );

  // --- the sky ---
  // A cold band above the horizon so the treeline has something to be a
  // silhouette against. Without it the top of frame is flat black and the
  // whole picture reads as two stripes.
  fillRectShader(
    f,
    0,
    60,
    _fw,
    120,
    linear(const ui.Offset(0, 60), const ui.Offset(0, 180),
        <ui.Color>[rgba(15, 21, 28, 0), rgba(35, 39, 44, 0.55)],
        <double>[0, 1]),
  );

  // stars, and some of them are not there any more. Deterministic per index so
  // the sky is the same sky all night rather than a snowstorm.
  for (var i = 0; i < 46; i++) {
    final double sx = ((i * 79) % 311).toDouble();
    final double sy = 62 + ((i * 53) % 96).toDouble();
    // the ones low in the sky go out with the town
    final bool out = sy > 140 && i % 3 == 0 && _townLit(s) < 7;
    if (out) continue;
    final double tw = 0.30 + math.sin(t * (0.7 + i % 5 * 0.3) + i) * 0.18;
    fillRect(f, sx, sy, 1, 1, rgba(204, 229, 255, tw * 0.5));
  }

  // --- a second transmitter, much further out ---
  // Depth, and a second beacon that is NOT in sync with ours — two lights
  // blinking at different rates is unsettling in a way one never is.
  const double fx = _fw * 0.17;
  f.drawPath(
    ui.Path()
      ..moveTo(fx, 150)
      ..lineTo(fx - 4, 178)
      ..moveTo(fx, 150)
      ..lineTo(fx + 4, 178),
    stroke(rgba(96, 108, 120, 0.28), 1),
  );
  final fb = math.sin(t * 1.13 + 2.1) * 0.5 + 0.5;
  fillRect(f, fx - 1, 148, 2, 2, rgba(255, 70, 45, 0.18 + fb * 0.42));

  // --- the treeline ---
  final ridge = ui.Path()
    ..moveTo(0, _fh)
    ..lineTo(0, 172);
  for (var i = 0.0; i <= _fw; i += 8) {
    // static, not scrolling — a horizon that moves is a vehicle window
    final h = 172 +
        math.sin(i * 0.052) * 6 +
        math.sin(i * 0.011) * 11 +
        (math.sin(i * 0.31).abs() > 0.86 ? -7 : 0); // the odd taller tree
    ridge.lineTo(i, h);
  }
  ridge.lineTo(_fw, _fh);
  ridge.close();
  f.drawPath(ridge, fill(const ui.Color(0xFF121417)));

  // --- the town, going out ---
  final lit = _townLit(s);
  for (var i = 0; i < 12; i++) {
    if (i >= lit) continue;
    final double wx = 18 + i * 24.0 + (i.isEven ? 3 : 0);
    final double wy = 176 + (i % 3) * 4.0;
    // the last few flicker
    final double fl = i >= lit - 2 ? (0.45 + math.sin(t * 9 + i) * 0.4) : 1.0;
    fillRect(f, wx, wy, 2, 2, rgba(255, 190, 90, 0.55 * fl));
  }

  // --- the mast, standing still ---
  const double px = _fw * 0.72;
  final mast = ui.Path()
    ..moveTo(px, 96)
    ..lineTo(px - 11, 178)
    ..moveTo(px, 96)
    ..lineTo(px + 11, 178);
  for (var y = 104.0; y < 178; y += 13) {
    final sp = (y - 96) / 82 * 11;
    mast.moveTo(px - sp, y);
    mast.lineTo(px + sp, y);
  }
  f.drawPath(mast, stroke(rgba(136, 153, 170, 0.42), 1));

  // the beacon, on a slow irregular period rather than a clean sine
  final bl = (math.sin(t * 1.7) * 0.5 + 0.5) * (math.sin(t * 0.41) * 0.3 + 0.7);
  fillRect(f, px - 1.5, 93, 3, 3,
      rgba(255, 60, 40, clampD(0.25 + bl * 0.7, 0, 1)));

  // --- and something on the ladder ---
  // Never drawn mid-move. Its height is a pure function of the night's
  // progress, so between two glances it has simply changed.
  final double cl = _climb(s);
  if (cl > 0.02) {
    final double cy = 176 - cl * 78;
    final double sp = (cy - 96) / 82 * 11;

    // The sky up there is near-black and so is the figure, so drawn plainly it
    // was invisible — measured off a baked frame, not guessed. The camera's
    // gain is riding up on an empty picture, so the air immediately around it
    // lifts, and the shape falls out of the lift.
    f.drawCircle(
      ui.Offset(px, cy - 2),
      14,
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(px, cy - 2),
          14,
          <ui.Color>[rgba(156, 176, 196, 0.20), rgba(156, 176, 196, 0)],
        ),
    );

    const ui.Color k = ui.Color(0xF0000000);
    fillRect(f, px - 2.6, cy - 6.0, 5.2, 7.6, k); // torso
    fillRect(f, px - 1.4, cy - 8.6, 2.8, 2.7, k); // head
    fillRect(f, px - 2.3, cy + 1.4, 1.8, 4.2, k); // legs, on a rung
    fillRect(f, px + 0.5, cy + 1.4, 1.8, 4.2, k);
    // and it has thrown a hand out past the frame of the tower
    fillRect(f, px + sp * 0.55, cy - 4.0, 3.4, 1.5, rgba(0, 0, 0, 0.85));

    // Near the top it is inside the beacon's throw, and takes the red on one
    // side every time the lamp comes round.
    if (cl > 0.60) {
      fillRect(f, px - 2.9, cy - 8.6, 1.1, 10.2,
          rgba(255, 70, 45, clampD(0.08 + bl * 0.26, 0, 1)));
    }
  }

  // --- fog in the field ---
  // Sits between the treeline and the camera, so the town and the far mast are
  // behind something. One band, drifting very slowly.
  fillRectShader(
    f,
    0,
    _fh * 0.70,
    _fw,
    38,
    linear(ui.Offset(0, _fh * 0.70), ui.Offset(0, _fh * 0.70 + 38),
        <ui.Color>[
          rgba(160, 180, 200, 0),
          rgba(160, 180, 200, 0.055 + math.sin(t * 0.13) * 0.02),
          rgba(160, 180, 200, 0),
        ],
        <double>[0, 0.5, 1]),
  );

  // --- the feeder line ---
  // A cable running from the mast off the left of frame, sagging. Period
  // correct, and it gives the empty middle of the picture something to cross.
  final wire = ui.Path()..moveTo(px, 108);
  for (var i = 0.0; i <= 1.0; i += 0.05) {
    final double wx = px - i * (px + 10);
    // catenary sag, plus a very slight sway
    final double sag = math.sin(i * math.pi) * 26 +
        math.sin(t * 0.6 + i * 3) * 1.2;
    wire.lineTo(wx, 108 + sag);
  }
  f.drawPath(wire, stroke(rgba(88, 99, 110, 0.5), 1));
  // and a bird on it that has not moved all night.
  //
  // Three pixels square read as a domino. It gets a head and a tail so that
  // at native CRT scale the shape is a bird and not a speck of dirt on the
  // lens — which is the whole point of it, since a bird that never once
  // shifts its weight is only unsettling if you can tell it is a bird.
  final double by = 108 + math.sin(0.42 * math.pi) * 26 - 3;
  const ui.Color bk = ui.Color(0xE6000000);
  fillRect(f, px - 74, by, 3, 2.6, bk); // body
  fillRect(f, px - 74.6, by - 1.4, 1.6, 1.6, bk); // head, turned this way
  fillRect(f, px - 71.4, by + 0.2, 2.2, 1, bk); // tail

  // --- weather ---
  // Snow, matching the window. Falls on a fixed lattice so it costs almost
  // nothing and never strobes.
  for (var i = 0; i < 34; i++) {
    final double sp = 9 + (i % 5) * 4.0;
    final double sx = ((i * 67) % 317).toDouble() +
        math.sin(t * 0.4 + i) * 3;
    final double sy = ((i * 41) + t * sp) % 240;
    fillRect(f, sx, sy, 1, 1, rgba(204, 229, 255, 0.10 + (i % 5) * 0.035));
  }

  // --- the waveform ---
  final rate = sigRate(s, a);
  // Rarely, and briefly, it is not a waveform. Driven off a slow clock so it
  // cannot be triggered or predicted, and short enough to be deniable.
  final double faceWin = math.sin(t * 0.083);
  final bool profile = faceWin > 0.9945;
  final wave = ui.Path();
  for (var i = 0; i < _fw; i++) {
    final double x = i / _fw;
    double amp;
    if (profile) {
      // a brow, an eye socket, a nose, lips, a chin — read as a trace
      amp = -18 * math.exp(-math.pow((x - 0.30) / 0.055, 2)) +
          9 * math.exp(-math.pow((x - 0.38) / 0.030, 2)) -
          21 * math.exp(-math.pow((x - 0.47) / 0.028, 2)) +
          6 * math.exp(-math.pow((x - 0.55) / 0.025, 2)) -
          11 * math.exp(-math.pow((x - 0.63) / 0.045, 2)) +
          math.sin(i * 0.7) * 0.8;
    } else {
      amp = math.sin(i * 0.09 + t * 4) * 10 +
          math.sin(i * 0.31 + t * 7) * 4 * math.min(1.0, rate / 50 + 0.2);
    }
    if (i == 0) {
      wave.moveTo(i.toDouble(), 52 + amp);
    } else {
      wave.lineTo(i.toDouble(), 52 + amp);
    }
  }
  f.drawPath(wave, stroke(rgba(204, 229, 255, profile ? 0.95 : 0.8), 1));

  // station ident text
  fillText(f, 'KBLK-7', const ui.Offset(_fw / 2, 26), _identStyle,
      anchor: TextAnchor.center, cache: feedText);
  fillText(f, 'NOW BROADCASTING · NIGHT ${s.night}',
      const ui.Offset(_fw / 2, 38), _subIdentStyle,
      anchor: TextAnchor.center, cache: feedText);

  // NO TUTORIAL BOX.
  //
  // There were THREE of these running at once, all saying the same sentence,
  // all on top of the picture: this panel, the directive marquee across the
  // top, and a toast. The whole session was spent cutting the game's habit of
  // talking over the player and then three overlapping tutorials went in that
  // covered the one thing they are supposed to be looking at.
  //
  // The directive strip already names whichever needle is off its mark, in
  // words, permanently, in the place the player's eye goes. That is enough.

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
    // dyingBurn, not dyingP: in NIGHTMARE the corpse DWELLS — it lies on the
    // tube whole and only burns out in its last 0.35s. dyingP across a 2.4s
    // window would stretch the blow-out into slow motion.
    final k = a.dyingBurn;
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
    fillRect(f, 0, 0, _fw, _fh, rgba(204, 229, 255, (1 - e) * 0.34),
        mode: ui.BlendMode.plus);
  }
  if (act != null) {
    final prog = act.t / act.window;
    drawAnom(f, act.def, t, prog);
    // THE MILKMAN. Not a ninth thing in the signal — he wears one of the eight
    // and dies to its key. What he does is take the picture away: milk climbs
    // the inside of the glass from the moment he lands and keeps climbing, so
    // the tell is readable for about a second and a half and then it is not.
    //
    // Drawn AFTER the entity and BEFORE everything else that reads the tube,
    // because the whole point is that it occludes the thing the player is
    // trying to identify. It never quite reaches the top: an answer has to
    // stay possible for someone who kept their nerve.
    if (act.milk) {
      final double climb = clampD(act.t / 1.6, 0, 1);
      final double top = _fh * (1 - 0.86 * climb);
      // the body of it, with a curdled edge rather than a clean waterline
      fillRect(f, 0, top + 4, _fw, _fh - top, rgba(238, 240, 232, 0.93));
      for (var i = 0.0; i < _fw; i += 4) {
        final double lip = math.sin(i * 0.21 + t * 1.7) * 2.2 +
            math.sin(i * 0.07 - t * 0.9) * 2.6;
        fillRect(f, i, top + lip, 4, 6, rgba(238, 240, 232, 0.93));
      }
      // and it runs down the glass from where it first hit
      for (var i = 0; i < 7; i++) {
        final double rx = ((i * 71) % 311) / 311 * _fw;
        final double rl = 10 + ((i * 53) % 37).toDouble() * climb;
        fillRect(f, rx, top - rl, 2.5, rl, rgba(238, 240, 232, 0.55));
      }
      // I DID NOT / BRING THIS
      //
      // The words have to do the work here, because clean white fluid climbing
      // a screen has an obvious reading and it is not dread. Two earlier goes
      // failed in different directions: SORRY I MISSED YOU was a note about a
      // doorstep, mundane in the wrong way, and TWO PINTS LIKE ALWAYS was a
      // joke about the size of the household.
      //
      // This is the delivery man disclaiming the delivery. He came, he wrote
      // on the inside of the glass, and the first thing he wanted the operator
      // to know is that whatever is filling the tube is not his and he did not
      // put it there.
      //
      // Which makes him a witness rather than the source, leaves the stuff on
      // the screen unexplained, and means something else got here first.
      //
      // Nothing anywhere else in the game mentions it.
      //
      // Written IN the milk rather than on it — drawn in the gap it leaves, so
      // the strokes are the picture showing through where a finger has been.
      // That is why they DARKEN as the milk deepens instead of brightening,
      // which is the whole difference between a word on the glass and a word
      // in the milk. Two lines, because it is a note and not a sign.
      if (climb > 0.34) {
        final double ink = clampD((climb - 0.34) / 0.5, 0, 1);
        final TextStyle hand = mono(15, rgba(96, 104, 96, 0.30 + ink * 0.55),
            weight: FontWeight.bold);
        final double mid = top + (_fh - top) * 0.40;
        fillText(f, 'I DID NOT', ui.Offset(_fw / 2, mid), hand,
            anchor: TextAnchor.center, cache: feedText);
        fillText(f, 'BRING THIS', ui.Offset(_fw / 2, mid + 17), hand,
            anchor: TextAnchor.center, cache: feedText);
      }
    }
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
          rgba(204, 229, 255, clampD(a.banishFx * 0.35, 0, 1)));
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
