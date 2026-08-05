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
import 'dart:typed_data';
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

/// ONE MARK ON THE TUBE ITSELF.
///
/// Was an inline record, which meant it could not change: `age += dt` on an
/// immutable record is a rebuild-and-write-back of every mark every frame, and
/// a mark that cannot age cannot set, cannot darken and cannot ever stop being
/// liftable. Everything below is downstream of that one limitation.
class GlassMark {
  GlassMark(this.x, this.y, this.r, this.seed, this.a)
      : r0 = r,
        a0 = a;

  double x, y, r, a;

  /// Spawn values. [r0] is what bounds the smear — see [BloodLayer.tick].
  final double r0, a0, seed;

  double age = 0;

  /// House style, the same curve as [Splat.dry]. One drying constant for the
  /// whole game rather than two that drift apart.
  double get dry => (1 - math.exp(-age / 70)).clamp(0.0, 1.0);

  /// The optical area this mark is currently costing the picture, in px².
  double get optical => math.pi * (r * 0.5) * (r * 0.5) * a;
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
  final List<GlassMark> glass = <GlassMark>[];

  // --- THE CAP WAS A CONVEYOR -----------------------------------------------
  //
  // `while (glass.length > 26) glass.removeAt(0)` read as a saturation point
  // and behaved as a DELETE. Measured against the live feed: arrivals run
  // 1.93/s at minute one and 3.49/s at minute ten, so mean residence was
  // 26/3.49 = 7.4 SECONDS and everything older than that was annihilated. The
  // arrival rate had already risen 1.8x across those nine minutes and the cap
  // ate the entire increase — the material to escalate with was being
  // generated and thrown away, every seven seconds, forever.
  //
  // Rendered, the result was a mode that stopped changing at minute fourteen:
  //
  //   min  1  coverage 28.6%  damage 2.03%
  //   min  2  coverage 23.1%  damage 1.64%   <- went DOWN
  //   min 10  coverage 39.8%  damage 2.85%
  //   min 20  coverage 38.2%  damage 3.19%
  //   min 40  coverage 38.2%  damage 3.19%   <- identical to minute 20
  //
  // So the cap becomes a BOND. Nothing that lands on a tube leaves it except
  // down the glass or on a hand: a mark that retires does not vanish, it
  // stamps what is left of it into [crust], which has no ceiling anywhere in
  // its update path. What is DRAWN is clamped; what ACCUMULATES is not. Every
  // way of getting this wrong puts the ceiling on the accumulator.

  /// The permanent layer, as optical depth per cell over an 8x6 grid on the
  /// tube. UNBOUNDED BY CONSTRUCTION — there is deliberately no `min`, no
  /// `clamp` and no subtract-the-oldest anywhere that writes to it. The
  /// clamping happens once, in the painter.
  final Float32List crust = Float32List(kCells);

  static const int kGx = 8, kGy = 6, kCells = 48;

  /// 422 x 278 — consts.dart's kScr.
  static const double kScrArea = 117316.0;
  static const double kCellArea = kScrArea / kCells;

  /// How much of a retiring mark survives as permanent staining. The rest is
  /// what ran down the glass and off the bottom.
  static const double kBond = 0.55;

  /// Seconds a mark stays liftable. After this it has set, and a hand moves it
  /// rather than lifting it. Ten because it must be shorter than the old 7.4s
  /// conveyor was long — a mark has to survive its own replacement — and long
  /// enough that a player who reacts to a mark can still get it.
  static const double kSet = 10.0;

  /// Population bound. Does the same thing retirement does (bond, then
  /// remove), so no mechanism can be starved by it — the distinction that
  /// every version of this that failed got wrong.
  static const int kLive = 64;

  /// Running total of [crust], so `soil` and `isEmpty` are O(1) rather than
  /// O(48) on a path the painter and the sim both touch every frame.
  double _crustSum = 0;

  /// How deep into the session we are, written by the runtime. Logarithmic and
  /// unclamped — see anomalies.dart. Drives how much of each mark bonds.
  double deep = 0;

