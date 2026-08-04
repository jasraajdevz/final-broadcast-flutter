// The CARRIER LOCK. The most-repeated verb in the game used to be flat: heat
// saturated after four strikes and paid nothing, so several hundred strikes a
// night all felt identical. These guard that it now has an arc.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('holding a rhythm escalates the payout, and stopping loses it', () {
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    final r = AnomalyRuntime(s);
    r.startBroadcast();

    final flat = tuneYield(s, r);
    expect(s.tune.tier, 0);

    // keep striking: the lock should climb all four steps
    for (var i = 0; i < 60; i++) {
      r.tuneStrike(kScr.center.dx, kScr.center.dy);
      mindTheDesk(r);
      r.tick(1 / 30.0);
    }
    expect(s.tune.tier, 4, reason: 'a sustained rhythm reaches full lock');
    expect(tuneYield(s, r), greaterThan(flat * 2.5),
        reason: 'full lock must actually pay — it is the reason to hold it');

    // stop, and it walks back down rather than dumping to zero
    final atTop = s.tune.tier;
    for (var i = 0; i < 60; i++) {
      mindTheDesk(r);
      r.tick(1 / 30.0);
    }
    expect(s.tune.tier, lessThan(atTop), reason: 'the lock decays when idle');
    expect(s.tune.tier, greaterThanOrEqualTo(0));
  });

  test('a fresh night starts unlocked', () {
    final s = GameState();
    final r = AnomalyRuntime(s);
    r.startBroadcast();
    for (var i = 0; i < 40; i++) {
      r.tuneStrike(kScr.center.dx, kScr.center.dy);
      mindTheDesk(r);
      r.tick(1 / 30.0);
    }
    expect(s.tune.tier, greaterThan(0));
    s.tune.reset();
    expect(s.tune.tier, 0);
    expect(s.tune.tierMult, 1.0);
  });
}
