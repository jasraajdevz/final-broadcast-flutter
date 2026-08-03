// FINAL BROADCAST — the composed booth.
//
// This is the seam the port left open: room.dart, window.dart, tube.dart,
// feed.dart and entities.dart each own a surface, and somebody has to draw them
// in the right order every frame. That order is load-bearing and matches the
// HTML exactly:
//
//   1. bake the 320x240 feed          (renderFeed)
//   2. tickTube(feed)                 (was renderFeed's last line — advances the
//                                      P22 persistence and bloom buffers that
//                                      paintTube/glassPass consume THIS frame)
//   3. shake + clip to the room
//   4. room -> window -> small monitors -> CRT -> desk
//   5. dread tint, jumpscare flash, grain, vignette
//
// Getting 2 out of order is silent: the tube still draws, it just has no
// persistence, so nothing smears and the picture looks like a pasted texture.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../bake.dart';
import '../consts.dart';
import '../state.dart';
import 'blood.dart';
import 'entities.dart';
import 'feed.dart';
import 'room.dart';
import 'tube.dart';
import 'window.dart';

/// Owns the per-frame buffers and the draw order for the whole cabinet.
class Booth {
  Booth(this.runtime) : room = RoomScene(runtime);

  final AnomalyRuntime runtime;
  final RoomScene room;
  final FeedRenderer feed = FeedRenderer();

  GameState get s => runtime.s;

  bool _ready = false;
  bool get ready => _ready;

  /// Bakes everything static. Safe to draw before this resolves — every
  /// surface degrades to "skip me" rather than throwing.
  Future<void> init() async {
    await initEntities();
    // entities.dart already baked the shared noise tiles; hand them to the room
    // rather than letting it bake a second set.
    await room.initRoom(noiseTiles: noiseTiles.isEmpty ? null : noiseTiles);
    await windowScene.init();
    await initTube();
    _ready = true;
  }

  void dispose() {
    feed.dispose();
    room.dispose();
    windowScene.dispose();
    disposeTubeBuffers();
  }

