// FINAL BROADCAST — WHAT IS ON THE GLASS.
//
// "its boring and wierd not even creepy it should be disturbingly traumatizing"
//
// Every scare in this build was a SYSTEM: a number went up, a meter turned
// red, a face flashed for a second and the room went back to normal. Systems
// are not disturbing. Nothing in the booth had ever been touched by anything.
//
// This is the layer that has. It is painted on the INSIDE of the glass you are
// looking through — between the player and the room, not in it — so there is
// no diegetic explanation for how it got there and the game never offers one.
//
// It accumulates. It does not wipe between anomalies. A bad night ends with a
// booth you cannot see out of, and the only way it gets cleaned is sunrise.
//
// Deliberately restrained on the first mark and ugly by the fifth: one smear
// is unsettling, a screen full of it is a different and worse feeling, and the
// distance between those two is a whole night of your decisions.

import 'dart:math' as math;
import 'dart:ui' as ui;

import '../bake.dart';
import '../consts.dart';

/// One mark. Position is in cabinet space so it survives a resize.
class Splat {
  Splat({
    required this.x,
    required this.y,
    required this.r,
    required this.seed,
    required this.heavy,
  });

  final double x;
  final double y;

  /// Rough radius of the body of the mark.
  final double r;

  /// Stable per-mark randomness, so a splat is the same splat every frame.
  final double seed;

  /// A heavy mark runs. A light one only sits there.
  final bool heavy;

  /// How far the runs have crept down the glass, 0..1. Blood does not stop
  /// moving the moment it lands, and something that is still moving twenty
  /// minutes later is worse than something that is not.
  double run = 0;
}

/// A hand, pressed flat and dragged. Drawn on the window, from the OUTSIDE.
class Handprint {
  Handprint({required this.x, required this.y, required this.seed, required this.flip});
  final double x;
  final double y;
  final double seed;
  final bool flip;
}

/// Everything on the glass tonight.
class BloodLayer {
  final List<Splat> splats = <Splat>[];

  /// Prints on the window pane. There is nothing out there that has hands.
  final List<Handprint> hands = <Handprint>[];

  /// 0..1 — a wash of it over the whole pane, for the worst moments.
  double wash = 0;

  void clear() {
    splats.clear();
    hands.clear();
    wash = 0;
  }

  /// Something put a hand on the window. From the outside.
  void addHand(double x, double y) {
    if (hands.length > 7) hands.removeAt(0);
    hands.add(Handprint(x: x, y: y, seed: rand(), flip: rand() < 0.5));
  }

  /// Something happened. [force] 0..1 scales how much and how heavy.
  ///
  /// Marks land near [ox],[oy] when given — the tube for a scare, the window
  /// for whatever is out there — so the glass remembers WHERE as well as how
  /// often.
  void add(double force, {double? ox, double? oy, int count = 0}) {
    final int n = count > 0 ? count : (2 + (force * 5)).round();
    for (var i = 0; i < n; i++) {
      final double a = rand() * math.pi * 2;
      final double d = rand() * (60 + force * 190);
      splats.add(Splat(
        x: (ox ?? kRoom.width * 0.5) + math.cos(a) * d,
        y: (oy ?? kRoom.height * 0.42) + math.sin(a) * d * 0.72,
        r: (5 + rand() * 22) * (0.55 + force * 0.9),
        seed: rand(),
        heavy: rand() < 0.35 + force * 0.4,
      ));
    }
    // Capped well under 1. The point is a booth you do not want to look at,
    // not a booth you cannot READ — a horror game that hides the keys from you
    // is not frightening, it is broken, and the player's death has to stay
    // their own fault.
    wash = math.min(0.55, wash + force * 0.20);
    // A hard cap, because an unbounded list is a frame-rate bug waiting for a
    // bad night. Oldest marks go first — the glass keeps the recent damage.
    while (splats.length > 90) {
      splats.removeAt(0);
    }
  }

  void tick(double dt) {
    for (final s in splats) {
      if (!s.heavy) continue;
      // Runs slow down as they lengthen, the way real ones do as they thin.
      s.run = math.min(1.0, s.run + dt * (0.030 + s.seed * 0.045) * (1 - s.run * 0.6));
    }
    wash = math.max(0, wash - dt * 0.012);
  }

  bool get isEmpty => splats.isEmpty && hands.isEmpty && wash <= 0.002;
}

// --- painting ---------------------------------------------------------------

const ui.Color _kDark = ui.Color(0xFF1A0204);
const ui.Color _kMid = ui.Color(0xFF4A0508);
const ui.Color _kWet = ui.Color(0xFF6B0A0E);

