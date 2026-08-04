// THE RIG, SIMULATED.
//
// The whole point of the rewrite is a number: the median stretch where the
// player has nothing to do. It was twenty seconds at every difficulty. These
// assert it is now about one, and that a harder night is BUSIER rather than
// merely more frequent.
//
// The operator below is deliberately NOT omniscient. The first version read
// every gauge perfectly and reacted in 0.30s, and under omniscience the design
// measured as balanced while producing NO DREAD AT ALL on nights 1 through 8 —
// a game tuned for a player who cannot exist. Divided attention is not a
// detail of this design, it IS the design, and a harness without it would have
// signed off on a game nobody can play.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/desk.dart';

class _Rng {
  _Rng(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return _s / 0x7FFFFFFF;
  }
}

/// What each entity chews on. The rig on its own is only half the game:
/// without anything biting the rails, dread flatlined and late nights were
/// survivable on autopilot.
const Map<String, (Rail, double)> kBites = <String, (Rail, double)>{
  'snow': (Rail.carrier, 2.6),
  'sleep': (Rail.modulation, 9.0),
  'vert': (Rail.plate, 7.0),
  'card': (Rail.modulation, -8.0),
};

class Night {
  Night(this.rig, this.actions, this.dead, this.peakDread, this.meanDread,
      this.mix);

  final Rig rig;
  final int actions;
  final List<double> dead;
  final List<double> deadAt = <double>[];
  final double peakDread;
  final double meanDread;
  final Map<String, int> mix;
  double meanStrain = 0, peakStrain = 0;

  double get actionsPerMin => actions / (rig.t / 60);
  double share(String k) => (mix[k] ?? 0) / actions;

  double get medianDead {
    if (dead.isEmpty) return 0;
    final s = List<double>.from(dead)..sort();
    return s[s.length ~/ 2];
  }

  double get worstDead =>
      dead.isEmpty ? 0 : dead.reduce((a, b) => a > b ? a : b);

  @override
  String toString() => 'acts ${actionsPerMin.toStringAsFixed(1)}/min  '
      'dead med ${medianDead.toStringAsFixed(2)}s  '
      'offAir ${rig.offAir.toStringAsFixed(0)}/${rig.ceiling.toStringAsFixed(0)}  '
      'trips ${rig.trips}  '
      'dread ${peakDread.toStringAsFixed(0)}/${meanDread.toStringAsFixed(0)}  '
      'strain ${meanStrain.toStringAsFixed(3)}/${peakStrain.toStringAsFixed(3)}  '
      'mix ${(<String>["up", "down", "mod", "entity", "log"]).map((k) => "$k ${(share(k) * 100).round()}%").join(" ")}  '
      '${rig.voided ? "VOID @${rig.t.toStringAsFixed(0)}s" : "held"}';
}

