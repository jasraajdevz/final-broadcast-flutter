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

  /// Seconds since it landed. Drives DRYING, which is the single biggest
  /// realism cue available: fresh blood is bright, wet and translucent, and
  /// within minutes it goes dark, matte and opaque as the haemoglobin
  /// oxidises. A screen where every mark is the same colour reads as paint no
  /// matter how good the shapes are — and once marks age at different rates
  /// you can tell at a glance which ones are from ten minutes ago and which
  /// one just happened.
  double age = 0;

  /// 0..1 — how dried. Non-linear: the surface skins over fast, the body of
  /// it takes much longer.
  double get dry => (1 - math.exp(-age / 70)).clamp(0.0, 1.0);

  /// Seconds until this run sheds its next bead.
  double dripIn = 0;
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

  /// Beads that have let go this frame, as (x, y, size). Drained by the sim
  /// and turned into sound: a drip you HEAR before you find it is worth more
  /// than one you only see.
  final List<({double x, double y, double size})> drips =
      <({double x, double y, double size})>[];

  /// Residual dots left behind by a run as it travels. Real runs do not slide
  /// cleanly — they pin, stretch and leave a broken trail.
  final List<({double x, double y, double r, double seed})> trail =
      <({double x, double y, double r, double seed})>[];

  /// ON THE TUBE ITSELF, and only in NIGHTMARE.
  ///
  /// Every other mark in this game is kept OFF the screen on purpose — that
  /// was a real bug once, blood spawning at kScr.center and covering the one
  /// thing the player has to read, and it was fixed by clipping the tube out.
  ///
  /// This is the same thing done deliberately and made answerable: it lands on
  /// the glass, it occludes the picture, and THE OPERATOR CAN WIPE IT OFF with
  /// a hand. That turns an obstruction into a fifth thing competing for two
  /// hands, which is the design the rest of the rewrite is built on, rather
  /// than into the game hiding the keys from you.
  ///
  /// It never fully clears. Wiping thins a mark and smears what is left.
  final List<({double x, double y, double r, double seed, double a})> glass =
      <({double x, double y, double r, double seed, double a})>[];

  /// Something got on the glass. NIGHTMARE only.
  void addGlass(double force) {
    final int n = 2 + (force * 4).round();
    for (var i = 0; i < n; i++) {
      glass.add((
        x: kScr.left + rand() * kScr.width,
        y: kScr.top + rand() * kScr.height,
        r: (14 + rand() * 46) * (0.6 + force),
        seed: rand(),
        a: 0.34 + force * 0.34,
      ));
    }
    while (glass.length > 26) {
      glass.removeAt(0);
    }
  }

  /// HOW WELL WIPING STILL WORKS, 1 down to 0.
  ///
  /// Set from how long the operator has actually been sitting there. This is
  /// the one thing in NIGHTMARE that exploits DURATION rather than dread, and
  /// duration is the only axis a horror game has left once the player has
  /// understood every jump it can make.
  ///
  /// For the first ten minutes a hand takes the glass back. By forty it moves
  /// what is there without removing it, so the tube ends up with everything
  /// that ever landed on it dragged into streaks, and the picture the operator
  /// is trying to read is behind an hour of their own cleaning.
  ///
  /// Nothing announces this. It just stops working, which is worse than being
  /// told it will.
  double grip = 1.0;

  /// A hand goes across the tube. Thins anything under it and leaves the rest
  /// dragged — a wiped screen is never a clean screen, and after long enough
  /// it is not even a wiped screen.
  void wipe(double x, double y) {
    for (var i = glass.length - 1; i >= 0; i--) {
      final g = glass[i];
      final double d =
          math.sqrt((g.x - x) * (g.x - x) + (g.y - y) * (g.y - y));
      if (d > 62) continue;
      final double cut = (1 - d / 62) * 0.55 * grip;
      final double left = g.a - cut;
      if (left <= 0.05) {
        glass.removeAt(i);
      } else {
        glass[i] = (
          // it drags further the less the hand is achieving
          x: g.x + (g.x - x) * (0.05 + (1 - grip) * 0.16),
          y: g.y + (g.y - y) * (0.05 + (1 - grip) * 0.16),
          r: g.r * (1.04 + (1 - grip) * 0.10),
          seed: g.seed,
          a: left,
        );
      }
    }
  }

  void clear() {
    glass.clear();
    splats.clear();
    hands.clear();
    trail.clear();
    drips.clear();
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
      s.age += dt;
      if (!s.heavy) continue;
      // A run creeps, and it creeps LESS as it dries — the same mark that ran
      // fast in its first ten seconds is barely moving two minutes later.
      final double before = s.run;
      s.run = math.min(
          1.0,
          s.run +
              dt * (0.030 + s.seed * 0.045) * (1 - s.run * 0.6) * (1 - s.dry * 0.85));

      if (s.run > before && s.run < 0.999) {
        // pin points: a travelling run leaves a broken trail behind it rather
        // than a clean stripe
        if (rand() < dt * 1.4) {
          trail.add((
            x: s.x + (rand() - 0.5) * s.r * 1.2,
            y: s.y + s.r * 0.5 + s.run * (48 + s.seed * 130) * rand(),
            r: 0.8 + rand() * 1.9,
            seed: rand(),
          ));
        }
        // and the fat ones shed a bead every so often, which is a SOUND
        s.dripIn -= dt;
        if (s.dripIn <= 0 && s.r > 11 && s.run > 0.30) {
          s.dripIn = 3.5 + rand() * 9.0;
          drips.add((
            x: s.x,
            y: s.y + s.r * 0.5 + s.run * (48 + s.seed * 130),
            size: (s.r / 26).clamp(0.15, 1.0),
          ));
        }
      }
    }
    while (trail.length > 160) {
      trail.removeAt(0);
    }
    wash = math.max(0, wash - dt * 0.012);
  }

  bool get isEmpty => splats.isEmpty && hands.isEmpty && wash <= 0.002;
}

