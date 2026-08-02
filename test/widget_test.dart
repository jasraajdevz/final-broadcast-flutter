// FINAL BROADCAST — widget smoke tests for the cabinet chrome.
//
// (This file was `flutter create`'s counter-app scaffold, which referenced a
// MyApp that no longer exists. Replaced with real coverage of the shell.)
//
// On the VM the conditional imports select the in-memory save stub and the
// silent audio engine, so the whole game boots and runs headless.
//
// Every screen is pumped at the default TEXT SIZE and again at the maximum
// 180%, because the status strip, the rack rows and the keycaps are the three
// places where the original's flex-shrink had to become caps and scale-down.
//
// NOTE: the test font is not Courier — every glyph is one em wide, roughly
// 1.6x the real advance — so these layouts are exercised well past their worst
// realistic case.

import 'package:final_broadcast/main.dart';
import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/tools.dart';
import 'package:final_broadcast/src/ui/ad_break.dart';
import 'package:final_broadcast/src/ui/boot_screen.dart';
import 'package:final_broadcast/src/ui/deck.dart';
import 'package:final_broadcast/src/ui/end_sheet.dart';
import 'package:final_broadcast/src/ui/manual.dart';
import 'package:final_broadcast/src/ui/rack.dart';
import 'package:final_broadcast/src/ui/status_bar.dart';
import 'package:final_broadcast/src/ui/toasts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gives the test a surface at least as big as the cabinet, then lays the
/// piece of chrome out at its real size.
Future<void> stage(
  WidgetTester tester,
  Widget child, {
  double width = 940,
  double height = 82,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        type: MaterialType.transparency,
        child: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the cabinet boots to the sign-on screen',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FinalBroadcastApp());
    await tester.pump(const Duration(milliseconds: 16));

    // The wordmark is a three-layer chromatic split (red / cyan / white), so
    // it is deliberately three Text widgets, not one.
    expect(find.text('FINAL BROADCAST'), findsNWidgets(3));
    expect(find.text('SIGN ON'), findsOneWidget);
    // The home screen is the front desk, not just a splash.
    expect(find.text("OPERATOR'S MANUAL"), findsOneWidget);
    // The deck is behind the boot overlay but already built.
    expect(find.text('DEGAUSS'), findsOneWidget);
  });

  testWidgets('sign on clears the boot screen and puts the station on air',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FinalBroadcastApp());
    await tester.pump(const Duration(milliseconds: 16));

    // A first run meets the LINE-UP CARD before the front desk. It has to be
    // passable in one tap without touching audio, or it is a wall.
    expect(find.text('HARDWARE CHECK'), findsOneWidget);
    await tester.tap(find.text('SKIP THE CHECK'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('HARDWARE CHECK'), findsNothing);

    await tester.tap(find.text('SIGN ON'));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('SIGN ON'), findsNothing);
    expect(find.text('ON AIR'), findsOneWidget);
    expect(find.text('KBLK-7 IS ON AIR — GOOD LUCK, OPERATOR'), findsOneWidget);
    // let the delayed second toast fire so no timer outlives the tree
    await tester.pump(const Duration(seconds: 2));
  });

  for (final scale in <double>[1.15, 1.8]) {
    group('TEXT SIZE ${(scale * 100).round()}%', () {
      late GameState s;
      late AnomalyRuntime runtime;

      setUp(() {
        s = GameState();
        s.ui = scale;
        for (final k in <String>['snow', 'card', 'niel']) {
          s.seen[k] = true;
        }
        s.sig = 1234567;
        s.segSig = 4321;
        s.lifetimeSig = 900000;
        runtime = AnomalyRuntime(s);
      });

      testWidgets('status strip', (WidgetTester tester) async {
        await stage(tester, StatusBar(s: s, runtime: runtime));
        expect(find.text('SIGNAL'), findsOneWidget);
        expect(find.text('DREAD'), findsOneWidget);
        expect(find.text('23:00'), findsOneWidget);
      });

      testWidgets('rack, all three tabs', (WidgetTester tester) async {
        for (final tab in <String>['tx', 'hw', 'st']) {
          s.tab = tab;
          await stage(
            tester,
            Rack(
                s: s,
                runtime: runtime,
                confirm: (String m, VoidCallback y, {bool danger = false}) {}),
            width: 340,
            height: 720,
          );
          await tester.pump();
        }
        // (the rack is a lazy ListView: at 180% the rows below SIGN-OFF are
        // off-screen and therefore never built.)
        expect(find.text('SIGN-OFF'), findsOneWidget);
      });

      testWidgets('deck', (WidgetTester tester) async {
        await stage(tester, Deck(s: s, runtime: runtime, tools: Tools(runtime), onManual: () {}),
            width: 940, height: 120);
        expect(find.text('OFF-HOOK'), findsOneWidget);
        expect(find.text('SPONSOR'), findsOneWidget);
        // a catalogued entity names its own key
        expect(find.text('SNOW CRAWLER'), findsOneWidget);
      });

      testWidgets('toasts', (WidgetTester tester) async {
        s.toast('BANISHED — THE SNOW CRAWLER', ToastKind.good);
        s.toast('✖ DEAD AIR GOT THROUGH', ToastKind.bad);
        await stage(tester, ToastLayer(s: s), width: 940, height: 120);
        expect(find.textContaining('BANISHED'), findsOneWidget);
      });

      testWidgets('manual', (WidgetTester tester) async {
        s.manPage = 'snow';
        await stage(
            tester, ManualSheet(s: s, runtime: runtime, onClose: () {}),
            width: 1280, height: 720);
        expect(find.text('THE SNOW CRAWLER'), findsWidgets);
        expect(find.text('EMERGENCY DESK'), findsOneWidget);

        // an entity that has never been on the tube
        s.manPage = 'call';
        await stage(
            tester, ManualSheet(s: s, runtime: runtime, onClose: () {}),
            width: 1280, height: 720);
        expect(find.text('UNCATALOGUED'), findsWidgets);
      });

      testWidgets('sponsor break', (WidgetTester tester) async {
        final ad = AdController(s: s, runtime: runtime);
        var done = false;
        ad.play('SPONSORED SEGMENT', () => done = true);
        ad.tick(1.0);
        await stage(tester, AdSheet(s: s, controller: ad),
            width: 1280, height: 720);
        expect(find.text('SPONSORED SEGMENT'), findsOneWidget);
        expect(find.text('SKIP IN 4'), findsOneWidget);
        expect(runtime.adPlaying, isTrue);

        ad.tick(6.0); // 1.0 + 6.0 is past kAdDuration
        expect(done, isTrue);
        expect(runtime.adPlaying, isFalse);
        expect(s.stats.ads, 1);
        await tester.pump(const Duration(milliseconds: 400)); // jingle timers
      });

      testWidgets('SIGNAL LOST sheet', (WidgetTester tester) async {
        runtime.signalLost();
        await stage(tester, EndSheet(s: s, runtime: runtime),
            width: 1280, height: 720);
        expect(find.text('## THE CARRIER DROPPED'), findsOneWidget);
        // The failure has to state a CONSEQUENCE, not a score. The sheet's
        // paragraphs are RichText spans, not Text widgets, so the finder has
        // to be told to look inside them.
        expect(
            find.textContaining('NOT IN THE SIGNAL ANY MORE',
                findRichText: true),
            findsOneWidget);
        expect(find.textContaining('EMERGENCY SPONSOR'), findsOneWidget);
      });

      testWidgets('06:00 sign-off sheet', (WidgetTester tester) async {
        runtime.dawn();
        await stage(tester, EndSheet(s: s, runtime: runtime),
            width: 1280, height: 720);
        expect(find.text('☀ 06:00 — SIGN-OFF'), findsOneWidget);
        // the revive button is hidden on the dawn sheet
        expect(find.textContaining('EMERGENCY SPONSOR'), findsNothing);
        expect(find.textContaining('SIGN THE LOG'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1)); // dawn chime timers
      });

      testWidgets('boot screen', (WidgetTester tester) async {
        await stage(tester, const BootScreen(onSignOn: _noop),
            width: 1280, height: 720);
        expect(find.text('FINAL BROADCAST'), findsOneWidget);
      });
    });
  }
}

void _noop() {}