  /// One frame of the booth, in cabinet coordinates (0,0)-(940,720).
  void paint(ui.Canvas g, double t) {
    // 1 + 2 — the feed, then the tube buffers that consume it
    feed.render(s, runtime, t);
    final ui.Image? img = feed.image;
    if (img != null) tickTube(img);

    g.save();
    // 3 — camera shake. The HTML translated the whole room by a random offset.
    if (runtime.shake > 0.2) {
      g.translate(rr(-runtime.shake, runtime.shake), rr(-runtime.shake, runtime.shake));
    }
    g.clipRect(kRoom);

    // 4 — the room, back to front
    room.drawRoom(g, t);
    windowScene.drawWindow(g, t, s);
    room.drawSmallMonitors(g, t);
    if (img != null) drawMainCRT(g, s, runtime, img, t);
    room.drawDesk(g, t);
    room.drawDust(g, t);

    // 5 — room-wide passes
    if (s.dread > 25) {
      fillRect(g, 0, 0, kRoom.width, kRoom.height,
          rgba(120, 0, 0, (s.dread - 25) / 75 * 0.16));
    }
    // PAINT THE FUMBLE. wrongFx was set, reset and decayed entirely inside
    // anomalies.dart and read by NOTHING in paint/ or ui/ — a wrong key was
    // literally invisible. A hard red wash plus a bezel-height bloom makes it
    // the loudest thing in the room for a third of a second.
    if (runtime.wrongFx > 0.004) {
      final w = runtime.wrongFx;
      fillRect(g, 0, 0, kRoom.width, kRoom.height, rgba(255, 40, 30, w * 0.20));
      final ui.Paint wp = ui.Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          ui.Offset(kScr.center.dx, kScr.center.dy),
          kScr.width * 0.9,
          <ui.Color>[rgba(255, 60, 45, w * 0.30), rgba(255, 60, 45, 0)],
        );
      g.drawRect(kRoom, wp);
    }
    // THE SAVE. A clean kill blows the tube out white; a save rings the whole
    // ROOM instead — a cold ring closing inward, so peripheral vision catches
    // it even when you are staring at the bezel. Drawn under the blackout so
    // a save into a scare still reads as two events.
    if (runtime.clutchFx > 0.004) {
      final double k = runtime.clutchFx;
      final double r = kRoom.width * (0.30 + 0.42 * (1 - k));
      final ui.Paint cp = ui.Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          ui.Offset(kScr.center.dx, kScr.center.dy),
          r,
          <ui.Color>[
            rgba(90, 220, 255, 0),
            rgba(90, 220, 255, k * 0.30),
            rgba(90, 220, 255, 0),
          ],
          <double>[0.0, 0.82, 1.0],
        );
      g.drawRect(kRoom, cp);
      fillRect(g, 0, 0, kRoom.width, kRoom.height, rgba(120, 210, 255, k * 0.05));
    }
    // BLACKOUT beat — the room's lights go. Drawn before the flash so a scare
    // that blacks out and then hits still reads as two separate events.
    final double dark = runtime.blackoutAlpha;
    if (dark > 0.001) {
      fillRect(g, 0, 0, kRoom.width, kRoom.height, rgba(0, 0, 0, dark * 0.92));
    }
    if (runtime.flash > 0 && s.flash) {
      fillRect(g, 0, 0, kRoom.width, kRoom.height,
          rgba(255, 240, 240, runtime.flash * 0.5));
    }
    // THE SHADOW OF WHAT IS BEHIND YOU.
    //
    // A fixed first-person shot has one thing a player can never do: turn
    // round. So the only honest way to put something behind them is to let it
    // block the light — the booth is lit from behind the chair, so anything
    // standing there throws a shape onto the desk and the back wall.
    //
    // It is never named, never announced, and no key addresses it. A player
    // either notices the room has got darker in a person-shaped way, or they
    // do not. Both outcomes are correct.
    if (runtime.presence > 0.004) {
      final double p = runtime.presence;
      // a soft, wide occlusion — the light going, not a sprite appearing
      final ui.Paint occ = ui.Paint()
        ..blendMode = ui.BlendMode.multiply
        ..shader = ui.Gradient.radial(
          ui.Offset(kRoom.width * 0.5, kRoom.height * 1.02),
          kRoom.width * 0.62,
          <ui.Color>[
            rgba(30, 28, 30, 1),
            rgba(120, 116, 120, 1),
            rgba(255, 255, 255, 1),
          ],
          <double>[0.0, 0.55, 1.0],
        );
      g.saveLayer(kRoom, ui.Paint()..color = rgba(255, 255, 255, p * 0.85));
      g.drawRect(kRoom, occ);
      g.restore();

      // and the head and shoulders of it, on the desk, very faint
      final double bob = math.sin(t * 0.7) * 3;
      final ui.Paint sil = ui.Paint()..color = rgba(0, 0, 0, p * 0.30);
      final double cx = kRoom.width * 0.5;
      final double base = kRoom.height + 40 + bob;
      g.drawOval(
        ui.Rect.fromCenter(
            center: ui.Offset(cx, base - 250), width: 132, height: 152),
        sil,
      );
      final ui.Path sh = ui.Path()
        ..moveTo(cx - 210, base)
        ..quadraticBezierTo(cx - 150, base - 210, cx, base - 214)
        ..quadraticBezierTo(cx + 150, base - 210, cx + 210, base)
        ..close();
      g.drawPath(sh, sil);
    }

    // WHAT IS ON THE GLASS. Last inside the room clip, over the CRT, the desk
    // and every effect — it is on the pane between the player and the booth,
    // and the game never explains how it got on the inside.
    drawBlood(g, runtime.blood, t);

    final ui.Image? grain = noiseTile(t, 18);
    if (grain != null) {
      drawImageStretch(g, grain, kRoom, nearestPaint(alpha: 0.035));
    }
    // vignette
    final ui.Rect vr = ui.Rect.fromCircle(
        center: ui.Offset(kRoom.width / 2, 330), radius: 640);
    final ui.Paint vp = ui.Paint()
      ..shader = ui.Gradient.radial(
        ui.Offset(kRoom.width / 2, 330),
        640,
        <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.85)],
        <double>[180 / 640, 1.0],
      );
    g.drawRect(vr.intersect(kRoom), vp);
    g.restore();

    // the rack's ambient shadow strip, drawn outside the room clip
    final ui.Paint sh = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(kRoom.width - 30, 0),
        ui.Offset(kRoom.width, 0),
        <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.8)],
      );
    g.drawRect(
        ui.Rect.fromLTWH(kRoom.width - 30, 0, 30, kCabH), sh);
  }
}

/// The widget the shell drops into the cabinet stack.
class BoothScene extends StatefulWidget {
  const BoothScene({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  State<BoothScene> createState() => _BoothSceneState();
}

class _BoothSceneState extends State<BoothScene> {
  late final Booth _booth = Booth(widget.runtime);
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _booth.init().then((_) {
      if (mounted) setState(() => _booted = true);
    });
  }

  @override
  void dispose() {
    _booth.dispose();
    super.dispose();
  }

  /// Striking the tube. The HTML hit-tested the SCR rect in canvas space; the
  /// cabinet is already in that space here, so the local position is the hit.
  void _strike(Offset p) {
    if (!kScr.contains(p)) return;
    widget.runtime.tuneStrike(p.dx, p.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _strike(e.localPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: RepaintBoundary(
          child: CustomPaint(
            size: const Size(kCabW, kCabH),
            painter: _BoothPainter(_booth, _booted),
          ),
        ),
      ),
    );
  }
}

class _BoothPainter extends CustomPainter {
  _BoothPainter(this.booth, this.booted) : super(repaint: booth.runtime);

  final Booth booth;
  final bool booted;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    booth.paint(canvas, booth.runtime.tGlobal);
  }

  @override
  bool shouldRepaint(covariant _BoothPainter old) =>
      old.booth != booth || old.booted != booted;
}
