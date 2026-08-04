// EVERY UPGRADE DESCRIPTION IS A PROMISE THE PLAYER PAYS FOR.
//
// This exists because four of them became lies in the space of one commit.
//
// When the producer economy came out, the station equipment was still selling
// signal — "+30% signal output", "+60% while a quota is unmet", "segment
// output can no longer be restated" — describing multipliers on a currency
// that nothing spends and a quota that no longer exists. Rewriting the SENTENCES
// to describe the new game and leaving the EFFECTS alone made it strictly
// worse: a stale description is merely out of date, and a lie is a thing the
// player hands over eight hundred billion for and does not receive.
//
// Three of them were lies for a subtler reason, and only an audit found them:
//
//   LEAD LINING said "jumpscares steal half as much" and halved a SIGNAL loss.
//   True in the letter, empty in fact, because the theft was of nothing.
//
//   TAPE VAULT said "offline signal accrual while tab is away" — a mechanic
//   that only means anything in an idle game, paying in the same dead
//   currency. It was the one upgrade whose old effect had no honest
//   translation, so it was given a new effect rather than a new sentence.
//
//   TUBE PREHEAT, SILVER HALIDE and SIGNAL COMPRESSOR each did real work on
//   the rig AND still applied a hidden signal multiplier underneath. A second
//   secret effect is not a bonus; it is the reason the printed one cannot be
//   trusted.
//
// So: every upgrade in the table must measurably change the thing it claims
// to. Not "has a call site" — a call site is what all twelve of them had while
// four were lying.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/desk.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

GameState _station({List<String> ups = const <String>[]}) {
  seedRandom(4242);
  final s = GameState()..night = 3;
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  for (final u in ups) {
    s.ups[u] = true;
  }
  return s;
}

/// Runs a rig forward with the runtime applying the installed equipment.
Rig _run(GameState s, {int frames = 90}) {
  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();
  for (var i = 0; i < frames; i++) {
    r.tick(1 / 30.0);
  }
  return r.rig;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every upgrade in the table has a description', () {
    for (final u in kUpgrades) {
      expect(u.ds.trim(), isNotEmpty, reason: '${u.nm} promises nothing');
    }
  });

  test('no description still sells the economy that was deleted', () {
    // The words that were true in the clicker and are lies in this game.
    const gone = <String>[
      'signal output',
      'offline signal',
      'segment output',
      'quota',
    ];
    for (final u in kUpgrades) {
      final d = u.ds.toLowerCase();
      for (final phrase in gone) {
        expect(d.contains(phrase), isFalse,
            reason: '${u.nm} still promises "$phrase", which nothing in the '
                'game has done since the producers came out');
      }
    }
  });

  test('TUBE PREHEAT actually cools the plate', () {
    final off = _run(_station());
    final on = _run(_station(ups: <String>['preheat']));
    expect(on.plateCoolMul, greaterThan(off.plateCoolMul));
    expect(on.plate, lessThan(off.plate),
        reason: 'the plate ran at ${on.plate.toStringAsFixed(1)} with the '
            'preheat installed against ${off.plate.toStringAsFixed(1)} without');
  });

  test('SILVER HALIDE actually makes the carrier track faster', () {
    final off = _station();
    final on = _station(ups: <String>['halide']);
    final ra = AnomalyRuntime(off, audio: const NullAudio())..startBroadcast();
    final rb = AnomalyRuntime(on, audio: const NullAudio())..startBroadcast();
    // wind both dials up and see which needle gets there first
    for (var i = 0; i < 8; i++) {
      ra.trimDrive(1);
      rb.trimDrive(1);
    }
    for (var i = 0; i < 30; i++) {
      ra.tick(1 / 30.0);
      rb.tick(1 / 30.0);
    }
    expect(rb.rig.carrier, greaterThan(ra.rig.carrier),
        reason: 'the carrier reached ${rb.rig.carrier.toStringAsFixed(1)} with '
            'the halide against ${ra.rig.carrier.toStringAsFixed(1)} without');
  });

  test('SIGNAL COMPRESSOR actually slows the modulation drift', () {
    final off = _run(_station(), frames: 200);
    final on = _run(_station(ups: <String>['comp']), frames: 200);
    expect(on.driftMul, lessThan(off.driftMul));
    expect((on.modulation - 50).abs(), lessThan((off.modulation - 50).abs()),
        reason: 'the needle sat ${(on.modulation - 50).abs().toStringAsFixed(1)}'
            ' off the mark with the compressor and '
            '${(off.modulation - 50).abs().toStringAsFixed(1)} without');
  });

  test('CARRIER HALO actually widens the licence', () {
    final off = _run(_station());
    final on = _run(_station(ups: <String>['halo']));
    expect(on.ceiling - off.ceiling, closeTo(20.0, 0.01),
        reason: 'the halo bought ${(on.ceiling - off.ceiling)} seconds, not 20');
  });

  test('TAPE VAULT actually files for you', () {
    // Its old effect had no honest translation, so it got a new one.
    expect(vaultLogPeriod(_station()), kLogPeriod);
    expect(vaultLogPeriod(_station(ups: <String>['vault'])),
        greaterThan(kLogPeriod * 1.4));
    expect(offlineGrant(_station(ups: <String>['vault'])), 0,
        reason: 'the vault is still accruing a currency nothing spends');
  });

  test('FAILSAFE RELAY actually bleeds dread faster', () {
    final off = _run(_station());
    final on = _run(_station(ups: <String>['failsafe']));
    expect(on.recoveryScale, greaterThan(off.recoveryScale * 1.9),
        reason: 'the relay promises twice as fast and delivers '
            '${(on.recoveryScale / off.recoveryScale).toStringAsFixed(2)}x');
  });
}