  /// THE INSTRUMENT: mean optical depth over the tube, 1.0 being one full
  /// opaque covering. No ceiling exists in its update path, which is the whole
  /// point — `glass.length` was pegged at a cap and read as "saturated" when
  /// it meant "capped", and it had been a tautology since 26 was written.
  double get soil {
    var s = _crustSum / kCells;
    for (final GlassMark m in glass) {
      s += m.optical / kScrArea;
    }
    return s;
  }

  int _cellAt(double x, double y) {
    final int gx =
        (((x - kScr.left) / kScr.width) * kGx).floor().clamp(0, kGx - 1);
    final int gy =
        (((y - kScr.top) / kScr.height) * kGy).floor().clamp(0, kGy - 1);
    return gy * kGx + gx;
  }

  /// Seventeen points on a fixed lattice inside the unit disc. Deterministic
  /// on purpose: a stamp that consumed rand() would make every seeded trace in
  /// the suite depend on how many marks happened to retire that frame.
  static const List<double> _diskA = <double>[
    0, 0.785, 1.571, 2.356, 3.142, 3.927, 4.712, 5.498, //
    0.393, 1.178, 1.963, 2.749, 3.534, 4.320, 5.105, 5.890,
  ];

  /// Spreads [optical] px² of bonded mass over the cells a disc of radius [r]
  /// at ([x],[y]) covers, then converts to per-cell optical DEPTH by dividing
  /// through by the cell area — which is what makes the crust term and the
  /// live term of [soil] the same unit and therefore addable.
  /// IT RUNS DOWN, and that is what stops the floor becoming a filter.
  ///
  /// Measured with a plain disc: by minute forty the ratio between the
  /// thickest and thinnest cell was 1.4x and every cell had passed the alpha
  /// clamp, so the whole tube was one flat 30% wash. That is the cap defect
  /// again, moved from the model into the render — the number kept climbing
  /// and the picture stopped changing at minute ten.
  ///
  /// A share of every mark is therefore laid into the cells BELOW it rather
  /// than around it. It is the right physics on a vertical piece of glass and
  /// it is the thing that gives the permanent layer structure: the tube grows
  /// vertical streaks that deepen for as long as the session lasts, instead of
  /// converging on a uniform grey.
  static const double kRunShare = 0.42;

  void _stamp(double x, double y, double r, double optical) {
    if (optical <= 0) return;
    _crustSum += optical / kCellArea;
    final double q = optical / kCellArea;

    final double disc = q * (1 - kRunShare) / 17.0;
    crust[_cellAt(x, y)] += disc;
    for (var i = 0; i < 16; i++) {
      final double rr = r * (i < 8 ? 0.55 : 0.85);
      crust[_cellAt(x + math.cos(_diskA[i]) * rr, y + math.sin(_diskA[i]) * rr)]
          += disc;
    }

    // The tail. Weighted toward the top of the run, because that is where a
    // run is fattest before it thins out and pins.
    const List<double> tail = <double>[0.34, 0.26, 0.19, 0.13, 0.08];
    for (var i = 0; i < tail.length; i++) {
      crust[_cellAt(x, y + r * (1.1 + i * 1.35))] += q * kRunShare * tail[i];
    }
    _crustDirty = true;
  }

  /// A mark stops being liftable and becomes part of the floor.
  void _bond(GlassMark m) {
    if (m.a <= 0.02) return;
    _stamp(m.x, m.y, m.r * 0.5, m.optical * kBond * (1 + deep * 0.30));
  }

