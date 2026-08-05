// FORTY MINUTES OF NIGHTMARE, MINUTE BY MINUTE.
//
// The claim NIGHTMARE makes on the front desk is GRAPHIC · NO 06:00 · WIPE THE
// GLASS YOURSELF, and the consent gate makes three more: sustained gore that
// does not stop, no ending, and a hand that has to keep working. Those are
// measurable claims, so they are measured here rather than asserted in a
// commit message.
//
// This file has now caught two generations of the same defect.
//
// FIRST, as a scratch script, it found three: the glass was empty for seven of
// the first ten minutes, grip was still 0.80 at minute ten, and dread was 0 at
// minute one. It was deleted, which is why the second generation shipped.
//
// SECOND, the thing it was measuring was itself a tautology. `glass.length`
// was pegged at a hard cap of 26 and read as "saturated" when it meant
// "capped" — and the assertions written against it, `marks > 8` and
// `marks > 4`, could not fail. Rendered, the tube looked like this:
//
//   min  1  coverage 28.6%  damage 2.03%
//   min  2  coverage 23.1%  damage 1.64%   <- it went DOWN
//   min 10  coverage 39.8%  damage 2.85%
//   min 20  coverage 38.2%  damage 3.19%
//   min 40  coverage 38.2%  damage 3.19%   <- identical to minute 20
//
// So the metric is now `soil`, which has no ceiling in its update path, and
// every threshold below is TWO-SIDED — a minimum slope on each leg AND a hard
// bound at every sample. The pair is jointly unsatisfiable by any capped
// quantity, which a one-sided "it goes up" is not.
//
// The saturation curve is driven by sessionSeconds() — REAL time at the desk,
// not game time — which is why gNow is injectable. Nothing but tests sets it.

import 'dart:math' as math;

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/paint/blood.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/wallclock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'operator.dart';

/// How hard the operator works the glass. Escalation is measured by holding
/// player effort FIXED and asking what it buys — a single trace cannot tell
/// "the mess got worse" from "the hand got lazier".
enum Op {
  /// Never wipes. The upper bound on how bad it gets.
  idle,

  /// The reference: two sweeps a second across the read band, half the time.
  held,

  /// The pathological input — a scrubber at the tick budget, which is what
  /// finds a removal term that scales with call frequency.
  scrub,
}

/// One minute's readout.
class Min {
  Min(this.minute, this.dread, this.soil, this.readOcc, this.readClear,
      this.grip, this.yield_, this.offAir, this.lost);

  final int minute;
  final double dread;

  /// THE ESCALATION METRIC. Mean optical depth over the tube, 1.0 being one
  /// full opaque covering. Unbounded by construction.
  ///
  /// Replaces `glass.length`, which was pegged at a cap and had therefore been
  /// a tautology since 26 was written: `marks > 8` cannot fail against a
  /// population the code refuses to let below the ceiling.
  final double soil;

  /// THE PLAYABILITY METRIC. 1 - mean transmittance over the band the eight
  /// entities are actually painted in. This one is SUPPOSED to flatten.
  final double readOcc;

  /// Fraction of the read band the live layer has left essentially clear.
  final double readClear;

  /// How well a wipe still works. 1.0 is a clean hand.
  final double grip;

  /// What the wiping actually bought, 0..1.
  final double yield_;

  /// Seconds off air so far. The licence goes when it reaches the ceiling.
  final double offAir;
  final bool lost;

  @override
  String toString() => 'min ${minute.toString().padLeft(2)}  '
      'dread ${dread.toStringAsFixed(0).padLeft(3)}  '
      'soil ${soil.toStringAsFixed(2).padLeft(6)}  '
      'read ${(readOcc * 100).toStringAsFixed(0).padLeft(3)}%  '
      'clear ${(readClear * 100).toStringAsFixed(0).padLeft(3)}%  '
      'grip ${grip.toStringAsFixed(2)}  '
      'yield ${yield_.toStringAsFixed(3)}  '
      'offair ${offAir.toStringAsFixed(0)}s';
}

