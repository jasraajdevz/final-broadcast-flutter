// TEMPORARY PROBE — delete after reading.
import 'package:final_broadcast/main.dart';
import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('how many strikes does ONE click on the tube produce?',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FinalBroadcastApp());
    await tester.pump();

    final root = tester.state(find.byType(GameRoot)) as dynamic;
    final GameState s = root.s as GameState;
    final AnomalyRuntime rt = root.runtime as AnomalyRuntime;

    // SIGN ON without startBroadcast()'s delayed toast timer.
    rt.signedOn = true;
    s.started = true;
    rt.scheduleNext();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final before = s.tune.strikes;
    final sigBefore = s.sig;
    final heatBefore = s.tune.heat;
    final yield1 = tuneYield(s, rt);

    await tester.tapAt(kScr.center);
    await tester.pump();

    // ignore: avoid_print
    print('PROBE strikes: $before -> ${s.tune.strikes}  (delta '
        '${s.tune.strikes - before})');
    // ignore: avoid_print
    print('PROBE sig: $sigBefore -> ${s.sig}  (delta ${s.sig - sigBefore}, '
        'one tuneYield = $yield1)');
    // ignore: avoid_print
    print('PROBE heat: $heatBefore -> ${s.tune.heat}  (one strike = +0.28)');
    // ignore: avoid_print
    print('PROBE pops: ${s.tune.pops.length}  ripples: ${s.tune.ripples.length}');
    // ignore: avoid_print
    print('PROBE recent(rate window): ${s.tune.recent.length}');

    // and a click on a DEAD part of the cabinet (the wall, not the tube)
    final s2 = s.tune.strikes;
    await tester.tapAt(const Offset(120, 60));
    await tester.pump();
    // ignore: avoid_print
    print('PROBE off-tube click strikes delta: ${s.tune.strikes - s2}');
  });
}
