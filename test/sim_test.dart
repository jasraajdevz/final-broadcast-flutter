// Regression guards for the two ways this game has already died once.
//
// Both were found by simulating whole nights headless, not by reading the code
// — the numbers looked reasonable in isolation and were catastrophic together.
// Keep them.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/bots.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

GameState _seeded() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 40;
  s.prod['dipole'] = 30;
  s.prod['vhf'] = 20;
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('automation cannot carry an unattended night', () {
    // A maxed LIBRARIAN with every tape logged, and not one key press. Before
    // assistBanish() this survived to 06:00 and banked 37 RP on its own; with
    // the full six-bot rack, two unattended nights banked 14,706.
    final s = _seeded();
    for (final a in kAnoms) {
      s.seen[a.id] = true;
      s.ups['bot.beat.${a.id}'] = true;
    }
    s.prod['bot.libr'] = 3;

    final r = AnomalyRuntime(s);
    final bots = BotRuntime.of(s, r);
    r.startBroadcast();

    var t = 0.0;
    const dt = 1 / 30.0;
    while (t < 21 * 60 && !r.lost) {
      r.tick(dt);
      bots.tick(dt);
      t += dt;
    }

    // Both of these are structural consequences of assistBanish restoring
    // lifetimeSig and streak, so they hold every run. Whether the night ends in
    // SIGNAL LOST is NOT asserted — the gap has +/-16% jitter, so it is a
    // coin-flip and would make this test flaky. It does lose most runs.
    expect(s.stats.streak, 0,
        reason: 'a bot must never build the player-earned streak');
    expect(rpGain(s), lessThan(5),
        reason: 'an unattended night must not bank meaningful prestige');
  });

  test('dread still rises across a played night', () {
    // The calm window used to FREEZE the countdown rather than consume it, so
    // protection was additive to the gap. A whole night peaked at 3.2 dread —
    // SIGNAL LOST was unreachable and the revive/prestige loop was dead.
    final s = _seeded();
    final r = AnomalyRuntime(s);
    r.startBroadcast();

    var t = 0.0, peak = 0.0;
    const dt = 1 / 30.0;
    while (t < 21 * 60 && !r.lost) {
      r.tick(dt);
      if (s.dread > peak) peak = s.dread;
      t += dt;
    }

    expect(peak, greaterThan(25),
        reason: 'dread must be able to climb, or there is no horror');
    expect(s.stats.banished + s.stats.scared, greaterThan(8),
        reason: 'anomalies must still actually arrive');
  });

  test('a quota measures output DURING its segment, not cumulatively', () {
    final s = _seeded();
    final r = AnomalyRuntime(s);
    r.startBroadcast();

    var t = 0.0;
    const dt = 1 / 30.0;
    var seg = segIndex(s);
    var sawReset = false;
    while (t < 21 * 60 && !r.lost && !sawReset) {
      final before = s.segSig;
      r.tick(dt);
      t += dt;
      if (segIndex(s) != seg) {
        seg = segIndex(s);
        if (s.segSig < before) sawReset = true;
      }
    }
    expect(sawReset, isTrue,
        reason: 'segSig must reset when the segment advances');
  });

  test('the night keeps spawning after the player starts winning', () {
    // The guaranteed head of an ALL CLEAR window hard-blocks beginWarn(). It is
    // granted on every banish, so if it ever stops draining the game silently
    // stops dead after the first kill — measured at the time: 1 manifest per
    // 21-minute night, no error, no test failure.
    final s = _seeded();
    final r = AnomalyRuntime(s);
    r.startBroadcast();

    var t = 0.0, manifests = 0;
    var wasActive = false;
    const dt = 1 / 60.0;
    while (t < 21 * 60 && !r.lost) {
      r.tick(dt);
      t += dt;
      final now = r.active != null;
      if (now && !wasActive) manifests++;
      wasActive = now;
      // play well: always answer correctly, so calm is granted constantly
      final a = r.active;
      if (a != null && a.stage == 1 && a.p > 0.3) r.pressCounter(a.def.counter);
    }
    expect(manifests, greaterThan(12),
        reason: 'a well-played night must not run out of anomalies');
    expect(s.stats.banished, greaterThan(10));
  });
}
