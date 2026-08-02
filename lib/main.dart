// FINAL BROADCAST — KBLK-7.
//
// A retro horror idle game, ported from a single self-contained HTML file.
// This is the shell: the fixed 1280x720 cabinet and its fit, the frame loop,
// the keyboard, and the wiring between the simulation (AnomalyRuntime), the
// audio engine, the ad break and the widget chrome.
//
// The simulation is NOT run here. One call per frame does all of it:
//     runtime.tick(dt);  tools.tick(dt);  bots.tick(dt);
// Everything else in _tick is presentation cadence — the 0.09s UI pulse and
// the 12s autosave, both straight out of the JS main loop.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'src/anomalies.dart';
import 'src/audio.dart';
import 'src/bots.dart';
import 'src/bake.dart' show mono;
import 'src/consts.dart';
import 'src/economy.dart';
import 'src/state.dart';
import 'src/story.dart';
import 'src/tools.dart';
import 'src/ui/ad_break.dart';
import 'src/ui/boot_screen.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/deck.dart';
import 'src/ui/end_sheet.dart';
import 'src/ui/log_sheet.dart';
import 'src/ui/manual.dart';
import 'src/ui/rack.dart';
import 'src/paint/booth.dart';
import 'src/paint/entities.dart' show drawAnom;
import 'src/ui/scene_slot.dart';
import 'src/ui/setup_screen.dart';
import 'src/ui/status_bar.dart';
import 'src/ui/toasts.dart';
import 'src/ui/wings.dart';
import 'src/ui/ui_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The painted booth, and the manual's per-entity preview plate.
  gSceneBuilder = (s, runtime) => BoothScene(s: s, runtime: runtime);
  gAnomPreview = drawAnom;
  runApp(const FinalBroadcastApp());
}

class FinalBroadcastApp extends StatelessWidget {
  const FinalBroadcastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FINAL BROADCAST — KBLK-7',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: K.black,
        canvasColor: K.black,
        fontFamily: kMonoFamily,
        fontFamilyFallback: kMonoFallback,
        splashFactory: NoSplash.splashFactory,
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: K.panel,
            border: Border.all(color: K.sheetBorder),
          ),
          textStyle: mono(12, K.ink),
        ),
      ),
      // The cabinet is a fixed pixel layout; the OS text-size setting must not
      // reflow it.
      builder: (context, child) =>
          MediaQuery.withNoTextScaling(child: child ?? const SizedBox()),
      home: const GameRoot(),
    );
  }
}

class GameRoot extends StatefulWidget {
  const GameRoot({super.key});

  @override
  State<GameRoot> createState() => _GameRootState();
}

class _PendingConfirm {
  const _PendingConfirm(this.message, this.onYes, this.danger);
  final String message;
  final VoidCallback onYes;
  final bool danger;
}

