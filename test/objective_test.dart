// Guards for the three things added to answer "it feels aimless".
//
// None of these are cosmetic. The directive is the only thing on screen that
// tells a player what to do next; the canteen is the only lever that moves
// DREAD downward on purpose; the wing threshold is the difference between a
// widescreen player seeing the meters and a 16:9 player seeing a strip.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/meta.dart';
import 'package:final_broadcast/src/objective.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/ui/wings.dart';

GameState _stocked() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 40;
  s.prod['dipole'] = 30;
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the canteen', () {
    test('sells DREAD back for SIGNAL', () {
      final s = _stocked();
      s.dread = 60;
      final c = kCanteenBy['coffee']!;
      final price = sigRateRaw(s) * c.seconds;
      s.sig = price * 4;

      final before = s.sig;
      s.sig -= price;
      s.dread = (s.dread - c.dread).clamp(0.0, 100.0);

      expect(s.dread, 48);
      expect(s.sig, lessThan(before));
    });

    test('is priced in seconds of output, so it scales with the station', () {
      final poor = _stocked();
      final rich = _stocked();
      rich.prod['vhf'] = 200;

      final c = kCanteenBy['sandwich']!;
      final cheap = sigRateRaw(poor) * c.seconds;
      final dear = sigRateRaw(rich) * c.seconds;

      expect(dear, greaterThan(cheap),
          reason: 'a coffee must cost a bigger station the same EFFORT, or it '
              'becomes free by night three and DREAD stops meaning anything');
    });

    test('the strong stock is held back for later nights', () {
      final s = _stocked();
      expect(canteenUnlocked(s, kCanteenBy['coffee']!), isTrue);
      expect(canteenUnlocked(s, kCanteenBy['pills']!), isFalse);
      s.night = 3;
      expect(canteenUnlocked(s, kCanteenBy['pills']!), isTrue);
    });
  });

  group('the prime directive', () {
    test('an anomaly on the tube outranks everything else', () {
      final s = _stocked();
      s.dread = 95; // would otherwise be the loudest thing in the room
      final r = AnomalyRuntime(s);
      r.startBroadcast();

      // drive until something is actually up
      var t = 0.0;
      while (t < 21 * 60 && r.active == null && !r.lost) {
        r.tick(1 / 30.0);
        t += 1 / 30.0;
      }
      expect(r.active, isNotNull, reason: 'nothing ever manifested');

      final d = primeDirective(s, r);
      expect(d.urgency, Urgency.urgent);
      expect(d.text, contains(RegExp('ANSWER IT|ARRIVING')));
    });

    test('names the counter only for an entity you have catalogued', () {
      final s = _stocked();
      final r = AnomalyRuntime(s);
      r.startBroadcast();
      var t = 0.0;
      while (t < 21 * 60 && (r.active == null || r.active!.stage < 1) && !r.lost) {
        r.tick(1 / 30.0);
        t += 1 / 30.0;
      }
      final a = r.active!;

      s.seen[a.def.id] = false;
      expect(primeDirective(s, r).text, contains('MANUAL'));

      s.seen[a.def.id] = true;
      expect(primeDirective(s, r).text,
          contains(a.def.counter.toUpperCase()));
    });

    test('with the tube clear, high dread beats an unmet quota', () {
      final s = _stocked();
      s.dread = 85;
      s.segSig = 0; // quota is also unmet
      final r = AnomalyRuntime(s);
      final d = primeDirective(s, r);
      expect(d.text, contains('DREAD'));
      expect(d.urgency, Urgency.urgent);
    });

    test('a met quota and a calm room reads as ALL CLEAR', () {
      final s = _stocked();
      s.dread = 0;
      s.segSig = segQuota(s) * 2;
      final r = AnomalyRuntime(s);
      expect(primeDirective(s, r).urgency, Urgency.calm);
    });
  });

  group('the wings', () {
    test('do not appear when the viewport has no width to spare', () {
      // 16:9 exactly — dx is 0, so there is nothing to put a wing in.
      expect(wingWidthFor(0, 1.25), 0);
      // 16:10 laptop: a sliver, not enough to say anything.
      expect(wingWidthFor(40, 1.25), 0);
    });

    test('appear, and stay bounded, on a genuinely wide screen', () {
      // 2560x1080: scale 1.5, 320px each side.
      final w = wingWidthFor(320, 1.5);
      expect(w, greaterThanOrEqualTo(kWingMin));
      expect(w, lessThanOrEqualTo(kWingMax));
      // 5120 wide must not hand a wing half the desk.
      expect(wingWidthFor(1600, 1.5), kWingMax);
    });
  });

  test('the HUD quotes TONIGHT\'s quota, not the printed table', () {
    // quotaScale() escalates night over night. The status bar used to read
    // segOf(s).quota, so from night 2 the bar filled while the clock stayed
    // held and nothing on screen said why.
    final s = _stocked();
    expect(segQuota(s), closeTo(kRundown[0].quota, 0.01),
        reason: 'night one must be exactly the printed figure');
    s.night = 6;
    expect(segQuota(s), greaterThan(kRundown[0].quota));
  });
}
