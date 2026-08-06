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
import 'src/wallclock.dart';
import 'src/archive.dart';
import 'src/career.dart';
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
import 'src/ui/scare_overlay.dart';
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
  const _PendingConfirm(this.message, this.onYes, this.danger,
      {this.yesLabel = 'OK', this.noLabel = 'CANCEL'});
  final String message;
  final VoidCallback onYes;
  final bool danger;
  final String yesLabel;
  final String noLabel;
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

  /// The rack, as an overlay, on a layout too narrow to give it a column.
  bool _rackOpen = false;
  String? _kbDown;
  Timer? _kbTimer;
  _PendingConfirm? _confirm;
  int _modalSig = -1;

  @override
  void initState() {
    super.initState();
    s = GameState.boot();
    resetSession();
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
      runtime.wipeGlass(p.dx, p.dy);
      runtime.tuneStrike(p.dx, p.dy);
    }
  }

  /// A HAND ACROSS THE GLASS.
  ///
  /// In NIGHTMARE the tube gets marked and the marks occlude the picture. This
  /// is how they come off: drag over them. It thins what is under the hand and
  /// smears the rest outward, so a wiped screen is never a clean screen — it
  /// is a screen somebody has wiped.
  ///
  /// Mechanically it is a fifth thing competing for two hands, which is the
  /// point. The alternative — an obstruction with no answer — is the game
  /// hiding the keys from the player, and their death has to stay their own.
  void _onPointerMove(PointerMoveEvent e) {
    final p = e.localPosition;
    if (p.dx >= kScr.left &&
        p.dx <= kScr.right &&
        p.dy >= kScr.top &&
        p.dy <= kScr.bottom) {
      runtime.wipeGlass(p.dx, p.dy);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // ENTER is the one key in the game that is HELD rather than tapped — a
    // signature takes time to lay down — so it needs the key-up too.
    if (e is KeyUpEvent) {
      if (e.logicalKey == LogicalKeyboardKey.enter ||
          e.logicalKey == LogicalKeyboardKey.numpadEnter) {
        runtime.releaseCheck();
        return KeyEventResult.handled;
      }
      // the ninth key is held, like the book
      if (e.logicalKey == LogicalKeyboardKey.digit9 ||
          e.logicalKey == LogicalKeyboardKey.numpad9) {
        runtime.endCarrier();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // KeyRepeatEvent is a different type, so `if(e.repeat)return` is implicit.
    // Arrow repeats reach the desk; everything else is edge-triggered.
    final bool isArrow = e.logicalKey == LogicalKeyboardKey.arrowUp ||
        e.logicalKey == LogicalKeyboardKey.arrowDown ||
        e.logicalKey == LogicalKeyboardKey.arrowLeft ||
        e.logicalKey == LogicalKeyboardKey.arrowRight;
    if (e is! KeyDownEvent && !(isArrow && e is KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
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

    // THE DESK. Up/Down wind the DRIVE, Left/Right trim the MODULATION. These
    // are the only continuous controls in the game and they are on the arrow
    // keys because that is where a hand rests without being told.
    //
    // Repeats are honoured: holding a dial down is how a dial is used, and the
    // rig is a setpoint rather than a pump, so there is nothing to farm by it.
    if (key == LogicalKeyboardKey.arrowUp) {
      runtime.trimDrive(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      runtime.trimDrive(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      runtime.nudgeMod(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      runtime.nudgeMod(-1);
      return KeyEventResult.handled;
    }

    // ENTER signs the book. See checks.dart — one key, always the same,
    // because the station check is an attention test, not a memory test.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      runtime.pressCheck();
      runtime.rig.sign();
      return KeyEventResult.handled;
    }
    // 9. Nothing in the game says this key exists.
    if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      runtime.beginCarrier();
      return KeyEventResult.handled;
    }

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
  StationDoc? _pendingLog;

  void _signOn() {
    final page = docForNight(s.night);
    if (page != null && unlocked(s, 'archive') && !docFound(s, s.night)) {
      s.log[s.night] = true;
      s.save();
      // BELT AND BRACES. The page from the desk is read with the controls
      // covered, and a modal that takes the operator's hands away must not let
      // the drums turn — measured in play, sixteen seconds went onto the
      // licence behind this sheet. The night is not supposed to have started
      // yet at all here, so this should be redundant; it is set anyway,
      // because "should be redundant" is how the first sixteen seconds got
      // charged.
      runtime.paused = true;
      setState(() => _pendingLog = page);
      return; // the night starts when the drawer closes
    }
    runtime.startBroadcast();
    setState(() {});
  }

  /// THE LONG SHIFT. Same desk, same eight things, no 06:00.
  void _signOnEndless() {
    s.endless = true;
    _signOn();
  }

  /// NIGHTMARE. Endless, harder, and the tube gets marked.
  ///
  /// GATED BEHIND AN EXPLICIT AGREEMENT, and the gate names what is actually
  /// in there rather than saying "graphic content" and leaving the player to
  /// find out. A warning that does not say WHAT is not a warning, it is a
  /// disclaimer — it protects the game rather than the person reading it.
  ///
  /// Defaults to no. It has to be chosen.
  void _signOnNightmare() {
    _showConfirm(
      'NIGHTMARE is a different game and you should know what is in it '
      'before you agree.\n\n'
      'SUSTAINED GORE. Blood lands ON the screen you are reading and stays '
      'there until you wipe it off by hand. It does not stop, wiping costs '
      'you licence time, and what has dried does not come off.\n\n'
      'WHAT YOU KILL TAKES SECONDS TO FINISH DYING, on screen.\n\n'
      'JUMP SCARES WITHOUT WARNING, full-screen, with sound.\n\n'
      'FLASHING AND STROBING IMAGES.\n\n'
      'IT DOES NOT END. There is no 06:00 and no winning — only how long you '
      'lasted before the licence went.\n\n'
      'If you are unsure, take a night shift instead. Nothing here is needed '
      'to see the rest of the game.',
      () {
        s.endless = true;
        s.nightmare = true;
        _signOn();
      },
      danger: true,
      yesLabel: 'I AGREE — I AM 18 OR OVER',
      noLabel: 'NO — TAKE ME BACK',
    );
  }

  void _closeLog() {
    runtime.paused = false;
    setState(() => _pendingLog = null);
    runtime.startBroadcast();
  }

  void _showConfirm(String message, VoidCallback onYes,
      {bool danger = false,
      String yesLabel = 'OK',
      String noLabel = 'CANCEL'}) {
    setState(() => _confirm = _PendingConfirm(message, onYes, danger,
        yesLabel: yesLabel, noLabel: noLabel));
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final w = box.maxWidth, h = box.maxHeight;
        // NARROW: DROP THE RACK AND GIVE ITS WIDTH TO THE PICTURE.
        //
        // The cabinet is 1280 wide, of which 940 is the status strip, the room
        // and the deck — everything you need to work the desk — and the right
        // 340 is the equipment rack, which is a shop you visit between
        // arrivals. On a 390-wide phone the whole 1280 scales to 0.30 and the
        // deck keys land at about four millimetres. Laying out only the 940
        // scales to 0.41, a 36% bigger picture, and costs nothing that is
        // needed WHILE the transmitter is running.
        //
        // This is the cheap half of a mobile layout and it is honest about
        // being that: the rack becomes an overlay behind a tab rather than a
        // column, and the room's own geometry is untouched, because kScr and
        // everything the painters draw against it are baked at fixed
        // coordinates inside kRoom. Reflowing THOSE is the expensive half.
        final bool narrow = w / h < 1.15 || w < 900;
        final double cabW = narrow ? kRoom.width : kCabW;
        final scale = math.min(w / cabW, h / kCabH);
        // Centre explicitly. The HTML has a comment about why grid/flex
        // centring cannot do this; Transform.scale from the top-left plus an
        // arithmetic offset is the same fix.
        final dx = (w - cabW * scale) / 2;
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
              width: cabW * scale,
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
                  width: cabW,
                  height: kCabH,
                  child: _cabinet(narrow),
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

  Widget _cabinet(bool narrow) {
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
            onPointerMove: _onPointerMove,
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
              // Not laid out at all when narrow: the cabinet is only 940 wide
              // there, so a panel at x=940 would be off the edge. It is
              // reachable as an overlay instead.
              // On a narrow layout it opens over the room instead, behind a
              // tab on the right edge. Everything in it is a between-arrivals
              // decision, so covering the picture to read it costs nothing the
              // player needs at that moment.
              if (narrow) ...<Widget>[
                Positioned(
                  right: 0,
                  top: kStatusRect.height + 8,
                  width: 26,
                  height: 132,
                  child: Pressable(
                    onTap: () => setState(() => _rackOpen = !_rackOpen),
                    builder: (_, bool hover, bool down) => Container(
                      decoration: BoxDecoration(
                        color: down || _rackOpen ? K.tabOnBg : K.tabBg,
                        border: Border.all(color: K.itemBorder),
                      ),
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Center(
                          child: Text(_rackOpen ? 'CLOSE' : 'HARDWARE',
                              style: mono(11, hover ? K.green : K.tabInk)),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_rackOpen)
                  Positioned(
                    left: 0,
                    top: kStatusRect.height,
                    width: kRoom.width,
                    height: kCabH - kStatusRect.height,
                    child: AnimatedBuilder(
                      animation: _uiListen,
                      builder: (_, _) => ColoredBox(
                        color: K.panel,
                        child: Rack(
                            s: s, runtime: runtime, confirm: _showConfirm),
                      ),
                    ),
                  ),
              ],
              if (!narrow)
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
              // THE SCARE, OVER EVERYTHING. Above the rack, the deck and the
              // status strip: a jumpscare that a UI panel is painted on top
              // of is not a jumpscare. Below the modals only, so a sheet can
              // still be read afterwards.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: runtime,
                  builder: (_, _) => ScareOverlay(runtime: runtime),
                ),
              ),

              if (_pendingLog != null)
                Positioned.fill(
                  child: LogSheet(
                    s: s,
                    page: _pendingLog!,
                    night: s.night,
                    onDone: _closeLog,
                  ),
                ),
              if (runtime.endScreen != EndScreen.none)
                Positioned.fill(
                  child: EndSheet(s: s, runtime: runtime),
                ),
              if (!runtime.signedOn)
                Positioned.fill(
                    child: HomeScreen(
                      s: s,
                      onSignOn: _signOn,
                      onManual: _openManual,
                      onEndless: _signOnEndless,
                      onNightmare: _signOnNightmare,
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
              // LAST IN THE STACK, DELIBERATELY.
              //
              // This sat above the home screen and NIGHTMARE shipped
              // unenterable: pressing the button set _confirm, the sheet was
              // built, and then Positioned.fill(HomeScreen) painted straight
              // over it and ate the pointer. The gate existed and was
              // invisible. A confirmation is by definition the topmost thing
              // on screen — anything that can cover it is a way to answer a
              // question the player was never shown.
              if (_confirm != null)
                Positioned.fill(
                  child: ModalScrim(
                    child: ConfirmSheet(
                      ui: s.ui,
                      message: _confirm!.message,
                      danger: _confirm!.danger,
                      yesLabel: _confirm!.yesLabel,
                      noLabel: _confirm!.noLabel,
                      onYes: () {
                        final yes = _confirm!.onYes;
                        setState(() => _confirm = null);
                        yes();
                      },
                      onNo: () => setState(() => _confirm = null),
                    ),
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
