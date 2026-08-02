// TEMPORARY PROBE 2 — delete after reading.
import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('how much of a night comes from CLICKING?', () {
    for (final cps in <double>[0, 1, 3, 5, 8]) {
      final s = GameState();
      for (final p in kProducers) {
        s.prod[p.id] = 0;
      }
      final r = AnomalyRuntime(s);
      r.signedOn = true;
      r.scheduleNext();
      var t = 0.0;
      const dt = 1 / 30.0;
      var clickAcc = 0.0;
      var fromClicks = 0.0;
      var banishes = 0;
      var heatSum = 0.0;
      var frames = 0;
      while (t < 21 * 60 && !r.lost) {
        r.tick(dt);
        // an ideal player: always presses the right key the instant it appears
        final a = r.active;
        if (a != null && !(a.masked && a.stage == 0)) {
          r.pressCounter(a.def.counter);
          banishes++;
        } else if (a != null) {
          r.pressCounter('cut');
        }
        clickAcc += cps * dt;
        while (clickAcc >= 1) {
          clickAcc -= 1;
          fromClicks += tuneYield(s, r);
          r.tuneStrike(400, 300);
        }
        // spend everything on the cheapest affordable tier, greedily
        for (var i = kProducers.length - 1; i >= 0; i--) {
          final p = kProducers[i];
          while (s.sig >= costOf(s, p) * 3) {
            if (!buyProducer(s, p, 1)) break;
          }
        }
        heatSum += s.tune.heat;
        frames++;
        t += dt;
      }
      // ignore: avoid_print
      print('PROBE cps=$cps  lifetime=${s.lifetimeSig.toStringAsFixed(0)}  '
          'sig=${s.sig.toStringAsFixed(0)}  rate=${sigRate(s, r).toStringAsFixed(0)}/s  '
          'fromClicks=${fromClicks.toStringAsFixed(0)}  banishes=$banishes  '
          'rp=${rpGain(s)}  avgHeat=${(heatSum / frames).toStringAsFixed(2)}');
    }
  });

  test('how many toasts fire in a night, and what do they say?', () {
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 40;
    s.prod['dipole'] = 30;
    final r = AnomalyRuntime(s);
    r.signedOn = true;
    r.scheduleNext();
    final seen = <String>[];
    var t = 0.0;
    const dt = 1 / 30.0;
    // shadow the bus so we capture everything, including evictions
    var lastLen = 0;
    while (t < 6 * 60 && !r.lost) {
      r.tick(dt);
      final a = r.active;
      if (a != null && !(a.masked && a.stage == 0)) {
        r.pressCounter(a.def.counter);
      }
      if (s.toasts.items.length > lastLen) {
        seen.add(s.toasts.items.last.msg);
      }
      lastLen = s.toasts.items.length;
      t += dt;
    }
    // ignore: avoid_print
    print('PROBE toasts in 6 minutes: ${seen.length}');
    for (final m in seen.take(24)) {
      // ignore: avoid_print
      print('   | $m');
    }
  });

  test('escalation: what changes between banish #1 and banish #40?', () {
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 50;
    final r = AnomalyRuntime(s);
    r.signedOn = true;
    for (final n in <int>[1, 5, 10, 20, 40]) {
      s.stats.streak = n;
      s.stats.banished = n;
      final calmFast = calmWindow(s, cleanliness: 1, streak: n);
      final calmSlow = calmWindow(s, cleanliness: 0, streak: n);
      // ignore: avoid_print
      print('PROBE streak=$n  calm(clean)=${calmFast.toStringAsFixed(1)}s  '
          'calm(buzzer)=${calmSlow.toStringAsFixed(1)}s  '
          'gap=${anomIntervalMean(s, 9).toStringAsFixed(1)}s  '
          'window=${banishWindow(s).toStringAsFixed(1)}s');
    }
    // and the payout curve
    s.stats.streak = 1;
    for (final n in <int>[1, 50, 500]) {
      s.prod['rabbit'] = n;
      final fastBonus = sigRateRaw(s) * 18;
      final slowBonus = sigRateRaw(s) * 9;
      // ignore: avoid_print
      print('PROBE rabbit=$n  cleanKill=+${fastBonus.toStringAsFixed(0)}  '
          'normal=+${slowBonus.toStringAsFixed(0)}  ratio=2.0x');
    }
  });
}
