import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/ui/home_screen.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The spine has to fit AND be legible at every text size — adding it
  // overflowed a 1280x720 cabinet by 96px on the first attempt.
  for (final ui in <double>[1.0, 1.15, 1.8]) {
  testWidgets('home shows the spine at TEXT SIZE $ui', (WidgetTester tester) async {
    final s = GameState()
      ..started = true..night = 6..survived = 5..rp = 14
      ..log[2] = true..log[3] = true..log[4] = true
      ..ui = ui;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: HomeScreen(s: s, onSignOn: () {}, onManual: () {}, onEndless: () {}, onNightmare: () {}, onSetup: () {}),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    for (final f in <String>[
      'OPERATOR, SECOND CLASS', 'OUTLAST R. OKONKWO',
    ]) {
      expect(find.text(f), findsOneWidget, reason: 'missing: $f');
    }
    expect(find.textContaining('OUTLASTED'), findsOneWidget);
    expect(find.textContaining('THEN:'), findsOneWidget);
    expect(find.textContaining('MORE NIGHTS'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the front desk overflowed at TEXT SIZE $ui');
  });
  }
}
