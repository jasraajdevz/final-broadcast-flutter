// THE 18+ GATE HAS TO BE ON SCREEN AND HITTABLE.
//
// NIGHTMARE shipped unenterable and nothing in a 229-test suite noticed,
// because every part of it worked in isolation: the button called the
// callback, the callback set _confirm, and the sheet built. What it did not
// do was appear. Positioned.fill(HomeScreen) came AFTER the confirm sheet in
// the root Stack, so the gate was painted over and its pointer eaten, and the
// only symptom was that pressing NIGHTMARE did nothing at all.
//
// That is a bug you can only find by pressing the button, so this file presses
// the button. tester.tap() hit-tests before it taps and fails if the widget it
// lands on is not the one it was aimed at — which means these tests fail if
// the gate is ever covered again, not merely if it stops being built.
//
// It is also the reason the accept button no longer reads OK. A content
// warning dismissed with OK has been acknowledged, not agreed to.

import 'package:final_broadcast/main.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boots the real app onto the front desk with NIGHTMARE offered.
///
/// The app loads whatever is in the store, so the fixture is written as a
/// save rather than poked into the tree: [GameState.survived] > 0 is what
/// unlocks THE LONG SHIFT and NIGHTMARE — neither door is shown to somebody
/// who has never held a shift, which is deliberate and is why a fresh boot
/// finds no NIGHTMARE button at all.
Future<void> _atFrontDesk(WidgetTester tester) async {
  (GameState()
        ..started = true
        ..hardwareChecked = true
        ..night = 3
        ..survived = 2
        // Night 3's file is already recovered, so signing on goes straight to
        // air instead of stopping at the archive drawer — this file is about
        // the gate, not about what the gate leads to.
        ..log[3] = true)
      .save();

  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const FinalBroadcastApp());
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('pressing NIGHTMARE shows the consent gate', (tester) async {
    await _atFrontDesk(tester);

    expect(find.text('NIGHTMARE'), findsOneWidget);
    await tester.tap(find.text('NIGHTMARE'));
    await tester.pump(const Duration(milliseconds: 16));

    // The gate is up...
    expect(find.text('CONFIRM'), findsOneWidget,
        reason: 'NIGHTMARE started with no warning, or the gate is covered');
    // ...and it says the things it has to say.
    for (final String warned in <String>[
      'SUSTAINED GORE',
      'JUMP SCARES WITHOUT WARNING',
      'FLASHING AND STROBING',
      'IT DOES NOT END',
    ]) {
      expect(find.textContaining(warned), findsOneWidget,
          reason: 'the warning no longer mentions: $warned');
    }
    // The player is asked to AGREE, not to acknowledge.
    expect(find.textContaining('I AGREE'), findsOneWidget);
    expect(find.text('OK'), findsNothing,
        reason: 'an 18+ warning cannot be dismissed with OK');
  });

  testWidgets('the gate is on top — the accept button is really hittable',
      (tester) async {
    await _atFrontDesk(tester);
    await tester.tap(find.text('NIGHTMARE'));
    await tester.pump(const Duration(milliseconds: 16));

    // THE ASSERTION THAT WOULD HAVE CAUGHT IT. warnIfMissed makes tap() fail
    // when the hit test lands on something else — i.e. when the home screen is
    // sitting on top of the gate, which is exactly what shipped.
    await tester.tap(find.textContaining('I AGREE'));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('CONFIRM'), findsNothing);
    // Agreeing starts NIGHTMARE, not an ordinary shift: no 06:00.
    expect(find.text('TAKE THE NIGHT SHIFT'), findsNothing,
        reason: 'agreeing did not sign on');
    await tester.pump(const Duration(seconds: 2)); // sign-on toasts
  });

  testWidgets('declining leaves you on the front desk, not in NIGHTMARE',
      (tester) async {
    await _atFrontDesk(tester);
    await tester.tap(find.text('NIGHTMARE'));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.textContaining('TAKE ME BACK'));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('CONFIRM'), findsNothing);
    expect(find.text('TAKE THE NIGHT SHIFT'), findsOneWidget,
        reason: 'declining the 18+ warning must not start anything');
  });
}
