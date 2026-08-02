// FINAL BROADCAST — the anomaly runtime.
//
// This is the JS `A` object plus sections 4, 5 and 9 of index.html: the
// scheduler, the sabotage rules, the jumpscare, SIGNAL LOST / revive / dawn /
// sign-off, and the simulation half of the main loop.
//
// Sabotage rules, all load-bearing and ported unchanged:
//   * gated on stage == 1, so a MASKED anomaly is never an unattributable debuff
//   * all mutable sabotage state lives on the ActiveAnom, so clearing it cannot
//     leak a debuff into the next intrusion
//   * a first sighting is LONGER but HALF strength — a demonstration, not a hazing
//   * nothing may ever disable the key that banishes it
//
// Three rules the scheduler adds on top, and the reason the runtime owns three
// timers instead of one:
//   * CALM — a correct counter opens a window in which nothing can manifest.
//     It is earned, it compounds with the streak, and the UI can read it
//     (`allClear`, `calmP`, `airState`). Getting it right must BUY something.
//   * AFTERMATH — a jumpscare opens a longer forced-quiet window. A scare can
//     therefore never chain into another one, which is the guarantee that keeps
//     a bad night recoverable rather than a death spiral.
//   * The two are mutually exclusive except during the FALSE CLEAR scare beat,
//     which lights the ALL CLEAR lamp on purpose and then takes it away.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'consts.dart';
import 'economy.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Audio contract
// ---------------------------------------------------------------------------

/// Everything the game asks of the synthesised audio engine. The audio agent
/// implements this; the runtime never touches WebAudio directly.
///
/// Method names, argument order and units are exactly the JS `AU` object's.
/// `env` oscillator types are the WebAudio strings: "sine", "square",
/// "sawtooth", "triangle".
abstract class GameAudio {
  void init();
  void resume();
  void setVol(double v);

  /// Per-frame update of the ambient bed (drips, whispers, heartbeat, ducking).
  void tick(double dt);

  /// 0..1 — how loud the room gets as DREAD rises.
  void setDread(double v);
  void setHeart(double bpm, double vol);
  void setStatic(double v);
  void setDrone(double v, double f);
  void deadAir(bool on);
  void duck(double v, int ms);

  void env(String type, double freq, double dur, double vol,
      [double? sweepTo, double? q]);
  void burst(double dur, double vol, double f0, double f1);
  void thump(double vol, double f0, [double? when]);
  void scream(double dur, double f0, double vol);
  void riser(double dur);

  void impact();
  void banishStinger(bool fast);
  void reject();
  void click();
  void tune(double p);
  void good();
  void bad();
  void buy();
  void warn();
  void scare();
  void ring();
  void boxNote(double f);
  void whisper();
  void creak();
  void pipe();
  void farThud();
}

/// A complete no-op audio engine. The default, so the game runs (and tests run)
/// with no sound stack at all.
class NullAudio implements GameAudio {
  const NullAudio();
  @override
  void init() {}
  @override
  void resume() {}
  @override
  void setVol(double v) {}
  @override
  void tick(double dt) {}
  @override
  void setDread(double v) {}
  @override
  void setHeart(double bpm, double vol) {}
  @override
  void setStatic(double v) {}
  @override
  void setDrone(double v, double f) {}
  @override
  void deadAir(bool on) {}
  @override
  void duck(double v, int ms) {}
  @override
  void env(String type, double freq, double dur, double vol,
      [double? sweepTo, double? q]) {}
  @override
  void burst(double dur, double vol, double f0, double f1) {}
  @override
  void thump(double vol, double f0, [double? when]) {}
  @override
  void scream(double dur, double f0, double vol) {}
  @override
  void riser(double dur) {}
  @override
  void impact() {}
  @override
  void banishStinger(bool fast) {}
  @override
  void reject() {}
  @override
  void click() {}
  @override
  void tune(double p) {}
  @override
  void good() {}
  @override
  void bad() {}
  @override
  void buy() {}
  @override
  void warn() {}
  @override
  void scare() {}
  @override
  void ring() {}
  @override
  void boxNote(double f) {}
  @override
  void whisper() {}
  @override
  void creak() {}
  @override
  void pipe() {}
  @override
  void farThud() {}
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// JS `A.active` — one live intrusion. Every mutable sabotage field lives here
/// so that nulling `active` cannot leak a debuff into the next one.
class ActiveAnom {
  ActiveAnom({
    required this.def,
    required this.window,
    required this.masked,
    required this.stage,
    required this.intensity,
  });

  final Anom def;

  /// Seconds it has been on the tube.
  double t = 0;

  /// Seconds available to banish it.
  final double window;

  /// Arrived wearing someone else's face (depth >= 28, 22% chance).
  final bool masked;

  /// 0 = masked and not yet stripped, 1 = present and sabotaging.
  int stage;

  /// 1 normally, 0.5 on a first sighting.
  final double intensity;

  /// THE TEST CARD GIRL — signal diverted into her lap.
  double held = 0;

  /// DEAD AIR — producer ids currently off the air.
  final List<String> mute = <String>[];

  /// DEAD AIR bite countdown.
  double bite = 1.9;

  /// THE CALLER.
  int rings = 0;
  double ringIv = 1.5;
  double dreadPaid = 0;

  /// Wrong keys pressed during this visit. Shortens the calm window a correct
  /// answer eventually buys — panicking costs you some of the reward.
  int wrongs = 0;

  /// 0..1 progress through the banish window.
  double get p => window <= 0 ? 0 : t / window;

  /// 1 when the counter was hit the instant it manifested, 0 at the last frame.
  double get cleanliness => clampD(1 - p, 0, 1);
}

// ---------------------------------------------------------------------------
// Scares
// ---------------------------------------------------------------------------

/// How a jumpscare is staged. One is chosen per entity when the window runs
/// out; each has a different shape in time, a different audio script and a
/// different thing for the painters to do.
enum ScareBeat {
  /// It arrives at the glass. Immediate hit, hard zoom, scream on top of the
  /// impact, two thumps behind it.
  lunge,

  /// The lights go. Room to black and total silence for [0.75]s — no static,
  /// no drone, a creak and a whisper — and then everything comes back at once
  /// with the thing already there.
  blackout,

  /// A false all-clear that turns. Plays the banish stinger, lights the ALL
  /// CLEAR lamp and toasts a banish that never happened, then, a second later,
  /// takes all of it back. The tell is that a real banish always quotes a
  /// signal figure and this one does not.
  falseClear,

