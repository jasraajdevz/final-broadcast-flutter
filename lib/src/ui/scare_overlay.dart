// FINAL BROADCAST — THE SCARE, AT FULL SIZE.
//
// "NOT SCARY ITS JUST NOT."
//
// Baked the composed frame and looked at it, which I should have done ten
// changes ago. The booth is 1280x720. The tube is kScr — 422x278 — which is
// 12.7% of it, and the entity art is drawn into a 320x240 buffer inside THAT.
//
// So every frightening thing this game has ever done has happened inside a
// postage stamp in the middle of a tidy, well-composed control room, while the
// other 87% of the screen stayed calm, lit, and full of dials. No amount of
// audio design or dread plumbing survives that. The monster was furniture.
//
// This is the scare taking the whole screen. The room goes. The rack goes. The
// keys go. There is nothing to look at except the thing, at 1280x720, for as
// long as it wants — and then the room comes back and you have to carry on.
//
// It draws ABOVE everything in the cabinet stack, including the rack widget,
// because a jumpscare that a UI panel is painted on top of is not a jumpscare.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../bake.dart';
import '../consts.dart';
import '../paint/entities.dart';

class ScareOverlay extends StatelessWidget {
  const ScareOverlay({super.key, required this.runtime});

  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(kCabW, kCabH),
          painter: _ScarePainter(runtime),
        ),
      ),
    );
  }
}

class _ScarePainter extends CustomPainter {
  _ScarePainter(this.r) : super(repaint: r);

  final AnomalyRuntime r;

