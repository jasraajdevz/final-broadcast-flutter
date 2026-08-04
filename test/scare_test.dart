// The two scare beats that were audio-only until now.
import 'package:flutter_test/flutter_test.dart';
import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BLACKOUT and AFTERIMAGE actually reach the painters', () {
    var sawBlackout = false, sawBurn = false;
    // Beats are chosen per entity, so run enough scares to see each at least once.
    for (var trial = 0; trial < 60 && !(sawBlackout && sawBurn); trial++) {
      final s = GameState();
      for (final p in kProducers) {
        s.prod[p.id] = 0;
      }
      s.prod['rabbit'] = 20;
      final r = AnomalyRuntime(s);
      r.startBroadcast();
      var t = 0.0;
      const dt = 1 / 30.0;
      var scares = 0;
      while (t < 12 * 60 && scares < 6) {
        final before = s.stats.scared;
        mindTheDesk(r);
                r.tick(dt);
        t += dt;
        if (s.stats.scared > before) scares = s.stats.scared;
        if (r.blackoutAlpha > 0.02) sawBlackout = true;
        if (r.burn > 0.02 && r.afterimageDef != null) sawBurn = true;
        if (sawBlackout && sawBurn) break;
      }
    }
    expect(sawBlackout, isTrue, reason: 'blackoutAlpha must actually rise');
    expect(sawBurn, isTrue, reason: 'afterimage must expose a face to burn in');
  });
}