  /// It leaves something behind. Softer opening hit, but the after-image burns
  /// into the tube for six seconds afterwards instead of two.
  afterimage,
}

/// What the ON AIR lamp — and anything else that wants one word for the state
/// of the booth — should be showing. Ordered worst to best.
enum AirState { off, lost, intrusion, warning, recovering, allClear, onAir }

/// A deck key lighting up green (correct) or red (wrong) for 260ms.
class KeyFlash {
  KeyFlash(this.good);
  final bool good;
  double t = 0;
  static const double duration = 0.26;
}

/// Which end-of-run sheet is up.
enum EndScreen { none, signalLost, dawn }

enum ParaStyle { body, dim, fine }

/// One paragraph of the end sheet. `chunks` alternate normal / bold, starting
/// normal — so `["Bank ", "12 RP", " tonight."]` renders "Bank **12 RP**
/// tonight." An empty leading chunk means the paragraph opens in bold.
class EndPara {
  const EndPara(this.chunks, [this.style = ParaStyle.body]);
  final List<String> chunks;
  final ParaStyle style;
}

/// The frozen contents of the SIGNAL LOST / SIGN-OFF sheet. Built once when the
/// sheet opens (the HTML builds its innerHTML at the same moment), so the
/// numbers on it do not drift while the player reads.
class EndScreenModel {
  const EndScreenModel({
    required this.win,
    required this.title,
    required this.body,
    required this.reviveLabel,
    required this.acceptLabel,
  });

  /// true for the 06:00 sign-off (green sheet), false for SIGNAL LOST (red).
  final bool win;
  final String title;
  final List<EndPara> body;

  /// null on the dawn sheet — the revive button is hidden there.
  final String? reviveLabel;
  final String acceptLabel;
}

/// Hook the ad-break controller registers so revive() and takeSponsor() can
/// roll a commercial. `done` runs when the spot finishes or is skipped.
typedef PlayAdFn = void Function(String label, void Function() done);

// ---------------------------------------------------------------------------
// AnomalyRuntime — the JS `A` object plus the simulation loop
// ---------------------------------------------------------------------------

class AnomalyRuntime extends ChangeNotifier {
  AnomalyRuntime(this.s, {GameAudio? audio}) : audio = audio ?? const NullAudio();

  final GameState s;
  GameAudio audio;

  /// Registered by the ad-break controller. If null, the spot is skipped and
  /// `done` fires immediately.
  PlayAdFn? playAd;

  /// True while a commercial is on screen. The ad controller owns this.
  bool adPlaying = false;

  // --- A ---
  ActiveAnom? active;
  double nextAt = 20;
  double warn = 0;
  Anom? warnDef;
  double shake = 0;
  double flash = 0;
  double glitch = 0;
  double scare = 0;
  Anom? scareDef;
  double banishFx = 0;
  double wrongFx = 0;
  bool lost = false;

  // -------------------------------------------------------------------------
  // Pacing and safety
  // -------------------------------------------------------------------------

  /// Seconds of GUARANTEED quiet bought by the last successful banish. While
  /// this is running the gap timer is frozen, so nothing can telegraph and
  /// nothing can manifest. This is the ALL CLEAR the deck promises.
  double calm = 0;

  /// The full length [calm] was granted at, for a countdown meter.
  double calmSpan = 0;

  /// Seconds of forced quiet after a jumpscare. Freezes the gap timer the same
  /// way [calm] does, so a scare can never chain into a second one. Dread also
  /// bleeds off much faster while this runs — the recovery is real.
  double aftermath = 0;

  /// The full length [aftermath] was granted at.
  double aftermathSpan = 0;

  /// The interval the last [scheduleNext] rolled, for the stability readout.
  double gapSpan = 0;

  /// Anomalies that have manifested since SIGN ON, or since the last sign-off.
  /// Feeds `openingEase()` so the first few of a night are spaced right out.
  int nightAnoms = 0;

  // -------------------------------------------------------------------------
  // Scare channels the painters read
  // -------------------------------------------------------------------------

  /// How the live (or most recent) scare is being staged.
  ScareBeat? scareBeat;

  /// Seconds of full room blackout left — the BLACKOUT beat's dark. Painters
  /// should use [blackoutAlpha], which fades the tail rather than popping.
  double blackout = 0;

  /// 0..1 burn left on the tube after the scare frame itself is over. Painters
  /// draw [afterimageDef]'s face at low alpha over the picture while this runs.
  double afterimage = 0;

  /// Total seconds [afterimage] decays over. 2.6s normally, 6.5s for the
  /// AFTERIMAGE beat.
  double afterimageSpan = 0;

  /// What is burned into the tube. Outlives [scareDef], which the scare frame
  /// clears after 1.5s.
  Anom? afterimageDef;

  /// True during the lie in the middle of a FALSE CLEAR beat. Everything looks
  /// banished — including [allClear] — and it is not.
  bool falseClear = false;

  /// Bumped whenever the world moves on. Every delayed scare beat captures it
  /// and no-ops if it no longer matches, so a sign-off mid-scare cannot fire a
  /// theft into the next night.
  int _scareSerial = 0;

  /// The global animation clock every painter reads. JS `tGlobal`.
  double tGlobal = 0;

  /// False until SIGN ON is pressed in THIS session, even for a returning
  /// operator — the boot screen is always shown, for the audio unlock.
  bool signedOn = false;

  EndScreen endScreen = EndScreen.none;
  EndScreenModel? endScreenModel;

  final Map<String, KeyFlash> keyFlashes = <String, KeyFlash>{};

  // -------------------------------------------------------------------------
  // Sabotage predicates (JS sabOn / sabP / sabK)
  // -------------------------------------------------------------------------

  bool sabOn(String id) {
    final a = active;
    return a != null && a.def.id == id && a.stage == 1;
  }

  /// Progress through the window, 0 when nothing is live.
  double sabP() {
    final a = active;
    return a == null ? 0 : a.t / a.window;
  }

  /// Intensity multiplier: 0.5 on a first sighting, 1 otherwise.
  double sabK() => active?.intensity ?? 1;

  /// SECOND CAMERA reads the counter off the bezel once installed, but never
  /// while the thing is still wearing a mask.
  Counter? get cam2Hint {
    final a = active;
    if (!(s.ups['cam2'] ?? false) || a == null) return null;
    if (a.masked && a.stage == 0) return null;
    return kCounterBy[a.def.counter];
  }