  /// Something got on the glass. NIGHTMARE only.
  void addGlass(double force) {
    final int n = 2 + (force * 4).round();
    for (var i = 0; i < n; i++) {
      // REJECTION SAMPLING, BOUNDED AT FOUR TRIES so it can never spin. A mean
      // occlusion figure cannot tell a readable tube from one with a hole
      // punched through the entity's face; this refuses to stack a mark where
      // a cell is already near opaque, so the mess spreads into the clean.
      double x = 0, y = 0;
      for (var tryN = 0; tryN < 4; tryN++) {
        x = kScr.left + rand() * kScr.width;
        y = kScr.top + rand() * kScr.height;
        if (1 - math.exp(-_liveCell[_cellAt(x, y)]) <= kCellMax) break;
      }
      // A SLAP. Escalating VARIANCE rather than rate or mean size: a rare
      // double-size mark reads as the night getting worse and lands as a beat,
      // while contributing barely more ink than the ordinary ones. Raising the
      // mean instead just raises the odds of one unlucky mark eating the face
      // the player is trying to read, which is felt as unfairness.
      final bool slap = rand() < 0.06 + deep * 0.10;
      // CAPPED IN ABSOLUTE TERMS, at 28% of the tube's width. Looked at rather
      // than measured: without this a slapped top-of-range mark at minute
      // forty spawns at 190 and smears to 361 on a 422px tube, and the tube
      // reads as four big red circles instead of as filthy glass. Size is the
      // weakest escalation axis anyway — a bigger mean mark mostly raises the
      // odds of one unlucky mark eating the face the player is reading, which
      // is felt as unfairness rather than as pressure. The slap stays; only
      // how far it can run is bounded.
      final double r = math.min(kMarkMax,
          (14 + rand() * 46) * (0.6 + force) * (slap ? 2.0 : 1.0));
      final double a = 0.34 + force * 0.34;
      final double seed = rand();
      // PROPORTIONAL, NOT BANG-BANG.
      //
      // A hard `if (readOcc >= ceiling) divert` against a measurement that
      // refreshes every 0.12s and a feed running 13 marks a second is a relay,
      // and it behaved like one: everything diverted, the live marks aged out,
      // occlusion collapsed, arrivals resumed, repeat. Sampled at the minute
      // boundary that showed twelve live marks on a tube that should carry a
      // hundred — the tube went DARK AND STILL, which is the one thing this
      // mode must never be.
      //
      // Diverting with probability proportional to the overshoot settles at an
      // equilibrium instead of ringing, and costs the escalation metric
      // nothing either way: a diverted mark is bonded, not dropped.
      //
      // THE THIRD TERM IS THE ONE THAT MATTERS. A ceiling on MEAN occlusion is
      // satisfied by a tube that is evenly half-covered everywhere, with no
      // sample anybody can actually read through: measured, liveOcc sat
      // obediently at 0.28 while the fraction of the read band still clear
      // fell to 0.4%. What a player needs is not a good average, it is
      // SOMEWHERE TO LOOK, so the governor is told to keep some.
      final double over = math
          .max(
            math.max(
              (readOcc - kReadCeil) / 0.10,
              (liveOcc - kLiveCeil) / 0.10,
            ),
            (kClearMin - readClear) / 0.10,
          )
          .clamp(0.0, 1.0);
      if (over > 0 && rand() < over) {
        // NO ROOM LEFT IN THE PICTURE. It still landed — it goes straight to
        // the floor instead of into the layer a hand can lift.
        //
        // This is why the playability ceiling costs the escalation metric
        // nothing. The governor gates the LIVE list; `crust` never sees a
        // bound. By minute forty most of every arrival is being diverted
        // straight into the permanent layer, so `soil` keeps climbing while
        // what the player can actually see holds flat at the ceiling.
        _stamp(x, y, r * 0.5,
            math.pi * (r * 0.5) * (r * 0.5) * a * kBond * (1 + deep * 0.30));
        continue;
      }
      glass.add(GlassMark(x, y, r, seed, a));
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

  /// A hand goes across the tube. THIS ONLY RECORDS THE PATH — all of the
  /// erosion happens in [tick], against a swept-distance budget.
  ///
  /// It has to, and this is the single most load-bearing change in the file.
  /// wipe() takes no dt and is called once per PointerMoveEvent plus once per
  /// PointerDownEvent — up to about 120 times a second on a trackpad, against
  /// the "one pass" that every constant here was originally written for. The
  /// old code survived that only because its removal term was subtractive and
  /// small; anything multiplicative or accumulating is catastrophic at 120Hz
  /// (a 0.40-per-call retention is 1e-24 over half a second of drag) and every
  /// tuning number is meaningless until the rate is pinned. Path LENGTH is the
  /// same whether it is sampled at 60Hz or 120Hz, so that is what is budgeted.
  void wipe(double x, double y) {
    if (_hand.isNotEmpty) {
      final ui.Offset l = _hand.last;
      if ((l.dx - x).abs() < 6 && (l.dy - y).abs() < 6) return; // coalesce
    }
    if (_hand.length < 64) _hand.add(ui.Offset(x, y));
  }

  final List<ui.Offset> _hand = <ui.Offset>[];

  static const double kWipeR = 62.0;

  /// A teleporting pointer is worth one segment, not the whole jump.
  static const double kSegMax = 40.0;

  /// px/s — a palm held still is still scrubbing.
  static const double kDwell = 90.0;

  /// px/s — two crossings of a 422px tube per second, and the reason a
  /// pathological scrubber cannot outrun the arrivals.
  static const double kMaxSweep = 900.0;

  static const double kLiftRate = 0.0035;
  static const double kCrustTake = 0.0015;
  static const double kCrustLift = 0.22;
  static const double kDrag = 0.055;

  /// What the last tick's wiping actually bought, 0..1 — optical mass lifted
  /// over optical mass that was under the hand. This is the player's own
  /// question ("what did that get me?") as a number, and it falls as ~1/soil
  /// with no floor, which is how constraint 2 is honoured rather than merely
  /// asserted.
  double wipeYield = 0;

  void clear() {
    glass.clear();
    splats.clear();
    hands.clear();
    trail.clear();
    drips.clear();
    _hand.clear();
    _lastPoint = null;
    _handIdle = 0;
    wash = 0;
    // A Float32List is invisible to isEmpty, so a permanent layer that
    // survived startBroadcast()'s clear() would have shipped green.
    crust.fillRange(0, kCells, 0);
    _crustSum = 0;
    // One image is one image, but a mode with no ending is exactly where you
    // do not want to find out you were wrong about that.
    _crustImg?.dispose();
    _crustImg = null;
    _liveCell.fillRange(0, kCells, 0);
    readOcc = liveOcc = readWorst = 0;
    readClear = 1;
    wipeYield = 0;
    _crustDirty = true;
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

    _tickGlass(dt);
  }

  // --- the tube --------------------------------------------------------------

  void _tickGlass(double dt) {
    for (final GlassMark m in glass) {
      m.age += dt;
    }

    _erode(dt);

    // RETIREMENT IS UNCONDITIONAL AND TIME-BASED, which is the structural
    // point. Any exit a mark can decline to satisfy leaves most of the tube
    // immortal — a 62px hand reaches pi*62^2 / 117316 = 10.3% of the glass and
    // the player only ever wipes where they are looking, so ~90% of marks are
    // never touched by anything. These retire on their own.
    for (var i = glass.length - 1; i >= 0; i--) {
      final GlassMark m = glass[i];
      if (m.age > kSet || m.a <= 0.02) {
        _bond(m);
        glass.removeAt(i);
      }
    }
    while (glass.length > kLive) {
      _bond(glass[0]);
      glass.removeAt(0);
    }

    _measureAge += dt;
    if (_measureAge >= kMeasureEvery) {
      _measureAge = 0;
      measureRead();
    }
  }

  /// Where the hand was when the last tick ended.
  ///
  /// THE PATH DOES NOT RESTART EVERY FRAME. Measuring travel only within one
  /// tick's buffer throws away the distance between the last point of the
  /// previous frame and the first point of this one — and a 60Hz mouse against
  /// a 60fps loop delivers exactly ONE point per tick, so that is not an edge
  /// case, it is the common case: every stroke would have measured as a palm
  /// resting on the glass. Caught by the wipe-degradation test reading a lift
  /// of 0.061 where it should read 0.9.
  ui.Offset? _lastPoint;
  double _handIdle = 0;

  /// All of the hand's work for this frame, budgeted on distance travelled.
  void _erode(double dt) {
    wipeYield = 0;
    if (_hand.isEmpty) {
      // A hand that has been off the glass for a moment starts a fresh stroke
      // rather than teleporting across the tube when it comes back.
      _handIdle += dt;
      if (_handIdle > 0.25) _lastPoint = null;
      return;
    }
    _handIdle = 0;

    final List<ui.Offset> path = <ui.Offset>[?_lastPoint, ..._hand];
    _lastPoint = _hand.last;

    var swept = kDwell * dt;
    for (var i = 1; i < path.length; i++) {
      swept += math.min(kSegMax, (path[i] - path[i - 1]).distance);
    }
    swept = math.min(swept, kMaxSweep * dt);

    var under = 0.0, lifted = 0.0;
    final int segs = math.max(1, path.length - 1);
    final double share = swept / segs;

    for (var s = 0; s < segs; s++) {
      final ui.Offset a = path[s];
      final ui.Offset b = path.length > 1 ? path[s + 1] : a;
      final double len = (b - a).distance;
      final double ux = len > 0.001 ? (b.dx - a.dx) / len : 0.0;
      final double uy = len > 0.001 ? (b.dy - a.dy) / len : 0.0;

      for (final GlassMark m in glass) {
        final double dx = m.x - b.dx, dy = m.y - b.dy;
        final double d2 = dx * dx + dy * dy;
        if (d2 > kWipeR * kWipeR) continue;
        final double w = 1 - math.sqrt(d2) / kWipeR;

        // THE 0.10 FLOOR IS CONSTRAINT 2 AS A CONSTANT. A blood-slick palm has
        // lost FRICTION, not the ability to move liquid — whatever just landed
        // can always be taken off, and what is permanent is the floor
        // underneath it. At grip 0.06 a full pass still lifts enough that nine
        // passes clear a mark: bad value the player cannot decline, which is
        // the mode's thesis stated in the wrist instead of in a meter.
        final double lift = kLiftRate * (0.10 + 0.90 * grip) * share * w;
        final double take = math.min(m.a, lift);
        under += m.optical;
        lifted += take * math.pi * (m.r * 0.5) * (m.r * 0.5);
        m.a -= take;

        // ALONG THE HAND, not radially outward. Pushing marks away from a
        // point builds a starburst; a hand moving left to right drags
        // everything left to right, and parallel streaks are the single most
        // recognisable thing about a smeared windscreen.
        m.x = (m.x + ux * kDrag * (1 - grip) * share)
            .clamp(kScr.left + 4, kScr.right - 4);
        m.y = (m.y + uy * kDrag * (1 - grip) * share)
            .clamp(kScr.top + 4, kScr.bottom - 4);
        // SPREADING CONSERVES. The same blood over more glass is thinner
        // blood, so growing r must thin a by the same area factor — and this
        // is not a nicety, it is the difference between a wipe helping and a
        // wipe helping the mess. Optical cost goes as r², so growth alone
        // multiplied a mark's eventual bonded mass by up to 3.6x: measured,
        // an operator who wiped for forty minutes finished with MORE permanent
        // staining (302) than one who never lifted a finger (258). Wiping made
        // it worse, which inverts the entire mechanic.
        //
        // BOUNDED too. Unclamped, r reached 357 from a spawn of 61 in forty
        // touches — painted at 179px on a 278px tube, spilling 40px past the
        // bezel, and the glass pass used to be drawn outside the room clip.
        final double rNew = math.min(
            m.r0 * 1.9, m.r * (1 + (1 - grip) * 0.10 * share / kWipeR));
        m.a *= (m.r * m.r) / (rNew * rNew);
        m.r = rNew;
      }

      // THE CRUST. Sub-linear with NO FLOOR: `take` goes to zero as thickness
      // grows, so soil is monotone under ANY wipe rate including a 120Hz
      // scrubber. A constant floor here would make drain scale with input
      // frequency while inflow does not, and a fast enough hand would invert
      // the sign of the entire curve.
      final int ci = _cellAt(b.dx, b.dy);
      if (crust[ci] > 0) {
        final double take =
            math.min(crust[ci], kCrustTake * grip * share / (1 + crust[ci]));
        crust[ci] -= take;
        // WHAT THE HAND IS UP AGAINST INCLUDES THE FLOOR. Counting only the
        // live layer flattered the wipe badly — by minute forty almost
        // everything under the palm is bonded, so a yield computed over live
        // marks alone reports what the hand does to the 3% it can still move
        // and says nothing about the 97% it cannot.
        under += crust[ci] * kCellArea;
        // Mostly moved, not removed. The rest of it is on the hand now.
        final int cj = _cellAt(
            (b.dx + ux * 40).clamp(kScr.left, kScr.right - 1),
            (b.dy + uy * 40).clamp(kScr.top, kScr.bottom - 1));
        final double moved = take * (1 - kCrustLift * grip);
        crust[cj] += moved;
        lifted += (take - moved) * kCellArea;
        _crustSum -= take - moved;
        _crustDirty = true;
      }
    }

    wipeYield = under > 0 ? (lifted / under).clamp(0.0, 1.0) : 0.0;
    _hand.clear();
  }

  // --- what the player can still read ---------------------------------------

  static const int kSx = 32, kSy = 8, kSamples = kSx * kSy;
  static const double kMeasureEvery = 0.12;
  /// How fast bonded thickness turns into opacity.
  ///
  /// 0.020 puts the permanent layer at its 0.30 alpha ceiling at a thickness
  /// of ~18, which the reference feed reaches around minute fourteen — early
  /// enough that the first quarter hour has a real coverage curve, late enough
  /// that the tube is not a brown filter by minute three.
  static const double kOptical = 0.020;
  /// The permanent floor's share of the light, and it is deliberately the
  /// SMALLER share.
  ///
  /// At 0.30 against a 0.44 read ceiling the floor ate two thirds of the
  /// budget and the governor starved the live layer to twelve marks — the tube
  /// went dark and STOPPED BEING BUSY, which is worse than either. The live
  /// layer is the one the player actually fights; the floor is what makes the
  /// fight unwinnable, and it does that job at 0.22 just as well.
  static const double kBakedMax = 0.22;
  static const double kCellMax = 0.78;

  /// The largest a single mark may ever spawn — 28% of the tube's width.
  static const double kMarkMax = 118.0;

  /// The governor setpoint, on TOTAL occlusion of the read band.
  ///
  /// 0.44 and not the 0.50 it was first set to: measured, 0.50 realised as
  /// 0.56-0.60 because the check runs at 4Hz and marks already alive keep
  /// growing after it. The gap between setpoint and outcome is the thing to
  /// tune, not the setpoint's resemblance to the target.
  /// 0.42, and the number it SETTLES at is 0.50 — proportional control has a
  /// steady-state offset and the setpoint is not the outcome. Set to 0.48 it
  /// realised 0.56, over the legibility line. Tune the outcome, not the
  /// constant's resemblance to the target.
  static const double kReadCeil = 0.42;

  /// AND a second gate on the LIVE layer alone.
  ///
  /// A total-occlusion ceiling can be satisfied entirely by permanent crust,
  /// at which point the live layer is free to blanket whatever is left — which
  /// measured as 6% of the read band still clear at minute thirty. The player
  /// has to be able to find the picture under the mess, and this is the term
  /// that guarantees it.
  static const double kLiveCeil = 0.28;

  /// How much of the read band must stay legible. THE playability guarantee —
  /// the other two ceilings are about averages and this one is about whether
  /// there is anywhere left to look.
  ///
  /// 0.38 as a setpoint realises a floor of ~0.15 across seeds; at 0.30 it
  /// realised 0.086, because the governor is proportional and lags a 0.12s
  /// measurement. Again: tune the outcome, not the constant.
  static const double kClearMin = 0.38;

  double _measureAge = kMeasureEvery;
  bool _crustDirty = true;
  ui.Image? _crustImg;

  final Float32List _liveCell = Float32List(kCells);

  /// 1 - mean transmittance over the read band, 0..1.
  double readOcc = 0;

  /// Live-only occlusion, which is what the governor gates on — the permanent
  /// floor must not be able to starve the live layer out of existence.
  double liveOcc = 0;

  /// Fraction of samples the live layer has left essentially clear.
  double readClear = 1;

  /// Worst single sample. A mean cannot see a hole punched through one face.
  double readWorst = 0;

  /// Composites the layer over the read band and reports what is left of the
  /// picture.
  ///
  /// Accumulation is OVER-COMPOSITE held as a transmittance product, not a sum
  /// and not a max. A sum is unbounded and unphysical and would be `glass 26`
  /// wearing a new hat; a max under-reports exactly the layering that smearing
  /// produces. A product is bounded in [0,1], is literally what the painter
  /// does, and can only flatten when the tube is genuinely opaque — so a flat
  /// trace always means a real problem rather than a measurement artefact.
  void measureRead() {
    _liveCell.fillRange(0, kCells, 0);
    for (final GlassMark m in glass) {
      _liveCell[_cellAt(m.x, m.y)] += m.optical / kCellArea;
    }

    var occ = 0.0, live = 0.0, clear = 0.0, worst = 0.0;
    for (var sy = 0; sy < kSy; sy++) {
      final double py = kRead.top + (sy + 0.5) * kRead.height / kSy;
      for (var sx = 0; sx < kSx; sx++) {
        final double px = kRead.left + (sx + 0.5) * kRead.width / kSx;
        final double tBaked = 1 - bakedAlphaAt(px, py);
        var tLive = 1.0;
        for (final GlassMark m in glass) {
          final double rr = m.r * 0.5 + 2.2; // painted radius plus the blur
          final double dx = m.x - px, dy = m.y - py;
          final double d2 = dx * dx + dy * dy;
          if (d2 > rr * rr) continue; // squared — no sqrt in the reject path
          tLive *= 1 - m.a * (1 - math.sqrt(d2) / rr);
        }
        final double o = 1 - tBaked * tLive;
        occ += o;
        live += 1 - tLive;
        if (1 - tLive <= 0.10) clear += 1;
        if (o > worst) worst = o;
      }
    }
    readOcc = occ / kSamples;
    liveOcc = live / kSamples;
    readClear = clear / kSamples;
    readWorst = worst;
  }

  /// The permanent layer's alpha at a point, bilinear over [crust].
  ///
  /// THIS is where the clamp lives, and it is the only one: the accumulator
  /// underneath it has no ceiling, so the mode keeps getting worse long after
  /// the picture has stopped getting darker.
  double bakedAlphaAt(double x, double y) {
    final double fx =
        (((x - kScr.left) / kScr.width) * kGx - 0.5).clamp(0.0, kGx - 1.0);
    final double fy =
        (((y - kScr.top) / kScr.height) * kGy - 0.5).clamp(0.0, kGy - 1.0);
    final int x0 = fx.floor(), y0 = fy.floor();
    final int x1 = math.min(x0 + 1, kGx - 1), y1 = math.min(y0 + 1, kGy - 1);
    final double tx = fx - x0, ty = fy - y0;
    final double c = crust[y0 * kGx + x0] * (1 - tx) * (1 - ty) +
        crust[y0 * kGx + x1] * tx * (1 - ty) +
        crust[y1 * kGx + x0] * (1 - tx) * ty +
        crust[y1 * kGx + x1] * tx * ty;
    return math.min(kBakedMax, 1 - math.exp(-c * kOptical));
  }

  /// Rebaked only when the field has actually moved, and at most four times a
  /// second. Null when there is nothing on the floor yet.
  ui.Image? _crustImage() {
    if (_crustSum <= 1e-9) {
      _crustImg?.dispose();
      _crustImg = null;
      return null;
    }
    if (_crustImg != null && !_crustDirty) return _crustImg;
    _crustDirty = false;
    final ui.Image? old = _crustImg;
    _crustImg = bakeImageSync(kGx, kGy, (ui.Canvas c) {
      final ui.Paint p = ui.Paint();
      for (var i = 0; i < kCells; i++) {
        final double d = crust[i];
        if (d <= 0) continue;
        // ONE clamp, here, on what is DRAWN. Nothing upstream of this has a
        // ceiling — that is the entire design.
        final double a = math.min(kBakedMax, 1 - math.exp(-d * kOptical));
        // and it keeps DARKENING after the alpha has topped out, which is the
        // axis that carries escalation once coverage cannot
        p.color = ui.Color.lerp(
                _kGlassDried, _kCrustDeep, 1 - math.exp(-d * 0.004))!
            .withValues(alpha: a);
        c.drawRect(
            ui.Rect.fromLTWH(
                (i % kGx).toDouble(), (i ~/ kGx).toDouble(), 1, 1),
            p);
      }
    });
    old?.dispose();
    return _crustImg;
  }

  void dispose() {
    _crustImg?.dispose();
    _crustImg = null;
  }

  bool get isEmpty =>
      splats.isEmpty &&
      hands.isEmpty &&
      glass.isEmpty &&
      _crustSum <= 1e-9 &&
      wash <= 0.002;
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
  g.save();
  // Clipped to the tube, which is both the fix and the correct fiction: these
  // marks are ON the glass, so one overhanging the bezel by 35px was always
  // wrong. Unclamped smearing used to put a 179px mark on a 278px tube.
  g.clipRect(kScr);

  // THE PERMANENT LAYER, in ONE draw call at any session length.
  //
  // 8x6 pixels, 192 bytes, stretched over the tube with hardware bilinear —
  // so the grid is invisible and the cost is flat at minute 1 and at minute
  // 120. A full-resolution crust texture was the obvious alternative and it is
  // 1.9MB per bake in a mode with no ending, plus a 0.6-1.5ms rasteriser
  // hitch that can land on a jump scare.
  final ui.Image? crustImg = b._crustImage();
  if (crustImg != null) {
    g.drawImageRect(
        crustImg,
        ui.Rect.fromLTWH(0, 0, BloodLayer.kGx.toDouble(),
            BloodLayer.kGy.toDouble()),
        kScr,
        smoothPaint());
  }

  // THE LIVE MARKS.
  //
  // The blur stays exactly as it was. Measured on this repo's backend: 26
  // per-mark MaskFilter circles cost 0.331ms, the same 26 with no blur at all
  // cost 0.190ms, the same 26 inside one saveLayer(ImageFilter.blur) cost
  // 0.558ms and as a single multi-oval Path 0.630ms. drawCircle plus
  // MaskFilter.normal hits Skia's analytic circle blur — one quad, no render
  // target. Batching only pays above about sixty marks. What DID need fixing
  // was allocating two Paints per mark per frame; there are now two, hoisted.
  final ui.Paint body = ui.Paint()
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.2);
  final ui.Paint tail = ui.Paint();
  for (final GlassMark s in b.glass) {
    // fresh is bright and thin, set is brown and flat — the same cue the
    // splat layer already uses, so one mark tells you how old it is
    body.color = ui.Color.lerp(_kGlassFresh, _kGlassDried, s.dry)!
        .withValues(alpha: s.a);
    g.drawCircle(ui.Offset(s.x, s.y), s.r * 0.5, body);
    // it does not sit still on a vertical piece of glass
    final double run = 8 + s.seed * 34 * s.a;
    tail.color = rgba(84, 6, 6, s.a * 0.75);
    g.drawRect(
        ui.Rect.fromLTWH(s.x - s.r * 0.10, s.y, s.r * 0.20, run), tail);
  }
  g.restore();
}

const ui.Color _kGlassFresh = ui.Color(0xFF800A0A);
const ui.Color _kGlassDried = ui.Color(0xFF4A0C0A);

/// The floor, once it has been there long enough to go black.
const ui.Color _kCrustDeep = ui.Color(0xFF1C0606);

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
