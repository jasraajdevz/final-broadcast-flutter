// TEMPORARY measurement harness for the horror-lens review. Delete after use.
import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
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

  test('PROBE: how much of a night is guaranteed-safe', () {
    for (final career in <int>[0, 20, 60, 150]) {
      final s = _seeded();
      s.stats.banished = career;
      final r = AnomalyRuntime(s);
      r.startBroadcast();

      var t = 0.0;
      const dt = 1 / 30.0;
      var safe = 0.0, warnT = 0.0, liveT = 0.0, openT = 0.0;
      var peak = 0.0;
      final beats = <String, int>{};
      var manifests = 0, telegraphed = 0;
      var lastWarn = -99.0;

      while (t < 21 * 60 && !r.lost) {
        final wasWarn = r.warn;
        final wasActive = r.active;
        r.tick(dt);
        if (wasWarn <= 0 && r.warn > 0) lastWarn = t;
        if (wasActive == null && r.active != null) {
          manifests++;
          if (t - lastWarn < 4) telegraphed++;
        }
        if (wasActive != null && r.active == null && r.scareBeat != null) {
          final k = r.scareBeat.toString();
          beats[k] = (beats[k] ?? 0) + 1;
        }
        if (r.calm > 0 || r.aftermath > 0) {
          safe += dt;
        } else if (r.active != null) {
          liveT += dt;
        } else if (r.warn > 0) {
          warnT += dt;
        } else {
          openT += dt;
        }
        if (s.dread > peak) peak = s.dread;
        t += dt;
      }
      final tot = t;
      // ignore: avoid_print
      print('career=$career ranTo=${t.toStringAsFixed(0)}s lost=${r.lost} '
          'manifests=$manifests telegraphed=$telegraphed '
          'SAFE=${(safe / tot * 100).toStringAsFixed(1)}% '
          'OPEN=${(openT / tot * 100).toStringAsFixed(1)}% '
          'WARN=${(warnT / tot * 100).toStringAsFixed(1)}% '
          'LIVE=${(liveT / tot * 100).toStringAsFixed(1)}% '
          'peakDread=${peak.toStringAsFixed(1)} '
          'banished=${s.stats.banished} scared=${s.stats.scared}');
    }
  });

  test('PROBE: perfect-play night', () {
    final s = _seeded();
    final r = AnomalyRuntime(s);
    r.startBroadcast();
    var t = 0.0;
    const dt = 1 / 30.0;
    var safe = 0.0, peak = 0.0;
    while (t < 30 * 60 && !r.lost) {
      r.tick(dt);
      final a = r.active;
      if (a != null) {
        r.pressCounter((a.masked && a.stage == 0) ? 'cut' : a.def.counter);
      }
      if (r.calm > 0 || r.aftermath > 0) safe += dt;
      if (s.dread > peak) peak = s.dread;
      t += dt;
    }
    // ignore: avoid_print
    print('PERFECT ran=${t.toStringAsFixed(0)}s lost=${r.lost} '
        'banished=${s.stats.banished} peakDread=${peak.toStringAsFixed(1)} '
        'safe=${(safe / t * 100).toStringAsFixed(1)}% clock=${shiftClock(s)}');
  });

  test('PROBE: pacing table', () {
    final s = GameState();
    for (final d in <int>[0, 6, 16, 40, 80, 200, 500]) {
      s.stats.banished = d;
      // ignore: avoid_print
      print('depth=${depth(s)} gap=${anomIntervalMean(s, 9).toStringAsFixed(1)} '
          'window=${banishWindow(s).toStringAsFixed(2)} '
          'tele=${telegraph(s)} pool=${unlockedAnoms(s).length} '
          'calmPerfectS5=${calmWindow(s, cleanliness: 1, streak: 5).toStringAsFixed(1)} '
          'calmBuzzerS1=${calmWindow(s, cleanliness: 0, streak: 1).toStringAsFixed(1)} '
          'recovery=${scareRecovery(s)}');
    }
  });
}
