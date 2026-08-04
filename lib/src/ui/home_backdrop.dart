// FINAL BROADCAST — THE FRONT DESK, AS A PLACE.
//
// The home screen was type on a radial gradient. It is the first thing anybody
// sees, it is where the decision to play another night is made, and it looked
// like a settings page.
//
// This is the station from outside, at three in the morning, in weather:
// the mast on the ridge with its beacon, the low building with one window lit,
// the treeline, sodium haze off a town that is mostly asleep, snow, and a
// fence. Everything is drawn rather than composited, so it costs no assets and
// scales to any cabinet size.
//
// Two rules held it together:
//
//   IT NEVER COMPETES WITH THE TYPE. Every element sits in the outer thirds or
//   below the fold, the centre band is kept dark and quiet, and the whole
//   thing is under a vignette. A beautiful backdrop that makes the SIGN ON
//   button hard to read is a worse home screen than the gradient was.
//
//   NOTHING LOOPS VISIBLY. The beacon, the snow and the window flicker all run
//   on rates that share no common multiple, because a front desk you sit on
//   for thirty seconds must not start repeating in front of you.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../bake.dart' show rgba;
import '../state.dart';

class HomeBackdrop extends StatefulWidget {
  const HomeBackdrop({super.key, required this.s});
  final GameState s;

  @override
  State<HomeBackdrop> createState() => _HomeBackdropState();
}

