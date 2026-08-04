// Every night card, simulated end to end.
//
// A card pulls six dials at once and they interact — OPEN LINE shortens the
// gap AND the window, A QUIET NIGHT cuts output while raising dread. Reading
// the numbers tells you nothing about whether the resulting night is a night.
// So each one gets played twice, headless: once well, once not at all.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/nights.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _forNight(int night) {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.night = night;
  // a station roughly appropriate to the night, so the quota is not absurd
  s.prod['rabbit'] = 60;
  s.prod['dipole'] = 45;
  s.prod['vhf'] = 30;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

/// One whole night. [play] false means the player never touches a key.
({int manifests, int banished, double peakDread, bool lost}) _night(
  int night, {
  required bool play,
}) {
  // Pinned, because these assertions are about a CARD's effect on a night and
  // an unseeded run turns each one into a coin-flip — the RATINGS SWEEP guard
  // passed alone and failed in a batch with no code change between them.
  seedRandom(night * 7919 + (play ? 1 : 2));
  final s = _forNight(night);
  final r = AnomalyRuntime(s);
  r.startBroadcast();

  var t = 0.0, peak = 0.0, manifests = 0;
  var wasActive = false;
  const dt = 1 / 60.0;
  while (t < 21 * 60 && !r.lost) {
    mindTheDesk(r);
        r.tick(dt);
    t += dt;
    if (s.dread > peak) peak = s.dread;
    final a = r.active;
    final now = a != null;
    if (now && !wasActive) manifests++;
    wasActive = now;
    if (play && a != null && a.stage == 1 && a.p > 0.3) {
      r.pressCounter(a.def.counter);
    }
  }
  return (
    manifests: manifests,
    banished: s.stats.banished,
    peakDread: peak,
    lost: r.lost
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('night one draws no card — the tutorial shift is the printed game', () {
    expect(cardForNight(1).id, 'none');
    final s = _forNight(1);
    expect(segQuota(s), closeTo(kRundown[0].quota, 0.01));
  });

  test('the deck never repeats itself two nights running', () {
    for (var n = 2; n < 2 + kNightCards.length * 3; n++) {
      expect(cardForNight(n).id, isNot(cardForNight(n + 1).id),
          reason: 'nights $n and ${n + 1} drew the same card');
    }
  });

  test('a career walks the whole deck before any card comes back', () {
    final seen = <String>{};
    for (var n = 2; n < 2 + kNightCards.length; n++) {
      seen.add(cardForNight(n).id);
    }
    expect(seen.length, kNightCards.length,
        reason: 'the stride must be coprime with the deck size');
  });

  test('every card is a trade, never a free ride or a pure tax', () {
    for (final c in kNightCards) {
      final gifts = <double>[
        c.output, c.rp, c.banishPay, c.window, c.gap, 1 / c.quota, 1 / c.dread,
      ].where((v) => v > 1.0001).length;
      final bills = <double>[
        c.output, c.rp, c.banishPay, c.window, c.gap, 1 / c.quota, 1 / c.dread,
      ].where((v) => v < 0.9999).length;
      expect(gifts, greaterThan(0), reason: '${c.nm} is pure tax');
      expect(bills, greaterThan(0), reason: '${c.nm} is a free ride');
    }
  });

  group('played well, every card is a night you can hold', () {
    for (var i = 0; i < kNightCards.length; i++) {
      final night = i + 2;
      final card = cardForNight(night);
      test('${card.nm} (night $night)', () {
        final r = _night(night, play: true);
        expect(r.manifests, greaterThan(8),
            reason: '${card.nm} ran out of anomalies — the night went dead');
        expect(r.banished, greaterThan(6),
            reason: '${card.nm}: answering correctly stopped working');
      });
    }
  });

  group('left alone, every card still takes the night off you', () {
    for (var i = 0; i < kNightCards.length; i++) {
      final night = i + 2;
      final card = cardForNight(night);
      test('${card.nm} (night $night)', () {
        final r = _night(night, play: false);
        expect(r.peakDread, greaterThan(25),
            reason: '${card.nm} cannot generate pressure — no horror in it');
      });
    }
  });
}