class _GameRootState extends State<GameRoot>
    with SingleTickerProviderStateMixin {
  late final GameState s;
  late final AnomalyRuntime runtime;
  late final AdController ad;
  late final BotRuntime bots;
  late final Tools tools;
  late final Ticker _ticker;
  late final Listenable _uiListen;

  /// syncUI() ran at ~11Hz in the HTML; the status bar, the rack and the
  /// manual repaint off this rather than off every frame.
  final ValueNotifier<int> _uiPulse = ValueNotifier<int>(0);

  /// Re-opened from the home screen; shown unconditionally on a first run.
  bool _showSetup = false;

  /// Set by _wings() each layout pass. The in-room directive strip is the
  /// fallback for when the viewport had no width to spare.
  bool _wingsShown = false;

  /// Bumped only when a modal appears or disappears, so the outer Stack does
  /// not rebuild 60 times a second.
  final ValueNotifier<int> _modalPulse = ValueNotifier<int>(0);

  final FocusNode _focus = FocusNode(debugLabel: 'cabinet');
  AppLifecycleListener? _life;

  /// One clock for both frame drivers, so the fallback below cannot
  /// double-count time against the Ticker.
  final Stopwatch _clock = Stopwatch();
  double _lastSec = 0;
  int _tickerFrames = 0;
  Timer? _fallback;
  Timer? _fallbackProbe;
  double _uiAcc = 0;
  double _saveAcc = 0;

  bool _manualOpen = false;
  String? _kbDown;
  Timer? _kbTimer;
  _PendingConfirm? _confirm;
  int _modalSig = -1;

  @override
  void initState() {
    super.initState();
    s = GameState.boot();
    runtime = AnomalyRuntime(s, audio: createGameAudio());
    tools = Tools(runtime);
    ad = AdController(s: s, runtime: runtime);
    runtime.playAd = ad.play;
    bots = BotRuntime.of(s, runtime);
    _uiListen = Listenable.merge(<Listenable>[_uiPulse, s]);

    // TAPE VAULT — offline accrual while the tab was away.
    final grant = offlineGrant(s);
    if (grant > 0) {
      s.sig += grant;
      s.toasts.pushDelayed(
          1200,
          'TAPE VAULT: +${fmt(grant)} SIG WHILE YOU WERE AWAY',
          ToastKind.gold);
    }

    // beforeunload / visibilitychange
    _life = AppLifecycleListener(onStateChange: (AppLifecycleState st) {
      if (st != AppLifecycleState.resumed) s.save();
    });

    _clock.start();
    _ticker = createTicker(_onTickerFrame)..start();

    // The HTML had a setTimeout fallback "for environments where rAF is
    // throttled off". Same guard here: if no Ticker frame has arrived in
    // 400ms, drive the loop from a 33ms Timer instead. The first real frame
    // cancels it again.
    _fallbackProbe = Timer(const Duration(milliseconds: 400), () {
      if (_tickerFrames == 0 && mounted) {
        _fallback = Timer.periodic(
            const Duration(milliseconds: 33), (_) => _advance());
      }
    });
  }

  @override
  void dispose() {
    _ticker
      ..stop()
      ..dispose();
    _fallback?.cancel();
    _fallbackProbe?.cancel();
    _kbTimer?.cancel();
    _life?.dispose();
    _focus.dispose();
    _uiPulse.dispose();
    _modalPulse.dispose();
    s.save();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // The frame
  // -------------------------------------------------------------------------

  void _onTickerFrame(Duration elapsed) {
    _tickerFrames++;
    _fallback?.cancel();
    _fallback = null;
    _advance();
  }

  void _advance() {
    final now = _clock.elapsedMicroseconds / 1e6;
    final raw = now - _lastSec;
    _lastSec = now;
    final dt = raw > 0.1 ? 0.1 : (raw < 0 ? 0.0 : raw);

    if (ad.active) ad.tick(dt);
    runtime.tick(dt);
    // ORDER IS LOAD-BEARING. tools.tick must run after runtime.tick with the same
    // dt: the flare freeze subtracts back the dt the runtime just added, and the
    // mirror intercepts one frame before the window expires. bots.tick is a plain
    // sequential call, never a runtime listener — the Librarian calls
    // pressCounter(), which notifies, and a listener would re-enter.
    tools.tick(dt);
    bots.tick(dt);

    _uiAcc += dt;
    if (_uiAcc > 0.09) {
      _uiAcc = 0;
      _uiPulse.value++;
    }
    _saveAcc += dt;
    if (_saveAcc > 12) {
      _saveAcc = 0;
      s.save();
    }

    final sig = (_manualOpen ? 1 : 0) |
        (ad.active ? 2 : 0) |
        (runtime.signedOn ? 4 : 0) |
        (runtime.endScreen.index << 3) |
        (_confirm != null ? 32 : 0);
    if (sig != _modalSig) {
      _modalSig = sig;
      _modalPulse.value++;
    }
  }

  // -------------------------------------------------------------------------
  // Input
  // -------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
    _focus.requestFocus();
    final p = e.localPosition;
    if (p.dx >= kScr.left &&
        p.dx <= kScr.right &&
        p.dy >= kScr.top &&
        p.dy <= kScr.bottom) {
      runtime.tuneStrike(p.dx, p.dy);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // KeyRepeatEvent is a different type, so `if(e.repeat)return` is implicit.
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;

    if (_confirm != null) {
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _confirm = null);
      }
      return KeyEventResult.handled;
    }
    // M must work BEFORE sign-on: the boot screen literally says "Press M any
    // time" and the bail below used to swallow it on exactly that screen.
    final chEarly = e.character?.toLowerCase();
    if (chEarly == 'm') {
      if (_manualOpen) {
        _closeManual();
      } else {
        _openManual();
      }
      return KeyEventResult.handled;
    }
    // Everything else still waits for SIGN ON — otherwise 1-8 would start the
    // audio graph before the player has asked for any.
    if (!runtime.signedOn) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.escape) {
      if (_manualOpen) _closeManual();
      return KeyEventResult.handled;
    }
    if (ad.active) {
      if (key == LogicalKeyboardKey.space && ad.canSkip) {
        setState(ad.end);
      }
      return KeyEventResult.handled;
    }
    final ch = e.character?.toLowerCase();
    if (ch == 'm') {
      if (_manualOpen) {
        _closeManual();
      } else {
        _openManual();
      }
      return KeyEventResult.handled;
    }
    if (ch != null && kToolKeys.contains(ch) && !_manualOpen) {
      runtime.audio.init();
      runtime.audio.resume();
      tools.pressKey(ch, purchase: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (ch != null) {
      for (final c in kCounters) {
        if (c.key == ch) {
          runtime.audio.init();
          runtime.audio.resume();
          runtime.pressCounter(c.id);
          _kbTimer?.cancel();
          setState(() => _kbDown = c.id);
          _kbTimer = Timer(const Duration(milliseconds: 90), () {
            if (mounted) setState(() => _kbDown = null);
          });
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _openManual() {
    runtime.audio.init();
    runtime.audio.resume();
    // if something is on the screen right now, that is the page you want
    final a = runtime.active;
    if (a != null && !(a.masked && a.stage == 0)) s.manPage = a.def.id;
    setState(() {
      _manualOpen = true;
      runtime.paused = true;
    });
  }

  void _closeManual() => setState(() {
        _manualOpen = false;
        runtime.paused = false;
      });

  /// The page from the desk, if tonight hands one over. Read between taking
  /// the shift and the shift starting — the one moment the player is not
  /// being asked to do anything.
  LogPage? _pendingLog;

  void _signOn() {
    final page = logPageFor(s.night);
    if (page != null && !logPageSeen(s, s.night)) {
      s.log[s.night] = true;
      s.save();
      setState(() => _pendingLog = page);
      return; // the night starts when the drawer closes
    }
    runtime.startBroadcast();
    setState(() {});
  }

  void _closeLog() {
    setState(() => _pendingLog = null);
    runtime.startBroadcast();
  }

  void _showConfirm(String message, VoidCallback onYes, {bool danger = false}) {
    setState(() => _confirm = _PendingConfirm(message, onYes, danger));
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final w = box.maxWidth, h = box.maxHeight;
        final scale = math.min(w / kCabW, h / kCabH);
        // Centre explicitly. The HTML has a comment about why grid/flex
        // centring cannot do this; Transform.scale from the top-left plus an
        // arithmetic offset is the same fix.
        final dx = (w - kCabW * scale) / 2;
        final dy = (h - kCabH * scale) / 2;
        final portrait = h > w;
        final tight = math.min(w, h) < 560;
        // Settle this before _cabinet() is built: the Positioned holding the
        // cabinet is constructed ahead of _wings() in the child list, so a
        // flag written inside _wings() would be one frame stale and the room
        // would briefly show the fallback strip AND the wing.
        _wingsShown = runtime.signedOn && wingWidthFor(dx, scale) > 0;
        return Stack(
          children: <Widget>[
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.2),
                    radius: 1.2,
                    colors: <Color>[UX.wrapBgInner, K.black],
                    stops: <double>[0, 0.75],
                  ),
                ),
              ),
            ),
            Positioned(
              left: dx,
              top: dy,
              width: kCabW * scale,
              height: kCabH * scale,
              // BoxFit.fill onto a box of exactly kCabW:kCabH aspect is a
              // uniform scale, and FittedBox lays the cabinet out at its own
              // 1280x720 first. A bare Transform.scale would NOT: below
              // 1280x720 the Positioned's loose constraints would squash the
              // SizedBox before the transform ever ran — the same class of
              // silent-alignment bug the HTML's #cab comment warns about.
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: kCabW,
                  height: kCabH,
                  child: _cabinet(),
                ),
              ),
            ),
            // THE WINGS. On anything wider than 16:9 the leftover width used
            // to be black bars. It now carries the meters and the night order,
            // which is also what decrowds the cabinet: the things that had no
            // room in 940px live out here instead of fighting for it.
            ..._wings(dx, dy, scale),
            // only nag when rotating actually helps
            if (portrait && tight) const Positioned.fill(child: RotateNag()),
          ],
        );
      },
    );
  }

  /// The side panels, at the cabinet's own scale so type sizes match. They
  /// vanish entirely below [kWingMin] logical px — a 16:9 player must be
  /// playing the same game, so nothing load-bearing may live out here.
  List<Widget> _wings(double dx, double dy, double scale) {
    if (!runtime.signedOn) return const <Widget>[];
    final double wLogical = wingWidthFor(dx, scale);
    if (wLogical <= 0) return const <Widget>[];
    final double wPx = wLogical * scale;
    final double hPx = kCabH * scale;

    // The wings live in the OUTER stack, above the DefaultTextStyle and the
    // transparent Material that _cabinet() installs — so without these two
    // every line of wing copy renders with the missing-Material underline.
    Widget wrap(Widget child) => FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: wLogical,
            height: kCabH,
            child: DefaultTextStyle(
              style: mono(14, K.ink),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        );

    return <Widget>[
      Positioned(
        left: dx - wPx,
        top: dy,
        width: wPx,
        height: hPx,
        child: AnimatedBuilder(
          animation: _uiListen,
          builder: (_, _) => wrap(MeterWing(s: s, runtime: runtime)),
        ),
      ),
      Positioned(
        left: dx + kCabW * scale,
        top: dy,
        width: wPx,
        height: hPx,
        child: AnimatedBuilder(
          animation: _uiListen,
          builder: (_, _) => wrap(OrderWing(s: s, runtime: runtime)),
        ),
      ),
    ];
  }

  Widget _cabinet() {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: DefaultTextStyle(
        style: mono(14, K.ink),
        // Slider, Checkbox and Tooltip all assert on a Material ancestor.
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
          animation: _modalPulse,
          builder: (BuildContext context, Widget? _) => Stack(
            children: <Widget>[
              // --- the painted booth, and the tube you strike ---
              Positioned.fill(
                child: MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedBuilder(
                      animation: runtime,
                      builder: (_, _) => buildScene(s, runtime),
                    ),
                  ),
                ),
              ),

              // The RIGHT NOW line lives in the wing when there is one. With
              // no spare width it gets a strip in the room instead, because it
              // is the one part of the wing that changes how the game plays.
              if (runtime.signedOn && !_wingsShown)
                Positioned(
                  left: 0,
                  top: kStatusRect.height,
                  width: kRoom.width,
                  height: 24,
                  child: AnimatedBuilder(
                    animation: _uiListen,
                    builder: (_, _) => DirectiveStrip(s: s, runtime: runtime),
                  ),
                ),

              // --- status strip ---
              Positioned(
                left: kStatusRect.left,
                top: kStatusRect.top,
                width: kStatusRect.width,
                height: kStatusRect.height,
                child: AnimatedBuilder(
                  animation: _uiListen,
                  builder: (_, _) => StatusBar(s: s, runtime: runtime),
                ),
              ),

              // --- equipment rack ---
              Positioned(
                left: kRackRect.left,
                top: kRackRect.top,
                width: kRackRect.width,
                height: kRackRect.height,
                child: AnimatedBuilder(
                  animation: _uiListen,
                  builder: (_, _) => Rack(
                    s: s,
                    runtime: runtime,
                    confirm: _showConfirm,
                  ),
                ),
              ),

              // --- console ---
              Positioned(
                left: kDeckRect.left,
                top: kDeckRect.top,
                width: kDeckRect.width,
                height: kDeckRect.height,
                child: AnimatedBuilder(
                  animation: runtime,
                  builder: (_, _) => Deck(
                    s: s,
                    runtime: runtime,
                    tools: tools,
                    onManual: _openManual,
                    kbDown: _kbDown,
                  ),
                ),
              ),

              // --- toasts ---
              Positioned(
                left: kToastRect.left,
                top: kToastRect.top,
                width: kToastRect.width,
                child: AnimatedBuilder(
                  animation: runtime,
                  builder: (_, _) => ToastLayer(s: s),
                ),
              ),

              // --- modals ---
              if (_manualOpen)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _uiListen,
                    builder: (_, _) => ManualSheet(
                      s: s,
                      runtime: runtime,
                      onClose: _closeManual,
                    ),
                  ),
                ),
              if (ad.active)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: runtime,
                    builder: (_, _) => AdSheet(s: s, controller: ad),
                  ),
                ),
              if (_pendingLog != null)
                Positioned.fill(
                  child: LogSheet(
                    s: s,
                    page: _pendingLog!,
                    onDone: _closeLog,
                  ),
                ),
              if (runtime.endScreen != EndScreen.none)
                Positioned.fill(
                  child: EndSheet(s: s, runtime: runtime),
                ),
              if (_confirm != null)
                Positioned.fill(
                  child: ModalScrim(
                    child: ConfirmSheet(
                      ui: s.ui,
                      message: _confirm!.message,
                      danger: _confirm!.danger,
                      onYes: () {
                        final yes = _confirm!.onYes;
                        setState(() => _confirm = null);
                        yes();
                      },
                      onNo: () => setState(() => _confirm = null),
                    ),
                  ),
                ),
              if (!runtime.signedOn)
                Positioned.fill(
                    child: HomeScreen(
                      s: s,
                      onSignOn: _signOn,
                      onManual: _openManual,
                      onSetup: () => setState(() => _showSetup = true),
                    )),
              // THE LINE-UP CARD sits on top of the home screen, because a
              // player on laptop speakers is playing a different, worse game
              // and there is no way for them to find that out in-fiction.
              if (!runtime.signedOn && (!s.hardwareChecked || _showSetup))
                Positioned.fill(
                  child: SetupScreen(
                    s: s,
                    runtime: runtime,
                    onDone: () => setState(() => _showSetup = false),
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