class _HomeBackdropState extends State<HomeBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 120),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _BackdropPainter(_c.value * 120, widget.s),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t, this.s);
  final double t;
  final GameState s;

  @override
  void paint(ui.Canvas g, ui.Size z) {
    final double w = z.width, h = z.height;
    final double horizon = h * 0.70;

    // --- the sky ---
    g.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(0, 0),
          ui.Offset(0, horizon),
          <ui.Color>[
            const ui.Color(0xFF060A0F),
            const ui.Color(0xFF0C131A),
            const ui.Color(0xFF172026),
          ],
          <double>[0, 0.62, 1],
        ),
    );

    // sodium haze off the town, low and to one side so the centre stays dark
    // Drawn over the WHOLE canvas, not over a band. Clipping a radial to a
    // rect leaves the rect's edge visible as a seam across the sky, which is
    // exactly what it did.
    g.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        // Pushed left and tightened: at w*0.24 with a 0.40w radius it reached
        // x=819, well inside the band the wordmark and buttons sit in, and
        // measured as the BRIGHTEST thing in the type area.
        ..shader = ui.Gradient.radial(
          ui.Offset(w * 0.13, horizon),
          w * 0.26,
          <ui.Color>[rgba(150, 96, 36, 0.38), rgba(150, 96, 36, 0)],
        ),
    );

    // --- stars, in the outer thirds only ---
    for (var i = 0; i < 90; i++) {
      final double sx = ((i * 131) % 997) / 997 * w;
      // keep the centre band clear for the wordmark
      if (sx > w * 0.30 && sx < w * 0.70 && i % 4 != 0) continue;
      final double sy = ((i * 71) % 397) / 397 * horizon * 0.86;
      final double tw =
          0.30 + math.sin(t * (0.29 + (i % 7) * 0.11) + i * 1.7) * 0.22;
      g.drawRect(ui.Rect.fromLTWH(sx, sy, 1.4, 1.4),
          ui.Paint()..color = rgba(200, 226, 244, (0.14 + tw * 0.3)));
    }

    // --- the ridge ---
    final ridge = ui.Path()..moveTo(0, h);
    ridge.lineTo(0, horizon + 6);
    for (double x = 0; x <= w; x += 9) {
      final double y = horizon +
          math.sin(x * 0.0042) * (h * 0.020) +
          math.sin(x * 0.011 + 1.3) * (h * 0.012);
      ridge.lineTo(x, y);
    }
    ridge
      ..lineTo(w, h)
      ..close();
    g.drawPath(ridge, ui.Paint()..color = const ui.Color(0xFF0A0F13));

    // --- the treeline: real trees, not a wobble ---
    for (var i = 0; i < 68; i++) {
      final double tx = (i / 68) * (w + 40) - 20;
      if (tx > w * 0.34 && tx < w * 0.66 && i % 3 != 0) continue; // keep centre
      final double th = h * (0.035 + ((i * 37) % 11) / 11 * 0.045);
      final double ty = horizon + math.sin(tx * 0.0042) * (h * 0.020) + 4;
      final tree = ui.Path()..moveTo(tx, ty);
      // a conifer: a narrow triangle with a couple of steps
      tree
        ..lineTo(tx - th * 0.26, ty)
        ..lineTo(tx, ty - th)
        ..lineTo(tx + th * 0.26, ty)
        ..close();
      g.drawPath(tree, ui.Paint()..color = const ui.Color(0xFF05090C));
    }

    // --- the mast, on the ridge, right of the type ---
    final double mx = w * 0.815;
    final double mTop = horizon - h * 0.40;
    final double mBase = horizon + h * 0.035;
    final ui.Paint lat = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = rgba(120, 146, 158, 0.55);
    final double spread = h * 0.030;
    g.drawPath(
      ui.Path()
        ..moveTo(mx - spread, mBase)
        ..lineTo(mx, mTop)
        ..lineTo(mx + spread, mBase),
      lat,
    );
    for (var i = 0; i < 13; i++) {
      final double f = i / 12;
      final double y = mBase + (mTop - mBase) * f;
      final double sp = spread * (1 - f);
      g.drawLine(ui.Offset(mx - sp, y), ui.Offset(mx + sp, y), lat);
      // the cross-bracing, which is what makes a lattice read as a lattice
      if (i < 12) {
        final double y2 = mBase + (mTop - mBase) * ((i + 1) / 12);
        final double sp2 = spread * (1 - (i + 1) / 12);
        g.drawLine(ui.Offset(mx - sp, y), ui.Offset(mx + sp2, y2), lat);
      }
    }
    // guy wires
    for (final d in <double>[-1, 1]) {
      g.drawLine(
        ui.Offset(mx + d * spread * 0.4, mTop + (mBase - mTop) * 0.28),
        ui.Offset(mx + d * w * 0.075, mBase),
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = rgba(90, 110, 120, 0.22),
      );
    }
    // the beacon. Its own rate, sharing no multiple with anything else here.
    final double bl =
        (math.sin(t * 0.83) * 0.5 + 0.5) * (math.sin(t * 0.19) * 0.25 + 0.75);
    g.drawCircle(ui.Offset(mx, mTop - 2), 2.4,
        ui.Paint()..color = rgba(255, 70, 48, 0.35 + bl * 0.6));
    g.drawCircle(
      ui.Offset(mx, mTop - 2),
      10 + bl * 7,
      ui.Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          ui.Offset(mx, mTop - 2),
          10 + bl * 7,
          <ui.Color>[rgba(255, 60, 40, 0.22 * bl), rgba(255, 60, 40, 0)],
        ),
    );

    // --- the transmitter hall, at the foot of its own mast ---
    //
    // Drawn AFTER the mast so the lattice rises from behind the roof,
    // which is how a transmitter site is actually laid out and also the
    // only band of the frame with no interface in it: at w*0.60 the lit
    // window landed underneath the AUDIO / SCREEN CHECK panel and read as
    // a stray orange rectangle rather than as a window in a building.
    final double bx = w * 0.755, by = horizon + h * 0.048;
    final double bw = w * 0.165, bh = h * 0.082;
    final double fl = math.sin(t * 0.37) * 0.5 + 0.5;
    final double wx = bx + bw * 0.62, wy = by + bh * 0.28;
    final double wW = bw * 0.14, wH = bh * 0.26;

    // The spill goes down FIRST, on the ground in front, and is centred BELOW
    // the sill rather than on the building. Drawn after the building it lit
    // the front wall instead of the snow, and the station read as a glowing
    // box brighter than the field around it — the opposite of a silhouette.
    g.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(wx + wW * 0.5, by + bh * 1.5),
          bw * 0.85,
          <ui.Color>[rgba(255, 186, 88, 0.16), rgba(255, 190, 90, 0)],
        ),
    );

    // and the building on top of it, darker than the ground it stands on
    g.drawRect(ui.Rect.fromLTWH(bx, by, bw, bh),
        ui.Paint()..color = const ui.Color(0xFF04070A));
    // the flat roof and its parapet, catching a little of the sky
    g.drawRect(ui.Rect.fromLTWH(bx - 3, by - 3, bw + 6, 3.5),
        ui.Paint()..color = const ui.Color(0xFF0E141A));
    // a vent stack, because a flat roof with nothing on it reads as a box
    g.drawRect(ui.Rect.fromLTWH(bx + bw * 0.21, by - 10, 3.5, 8),
        ui.Paint()..color = const ui.Color(0xFF0B1014));

    // ONE window lit. Somebody is on shift, and it is not you yet.
    final ui.Rect win = ui.Rect.fromLTWH(wx, wy, wW, wH);
    g.drawRect(win, ui.Paint()..color = rgba(255, 196, 96, 0.34 + fl * 0.26));
    // the glass is brighter at the top, where the fitting is
    g.drawRect(
      win,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(0, wy),
          ui.Offset(0, wy + wH),
          <ui.Color>[rgba(255, 226, 160, 0.30), rgba(255, 150, 50, 0.0)],
        ),
    );
    // frame and mullion — the detail that stops it being an orange rectangle
    final ui.Paint mull = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = rgba(20, 12, 6, 0.85);
    g.drawLine(ui.Offset(wx + wW * 0.5, wy), ui.Offset(wx + wW * 0.5, wy + wH),
        mull);
    g.drawLine(ui.Offset(wx, wy + wH * 0.45),
        ui.Offset(wx + wW, wy + wH * 0.45), mull);
    g.drawRect(win, mull);

    // AND SOMEBODY WALKS PAST IT.
    //
    // Once every forty-odd seconds, for under two. Long enough to register,
    // short enough that a player looking at the SIGN ON button catches it in
    // the corner of their eye and has to decide whether they saw anything.
    // There is nobody else at this station. That is established in the
    // archive, and it is why this is here.
    final double walk = (t % 43.0) / 1.8;
    if (walk < 1.0) {
      final double fx = wx - wW * 0.2 + wW * 1.4 * walk;
      g.save();
      g.clipRect(win);
      final ui.Paint body = ui.Paint()..color = rgba(6, 4, 2, 0.92);
      g.drawRect(
          ui.Rect.fromLTWH(fx - wW * 0.15, wy + wH * 0.30, wW * 0.30, wH),
          body);
      g.drawCircle(ui.Offset(fx, wy + wH * 0.26), wW * 0.13, body);
      g.restore();
    }


    // --- the fence in the near ground ---
    final double fy = h * 0.945;
    for (double x = -10; x < w + 10; x += w * 0.045) {
      g.drawRect(ui.Rect.fromLTWH(x, fy - h * 0.035, 2, h * 0.035),
          ui.Paint()..color = rgba(4, 6, 8, 0.85));
    }
    for (final yy in <double>[fy - h * 0.030, fy - h * 0.016]) {
      g.drawLine(ui.Offset(0, yy), ui.Offset(w, yy),
          ui.Paint()
            ..strokeWidth = 1
            ..color = rgba(4, 6, 8, 0.7));
    }

    // --- weather ---
    for (var i = 0; i < 120; i++) {
      final double sp = h * (0.010 + (i % 6) * 0.004);
      final double sx = (((i * 89) % 991) / 991 * w) + math.sin(t * 0.2 + i) * 9;
      final double sy = (((i * 53) % 397) / 397 * h + t * sp * 6) % h;
      final double a = 0.05 + (i % 6) * 0.022;
      g.drawRect(ui.Rect.fromLTWH(sx, sy, 1.3, 2.4),
          ui.Paint()..color = rgba(214, 232, 242, a));
    }

    // --- and the whole thing under glass ---
    // Heavy vignette, so the type in the middle always sits on near-black no
    // matter how much detail is behind it.
    g.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(w / 2, h * 0.42),
          math.max(w, h) * 0.62,
          <ui.Color>[rgba(0, 0, 0, 0.10), rgba(0, 0, 0, 0.72)],
          <double>[0.34, 1.0],
        ),
    );
    // a band of extra darkness exactly where the wordmark and buttons live
    g.drawRect(
      ui.Rect.fromLTWH(0, h * 0.10, w, h * 0.62),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          ui.Offset(0, h * 0.10),
          ui.Offset(0, h * 0.72),
          <ui.Color>[rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.42), rgba(0, 0, 0, 0)],
          <double>[0, 0.45, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => true;
}


/// Test-only hook. The widget drives a repeating AnimationController, which
/// never settles under the widget tester — so the backdrop is baked through
/// the painter directly rather than pumped, which is also how it got looked at
/// while it was being drawn.
class HomeBackdropProbe {
  static void paint(ui.Canvas g, ui.Size size, GameState s, double t) =>
      _BackdropPainter(t, s).paint(g, size);
}