// --- painting ---------------------------------------------------------------

// THE DRYING CURVE.
//
// Fresh arterial blood on glass is bright, thin and TRANSLUCENT — you can see
// the room through the edges of it. Within a couple of minutes the haemoglobin
// oxidises and it goes dark, matte, opaque and slightly brown. Every mark in
// the first pass was the same flat maroon, which is why the whole layer read
// as paint: paint does not change, and the eye knows that.
const ui.Color _kFresh = ui.Color(0xFF8E0F14); // just landed
const ui.Color _kDried = ui.Color(0xFF25100A); // ten minutes old, browner
const ui.Color _kDeep = ui.Color(0xFF120203); // the thick middle
const ui.Color _kSheen = ui.Color(0xFFD46A62); // wet highlight, fresh only

ui.Color _lerpC(ui.Color a, ui.Color b, double f) {
  final double k = f.clamp(0.0, 1.0);
  return ui.Color.fromARGB(
    255,
    (a.r * 255 + (b.r - a.r) * 255 * k).round(),
    (a.g * 255 + (b.g - a.g) * 255 * k).round(),
    (a.b * 255 + (b.b - a.b) * 255 * k).round(),
  );
}

/// Body colour for a mark of the given dryness.
ui.Color _bodyOf(double dry) => _lerpC(_kFresh, _kDried, dry);

/// Draws the whole layer, in cabinet space. Call INSIDE the room clip, last,
/// so it sits on the glass in front of everything including the CRT.
void drawBlood(ui.Canvas g, BloodLayer b, double t) {
  if (b.isEmpty) return;

  // THE TUBE IS NEVER COVERED.
  //
  // The first version spawned every mark at the centre of kScr and drew it
  // last, over everything — so a bad night put a large red blob directly on
  // top of the one surface the player has to read. Baked and looked at: the
  // picture was gone. That is not atmosphere, that is breaking the game.
  //
  // The blood is on the BOOTH glass. The CRT is recessed behind its bezel, so
  // it is physically the one thing in the room that would NOT catch spatter,
  // and cutting it out is both the correct fiction and the thing that keeps
  // the game playable.
  g.save();
  g.clipRect(kScr.inflate(6), clipOp: ui.ClipOp.difference);

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

  // the broken trail a travelling run leaves behind it
  for (final d in b.trail) {
    g.drawOval(
      ui.Rect.fromCenter(
          center: ui.Offset(d.x, d.y), width: d.r * 1.6, height: d.r * 2.2),
      fill(rgba(58, 8, 10, 0.55)),
    );
  }
  for (final s in b.splats) {
    _splat(g, s, t);
  }
  for (final h in b.hands) {
    _hand(g, h);
  }
  g.restore();
  // AND THEN, IN NIGHTMARE ONLY, THE PART THAT IS ON THE TUBE.
  //
  // Drawn last and deliberately outside the clip that protects the screen
  // everywhere else, because here it is supposed to be in the way — and it is
  // answerable, which is the difference. b.wipe() takes it off.
  for (final s in b.glass) {
    final ui.Paint p = ui.Paint()
      ..color = rgba(96, 8, 8, s.a)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.2);
    g.drawCircle(ui.Offset(s.x, s.y), s.r * 0.5, p);
    // it does not sit still on a vertical piece of glass
    final double run = 8 + s.seed * 34 * s.a;
    g.drawRect(
        ui.Rect.fromLTWH(s.x - s.r * 0.10, s.y, s.r * 0.20, run),
        ui.Paint()..color = rgba(84, 6, 6, s.a * 0.75));
  }

}