/// Draws the whole layer, in cabinet space. Call INSIDE the room clip, last,
/// so it sits on the glass in front of everything including the CRT.
void drawBlood(ui.Canvas g, BloodLayer b, double t) {
  if (b.isEmpty) return;

  if (b.wash > 0.004) {
    // not a red filter over the picture — a thin film on the pane, darkest at
    // the edges where it has had somewhere to pool
    final ui.Paint wp = ui.Paint()
      ..blendMode = ui.BlendMode.multiply
      ..shader = ui.Gradient.radial(
        ui.Offset(kRoom.width * 0.5, kRoom.height * 0.45),
        kRoom.width * 0.78,
        <ui.Color>[
          rgba(255, 190, 190, 1 - b.wash * 0.10),
          rgba(150, 20, 24, 1 - b.wash * 0.55),
        ],
      );
    g.drawRect(kRoom, wp);
  }

  for (final s in b.splats) {
    _splat(g, s, t);
  }
  for (final h in b.hands) {
    _hand(g, h);
  }
}

/// A palm and four fingers, smeared downward. Deliberately a little too big
/// and with the fingers a little too long — a hand you recognise instantly and
/// then keep looking at because the proportions are not right.
void _hand(ui.Canvas g, Handprint h) {
  final double s = 1.0 + h.seed * 0.35;
  final double dir = h.flip ? -1 : 1;
  final ui.Paint pt = fill(rgba(104, 9, 13, 0.72));

  // palm — broad, and squarer than an oval, because a pressed palm flattens
  g.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromCenter(
        center: ui.Offset(h.x, h.y + 2 * s),
        width: 34 * s,
        height: 36 * s,
      ),
      ui.Radius.circular(13 * s),
    ),
    pt,
  );
  // fingers — four, held CLOSE, and one knuckle too long each. Splayed wide
  // reads as a cartoon starfish; nearly-together reads as a hand, and then
  // the length is the thing that is wrong about it.
  for (var i = 0; i < 4; i++) {
    final double a = (-0.30 + i * 0.20) * dir;
    final double len = (34 + _n(h.seed * 9 + i) * 14) * s;
    final double fx = h.x + (-12 + i * 8.0) * s * dir;
    final double fy = h.y - 15 * s;
    g.save();
    g.translate(fx, fy);
    g.rotate(a * 0.75);
    g.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(-4.2 * s, -len, 8.4 * s, len + 10 * s),
        ui.Radius.circular(4.2 * s),
      ),
      pt,
    );
    g.restore();
  }
  // thumb
  g.save();
  g.translate(h.x + 16 * s * dir, h.y + 4 * s);
  g.rotate(1.05 * dir);
  g.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(-4 * s, -20 * s, 8 * s, 24 * s),
      ui.Radius.circular(4 * s),
    ),
    pt,
  );
  g.restore();

  // the drag, downward, because it did not lift the hand off cleanly
  final ui.Paint smear = ui.Paint()
    ..shader = ui.Gradient.linear(
      ui.Offset(h.x, h.y),
      ui.Offset(h.x, h.y + 54 * s),
      <ui.Color>[rgba(104, 9, 13, 0.5), rgba(104, 9, 13, 0)],
    );
  g.drawRect(
      ui.Rect.fromLTWH(h.x - 15 * s, h.y, 30 * s, 56 * s), smear);
}

