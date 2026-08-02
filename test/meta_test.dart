import 'package:flutter_test/flutter_test.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/meta.dart';
import 'package:final_broadcast/src/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('RP is a budget and its purchases survive sign-off', () {
    final s = GameState();
    s.rp = 20;
    final w0 = banishWindow(s);
    expect(buyMeta(s, 'ferrite'), isTrue);
    expect(s.rp, 17);
    expect(banishWindow(s), greaterThan(w0));

    expect(buyMeta(s, 'standing'), isTrue);
    for (final p in kProducers) { s.prod[p.id] = 5; }
    s.resetForNewNight();
    expect(s.prod[kProducers[0].id], 5, reason: 'STANDING ORDER keeps tier 1');
    expect(s.prod[kProducers[1].id], 0, reason: 'and only tier 1 at level 1');
    expect(metaLevel(s, 'ferrite'), 1, reason: 'meta must survive the night');

    final json = s.toJson();
    final s2 = GameState()..readJson(json);
    expect(metaLevel(s2, 'ferrite'), 1, reason: 'meta must round-trip the save');

    // and it is finite
    s.rp = 0;
    expect(buyMeta(s, 'pay'), isFalse);
  });
}