  @override
  void paint(ui.Canvas g, ui.Size size) {
    final Anom? def = r.scareDef;
    if (r.scare <= 0 || def == null) return;

    // 1 at the instant of the hit, falling to 0 as it lets go
    final double k = (r.scare / 1.5).clamp(0.0, 1.0);
    final double bite = 1 - k;

    g.save();

    // THE ROOM IS GONE. Not dimmed — gone. Anything still visible around the
    // edge gives the eye somewhere safe to rest, and there is not supposed to
    // be anywhere safe to rest.
    fillRect(g, 0, 0, kCabW, kCabH, rgba(0, 0, 0, math.min(1.0, 0.86 + k * 0.14)));

    // violent, and it does not settle
    final double sh = 26 * k;
    g.translate(rr(-sh, sh), rr(-sh, sh));

    // THE THING, at the size of the whole cabinet. The entity painters draw
    // into a 320x240 space, so this is a 4x blow-up — deliberately past the
    // point where the art holds together, because a face that resolves
    // cleanly is a picture and a face that does not is a problem.
    final double z = (kCabH / 240) * (1.55 + bite * 0.55);
    g.save();
    final double cx = kCabW / 2 + math.sin(r.tGlobal * 41) * 5 * k;
    final double cy = kCabH * 0.46;
    g.translate(cx, cy);
    g.scale(z, z);
    g.translate(-160, -120); // centre the 320x240 entity space
    // chromatic tear — three passes, offset, so nothing has one edge
    for (var i = 0; i < 3; i++) {
      final double dx = (i - 1) * 5.5 * (0.4 + k);
      g.save();
      g.translate(dx, 0);
      g.saveLayer(
        const ui.Rect.fromLTWH(-200, -200, 720, 640),
        ui.Paint()
          ..blendMode = ui.BlendMode.plus
          // Tuned by baking the frame twice. At 0.92 white it bleached to a
          // daylight photograph; at 0.62 with a heavy vignette and full grain
          // the face vanished into noise entirely. The face has to be the
          // clearest thing in the frame — everything else is seasoning.
          ..color = i == 1
              ? rgba(255, 244, 238, 0.88)
              : (i == 0 ? rgba(255, 30, 30, 0.34) : rgba(30, 150, 235, 0.28)),
      );
      drawAnom(g, def, r.tGlobal, 1);
      g.restore();
      g.restore();
    }
    g.restore();

    // THE SOCKETS. Full-cabinet scale, sitting where the eye hunts for eyes.
    final double eyeY = kCabH * 0.36;
    for (var s = -1; s <= 1; s += 2) {
      final double ex = cx + s * kCabW * 0.135;
      g.drawRect(
        const ui.Rect.fromLTWH(0, 0, kCabW, kCabH),
        ui.Paint()
          ..shader = ui.Gradient.radial(
            ui.Offset(ex, eyeY),
            kCabW * 0.085 * (1 + bite * 0.30),
            <ui.Color>[
              const ui.Color(0xFF000000),
              const ui.Color(0xFF000000),
              rgba(90, 6, 8, 0.8),
              rgba(90, 6, 8, 0),
            ],
            <double>[0, 0.44, 0.74, 1],
          ),
      );
      // what has run out of it
      fillRect(g, ex - kCabW * 0.010, eyeY, kCabW * 0.020,
          kCabH * 0.10 + bite * 190, rgba(104, 8, 12, 0.62));
    }

    // No drawn mouth. The entity art already has a face at this scale, and a
    // second small oval on top of it read as a sticker. The sockets are the
    // only feature worth forcing, because they are the thing the eye hunts
    // for and the thing that is wrong.

    // and it is on the lens between you and it
    for (var i = 0; i < 7; i++) {
      final double sx = kCabW * (0.10 + ((i * 53) % 79) / 79 * 0.80);
      final double sy = kCabH * (0.08 + ((i * 31) % 67) / 67 * 0.76);
      final double sr = 5.0 + ((i * 17) % 13) / 13 * 16 * (0.4 + bite);
      g.drawOval(
        ui.Rect.fromCenter(
            center: ui.Offset(sx, sy), width: sr * 2, height: sr * 2.4),
        fill(rgba(120, 9, 13, 0.6)),
      );
      fillRect(g, sx - sr * 0.20, sy, sr * 0.40, sr * (2 + bite * 9),
          rgba(92, 7, 11, 0.5));
    }

    // CRUSH IT. A scare that is brighter than the room reads as a light being
    // switched on. This is the opposite of that: everything but the middle of
    // the face goes to black, so there is one thing in the frame and it is
    // looking at you.
    g.drawRect(
      const ui.Rect.fromLTWH(0, 0, kCabW, kCabH),
      ui.Paint()
        ..blendMode = ui.BlendMode.multiply
        ..shader = ui.Gradient.radial(
          ui.Offset(cx, cy),
          kCabW * 0.52,
          <ui.Color>[
            rgba(255, 240, 238, 1), // the face itself is untouched
            rgba(150, 120, 118, 1),
            rgba(4, 0, 0, 1),
          ],
          <double>[0, 0.58, 1.0],
        ),
    );

    // the frame tears
    final ui.Image? n = noiseTile(r.tGlobal, 60);
    if (n != null) {
      drawImageStretch(g, n, const ui.Rect.fromLTWH(0, 0, kCabW, kCabH),
          // rises as it DECAYS. Full grain on the hit buried the face at the
          // exact frame it needed to be legible.
          nearestPaint(alpha: 0.06 + (1 - k) * 0.26));
    }
    for (var i = 0; i < 5; i++) {
      final double y = rr(0, kCabH);
      fillRect(g, 0, y, kCabW, rr(2, 22) * k,
          rgba(255, 255, 255, 0.05 + k * 0.10));
    }

    g.restore();
  }

  @override
  bool shouldRepaint(covariant _ScarePainter old) => true;
}

/// Test-only hook so the frame can be baked and LOOKED AT without fighting
/// the widget tester's screenshot path. This exists because the whole reason
/// the scare was 12.7% of the screen for so long is that nobody ever rendered
/// it and looked.
class ScareOverlayPainterProbe {
  static void paint(ui.Canvas g, AnomalyRuntime r) =>
      _ScarePainter(r).paint(g, const ui.Size(kCabW, kCabH));
}
