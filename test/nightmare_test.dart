// TEN MINUTES OF NIGHTMARE, MINUTE BY MINUTE.
//
// The claim NIGHTMARE makes on the front desk is GRAPHIC · NO 06:00 · WIPE THE
// GLASS YOURSELF, and the consent gate makes three more: sustained gore that
// does not stop, no ending, and a hand that has to keep working. Those are
// measurable claims, so they are measured here rather than asserted in a
// commit message.
//
// This started as a scratch script and found three defects in a build I had
// already called finished:
//
//                            before        after
//   marks on glass, min 1     0-2          15      (absent for seven minutes)
//   wipe grip at min 10       0.80         0.34
//   dread at min 1            0            32
//
// A scratch script that finds three defects and is then deleted is a scratch
// script that will let the fourth one through, so it lives here now.
//
// The saturation curve is driven by sessionSeconds() — REAL time at the desk,
// not game time — which is why gNow is injectable. Nothing but tests sets it.

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/wallclock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'operator.dart';

/// One minute's readout.
class Min {
  Min(this.minute, this.dread, this.marks, this.grip, this.smear, this.offAir,
      this.lost);

  final int minute;
  final double dread;

  /// Marks currently ON the glass the player is reading through.
  final int marks;

  /// How well a wipe still works. 1.0 is a clean hand.
  final double grip;
  /// How far the runs have crept down the glass, 0..1.
  final double smear;

  /// Seconds off air so far. The licence goes when it reaches the ceiling.
  final double offAir;
  final bool lost;

  @override
  String toString() => 'min ${minute.toString().padLeft(2)}  '
      'dread ${dread.toStringAsFixed(0).padLeft(3)}  '
      'glass ${marks.toString().padLeft(2)}  '
      'grip ${grip.toStringAsFixed(2)}  '
      'run ${smear.toStringAsFixed(2)}  '
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
List<Min> traceNightmare({int minutes = 10, int seed = 20260805}) {
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
  for (var m = 1; m <= minutes; m++) {
    while (t < m * 60 && !r.lost) {
      mindTheDesk(r);
      r.tick(dt);
      final a = r.active;
      if (a != null && a.t > 1.2) r.pressCounter(a.def.counter);

      // A PLAYER WIPES. Not perfectly and not for free — a wipe is a hand
      // leaving the desk, and the glass is 422x278, so one pass does not
      // clear it. Four passes a second across the middle of the tube is
      // roughly what somebody does when they cannot read the needles.
      if (r.blood.glass.length > 4 && (t * 30).round() % 8 == 0) {
        r.blood.wipe(kScr.left + kScr.width * 0.5, kScr.top + kScr.height * 0.5);
      }

      t += dt;
      wall = t0.add(Duration(milliseconds: (t * 1000).round()));
    }
    out.add(Min(m, s.dread, r.blood.glass.length, r.blood.grip,
        _meanRun(r), r.rig.offAir, r.lost));
    if (r.lost) break;
  }
  return out;
}

/// How far the marks currently on the glass have run, averaged. A number that
/// climbs is blood that is still moving after it landed.
double _meanRun(AnomalyRuntime r) {
  final runs = r.blood.splats.map((p) => p.run).toList();
  if (runs.isEmpty) return 0;
  return runs.reduce((a, b) => a + b) / runs.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('READOUT — ten minutes of NIGHTMARE', () {
    for (final Min m in traceNightmare()) {
      // ignore: avoid_print
      print(m);
    }
  });

  test('the blood is there from the first minute and never leaves', () {
    // THE DEFECT THIS CATCHES. The glass measured 0-2 marks and was empty for
    // seven of the first ten minutes — a mode whose whole promise is that the
    // screen gets dirty, with a clean screen. A player who agreed to
    // SUSTAINED GORE and got a tidy tube was mis-sold.
    final t = traceNightmare();
    expect(t.first.marks, greaterThan(8),
        reason: 'minute 1 had only ${t.first.marks} marks on the glass');
    for (final Min m in t) {
      expect(m.marks, greaterThan(4),
          reason: 'the glass came clean at minute ${m.minute}');
    }
  });

  test('the hand stops working — a wipe at minute 10 is not a wipe at minute 1',
      () {
    // Wipe efficiency has to decay or the mechanic is a chore rather than a
    // losing fight. Measured 0.80 at minute 10, which is not a fight.
    final t = traceNightmare();
    expect(t.first.grip, greaterThan(0.85));
    expect(t.last.grip, lessThan(0.45),
        reason: 'grip was still ${t.last.grip.toStringAsFixed(2)} after ten '
            'minutes — the hand never tires');
  });

  test('dread is already high in the first minute and does not come down', () {
    // NIGHTMARE has a rising floor under dread; an ordinary night starts at 0
    // and earns it. Measured 0 at minute 1 and single digits until minute 6,
    // which made the opening of NIGHTMARE calmer than a night shift.
    final t = traceNightmare();
    expect(t.first.dread, greaterThan(25),
        reason: 'NIGHTMARE opened at dread ${t.first.dread.toStringAsFixed(0)}');
    for (var i = 1; i < t.length; i++) {
      expect(t[i].dread, greaterThan(t[i - 1].dread - 12),
          reason: 'dread fell away at minute ${t[i].minute}');
    }
    expect(t.last.dread, greaterThan(t.first.dread),
        reason: 'ten minutes in NIGHTMARE left the operator no worse off');
  });

  test('it does not end', () {
    // The gate promises no 06:00. A shift that quietly stops at dawn would
    // make that a lie, and endless is the one claim a player cannot check
    // without sitting there.
    final t = traceNightmare(minutes: 12);
    final done = t.where((Min m) => m.lost);
    expect(done, isEmpty,
        reason: 'NIGHTMARE ended on its own at minute '
            '${done.isEmpty ? -1 : done.first.minute}');
    expect(t.length, 12);
  });
}