  // -------------------------------------------------------------------------
  // Deck feedback
  // -------------------------------------------------------------------------

  void flashKey(String cid, bool good) {
    keyFlashes[cid] = KeyFlash(good);
  }

  KeyFlash? keyFlashOf(String cid) => keyFlashes[cid];

  /// The deck goes hot whenever something is on the tube.
  bool get keysHot => active != null;

  // -------------------------------------------------------------------------
  // Read-side API — everything the status bar and the painters need
  // -------------------------------------------------------------------------

  /// True while the booth is under the guaranteed-quiet window earned by a
  /// correct counter. Nothing can manifest. Show it.
  bool get allClear => calm > 0 && active == null && warn <= 0 && !lost;

  /// 0..1 of the calm window left, for a draining meter.
  double get calmP => calmSpan <= 0 ? 0 : clampD(calm / calmSpan, 0, 1);

  /// Whole seconds of calm left, for a countdown.
  int get calmSeconds => calm <= 0 ? 0 : calm.ceil();

  /// The streak the current calm window was compounded from.
  int get calmStreak => s.stats.streak;

  /// True while the booth is in post-jumpscare recovery. Also a hard no-spawn
  /// window, but it was not earned and it should not read as safety.
  bool get recovering => aftermath > 0 && !falseClear;

  /// 0..1 of the recovery window left.
  double get recoverP =>
      aftermathSpan <= 0 ? 0 : clampD(aftermath / aftermathSpan, 0, 1);

  int get recoverSeconds => aftermath <= 0 ? 0 : aftermath.ceil();

  /// Room-wide blackout alpha for the BLACKOUT beat, 0..1, self-fading.
  double get blackoutAlpha => clampD(blackout * 3, 0, 1);

  /// The lingering burn on the tube, 0..1. Zero while the scare frame itself is
  /// still up — this is what is left AFTER it.
  double get burn => scare > 0 ? 0 : clampD(afterimage, 0, 1);

  /// 0..1 — how far the carrier has drifted towards the next intrusion. Flat 0
  /// while protected, so a stability meter reads as genuinely parked.
  double get threatP {
    if (lost || !signedOn) return 0;
    if (active != null || warn > 0) return 1;
    if (calm > 0 || aftermath > 0) return 0;
    if (gapSpan <= 0) return 0;
    return clampD(1 - nextAt / gapSpan, 0, 1);
  }

  /// One word for the state of the booth.
  AirState get airState {
    if (lost) return AirState.lost;
    if (!signedOn) return AirState.off;
    if (active != null) return AirState.intrusion;
    if (warn > 0) return AirState.warning;
    if (calm > 0) return AirState.allClear;
    if (aftermath > 0) return AirState.recovering;
    return AirState.onAir;
  }

  /// The ON AIR lamp's text for [airState].
  String get airLabel {
    switch (airState) {
      case AirState.off:
        return 'OFF AIR';
      case AirState.lost:
        return 'SIGNAL LOST';
      case AirState.intrusion:
        return '## INTRUSION';
      case AirState.warning:
        return '!! DISTURBANCE';
      case AirState.allClear:
        return 'ALL CLEAR ${calmSeconds}s';
      case AirState.recovering:
        return 'RECOVERING ${recoverSeconds}s';
      case AirState.onAir:
        return 'ON AIR';
    }
  }

  // -------------------------------------------------------------------------
  // Scheduler
  // -------------------------------------------------------------------------

  /// Rolls the next gap. The gap timer does NOT start running until both
  /// protection windows have expired — see [_simulate].
  void scheduleNext() {
    nextAt = anomInterval(s, nightAnoms);
    gapSpan = nextAt;
  }

  /// A banish the PLAYER did not perform. Clears the tube and pays the signal
  /// so a bot can still save you, but credits no lifetime output, no streak and
  /// no calm — automation must not be able to earn your prestige for you.
  /// Measured before this existed: a maxed Librarian, zero key presses, banked
  /// 37 RP a night on its own.
  void assistBanish() {
    final a = active;
    if (a == null) return;
    final before = s.lifetimeSig;
    final streak = s.stats.streak;
    final calmWas = calm, calmSpanWas = calmSpan;
    resolve(true, true);
    s.lifetimeSig = before;
    s.stats.streak = streak;
    calm = calmWas;
    calmSpan = calmSpanWas;
  }

  /// Opens the guaranteed-quiet window a correct answer just bought.
  ///
  /// Never shortens an existing window — a rapid second banish can only ever
  /// add safety — and always clears the post-scare recovery, because earned
  /// calm supersedes it.
  void grantCalm(double seconds) {
    if (seconds <= 0) return;
    aftermath = 0;
    aftermathSpan = 0;
    if (seconds > calm) {
      calm = seconds;
      calmSpan = seconds;
    }
  }

  void beginWarn() {
    // Belt and braces: the caller already checked, but nothing may telegraph
    // inside a protection window under any circumstances.
    if (calm > 0 || aftermath > 0 || lost) return;
    final pool = unlockedAnoms(s);
    warnDef = pick(pool);
    warn = telegraph(s);
    audio.warn();
    audio.riser(warn);
    s.toast('!! CARRIER DISTURBANCE', ToastKind.bad);
  }

