// FINAL BROADCAST — the seam between the widget shell and the painted booth.
//
// The booth itself (WALLTEX, the feed, the face plates, the field, the
// lurkers) is a separate, much larger piece of work and lives outside this
// file. main.dart never names it directly: it calls [buildScene], which hands
// off to [gSceneBuilder] if something has registered one and otherwise draws
// the stand-in below.
//
// TO WIRE THE REAL BOOTH IN, one line in main() before runApp():
//
//     gSceneBuilder = (s, runtime) => BoothScene(s: s, runtime: runtime);
//     gAnomPreview  = drawAnom;          // for the manual's 320x240 plate
//
// Nothing else in the shell has to change. The scene widget is laid out in
// 1280x720 cabinet coordinates and should repaint off `runtime` (it notifies
// every frame) reading `runtime.tGlobal` as its clock.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../bake.dart';
import '../consts.dart';
import '../state.dart';

/// Builds the painted booth. Registered by whoever owns the scene.
typedef SceneBuilder = Widget Function(GameState s, AnomalyRuntime runtime);

/// The manual's per-entity preview — the JS `drawAnom(g, def, t, prog)`,
/// drawing into a 320x240 canvas.
typedef AnomPreviewPainter = void Function(
    ui.Canvas canvas, Anom def, double t, double prog);

SceneBuilder? gSceneBuilder;
AnomPreviewPainter? gAnomPreview;

/// The scene layer, or the stand-in if none is registered.
Widget buildScene(GameState s, AnomalyRuntime runtime) {
  final b = gSceneBuilder;
  if (b != null) return b(s, runtime);
  return PlaceholderScene(s: s, runtime: runtime);
}

/// A deliberately plain stand-in: the room rectangles at their real
/// coordinates so the widget chrome can be laid out, checked and played
/// against something, plus the strike feedback so the tube is obviously live.
class PlaceholderScene extends StatelessWidget {
  const PlaceholderScene({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PlaceholderPainter(s: s, runtime: runtime),
        size: const Size(kCabW, kCabH),
      );
}

class _PlaceholderPainter extends CustomPainter {
  _PlaceholderPainter({required this.s, required this.runtime})
      : super(repaint: runtime);

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final t = runtime.tGlobal;

    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height),
        fill(const ui.Color(0xFF05070A)));

    // back wall
    canvas.drawRect(
      kWall,
      ui.Paint()
        ..shader = radialR0(
          ui.Offset(kWall.center.dx, kWall.top + kWall.height * 0.35),
          10,
          kWall.width * 0.8,
          <ui.Color>[const ui.Color(0xFF141A1B), const ui.Color(0xFF080B0C)],
          <double>[0, 1],
        ),
    );

    // the window onto the field
    canvas.drawRect(kWin, fill(const ui.Color(0xFF0A1116)));
    canvas.drawRect(kWin, stroke(const ui.Color(0xFF1A2426), 2));

    // security monitors
    for (final p in kSide) {
      final r = ui.Rect.fromLTWH(p.dx, p.dy, kSideW, kSideH);
      canvas.drawRect(r, fill(const ui.Color(0xFF0C1011)));
      canvas.drawRect(r.deflate(4), fill(const ui.Color(0xFF07100B)));
      canvas.drawRect(r, stroke(const ui.Color(0xFF1B2426), 2));
    }

    // the tube
    canvas.drawRRect(
        ui.RRect.fromRectXY(kCrt, 14, 14), fill(const ui.Color(0xFF15191A)));
    canvas.drawRRect(ui.RRect.fromRectXY(kCrt, 14, 14),
        stroke(const ui.Color(0xFF262E30), 2));
    final flicker = 0.06 + 0.02 * math.sin(t * 7.3);
    canvas.drawRRect(
        ui.RRect.fromRectXY(kScr, 10, 10), fill(const ui.Color(0xFF04120A)));
    canvas.drawRRect(
      ui.RRect.fromRectXY(kScr, 10, 10),
      ui.Paint()
        ..shader = radialR0(
          kScr.center,
          8,
          kScr.width * 0.62,
          <ui.Color>[
            K.green.withValues(alpha: flicker * 2.2),
            const ui.Color(0x00000000),
          ],
          <double>[0, 1],
        ),
    );
    // scanlines
    final line = fill(const ui.Color(0x33000000));
    for (double y = kScr.top; y < kScr.bottom; y += 3) {
      canvas.drawRect(ui.Rect.fromLTWH(kScr.left, y, kScr.width, 1), line);
    }

    fillText(
      canvas,
      'NO SCENE PAINTER REGISTERED',
      ui.Offset(kScr.center.dx, kScr.center.dy - 8),
      mono(15, K.greenDim, letterSpacing: 2),
      anchor: TextAnchor.center,
    );
    fillText(
      canvas,
      runtime.signedOn ? 'HOLD IT INSIDE THE LIMITS' : 'KBLK-7',
      ui.Offset(kScr.center.dx, kScr.center.dy + 16),
      mono(12, K.greenDim, letterSpacing: 3),
      anchor: TextAnchor.center,
    );

    // desk
    canvas.drawRect(
        const ui.Rect.fromLTWH(0, 568, 940, 152), fill(const ui.Color(0xFF0B0E0F)));
    canvas.drawRect(const ui.Rect.fromLTWH(0, 568, 940, 2),
        fill(const ui.Color(0xFF1B2426)));

    // strike feedback — TUNE lives in GameState, so it works even here
    for (final r in s.tune.ripples) {
      final p = r.t / 0.55;
      canvas.drawCircle(
        ui.Offset(r.x, r.y),
        6 + p * 46,
        stroke(K.green.withValues(alpha: (1 - p) * 0.5), 2),
      );
    }
    for (final pop in s.tune.pops) {
      final p = pop.t / 0.9;
      fillText(
        canvas,
        pop.v,
        ui.Offset(pop.x, pop.y - p * 34),
        mono(14, K.green.withValues(alpha: 1 - p), letterSpacing: 1),
        anchor: TextAnchor.center,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaceholderPainter oldDelegate) => true;
}