/// A competent operator with human hands and one pair of eyes.
Night playNight(int night,
    {double seconds = 8 * 60, int seed = 7717, double missRate = 0}) {
  final rig = Rig(night);
  final rng = _Rng(seed + night * 31);
  var nextArrival = 8.0;
  String? live;
  var liveFor = 0.0;
  final dead = <double>[];
  final deadStart = <double>[];
  final mix = <String, int>{};
  var actions = 0, idle = 0.0, cooldown = 0.0, notice = 0.0;
  var peak = 0.0, dreadSum = 0.0, strainSum = 0.0, strainPeak = 0.0;
  const dt = 1 / 30.0;

  void mark(String k) => mix[k] = (mix[k] ?? 0) + 1;

  while (rig.t < seconds && !rig.voided) {
    rig.bite.clear();
    if (live != null) {
      final b = kBites[live]!;
      rig.bite[b.$1] = b.$2;
      liveFor += dt;
    } else {
      nextArrival -= dt;
      if (nextArrival <= 0) {
        live = kBites.keys.elementAt((rng.next() * 4).floor() % 4);
        liveFor = 0;
        nextArrival = 11 + rng.next() * 9 - night * 0.35;
      }
    }
    rig.tick(dt, handsCommitted: cooldown > 0);
    if (rig.voided) break;
    if (rig.dread > peak) peak = rig.dread;
    dreadSum += rig.dread * dt;
    strainSum += rig.strain * dt;
    if (rig.strain > strainPeak) strainPeak = rig.strain;

    var acted = false;
    if (cooldown > 0) {
      cooldown -= dt;
    } else if (rig.wrongCount > 0 && notice > 0) {
      notice -= dt;
    } else {
      notice = 0.35 + 0.42 * (rig.wrongCount - 1).clamp(0, 4);
      if (live != null && liveFor > 0.9) {
        if (rng.next() < missRate) {
          final b = kBites[live]!;
          rig.attach(live, b.$1, b.$2.abs() * 0.30);
        }
        live = null;
        mark('entity');
        cooldown = 0.30;
        acted = true;
      } else if (rig.logDue <= 0) {
        rig.sign();
        mark('log');
        // Signing is a real commitment with both hands off the desk. It is the
        // one interruption you can SEE coming, and the dread of a scheduled
        // interruption is the price it charges everywhere else.
        cooldown = 1.9;
        acted = true;
      } else if (rig.plate > 88) {
        rig.trim(-1);
        mark('down');
        cooldown = 0.30;
        acted = true;
      } else if (rig.carrier < 56 && rig.plate < 86) {
        rig.trim(1);
        mark('up');
        cooldown = 0.30;
        acted = true;
      } else if (rig.modulation < 50 - kModGreen + 2) {
        rig.nudge(1);
        mark('mod');
        cooldown = 0.30;
        acted = true;
      } else if (rig.modulation > 50 + kModGreen - 2) {
        rig.nudge(-1);
        mark('mod');
        cooldown = 0.30;
        acted = true;
      } else if (rig.carrier > 70 && rig.plate > 62) {
        // running hotter than the night needs
        rig.trim(-1);
        mark('down');
        cooldown = 0.30;
        acted = true;
      }
    }

    if (acted) {
      actions++;
      if (idle > 0.05) {
        dead.add(idle);
        deadStart.add(rig.t - idle);
        idle = 0;
      }
    } else {
      idle += dt;
    }
  }
  if (idle > 0.05) {
    dead.add(idle);
    deadStart.add(rig.t - idle);
  }
  return Night(rig, actions, dead, peak, dreadSum / rig.t, mix)
    ..deadAt.addAll(deadStart)
    ..meanStrain = strainSum / rig.t
    ..peakStrain = strainPeak;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('READOUT', () {
    for (final n in <int>[1, 3, 5, 8, 12, 16, 20, 24, 28]) {
      // ignore: avoid_print
      print('night ${n.toString().padLeft(2)}: ${playNight(n)}');
    }
  });

  test('THE defect is gone: there is no dead air', () {
    // Shipped build: median 20s at EVERY night, worst 36-54s, and flat across
    // the whole career.
    for (final n in <int>[1, 3, 5, 8, 12, 16]) {
      final r = playNight(n);
      expect(r.medianDead, lessThan(3.0),
          reason: 'night $n median dead ${r.medianDead.toStringAsFixed(1)}s');
    }
  });

  test('and the career closes the holes it leaves early', () {
    // Asserted as a COUNT rather than as the single worst stretch, because the
    // worst is the wrong statistic and looking at the distribution is what
    // showed it: night 1 measures 24 separate stretches over six seconds and
    // night 16 measures 7, but their LONGEST are 13.5s and 10.8s — nearly the
    // same. A guard on the maximum would have read as "the career does not
    // close its holes", which is false; a guard on the median would have
    // missed both, at 2.4s and 1.1s.
    //
    // Night 1 is where the operator learns the desk and it is SUPPOSED to have
    // quiet in it. What must not happen — and what the shipped build did — is
    // the quiet still being there on night 16.
    int holes(Night n) => n.dead.where((d) => d > 6).length;
    final early = playNight(1);
    final late = playNight(16);
    expect(holes(late), lessThan(holes(early) / 2),
        reason: 'night 16 has ${holes(late)} stretches over six seconds '
            'against night 1\'s ${holes(early)} — the career is not closing '
            'them');
    expect(holes(late), lessThan(12),
        reason: 'night 16 still has ${holes(late)} holes over six seconds');
  });

  test('no single system wears the whole shift', () {
    // "you're supposed to be in multiple things" is a claim about the MIX, not
    // just about there being something to do, and the two are easy to confuse:
    // a night can have no dead air at all and still be one gauge wobbling.
    //
    // Drift used to be identical at every difficulty while drive work scaled
    // with the night's decay, so night 1 measured modulation at 60% of every
    // action against drive at 17%. The late game was four systems and the
    // early game was one — and the early game is exactly where a player
    // decides whether this is about a transmitter or about one needle.
    for (final n in <int>[1, 3, 5, 8, 12, 16]) {
      final r = playNight(n);
      final drive = r.share('up') + r.share('down');
      for (final e in <String, double>{
        'the drive': drive,
        'modulation': r.share('mod'),
        'the entities': r.share('entity'),
      }.entries) {
        expect(e.value, lessThan(0.62),
            reason: 'night $n spends ${(e.value * 100).round()}% of every '
                'action on ${e.key} alone');
      }
      expect(r.share('mod'), greaterThan(0.12),
          reason: 'night $n barely touches the modulation at all');
      expect(drive, greaterThan(0.15),
          reason: 'night $n barely touches the drive at all');
    }
  });

  test('a harder night is BUSIER, not merely louder', () {
    final a = playNight(1);
    final b = playNight(12);
    expect(b.actionsPerMin, greaterThan(a.actionsPerMin * 1.25),
        reason: 'night 12 asks ${b.actionsPerMin.toStringAsFixed(1)}/min '
            'against night 1 ${a.actionsPerMin.toStringAsFixed(1)}/min');
  });

  test('the player is asked for something every few seconds', () {
    // Shipped build: 2.6/min at every difficulty. The floor here is per-night
    // rather than flat, because an early night SHOULD be calm — the mistake
    // this whole rewrite exists to undo was a game that was equally empty at
    // every point in a career.
    const floors = <int, double>{1: 12, 5: 14, 12: 25, 20: 32};
    for (final e in floors.entries) {
      final r = playNight(e.key);
      expect(r.actionsPerMin, greaterThan(e.value),
          reason: 'night ${e.key} asks only '
              '${r.actionsPerMin.toStringAsFixed(1)}/min');
      expect(r.actionsPerMin, lessThan(75),
          reason: 'night ${e.key} asks ${r.actionsPerMin.toStringAsFixed(1)}'
              '/min, which is a typing test');
    }
  });

  test('NO KEY MAKES A NUMBER GO UP — drive is a dial, not a pump', () {
    // THE rule the first attempt broke. It had push() adding +13 carrier a
    // press, and counting actions showed push was 51-68% of everything the
    // operator did and rising: a clicker with a new name.
    //
    // Winding the dial to maximum and leaving it there must NOT be a winning
    // strategy — it must cook the transmitter.
    final r = Rig(3);
    for (var i = 0; i < 40; i++) {
      r.trim(1); // pin it at 100 and walk away
    }
    expect(r.drive, 100);
    for (var i = 0; i < 30 * 60 && !r.voided; i++) {
      r.tick(1 / 30.0);
    }
    expect(r.trips, greaterThan(0),
        reason: 'the transmitter can be pinned at full drive for a minute '
            'without consequence, which makes the dial a pump');
  });

  test('and running cold is not free either', () {
    // The other half of the dilemma: back the dial off to save the plate and
    // the drums turn instead. Neither extreme may be a dominant strategy.
    final r = Rig(3);
    for (var i = 0; i < 40; i++) {
      r.trim(-1);
    }
    for (var i = 0; i < 30 * 60 && !r.voided; i++) {
      r.tick(1 / 30.0);
    }
    expect(r.offAir, greaterThan(20),
        reason: 'the transmitter can be run cold for a minute for '
            '${r.offAir.toStringAsFixed(1)}s of ledger — there is no cost to '
            'hiding at the bottom of the dial');
  });

  test('the drums never run backward', () {
    // The score is a penalty counter. There is nothing to farm and no number
    // anywhere a player can make bigger — IN SPEC time raises the CEILING
    // instead, so the ledger stays monotonic.
    final r = Rig(2);
    var last = 0.0;
    for (var i = 0; i < 30 * 200; i++) {
      r.tick(1 / 30.0);
      expect(r.offAir, greaterThanOrEqualTo(last));
      last = r.offAir;
    }
  });

  test('holding it clean buys allowance back', () {
    final r = Rig(1);
    r.drive = 74; // a good operating point for an early night
    final before = r.ceiling;
    for (var i = 0; i < 30 * 90; i++) {
      r.tick(1 / 30.0);
      if (r.logDue <= 0) r.sign();
      if (r.modulation < 40) r.nudge(1);
      if (r.modulation > 60) r.nudge(-1);
    }
    expect(r.ceiling, greaterThan(before),
        reason: 'ninety clean seconds bought nothing');
  });

  test('a missed window leaves something that does not go away', () {
    // Every one of the three design judges asked for this independently. It is
    // what makes a night ACCUMULATE: in the shipped build a miss cost some
    // dread and the moment passed, so nothing a player did to themselves was
    // ever visible later and losing never felt like their own fault.
    final clean = playNight(8);
    final sloppy = playNight(8, missRate: 0.5);
    expect(sloppy.rig.attached.length, greaterThan(3),
        reason: 'nothing got its teeth in across a whole sloppy night');
    expect(sloppy.rig.offAir, greaterThan(clean.rig.offAir),
        reason: 'carrying ${sloppy.rig.attached.length} attachments cost the '
            'sloppy operator nothing on the ledger');
  });

  test('the night can be lost, and lost late', () {
    // Dying at three quarters of the way through is the near-miss the whole
    // "one more night" hook depends on, and it falls out of the mechanics
    // rather than being scripted.
    Night? died;
    for (final n in <int>[16, 20, 24, 28]) {
      final r = playNight(n);
      if (r.rig.voided) {
        died = r;
        break;
      }
    }
    expect(died, isNotNull, reason: 'no night in the career is ever lost');
    expect(died!.rig.t, greaterThan(8 * 60 * 0.4),
        reason: 'the licence went at ${died.rig.t.toStringAsFixed(0)}s — that '
            'is a beating, not a near miss');
  });

  test('dread breathes rather than pinning at either end', () {
    final easy = playNight(1);
    expect(easy.meanDread, lessThan(25), reason: 'night 1 should not terrify');
    final mid = playNight(12);
    expect(mid.peakDread, greaterThan(25),
        reason: 'night 8 never frightens anybody: peak '
            '${mid.peakDread.toStringAsFixed(0)}');
    expect(mid.meanDread, lessThan(mid.peakDread * 0.85),
        reason: 'dread sits at its peak instead of recovering: mean '
            '${mid.meanDread.toStringAsFixed(0)} against peak '
            '${mid.peakDread.toStringAsFixed(0)}');
  });

  test('THE RERUN uses your own hands, twelve seconds late', () {
    final r = Rig(3);
    const dt = 1 / 30.0;
    // twelve seconds of the operator winding the drive about
    for (var i = 0; i < 400; i++) {
      if (i % 40 == 0) r.trim(1);
      if (i % 97 == 0) r.trim(-1);
      if (r.logDue <= 0) r.sign();
      r.tick(dt);
    }
    expect(r.tape.length, greaterThan(8), reason: 'nothing reached the tape');
    final driveBefore = r.drive;
    r.ghosting = true;
    for (var i = 0; i < 200 && !r.voided; i++) {
      r.tick(dt);
    }
    expect(r.drive, isNot(driveBefore),
        reason: 'the operator took their hands off the desk and the dial did '
            'not move — the Rerun is replaying nothing');
  });

  test('the Rerun cannot sign the book for you', () {
    // An entity that does your paperwork is a helper.
    final r = Rig(3);
    const dt = 1 / 30.0;
    r.sign();
    for (var i = 0; i < 400; i++) {
      r.tick(dt);
    }
    final dueBefore = r.logDue;
    r.ghosting = true;
    for (var i = 0; i < 90 && !r.voided; i++) {
      r.tick(dt);
    }
    expect(r.logDue, lessThan(dueBefore),
        reason: 'the Rerun signed the book for the operator');
  });
}