void _splat(ui.Canvas g, Splat s, double t) {
  // the body: an irregular blob, never a circle — a circle reads as a bullet
  // hole in a video game, and this is supposed to read as something wet
  // Quadratics, not line segments. An 11-gon reads as a polygon at any size —
  // the eye finds the straight edges immediately and the whole thing stops
  // being wet and starts being a shape someone drew.
  const int lobes = 13;
  double rAt(int i) {
    final int k = i % lobes;
    return s.r *
        (0.58 +
            0.42 * _n(s.seed * 31 + k * 1.7) +
            0.16 * _n(s.seed * 7 + k * 3.1));
  }
  // Spatter is DIRECTIONAL. Every mark being a round blob with a tail out of
  // the middle is why the first pass read as mushrooms: real marks are
  // stretched along the line they arrived on, and the line differs per mark.
  final double axis = _n(s.seed * 91) * math.pi;
  final double stretch = 1.0 + _n(s.seed * 53) * 1.6;
  final double ca = math.cos(axis), sa = math.sin(axis);
  ui.Offset ptAt(int i) {
    final double a = i / lobes * math.pi * 2;
    final double rr0 = rAt(i);
    // in splat space, then rotated onto the impact axis
    final double px = math.cos(a) * rr0 * stretch;
    final double py = math.sin(a) * rr0 * 0.72;
    return ui.Offset(s.x + px * ca - py * sa, s.y + px * sa + py * ca);
  }

  final ui.Path p = ui.Path();
  ui.Offset mid(ui.Offset a, ui.Offset b) =>
      ui.Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  p.moveTo(mid(ptAt(0), ptAt(1)).dx, mid(ptAt(0), ptAt(1)).dy);
  for (var i = 1; i <= lobes; i++) {
    final ui.Offset c = ptAt(i);
    final ui.Offset nx = mid(ptAt(i), ptAt(i + 1));
    p.quadraticBezierTo(c.dx, c.dy, nx.dx, nx.dy);
  }
  p.close();
  g.drawPath(p, fill(_kMid));

  // a darker, dried edge — the thing that stops it looking like paint
  g.drawPath(
      p,
      stroke(_kDark, 1.6 + s.r * 0.06)
        ..style = ui.PaintingStyle.stroke);

  // the wet highlight, offset up-left like a light source in the room
  // A faint sheen, not a specular ball. The first pass put a big soft
  // highlight up-left on every mark and they all read as polished spheres.
  final ui.Paint hi = ui.Paint()
    ..shader = ui.Gradient.radial(
      ui.Offset(s.x - s.r * 0.18, s.y - s.r * 0.22),
      s.r * 0.55,
      <ui.Color>[rgba(150, 34, 36, 0.16), rgba(120, 14, 18, 0)],
    );
  g.save();
  g.clipPath(p);
  g.drawRect(
      ui.Rect.fromCircle(center: ui.Offset(s.x, s.y), radius: s.r * 1.4), hi);
  g.restore();

  // satellite spatter — the small stuff that sells the impact
  final int sat = 2 + (s.seed * 4).floor();
  for (var i = 0; i < sat; i++) {
    final double a = _n(s.seed * 13 + i) * math.pi * 2;
    final double d = s.r * (1.3 + _n(s.seed * 5 + i * 2) * 2.4);
    final double rr1 = 0.9 + _n(s.seed * 3 + i * 5) * 2.6;
    g.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(s.x + math.cos(a) * d, s.y + math.sin(a) * d * 0.8),
        width: rr1 * 2,
        height: rr1 * 2.4,
      ),
      fill(_kDark),
    );
  }

  if (!s.heavy || s.run <= 0.004) return;

  // THE RUN. The part that keeps moving after you have stopped looking.
  // A run is not a stick with a ball on it. It is wide where it left the body,
  // it narrows unevenly, it wanders as it finds the grain of the glass, and
  // most of them dry out before they bead.
  final double len = s.run * (48 + s.seed * 130);
  final double w0 = s.r * (0.30 + s.seed * 0.18);
  // leaves from the low edge, offset along the mark, never dead centre
  final double ox0 = (_n(s.seed * 71) - 0.5) * s.r * 1.5 * stretch;
  final double oy0 = s.r * 0.55;
  const int segs = 9;
  final List<ui.Offset> lft = <ui.Offset>[];
  final List<ui.Offset> rgt = <ui.Offset>[];
  for (var i = 0; i <= segs; i++) {
    final double f = i / segs;
    // narrows fast at first, then creeps
    final double w = w0 * (1 - f) * (1 - f) * 0.75 + w0 * 0.16 * (1 - f);
    final double wob =
        (_n(s.seed * 17 + i * 2.3) - 0.5) * 6.5 * f + (_n(s.seed * 5) - 0.5) * 3;
    final double y = s.y + oy0 + len * f;
    lft.add(ui.Offset(s.x + ox0 - w + wob, y));
    rgt.add(ui.Offset(s.x + ox0 + w + wob, y));
  }
  final ui.Path drip = ui.Path()..moveTo(lft.first.dx, lft.first.dy);
  for (final o in lft.skip(1)) {
    drip.lineTo(o.dx, o.dy);
  }
  for (final o in rgt.reversed) {
    drip.lineTo(o.dx, o.dy);
  }
  drip.close();
  g.drawPath(drip, fill(_kMid));

  // only the fat ones ever reach a bead
  if (w0 > s.r * 0.42 && s.run > 0.35) {
    final ui.Offset tip = lft.last;
    g.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(tip.dx + w0 * 0.16, tip.dy),
        width: w0 * 0.85,
        height: w0 * 1.15,
      ),
      fill(_kWet),
    );
  }
}

/// Cheap stable hash in 0..1. Deterministic per splat, so nothing crawls.
double _n(double x) {
  final double v = math.sin(x * 12.9898) * 43758.5453;
  return v - v.floorToDouble();
}