/// A palm and four fingers, smeared downward. Deliberately a little too big
/// and with the fingers a little too long — a hand you recognise instantly and
/// then keep looking at because the proportions are not right.
void _hand(ui.Canvas g, Handprint h) {
  final double s = 1.0 + h.seed * 0.35;
  final double dir = h.flip ? -1 : 1;
  // old, thick, and mostly opaque — this was pressed and held, not thrown
  final ui.Paint pt = fill(rgba(52, 14, 11, 0.86));

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
      <ui.Color>[rgba(52, 14, 11, 0.62), rgba(52, 14, 11, 0)],
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

  final double dry = s.dry;
  final ui.Color body = _bodyOf(dry);
  // TRANSLUCENT while fresh. Blood on glass is not a sticker: thin blood lets
  // the room through and only reads as opaque where it has pooled. Opacity
  // climbs as it dries and thickens.
  final double alpha = 0.62 + dry * 0.34;

  // 1. the halo — the thinnest film, wider than the mark, barely there. This
  //    is the edge you actually perceive first and the first pass had none.
  final ui.Paint halo = ui.Paint()
    ..shader = ui.Gradient.radial(
      ui.Offset(s.x, s.y),
      s.r * 1.45,
      <ui.Color>[
        // tight and faint. At 0.30 over 2.1r this read as a glow around the
        // mark — light coming OFF it — which is exactly wrong for a fluid.
        body.withValues(alpha: alpha * 0.11),
        body.withValues(alpha: 0),
      ],
      <double>[0.72, 1.0],
    );
  g.drawRect(
      ui.Rect.fromCircle(center: ui.Offset(s.x, s.y), radius: s.r * 2.2), halo);

  // 2. the body
  g.drawPath(p, fill(body.withValues(alpha: alpha)));

  // 3. the pooled middle — thicker, darker, and offset, because a mark does
  //    not pool at its own centroid
  g.save();
  g.clipPath(p);
  final ui.Paint core = ui.Paint()
    ..shader = ui.Gradient.radial(
      ui.Offset(s.x + (_n(s.seed * 3) - 0.5) * s.r * 0.5,
          s.y + (_n(s.seed * 11) - 0.5) * s.r * 0.4),
      s.r * 1.1,
      <ui.Color>[
        _kDeep.withValues(alpha: 0.55 + dry * 0.25),
        _kDeep.withValues(alpha: 0),
      ],
    );
  g.drawRect(
      ui.Rect.fromCircle(center: ui.Offset(s.x, s.y), radius: s.r * 2), core);
  g.restore();

  // 4. the dried rim. Blood dries from the outside in, so an older mark has a
  //    hard dark ring and a fresh one does not.
  if (dry > 0.06) {
    g.drawPath(
        p,
        stroke(_kDried.withValues(alpha: 0.30 + dry * 0.55),
            0.9 + s.r * 0.045));
  }

  // 5. SPINES. Surface tension breaks the leading edge of an impact into fine
  //    points. This is the single most recognisable thing about real spatter
  //    and a smooth outline never reads right without it.
  final int spines = 3 + (_n(s.seed * 23) * 7).floor();
  for (var i = 0; i < spines; i++) {
    final double sa = axis + (_n(s.seed * 41 + i * 2.7) - 0.5) * 2.2;
    final double base = rAt((i * 3) % lobes);
    final double len = base * (0.35 + _n(s.seed * 19 + i) * 1.5);
    final double bx = s.x + math.cos(sa) * base * 0.92 * stretch;
    final double by = s.y + math.sin(sa) * base * 0.72;
    final ui.Path sp = ui.Path()
      ..moveTo(bx - math.sin(sa) * 1.6, by + math.cos(sa) * 1.6)
      ..lineTo(bx + math.sin(sa) * 1.6, by - math.cos(sa) * 1.6)
      ..lineTo(bx + math.cos(sa) * len, by + math.sin(sa) * len * 0.8)
      ..close();
    g.drawPath(sp, fill(body.withValues(alpha: alpha * 0.9)));
    // and a detached droplet past the tip of some of them
    if (_n(s.seed * 61 + i) > 0.55) {
      final double dd = len * (1.25 + _n(s.seed * 71 + i) * 0.8);
      final double dr = 0.7 + _n(s.seed * 83 + i) * 1.6;
      g.drawOval(
        ui.Rect.fromCenter(
          center: ui.Offset(
              bx + math.cos(sa) * dd, by + math.sin(sa) * dd * 0.8),
          width: dr * 2,
          height: dr * 2.3,
        ),
        fill(body.withValues(alpha: alpha)),
      );
    }
  }

  // the wet highlight, offset up-left like a light source in the room
  // WET SHEEN, and only while it is wet. A dried mark has no specular at all,
  // so a screen of old marks with one bright fresh one tells you instantly
  // which thing just happened — without a single word of UI.
  if (dry < 0.85) {
    final double wet = 1 - dry / 0.85;
    final ui.Paint hi = ui.Paint()
      ..blendMode = ui.BlendMode.plus
      ..shader = ui.Gradient.radial(
        ui.Offset(s.x - s.r * 0.20, s.y - s.r * 0.26),
        s.r * 0.62,
        <ui.Color>[
          _kSheen.withValues(alpha: 0.20 * wet),
          _kSheen.withValues(alpha: 0),
        ],
      );
    g.save();
    g.clipPath(p);
    g.drawRect(
        ui.Rect.fromCircle(center: ui.Offset(s.x, s.y), radius: s.r * 1.4), hi);
    g.restore();
  }

  // AEROSOL. A high-energy impact throws a mist of sub-millimetre droplets
  // well beyond the mark. Individually invisible; collectively the difference
  // between "a shape" and "something hit this".
  final int mist = 10 + (_n(s.seed * 29) * 16).floor();
  for (var i = 0; i < mist; i++) {
    final double ma = axis + (_n(s.seed * 37 + i * 1.3) - 0.5) * 2.6;
    final double md = s.r * (1.4 + _n(s.seed * 43 + i * 2.1) * 4.2);
    final double mr = 0.28 + _n(s.seed * 47 + i * 3.3) * 0.62;
    g.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(
            s.x + math.cos(ma) * md * stretch, s.y + math.sin(ma) * md * 0.8),
        width: mr * 2,
        height: mr * 2.2,
      ),
      fill(body.withValues(alpha: (0.22 + dry * 0.30) * (1 - md / (s.r * 6)))),
    );
  }

  // satellite spatter — the small stuff that sells the impact
  final int sat = 2 + (s.seed * 4).floor();
  for (var i = 0; i < sat; i++) {
    final double a = _n(s.seed * 13 + i) * math.pi * 2;
    final double d = s.r * (1.3 + _n(s.seed * 5 + i * 2) * 2.4);
    final double rr1 = 0.7 + _n(s.seed * 3 + i * 5) * 1.7;
    g.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(s.x + math.cos(a) * d, s.y + math.sin(a) * d * 0.8),
        width: rr1 * 2,
        height: rr1 * 2.4,
      ),
      fill(_kDeep.withValues(alpha: 0.55 + dry * 0.35)),
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
  g.drawPath(drip, fill(body.withValues(alpha: alpha * 0.95)));

  // only the fat ones ever reach a bead
  if (w0 > s.r * 0.42 && s.run > 0.35) {
    final ui.Offset tip = lft.last;
    g.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(tip.dx + w0 * 0.16, tip.dy),
        width: w0 * 0.85,
        height: w0 * 1.15,
      ),
      fill(_lerpC(_kFresh, _kDried, dry * 0.6)
          .withValues(alpha: 0.55 + dry * 0.4)),
    );
  }
}

/// Cheap stable hash in 0..1. Deterministic per splat, so nothing crawls.
double _n(double x) {
  final double v = math.sin(x * 12.9898) * 43758.5453;
  return v - v.floorToDouble();
}