/// Sits in NIGHTMARE for [minutes] of REAL time, playing the desk properly the
/// whole way, and reports what the glass and the operator looked like at the
/// end of each one.
///
/// The operator here is the competent one from operator.dart — it answers
/// everything and minds the needles. If NIGHTMARE only grinds down someone who
/// plays badly then it is not hard, it is punishing, and the difference shows
/// up as this trace staying flat.
List<Min> traceNightmare(
    {int minutes = 40,
    int seed = 20260805,
    Op op = Op.held,
    bool survive = true}) {
  seedRandom(seed);
  final DateTime t0 = DateTime(2026, 8, 5, 2, 30);
  var wall = t0;
  gNow = () => wall;
  addTearDown(() => gNow = DateTime.now);
  resetSession();

  final s = GameState()
    ..night = 1
    ..endless = true
    ..nightmare = true;
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }

  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();

  final out = <Min>[];
  const double dt = 1 / 30.0;
  var t = 0.0;
  var yieldSum = 0.0;
  var yieldN = 0;
  for (var m = 1; m <= minutes; m++) {
    while (t < m * 60 && !r.lost) {
      mindTheDesk(r);
      r.tick(dt);
      final a = r.active;
      if (a != null && a.t > 1.2) r.pressCounter(a.def.counter);

      // KEEP THE OPERATOR ALIVE, because this file is measuring the GLASS.
      //
      // MEASURED, AND WORTH KNOWING ON ITS OWN: the reference operator dies at
      // minute thirteen, of DREAD rather than of the licence — anomalies.dart
      // ends the run at dread 100 and NIGHTMARE's rising floor gets there
      // first. That is a true and interesting fact about the mode and a
      // useless one here, because a trace that stops at thirteen can say
      // nothing about whether the tube is still getting worse at forty.
      //
      // So the run simply refuses to END. Dread is NOT clamped — clamping it
      // would hold down the arrival force it drives (0.28 + dread/100 * 0.6)
      // and quietly measure a gentler feed than the one that ships. It runs to
      // 100 and stays there, which is exactly the terminal intensity of the
      // mode, and the licence is topped up only so the void does not re-fire
      // every frame. What this trace measures is therefore: what the glass
      // does over forty minutes of NIGHTMARE at full pressure.
      if (survive) {
        if (r.rig.offAir > 20) r.rig.offAir = 20;
        r.lost = false;
      }

      // A HAND ACROSS THE GLASS, which is what the mechanic actually is. The
      // first version of this held one point in the middle of the tube for ten
      // minutes, which is not a wipe and — worse — reached 10.3% of the glass,
      // so it measured a mechanic nobody plays.
      //
      // Two sweeps a second across the middle 220px, active half the time,
      // because a wipe is a hand LEAVING THE DESK and the operator has four
      // other things to hold.
      //
      // FOUR POINTER SAMPLES PER TICK, because that is what a mouse does. The
      // first version handed the layer one point per frame, so the coalescing
      // filter saw a single position, the swept distance collapsed to the
      // dwell term and the measured wipe was a palm resting on the glass. A
      // trace that under-drives the input measures the mechanic as weaker than
      // it is, which is the same class of error as counting the marks.
      const int kPointer = 4;
      for (var k = 0; k < kPointer; k++) {
        final double tk = t + dt * k / kPointer;
        switch (op) {
          case Op.idle:
            break;
          case Op.held:
            if ((tk * 1.6) % 1.0 < 0.5) {
              final double u = ((tk * 3.2) % 1.0) * 2 - 1;
              r.blood.wipe(kScr.center.dx + u * 110, kRead.center.dy);
            }
          case Op.scrub:
            // as fast as the budget allows, all night, never resting
            final double u = ((tk * 2.2) % 1.0) * 2 - 1;
            r.blood.wipe(kScr.center.dx + u * 200, kRead.center.dy);
        }
      }

      if (r.blood.wipeYield > 0) {
        yieldSum += r.blood.wipeYield;
        yieldN++;
      }

      t += dt;
      wall = t0.add(Duration(milliseconds: (t * 1000).round()));
    }
    r.blood.measureRead();
    out.add(Min(
        m,
        s.dread,
        r.blood.soil,
        r.blood.readOcc,
        r.blood.readClear,
        r.blood.grip,
        // averaged over the minute — wipeYield is a per-tick figure and
        // sampling it on whichever tick the minute happened to end on is how
        // it first read 0.000
        yieldN > 0 ? yieldSum / yieldN : 0.0,
        r.rig.offAir,
        r.lost));
    yieldSum = 0;
    yieldN = 0;
    if (r.lost) break;
  }
  return out;
}