  void manifest() {
    final Anom def = warnDef ?? pick<Anom>(unlockedAnoms(s));
    warnDef = null;
    warn = 0;
    calm = 0;
    calmSpan = 0;
    nightAnoms++;
    final d = depth(s);
    final masked = d >= 28 && rand() < 0.22;
    final first = !(s.seen[def.id] ?? false);
    active = ActiveAnom(
      def: def,
      window: banishWindow(s) * (first ? 1.25 : 1) + (masked ? 1.2 : 0),
      masked: masked,
      stage: masked ? 0 : 1,
      intensity: first ? 0.5 : 1,
    );
    if (first) {
      s.seen[def.id] = true;
      s.toast('NEW ENTRY LOGGED — ${def.nm}', ToastKind.gold);
      s.toasts.pushDelayed(900, 'PRESS M TO READ THE MANUAL', ToastKind.gold);
    }
    audio.setStatic(0.14);
    audio.setDrone(0.18, 38 + rand() * 18);
    audio.impact(); // the riser has to land on something
    audio.deadAir(def.id == 'dead'); // room out, heartbeat left in
    glitch = 1;
    if (def.id == 'call') audio.ring();
    if (def.id == 'sleep') {
      const notes = [880.0, 784.0, 659.0, 587.0];
      for (var i = 0; i < notes.length; i++) {
        final f = notes[i];
        _later(i * 280, () => audio.boxNote(f));
      }
    }
    if (def.id == 'dead') {
      audio.setStatic(0.0);
      audio.setDrone(0.02, 30);
    }
    // NIGHT WATCH auto-banish
    if ((s.ups['watch'] ?? false) && rand() < 0.14) {
      _later(600, () {
        final a = active;
        if (a != null && identical(a.def, def)) {
          s.toast('NIGHT WATCH HANDLED IT', ToastKind.good);
          resolve(true, true);
        }
      });
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Player input
  // -------------------------------------------------------------------------

  /// JS pressCounter(cid). `cid` is a Counter.id, not a key digit.
  void pressCounter(String cid) {
    audio.click();
    final a = active;
    if (a == null) {
      flashKey(cid, false);
      notifyListeners();
      return;
    }
    if (a.masked && a.stage == 0) {
      if (cid == 'cut') {
        a.stage = 1;
        a.t = math.max(0, a.t - 0.6);
        flashKey(cid, true);
        s.toast('MASK STRIPPED — NOW COUNTER IT', ToastKind.gold);
        audio.env('square', 300, 0.1, 0.1, 600);
        notifyListeners();
        return;
      }
      wrongPress(cid);
      return;
    }
    if (cid == a.def.counter) {
      flashKey(cid, true);
      resolve(true, false);
    } else {
      wrongPress(cid);
    }
  }

  void wrongPress(String cid) {
    flashKey(cid, false);
    audio.reject();
    s.stats.wrong++;
    wrongFx = 1;
    final pen = (s.ups['autocue'] ?? false) ? 0.45 : 0.9;
    active?.wrongs++;
    active?.t += pen;
    shake = math.max(shake, 6);
    s.dread = math.min(100, s.dread + 3);
    notifyListeners();
  }

  /// Strike the CRT by hand. Coordinates are in 1280x720 cabinet space and are
  /// expected to be inside SCR — the caller hit-tests, exactly as the HTML's
  /// pointerdown handler does.
  void tuneStrike(double x, double y) {
    if (!signedOn || adPlaying || lost) return;
    audio.init();
    audio.resume();
    final g = tuneYield(s, this);
    s.sig += g;
    s.tune.strike(x, y, '+${fmt(g)}', tGlobal);
    audio.tune(s.tune.heat);
    notifyListeners();
  }

  /// The SIGN ON button.
  void startBroadcast() {
    audio.init();
    audio.resume();
    audio.setVol(s.sfx);
    signedOn = true;
    s.started = true;
    // Coming back to the desk — mid-night or not — earns the slow opening.
    nightAnoms = 0;
    calm = 0;
    calmSpan = 0;
    aftermath = 0;
    aftermathSpan = 0;
    scheduleNext();
    s.save();
    audio.env('sine', 1000, 0.5, 0.12, 1000);
    s.toast('KBLK-7 IS ON AIR — GOOD LUCK, OPERATOR', ToastKind.gold);
    s.toasts
        .pushDelayed(1600, 'BUY A TRANSMITTER FROM THE RACK ->', ToastKind.gold);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Resolution
  // -------------------------------------------------------------------------

  /// JS resolve(success, silent).
  void resolve(bool success, bool silent) {
    final a = active;
    if (a == null) return;
    final hadMute = a.mute.isNotEmpty;
    active = null;
    glitch = 0;
    audio.setStatic(0.03);
    audio.setDrone(0, 42);
    audio.deadAir(false);
    audio.setHeart(46, 0);
    if (hadMute) s.toast('TRANSMITTERS BACK ON AIR', ToastKind.good);
    if (success) {
      s.stats.banished++;
      s.stats.streak++;
      s.stats.bestStreak = math.max(s.stats.bestStreak, s.stats.streak);
      final fast = a.t < a.window * 0.4;
      if (fast) s.stats.perfect++;
      // Payouts use the UNSABOTAGED rate — being robbed must not also cut the
      // reward — and are floored on tuneYield so a banish always pays.
      // NOTE: computed AFTER active=null, so sigRate() here is unmuted.
      var bonus = math.max(sigRateRaw(s) * (fast ? 18 : 9),
          tuneYield(s, this) * (fast ? 26 : 14));
      if (a.held > 0) {
        final back = a.held * (fast ? 1.45 : 1.2);
        bonus += back;
        s.toast('SHE GIVES IT BACK — +${fmt(back)} SIG', ToastKind.good);
      }
      s.sig += bonus;
      // Banishing is the FAST way to make quota — the bonus counts as output
      // broadcast, so a clean kill is worth a real slice of the segment.
      s.segSig += bonus;
      s.lifetimeSig += bonus;
      banishFx = 1;
      s.dread = math.max(0, s.dread - 6);
      if (!silent) audio.banishStinger(fast);
      s.toast(
          '${fast ? "CLEAN KILL — " : "BANISHED — "}${a.def.nm}  +${fmt(bonus)} SIG'
          '${s.stats.streak > 2 ? "   ×${s.stats.streak} STREAK" : ""}',
          ToastKind.good);

      // --- the ALL CLEAR ---
      // The whole point of the deck: if you got it right, you are SAFE, and
      // the game says so in as many words. Length scales with how clean the
      // kill was and compounds with the streak; a jumpscare resets the streak,
      // so the compounding has to be defended every time.
      grantCalm(calmWindow(s,
          cleanliness: a.cleanliness,
          streak: s.stats.streak,
          fumbles: a.wrongs));
      audio.env('sine', 700, 0.18, 0.05, 1050);
      s.toasts.pushDelayed(
          760,
          'ALL CLEAR — ${calm.round()}s'
          '${s.stats.streak > 2 ? "   (×${s.stats.streak} STREAK)" : ""}',
          ToastKind.good);
    }
    scheduleNext();
    notifyListeners();
  }

  /// Runs every frame an anomaly is actually present (stage 1 only).
  /// `p` is progress through the banish window.
  void sabotageTick(double dt, double p) {
    final a = active;
    if (a == null || a.stage != 1) return;

    // DEAD AIR — takes the station off the air one transmitter tier at a time,
    // biggest first. Rack rows go dark and the /s figure steps down.
    if (a.def.id == 'dead') {
      a.bite -= dt;
      if (a.bite <= 0) {
        a.bite = math.max(0.85, 1.9 - p * 1.05);
        final live = kProducers
            .where((q) => (s.prod[q.id] ?? 0) > 0 && prodLive(this, q.id))
            .toList();
        if (live.length > (sabK() < 1 ? 1 : 0)) {
          // a first meeting never takes them all
          final victim = live[live.length - 1];
          a.mute.add(victim.id);
          audio.env('sine', 150, 0.5, 0.12, 38);
          audio.burst(0.3, 0.16, 900, 90);
          shake = math.max(shake, 7);
          s.toast('## ${victim.nm} IS OFF THE AIR', ToastKind.bad);
        }
      }
    }

    // THE CALLER — it does not touch your money. It rings, and every ring is
    // dread. A fixed budget per visit.
    if (a.def.id == 'call') {
      a.ringIv -= dt;
      if (a.ringIv <= 0) {
        a.ringIv = math.max(0.42, 1.5 - p * 1.05);
        a.rings++;
        final budget = 9 * sabK();
        final pay = math.min(budget - a.dreadPaid, budget / 7);
        if (pay > 0) {
          s.dread = math.min(100, s.dread + pay);
          a.dreadPaid += pay;
        }
        audio.ring();
        shake = math.max(shake, 2.5 + p * 4);
        if (a.rings == 3) {
          s.toast('EVERY LINE IS RINGING — ANSWER IT', ToastKind.bad);
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // Jumpscares
  // -------------------------------------------------------------------------

  /// Each entity scares in its own idiom. It gets its signature beat most of
  /// the time and a wildcard the rest, so meeting the same thing twice is not
  /// the same scare twice.
  static const Map<String, ScareBeat> kSignatureBeat = <String, ScareBeat>{
    'snow': ScareBeat.lunge, // the grain finishes the face, then comes
    'sleep': ScareBeat.falseClear, // a performer: he says goodnight, then turns
    'vert': ScareBeat.blackout, // he lives in the seam; the seam widens
    'dead': ScareBeat.blackout, // an absence — it takes the lights with it
    'card': ScareBeat.falseClear, // she steps back into the card. She does not
    'rerun': ScareBeat.afterimage, // four seconds of tape that will not erase
    'niel': ScareBeat.lunge, // he files, and then he is at the glass
    'call': ScareBeat.falseClear, // the line goes dead. The line is not dead
  };

  ScareBeat beatFor(Anom def) {
    final ScareBeat sig = kSignatureBeat[def.id] ?? ScareBeat.lunge;
    if (rand() < 0.68) return sig;
    return pick(ScareBeat.values.where((b) => b != sig).toList());
  }

  /// Seconds between the window running out and the hit actually landing. The
  /// staged beats spend it lying to you.
  static double beatLead(ScareBeat b) {
    switch (b) {
      case ScareBeat.blackout:
        return 0.75;
      case ScareBeat.falseClear:
        return 1.0;
      case ScareBeat.lunge:
      case ScareBeat.afterimage:
        return 0;
    }
  }

  /// JS jumpscare(). The window ran out.
  ///
  /// Opens the forced-quiet recovery window FIRST, so that whatever the beat
  /// does with the next second, nothing can telegraph over the top of it and
  /// nothing can manifest while the player is still recovering.
  void jumpscare() {
    final a = active;
    if (a == null) return;
    final Anom def = a.def;
    final double held = a.held;
    active = null;
    glitch = 0;
    calm = 0;
    calmSpan = 0;
    falseClear = false;

    s.stats.scared++;
    s.stats.streak = 0;

    final ScareBeat beat = beatFor(def);
    scareBeat = beat;
    final int serial = ++_scareSerial;

    // recovery = the lead-in + the 1.5s scare frame + the earned quiet
    aftermathSpan = beatLead(beat) + 1.5 + scareRecovery(s);
    aftermath = aftermathSpan;

    _stageScare(def, beat, serial, held);
    scheduleNext();
    notifyListeners();
  }

  /// The pre-hit half of a beat. Everything here is a lie the player is about
  /// to be punished for believing.
  void _stageScare(Anom def, ScareBeat beat, int serial, double held) {
    switch (beat) {
      case ScareBeat.lunge:
      case ScareBeat.afterimage:
        audio.deadAir(false);
        audio.duck(0.3, 800);
        _scareHit(def, beat, serial, held);
        break;

      case ScareBeat.blackout:
        // The lights go, and the room goes with them: no static, no drone, no
        // room tone at all. Just a creak, and something breathing in it.
        blackout = 1.08; // 0.75s of solid dark, then a self-expiring tail
        audio.deadAir(true);
        audio.setStatic(0);
        audio.setDrone(0, 18);
        audio.setHeart(58, 0.05);
        audio.env('sine', 130, 0.40, 0.10, 34);
        shake = math.max(shake, 4);
        s.toast('.. MAINS DROPPED', ToastKind.bad);
        _atScare(serial, 240, audio.creak);
        _atScare(serial, 520, audio.whisper);
        _atScare(serial, 750, () => _scareHit(def, beat, serial, held));
        break;

      case ScareBeat.falseClear:
        // It plays the banish. Stinger, green wash, ALL CLEAR lamp, the lot.
        // The only tell is the toast: a real banish always quotes a signal
        // figure, and this one never does.
        falseClear = true;
        banishFx = 1;
        calm = 4;
        calmSpan = 4;
        audio.deadAir(false);
        audio.setStatic(0.03);
        audio.setDrone(0, 42);
        audio.setHeart(52, 0.04);
        audio.banishStinger(false);
        audio.good();
        s.toast('BANISHED — ${def.nm}', ToastKind.good);
        _atScare(serial, 560, () {
          audio.riser(0.44);
          audio.whisper();
        });
        _atScare(serial, 1000, () => _scareHit(def, beat, serial, held));
        break;
    }
  }

  /// The hit. Sets the render channels, plays the beat's audio, takes what it
  /// came for, and starts the long climb back down.
  void _scareHit(Anom def, ScareBeat beat, int serial, double held) {
    if (_scareSerial != serial) return;
    falseClear = false;
    blackout = 0;
    banishFx = 0;
    calm = 0;
    calmSpan = 0;

    // the channel feed.dart and tube.dart already read: 1.5s, counting down
    scare = 1.5;
    scareDef = def;
    // and the burn it leaves on the tube afterwards
    afterimageDef = def;
    afterimage = 1;
    afterimageSpan = beat == ScareBeat.afterimage ? 6.5 : 2.6;

    switch (beat) {
      case ScareBeat.lunge:
        shake = math.max(shake, 34);
        flash = 1;
        audio.scare();
        audio.impact();
        audio.scream(0.55, 190, 0.34);
        audio.thump(0.60, 44);
        _atScare(serial, 130, () => audio.thump(0.42, 33));
        _atScare(serial, 380, () {
          audio.burst(0.35, 0.18, 1400, 120);
          shake = math.max(shake, 16);
        });
        _atScare(serial, 900, audio.farThud);
        break;

      case ScareBeat.blackout:
        shake = math.max(shake, 36);
        flash = 1;
        audio.deadAir(false); // everything comes back at once
        audio.scare();
        audio.impact();
        audio.scream(0.50, 150, 0.36);
        audio.thump(0.70, 40);
        _atScare(serial, 300, () => audio.thump(0.40, 30));
        _atScare(serial, 820, audio.pipe);
        break;

      case ScareBeat.falseClear:
        shake = math.max(shake, 40);
        flash = 1;
        audio.scare();
        audio.impact();
        audio.scream(0.62, 210, 0.38);
        audio.thump(0.75, 48);
        _atScare(serial, 240, () => audio.thump(0.40, 34));
        _atScare(serial, 700, audio.whisper);
        break;

      case ScareBeat.afterimage:
        shake = math.max(shake, 26);
        flash = 0.75;
        audio.scare();
        audio.impact();
        audio.scream(0.40, 170, 0.26);
        audio.thump(0.50, 42);
        _atScare(serial, 620, () => audio.burst(0.50, 0.14, 700, 60));
        _atScare(serial, 1500, audio.whisper);
        _atScare(serial, 2700, audio.pipe);
        break;
    }

    audio.setStatic(0.26);
    audio.setDrone(0, 42);
    audio.setHeart(158, 0.34);
    // The old recovery was one 1.4s step. This is four, over five seconds, so
    // the room takes as long to settle as the player does.
    _atScare(serial, 1500, () {
      audio.setStatic(0.12);
      audio.setHeart(104, 0.16);
    });
    _atScare(serial, 3200, () {
      audio.setStatic(0.06);
      audio.setHeart(78, 0.08);
    });
    _atScare(serial, 5200, () {
      audio.setStatic(0.03);
      audio.setHeart(50, 0.03);
      audio.creak();
      s.toast('CARRIER RECOVERED', ToastKind.plain);
    });

    // --- what it takes. Unchanged per-entity maths; only the timing moved. ---
    final half = (s.ups['lead'] ?? false) ? 0.5 : 1.0;
    final halo = s.ups['halo'] ?? false;
    var lostSig = 0.0, lostSeg = 0.0;
    if (def.id == 'niel') {
      // He restates the segment's output — the quota bar visibly walks backward,
      // which is his whole point. HALO protects the filing.
      lostSeg = halo ? 0 : s.segSig * 0.30 * half;
      s.segSig -= lostSeg;
      lostSig = s.sig * 0.10 * half;
      s.sig -= lostSig;
    } else if (def.id == 'card') {
      // She already has the pile; taking a third of the bank on top would be a
      // double charge for the same visit. Reported loss includes `held`, but
      // only the 10% is actually deducted — held was never in the bank.
      lostSig = held + s.sig * 0.10 * half;
      s.sig -= s.sig * 0.10 * half;
    } else if (def.id == 'dead') {
      lostSig = s.sig * 0.55 * half;
      s.sig -= lostSig;
    } else {
      lostSig = s.sig * 0.32 * half;
      s.sig -= lostSig;
    }
    s.sig = math.max(0, s.sig);
    s.segSig = math.max(0, s.segSig);
    s.dread = math.min(100, s.dread + 26);
    s.toast(
        'X ${def.nm} '
        '${beat == ScareBeat.falseClear ? "NEVER LEFT" : "GOT THROUGH"}'
        ' — -${fmt(lostSig)} SIG'
        '${lostSeg > 1 ? " / -${fmt(lostSeg)} OUTPUT" : ""}',
        ToastKind.bad);
    if (s.dread >= 100) signalLost();
    notifyListeners();
  }

  /// [_later], but the callback is dropped if the world moved on — a sign-off,
  /// a dawn, a death or another scare all invalidate a pending beat.
  void _atScare(int serial, int millis, void Function() fn) {
    _later(millis, () {
      if (_scareSerial != serial) return;
      fn();
    });
  }

  /// Wipes every scare channel and cancels any beat still in flight.
  void _clearScareFx() {
    _scareSerial++;
    scare = 0;
    scareDef = null;
    scareBeat = null;
    afterimage = 0;
    afterimageSpan = 0;
    afterimageDef = null;
    blackout = 0;
    falseClear = false;
    calm = 0;
    calmSpan = 0;
    aftermath = 0;
    aftermathSpan = 0;
  }

  // -------------------------------------------------------------------------
  // SIGNAL LOST / REVIVE / DAWN / SIGN OFF
  // -------------------------------------------------------------------------

  void signalLost() {
    if (lost) return;
    lost = true;
    active = null;
    // No beat still in flight may fire over the sheet, and neither protection
    // window survives the run ending. `scare` / `afterimage` are deliberately
    // left alone so the frame that killed you gets to finish playing.
    _scareSerial++;
    falseClear = false;
    blackout = 0;
    calm = 0;
    calmSpan = 0;
    aftermath = 0;
    aftermathSpan = 0;
    audio.setStatic(0.3);
    audio.setDrone(0.25, 26);
    final rg = rpGain(s);
    final mult = (1 + (s.rp + rg) * 0.08).toStringAsFixed(2);
    endScreen = EndScreen.signalLost;
    endScreenModel = EndScreenModel(
      win: false,
      title: '## SIGNAL LOST',
      reviveLabel: 'EMERGENCY SPONSOR — STAY ON AIR',
      acceptLabel:
          rg > 0 ? 'SIGN OFF — BANK ${fmt(rg)} RP' : 'SIGN OFF (0 RP)',
      body: <EndPara>[
        EndPara(<String>[
          'The dread meter is full. Every monitor in the building is showing '
              'the same room, and it is ',
          'this',
          ' one.',
        ]),
        EndPara(<String>[
          'The clock stopped at ',
          shiftClock(s),
          ' during ${segOf(s).nm}. You needed to reach 06:00.',
        ]),
        EndPara(<String>[
          'NIGHT ${s.night}  ·  BANISHED ${s.stats.banished}'
              '  ·  BEST STREAK ${s.stats.bestStreak}',
        ]),
        EndPara(<String>[
          'An ',
          'emergency sponsor',
          ' will buy the rest of the hour — watch the spot and the dread '
              'resets to a survivable level, everything you own stays yours. '
              'This will be revive ',
          '#${s.revives + 1}',
          ' tonight.',
        ]),
        EndPara(<String>[
          'Or sign off: bank ',
          '${fmt(rg)} ratings point${rg == 1 ? "" : "s"}',
          ' (permanent ×$mult to everything), lose the transmitters, '
              'start NIGHT ${s.night + 1}.',
        ], ParaStyle.dim),
      ],
    );
    notifyListeners();
  }

  /// EMERGENCY SPONSOR — watch the spot, stay on air.
  void revive() {
    endScreen = EndScreen.none;
    notifyListeners();
    _rollAd('EMERGENCY SPONSORSHIP', () {
      s.revives++;
      s.dread = 45;
      lost = false;
      s.sponsorEnd = math.max(s.sponsorEnd, 45);
      _clearScareFx();
      // You came back from the dead. You do not get hit in the doorway: a full
      // recovery window, and the night's ease-in is partly re-armed.
      aftermathSpan = scareRecovery(s);
      aftermath = aftermathSpan;
      nightAnoms = 1;
      scheduleNext();
      audio.setStatic(0.03);
      audio.setDrone(0, 42);
      audio.deadAir(false);
      s.toast('SPONSOR SECURED — BACK ON AIR', ToastKind.gold);
      notifyListeners();
    });
  }

  /// 06:00. The thing the whole night was for.
  void dawn() {
    if (lost) return;
    lost = true;
    active = null;
    warn = 0;
    warnDef = null;
    _clearScareFx();
    audio.setStatic(0.03);
    audio.setDrone(0, 42);
    audio.deadAir(false);
    audio.setHeart(46, 0);
    audio.env('sine', 523, 0.9, 0.12, 523);
    _later(300, () => audio.env('sine', 659, 0.9, 0.12, 659));
    _later(600, () => audio.env('sine', 784, 1.6, 0.14, 784));
    s.survived++;
    s.dawnBonus = 6; // surviving is worth more than bailing out
    final g = rpGain(s) + s.dawnBonus;
    final mult = (1 + (s.rp + g) * 0.08).toStringAsFixed(2);
    endScreen = EndScreen.dawn;
    endScreenModel = EndScreenModel(
      win: true,
      title: '☀ 06:00 — SIGN-OFF',
      reviveLabel: null,
      acceptLabel: 'SIGN THE LOG — BANK ${fmt(g)} RP',
      body: <EndPara>[
        EndPara(<String>[
          'The test card comes up on its own. Whatever was in the signal goes '
              'back down into it, the way it does every morning, and the room '
              'is just a room again.',
        ]),
        EndPara(<String>[
          '',
          'YOU MADE IT TO 06:00.',
          ' Night ${s.night} survived — ${s.stats.banished} banished, '
              '${s.stats.scared} got through, best streak '
              '${s.stats.bestStreak}.',
        ]),
        EndPara(<String>[
          'Sign the log and hand over. Bank ',
          '${fmt(g)} ratings points',
          ' (permanent ×$mult to everything) and open NIGHT ${s.night + 1}, '
              'which starts at 23:00 and is worse.',
        ]),
        EndPara(<String>['Nights survived: ${s.survived}'], ParaStyle.fine),
      ],
    );
    notifyListeners();
  }

  /// Prestige. Banks RP, wipes the run, starts the next night.
  void signOff() {
    endScreen = EndScreen.none;
    endScreenModel = null;
    // rpGain() must be read BEFORE lifetimeSig is cleared.
    final g = rpGain(s) + s.dawnBonus;
    s.dawnBonus = 0;
    s.rp += g;
    s.resetForNewNight();
    lost = false;
    active = null;
    // A new night starts clean: signalLost() left the bed wound up and a
    // telegraphed anomaly may still have been pending.
    warn = 0;
    warnDef = null;
    shake = 0;
    flash = 0;
    glitch = 0;
    banishFx = 0;
    wrongFx = 0;
    keyFlashes.clear();
    _clearScareFx();
    // A fresh night gets the slow opening back.
    nightAnoms = 0;
    audio.setStatic(0.03);
    audio.setDrone(0, 42);
    audio.deadAir(false);
    scheduleNext();
    s.save();
    s.toast('SIGNED OFF — +${fmt(g)} RP — NIGHT ${s.night} BEGINS',
        ToastKind.gold);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Sponsor
  // -------------------------------------------------------------------------

  /// SPONSOR key: watch a spot for ×3 output for 60s, then a 150s cooldown.
  void takeSponsor() {
    if (s.sponsorCd > 0 || s.sponsorEnd > 0) return;
    _rollAd('SPONSORED SEGMENT', () {
      s.sponsorEnd = 60;
      s.sponsorCd = 150;
      s.toast('SPONSORED SEGMENT — ×3 OUTPUT FOR 60s', ToastKind.gold);
      audio.env('triangle', 440, 0.2, 0.14, 880);
      notifyListeners();
    });
  }

  bool get sponsorReady => s.sponsorEnd <= 0 && s.sponsorCd <= 0;

  void _rollAd(String label, void Function() done) {
    final fn = playAd;
    if (fn == null) {
      done();
      return;
    }
    fn(label, done);
  }

  // -------------------------------------------------------------------------
  // Main loop  (JS section 9, simulation half)
  // -------------------------------------------------------------------------

  /// One frame. Call from a Ticker with the real delta, already clamped by the
  /// caller if you want the JS `Math.min(0.1, dt)` guard — this method applies
  /// it anyway.
  ///
  /// Rendering, the lurkers in the field and the ad-break tick are NOT done
  /// here; they belong to the scene and ad controllers.
  void tick(double rawDt) {
    final double dt = rawDt > 0.1 ? 0.1 : (rawDt < 0 ? 0.0 : rawDt);
    tGlobal += dt;

    if (signedOn && !adPlaying && !lost) {
      _simulate(dt);
    }

    // The room keeps breathing behind modals, the manual and the ad break.
    audio.tick(dt);
    audio.setDread(s.dread / 100);

    s.tune.tick(dt, tGlobal);

    shake = math.max(0, shake - dt * 36);
    flash = math.max(0, flash - dt * 3.2);
    // The false clear holds its green wash until the beat takes it away.
    if (!falseClear) banishFx = math.max(0, banishFx - dt * 2.4);
    wrongFx = math.max(0, wrongFx - dt * 3);
    blackout = math.max(0, blackout - dt);
    if (scare > 0) {
      scare -= dt;
      if (scare <= 0) {
        scare = 0;
        scareDef = null;
      }
    } else if (afterimage > 0) {
      // The burn only starts fading once the scare frame is off the tube.
      afterimage = afterimageSpan <= 0 ? 0 : afterimage - dt / afterimageSpan;
      if (afterimage <= 0) {
        afterimage = 0;
        afterimageSpan = 0;
        afterimageDef = null;
        scareBeat = null;
      }
    }
    if (keyFlashes.isNotEmpty) {
      keyFlashes.forEach((_, f) => f.t += dt);
      keyFlashes.removeWhere((_, f) => f.t >= KeyFlash.duration);
    }

    s.toasts.tick(dt);
    notifyListeners();
  }

  void _simulate(double dt) {
    // --- economy ---
    final sr = sigRate(s, this);
    // THE TEST CARD GIRL: income goes into her lap instead of the bank. Nothing
    // is destroyed — the bank never falls — it just stops arriving.
    final a0 = active;
    if (sabOn('card') && a0 != null) {
      a0.held += sr * dt * sabK();
      s.sig += sr * dt * (1 - sabK());
    } else {
      s.sig += sr * dt;
    }
    // Quotas are met by TRANSMITTING. Output counts even while the Test Card
    // Girl is holding the bank, because it did go out — she just kept it.
    final out = sr * dt;
    s.segSig += out;
    s.lifetimeSig += out;
    s.airtime += dt;

    // --- the shift clock ---
    // Runs freely to :59 then HOLDS until the segment's quota is met.
    final seg0 = segIndex(s);
    if (s.shiftMin % 60 >= 59 && !quotaMet(s)) {
      if (!s.stalled) {
        s.stalled = true;
        s.toast('⧗ CLOCK HELD — ${segOf(s).nm} IS SHORT OF VIEWERS',
            ToastKind.bad);
      }
      s.dread = math.min(100, s.dread + dt * 0.9);
    } else {
      if (s.stalled) {
        s.stalled = false;
        s.toast('QUOTA MET — CLOCK RUNNING', ToastKind.good);
      }
      s.shiftMin += dt / kMinReal;
      if (segIndex(s) != seg0 && s.shiftMin < kShiftMinutes) {
        // A quota measures what you broadcast DURING its segment. Without this
        // reset the thresholds silently became cumulative, which is not what
        // the HUD ("BROADCAST / THIS SEGMENT") or the Nielsen's restatement say.
        s.segSig = 0;
        final sg = segOf(s);
        s.toast('▶ ${shiftClock(s)}  ${sg.nm}', ToastKind.gold);
        s.toasts.pushDelayed(1100, sg.line, ToastKind.gold);
        audio.env('sine', 392, 0.5, 0.10, 392);
        _later(260, () => audio.env('sine', 523, 0.7, 0.10, 523));
      }
      if (s.shiftMin >= kShiftMinutes) dawn();
    }

    // --- dread decay ---
    // Bleeds off much faster inside a protection window. Recovering from a
    // scare is supposed to be something you can watch happen, and the calm you
    // bought with a clean kill should visibly pay for the last one.
    var dec = (s.ups['failsafe'] ?? false) ? 1.6 : 0.8;
    if (aftermath > 0) {
      dec *= 2.6;
    } else if (calm > 0) {
      dec *= 1.5;
    }
    if (active == null) s.dread = math.max(0, s.dread - dec * dt);

    // --- sponsor timers ---
    if (s.sponsorEnd > 0) {
      s.sponsorEnd -= dt;
      if (s.sponsorEnd <= 0) {
        s.sponsorEnd = 0;
        s.toast('SPONSORSHIP ENDED', ToastKind.gold);
      }
    } else if (s.sponsorCd > 0) {
      s.sponsorCd -= dt;
    }

    // --- anomaly scheduler ---
    final a = active;
    if (a != null) {
      a.t += dt;
      s.dread = math.min(100, s.dread + dt * (1.2 + depth(s) * 0.02));
      final p = a.t / a.window;
      audio.setStatic(a.def.id == 'dead' ? 0.005 : 0.08 + p * 0.22);
      // 54 -> 172bpm; p*p back-loads the panic
      audio.setHeart(54 + p * p * 118, 0.10 + p * 0.34);
      sabotageTick(dt, p);
      if (a.t >= a.window) jumpscare();
    } else if (warn > 0) {
      warn -= dt;
      if (warn <= 0) manifest();
    } else {
      // Between anomalies the heart is only there if the night has gone badly.
      audio.setHeart(44 + s.dread * 0.36,
          s.dread > 55 ? (s.dread - 55) / 45 * 0.13 : 0);
      // The gap timer is FROZEN inside a protection window. This is the whole
      // promise: while ALL CLEAR (or the post-scare recovery) is up, nothing
      // can telegraph and nothing can manifest, full stop.
      if (aftermath > 0) {
        aftermath -= dt;
        if (aftermath <= 0) {
          aftermath = 0;
          aftermathSpan = 0;
        }
      } else if (calm > 0) {
        // Calm BLOCKS a manifest; it must not also pause the countdown, or the
        // protection is additive to the gap and the effective spacing nearly
        // doubles. Measured before this: a whole night peaked at 3.2 dread.
        nextAt -= dt;
        calm -= dt;
        if (calm <= 0) {
          calm = 0;
          calmSpan = 0;
          // The lamp going out is the only warning that the gap is live again.
          audio.env('sine', 240, 0.22, 0.045, 190);
        }
      } else {
        nextAt -= dt;
        if (nextAt <= 0) beginWarn();
      }
    }
    if (s.dread >= 100 && active == null && !lost) signalLost();
  }

  /// JS setTimeout. Fire-and-forget; every callback is written to be a no-op if
  /// the world moved on.
  void _later(int millis, void Function() fn) {
    Future<void>.delayed(Duration(milliseconds: millis), fn);
  }
}
