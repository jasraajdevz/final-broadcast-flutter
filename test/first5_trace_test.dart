// TEMPORARY diagnostic — first-five-minutes trace. Delete after the report.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _fresh() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  return s;
}

/// Runs `seconds` of game time inside FakeAsync so pushDelayed / _later fire.
void _trace(String label, {required bool clicks, required bool buys}) {
  // ignore: avoid_print
  print('\n===== $label =====');
  fakeAsync((fa) {
    final s = _fresh();
    final r = AnomalyRuntime(s);
    final seen = <Toast>{};
    var t = 0.0;
    const dt = 1 / 30.0;
    String? lastAir;
    var lastActive = '';
    var strikeAcc = 0.0;

    void drain() {
      for (final x in s.toasts.items) {
        if (seen.add(x)) {
          // ignore: avoid_print
          print('  t=${t.toStringAsFixed(1)}s  TOAST[${x.kind.name}] ${x.msg}');
        }
      }
    }

    r.startBroadcast();
    fa.elapse(const Duration(milliseconds: 1));
    drain();

    while (t < 300) {
      mindTheDesk(r);
            r.tick(dt);
      // FakeAsync needs real elapse for Future.delayed callbacks
      fa.elapse(const Duration(milliseconds: 33));
      t += dt;

      if (clicks) {
        strikeAcc += dt;
        // a curious player: ~3 strikes/sec once they discover it, from t=6s
        if (t > 6 && strikeAcc > 1 / 3) {
          strikeAcc = 0;
          r.tuneStrike(400, 300);
        }
      }
      if (buys) {
        for (final p in kProducers) {
          final n = 1;
          if (s.sig >= bulkCost(s, p, n) && (s.prod[p.id] ?? 0) < 40) {
            buyProducer(s, p, n);
            break;
          }
        }
      }
      drain();

      final air = r.airLabel;
      if (air != lastAir) {
        lastAir = air;
        // ignore: avoid_print
        print('  t=${t.toStringAsFixed(1)}s  AIR -> $air'
            '   sig=${fmt(s.sig)} seg=${fmt(s.segSig)}/${fmt(segOf(s).quota)}'
            ' clock=${shiftClock(s)} dread=${s.dread.toStringAsFixed(1)}');
      }
      final act = r.active?.def.nm ?? '';
      if (act != lastActive) {
        lastActive = act;
        if (act.isNotEmpty) {
          final a = r.active!;
          // ignore: avoid_print
          print('  t=${t.toStringAsFixed(1)}s  ** MANIFEST $act '
              'counter=${kCounterBy[a.def.counter]!.nm}(key ${kCounterBy[a.def.counter]!.key}) '
              'window=${a.window.toStringAsFixed(1)}s masked=${a.masked} '
              'first-sighting-intensity=${a.intensity}');
        }
      }
      if (r.lost) {
        // ignore: avoid_print
        print('  t=${t.toStringAsFixed(1)}s  !! LOST');
        break;
      }
    }
    // ignore: avoid_print
    print('  --- after ${t.toStringAsFixed(0)}s: sig=${fmt(s.sig)} '
        'clock=${shiftClock(s)} seg=${segOf(s).nm} '
        'segSig=${fmt(s.segSig)}/${fmt(segOf(s).quota)} quotaMet=${quotaMet(s)} '
        'stalled=${s.stalled} dread=${s.dread.toStringAsFixed(1)} '
        'banished=${s.stats.banished} scared=${s.stats.scared} '
        'seen=${s.seen.length}/8 tuneStrikes=${s.tune.strikes}');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first five minutes — player never discovers the tube', () {
    _trace('NO CLICKS, NO BUYS', clicks: false, buys: false);
  });

  test('first five minutes — player clicks but never presses a key', () {
    _trace('CLICKS + BUYS, NEVER PRESSES A COUNTER KEY',
        clicks: true, buys: true);
  });

  test('economy at t=0', () {
    final s = _fresh();
    final r = AnomalyRuntime(s);
    // ignore: avoid_print
    print('\ntuneYield at 0 producers, 0 rp = ${tuneYield(s, r)}');
    // ignore: avoid_print
    print('cost of first RABBIT EARS = ${costOf(s, kProducers[0])}');
    // ignore: avoid_print
    print('strikes needed for first rabbit = '
        '${(costOf(s, kProducers[0]) / tuneYield(s, r)).ceil()}');
    // ignore: avoid_print
    print('first gap: mean=${anomIntervalMean(s, 0)}  '
        'window=${banishWindow(s)}  telegraph=${telegraph(s)}');
    // ignore: avoid_print
    print('unlocked anoms at depth 0: '
        '${unlockedAnoms(s).map((a) => "${a.nm}->${kCounterBy[a.counter]!.nm}").join(", ")}');
    // ignore: avoid_print
    print('segment 0 quota = ${kRundown[0].quota}, seconds of clock per seg = '
        '${60 * kMinReal}');
  });
}