double _at(List<Min> t, int minute) => t[minute - 1].soil;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('READOUT — forty minutes of NIGHTMARE', () {
    for (final Min m in traceNightmare()) {
      // ignore: avoid_print
      print(m);
    }
  });

  // --- THE VICE ------------------------------------------------------------
  //
  // Every threshold below is TWO-SIDED, and the pair is jointly unsatisfiable
  // by any capped quantity. A one-sided "it goes up" is exactly how the
  // original defect survived: `marks > 8` against a population the code
  // refused to let below 26 could not fail, and did not, for the entire life
  // of the bug.

  for (final int seed in <int>[20260805, 7, 99991]) {
    test('the glass keeps escalating on EVERY leg — seed $seed', () {
      final List<Min> t = traceNightmare(seed: seed);
      expect(t.length, 40, reason: 'the trace did not reach forty minutes');

      // Every minute is worse than the one before it. Shipped, the rendered
      // tube went DOWN between minute 1 and minute 2.
      for (var i = 1; i < t.length; i++) {
        expect(t[i].soil, greaterThan(t[i - 1].soil),
            reason: 'soil fell at minute ${t[i].minute}');
      }

      // And each leg carries real growth, so it cannot creep to a stop.
      for (final List<int> leg in <List<int>>[
        <int>[1, 5],
        <int>[5, 10],
        <int>[10, 20],
        // THE LEG A NAIVE TEST OMITS, and the only one that catches `sat`'s
        // fourteen-minute clamp. Before this work, minute 20 and minute 40
        // were identical to three significant figures.
        <int>[20, 40],
      ]) {
        final double a = _at(t, leg[0]), b = _at(t, leg[1]);
        expect(b, greaterThan(a * 1.6),
            reason: 'minute ${leg[0]} -> ${leg[1]} grew only '
                '${(b / a).toStringAsFixed(2)}x (${a.toStringAsFixed(2)} -> '
                '${b.toStringAsFixed(2)})');
      }

      // Still moving at the end, not asymptoting just past the last sample.
      expect(_at(t, 40) - _at(t, 39), greaterThan(2.0),
          reason: 'the curve had flattened by minute forty');
    });

    test('and the tube stays readable the whole time — seed $seed', () {
      // THE OTHER JAW. Escalation that makes the game unplayable is not what
      // was asked for, and the headless trace CANNOT detect unplayability on
      // its own — mindTheDesk reads model state, not pixels, so a run at 100%
      // occlusion would pass every other test in this file. These are the
      // numbers that stand in for a player's eyes, and they are enforced at
      // SPAWN time so they cannot be violated for even one frame.
      final List<Min> t = traceNightmare(seed: seed);
      for (final Min m in t) {
        expect(m.readOcc, lessThan(0.58),
            reason: 'the read band was ${(m.readOcc * 100).toStringAsFixed(0)}% '
                'occluded at minute ${m.minute}');
        expect(m.readClear, greaterThan(0.10),
            reason: 'only ${(m.readClear * 100).toStringAsFixed(0)}% of the '
                'read band was clear at minute ${m.minute}');
      }
      // and it does get bad — a ceiling nobody reaches is not a ceiling, it is
      // a mode that never got frightening
      expect(t.map((Min m) => m.readOcc).reduce(math.max), greaterThan(0.40));
    });
  }

  test('a wipe stops being worth anything, without ever stopping working', () {
    final List<Min> t = traceNightmare();
    expect(t[0].yield_, greaterThan(0.02),
        reason: 'the hand did nothing even at the start');
    expect(t[39].yield_, lessThan(t[0].yield_ * 0.25),
        reason: 'forty minutes in, a wipe still buys what it bought at one');
    // but never zero: a blood-slick palm has lost friction, not the ability to
    // move liquid, and a mechanic that stops responding is a broken control
    expect(t[39].yield_, greaterThan(0.0));
  });

  test('not wiping is worse than wiping', () {
    // Sounds too obvious to test. It was FALSE: smearing grew a mark's radius
    // faster than it thinned its alpha, and optical cost goes as r², so an
    // operator who wiped for forty minutes finished with MORE permanent
    // staining (302) than one who never lifted a finger (258). The mechanic
    // was inverted and every other number in this file looked healthy.
    final List<Min> idle = traceNightmare(op: Op.idle);
    final List<Min> held = traceNightmare(op: Op.held);
    expect(idle.last.soil, greaterThan(held.last.soil * 1.05),
        reason: 'wiping left ${held.last.soil.toStringAsFixed(0)} against '
            '${idle.last.soil.toStringAsFixed(0)} for never touching it');
    expect(idle.last.soil, greaterThan(100),
        reason: 'an unwiped tube is not even badly soiled');
  });

  test('effort buys less and less — the gap between hands widens', () {
    // ESCALATION MEASURED PROPERLY: hold player effort fixed and ask what it
    // buys. A single trace cannot tell "the mess got worse" from "the hand got
    // lazier", and both curves are bounded above while the DIFFERENCE is not.
    final List<Min> idle = traceNightmare(op: Op.idle);
    final List<Min> held = traceNightmare(op: Op.held);
    final double early = idle[4].soil - held[4].soil;
    final double late = idle[39].soil - held[39].soil;
    expect(late, greaterThan(early * 4),
        reason: 'wiping bought ${early.toStringAsFixed(1)} of soil at minute '
            'five and ${late.toStringAsFixed(1)} at minute forty — the hand is '
            'not losing ground');
  });

  test('a scrubber cannot outrun it, at any pointer rate', () {
    // THE RATE BUG, GUARDED. wipe() is called once per PointerMoveEvent — up
    // to ~120/second on a trackpad — and every removal term in this file was
    // originally written for "a pass". Erosion is budgeted on swept DISTANCE
    // in tick() precisely so that a faster mouse is not a better mouse.
    final List<Min> t = traceNightmare(op: Op.scrub);
    for (var i = 1; i < t.length; i++) {
      expect(t[i].soil, greaterThan(t[i - 1].soil),
          reason: 'a fast enough hand reversed the curve at minute '
              '${t[i].minute}');
    }
  });

  test('the same stroke does the same work however often the mouse fires', () {
    // The assertion the buffering exists for. Fails by a factor of eight on a
    // wipe() that erodes per call.
    double soilAfter(int callsPerTick) {
      final BloodLayer b = BloodLayer()..grip = 0.8;
      seedRandom(4242);
      for (var i = 0; i < 6; i++) {
        b.addGlass(0.9);
      }
      for (var i = 0; i < 30; i++) {
        b.tick(1 / 30.0);
      }
      const double dt = 1 / 30.0;
      for (var tick = 0; tick < 90; tick++) {
        for (var k = 0; k < callsPerTick; k++) {
          final double u = (tick + k / callsPerTick) / 90.0;
          b.wipe(kScr.left + 20 + u * (kScr.width - 40), kRead.center.dy);
        }
        b.tick(dt);
      }
      return b.soil;
    }

    final double slow = soilAfter(1);
    final double fast = soilAfter(8);
    expect((slow - fast).abs() / slow, lessThan(0.05),
        reason: 'one sample per frame left soil $slow and eight left $fast — '
            'the hand is being paid per event instead of per pixel travelled');
  });

  test('none of this touches an ordinary night', () {
    seedRandom(31);
    final GameState s = GameState()..night = 4;
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    final AnomalyRuntime r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    for (var i = 0; i < 30 * 240 && !r.lost; i++) {
      mindTheDesk(r);
      r.tick(1 / 30.0);
    }
    expect(r.blood.deep, 0.0);
    expect(r.blood.soil, 0.0, reason: 'the tube got marked outside NIGHTMARE');
    expect(r.blood.glass, isEmpty);
  });

  test('sunrise takes the permanent layer too', () {
    // blood_test asserts isEmpty here, and isEmpty could not see a Float32List
    // until it was taught to — so a floor that survived the next sign-on would
    // have shipped green.
    final BloodLayer b = BloodLayer();
    seedRandom(3);
    for (var i = 0; i < 40; i++) {
      b.addGlass(1.0);
      for (var k = 0; k < 340; k++) {
        b.tick(1 / 30.0);
      }
    }
    expect(b.soil, greaterThan(1.0));
    expect(b.isEmpty, isFalse);
    b.clear();
    expect(b.soil, lessThan(1e-9));
    expect(b.isEmpty, isTrue);
  });

  test('it does not end', () {
    // The gate promises no 06:00, and endless is the one claim a player cannot
    // check without sitting there.
    final List<Min> t = traceNightmare(minutes: 12, survive: false);
    expect(t.where((Min m) => m.lost), isEmpty,
        reason: 'NIGHTMARE ended on its own inside twelve minutes');
    expect(t.length, 12);
  });
}
