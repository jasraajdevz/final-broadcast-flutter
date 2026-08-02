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

  /// 0..1 progress through the banish window.
  double get p => window <= 0 ? 0 : t / window;
}

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
  // Scheduler
  // -------------------------------------------------------------------------

  void scheduleNext() {
    nextAt = anomInterval(s);
  }

  void beginWarn() {
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
      // Banishing is the FAST way to make quota.
      final vg = math.max(3.0, segOf(s).quota * (fast ? 0.16 : 0.09));
      s.subs += vg;
      s.lifetimeSubs += vg;
      banishFx = 1;
      s.dread = math.max(0, s.dread - 6);
      if (!silent) audio.banishStinger(fast);
      s.toast(
          '${fast ? "CLEAN KILL — " : "BANISHED — "}${a.def.nm}  +${fmt(bonus)} SIG'
          '${s.stats.streak > 2 ? "   ×${s.stats.streak} STREAK" : ""}',
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

  /// JS jumpscare(). The window ran out.
  void jumpscare() {
    final a = active;
    if (a == null) return;
    final def = a.def;
    active = null;
    glitch = 0;
    scare = 1.5;
    scareDef = def;
    shake = 26;
    flash = 1;
    audio.scare();
    audio.setStatic(0.22);
    audio.setDrone(0, 42);
    audio.deadAir(false);
    audio.setHeart(150, 0.30);
    _later(1400, () {
      audio.setStatic(0.03);
      audio.setHeart(70, 0.06);
    });

    s.stats.scared++;
    s.stats.streak = 0;
    final half = (s.ups['lead'] ?? false) ? 0.5 : 1.0;
    final halo = s.ups['halo'] ?? false;
    var lostSig = 0.0, lostSub = 0.0;
    if (def.id == 'niel') {
      lostSub = halo ? 0 : s.subs * 0.28 * half;
      s.subs -= lostSub;
      lostSig = s.sig * 0.10 * half;
      s.sig -= lostSig;
    } else if (def.id == 'card') {
      // She already has the pile; taking a third of the bank on top would be a
      // double charge for the same visit. Reported loss includes `held`, but
      // only the 10% is actually deducted — held was never in the bank.
      lostSig = a.held + s.sig * 0.10 * half;
      s.sig -= s.sig * 0.10 * half;
    } else if (def.id == 'dead') {
      lostSig = s.sig * 0.55 * half;
      s.sig -= lostSig;
    } else {
      lostSig = s.sig * 0.32 * half;
      s.sig -= lostSig;
      lostSub = halo ? 0 : s.subs * 0.08 * half;
      s.subs -= lostSub;
    }
    s.sig = math.max(0, s.sig);
    s.subs = math.max(0, s.subs);
    s.dread = math.min(100, s.dread + 26);
    s.toast(
        '✖ ${def.nm} GOT THROUGH — −${fmt(lostSig)} SIG'
        '${lostSub > 1 ? " / −${fmt(lostSub)} SUBS" : ""}',
        ToastKind.bad);
    scheduleNext();
    if (s.dread >= 100) signalLost();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // SIGNAL LOST / REVIVE / DAWN / SIGN OFF
  // -------------------------------------------------------------------------

  void signalLost() {
    if (lost) return;
    lost = true;
    active = null;
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
      scheduleNext();
      audio.setStatic(0.03);
      audio.setDrone(0, 42);
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
    // rpGain() must be read BEFORE lifetimeSubs is cleared.
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
    scare = 0;
    scareDef = null;
    shake = 0;
    flash = 0;
    glitch = 0;
    keyFlashes.clear();
    audio.setStatic(0.03);
    audio.setDrone(0, 42);
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
    banishFx = math.max(0, banishFx - dt * 2.4);
    wrongFx = math.max(0, wrongFx - dt * 3);
    if (scare > 0) {
      scare -= dt;
      if (scare <= 0) {
        scare = 0;
        scareDef = null;
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
    final ur = subRate(s, this);
    // THE TEST CARD GIRL: income goes into her lap instead of the bank. Nothing
    // is destroyed — the bank never falls — it just stops arriving.
    final a0 = active;
    if (sabOn('card') && a0 != null) {
      a0.held += sr * dt * sabK();
      s.sig += sr * dt * (1 - sabK());
    } else {
      s.sig += sr * dt;
    }
    final dsub = ur * dt;
    s.subs += dsub;
    s.lifetimeSubs += dsub;
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
        final sg = segOf(s);
        s.toast('▶ ${shiftClock(s)}  ${sg.nm}', ToastKind.gold);
        s.toasts.pushDelayed(1100, sg.line, ToastKind.gold);
        audio.env('sine', 392, 0.5, 0.10, 392);
        _later(260, () => audio.env('sine', 523, 0.7, 0.10, 523));
      }
      if (s.shiftMin >= kShiftMinutes) dawn();
    }

    // --- dread decay ---
    final dec = ((s.ups['failsafe'] ?? false) ? 1.6 : 0.8) * dt;
    if (active == null) s.dread = math.max(0, s.dread - dec);

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
      nextAt -= dt;
      if (nextAt <= 0) beginWarn();
    }
    if (s.dread >= 100 && active == null && !lost) signalLost();
  }

  /// JS setTimeout. Fire-and-forget; every callback is written to be a no-op if
  /// the world moved on.
  void _later(int millis, void Function() fn) {
    Future<void>.delayed(Duration(milliseconds: millis), fn);
  }
}
