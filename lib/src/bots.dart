// FINAL BROADCAST — the automation rack.
//
// KBLK-7 was built in 1968 for a staff of nine. There is one of you. Everything
// in this file is a piece of the station that used to be somebody's job, wired
// back up and left running unattended: a solenoid keying arm on the bezel, the
// dock camera nobody watches, a stagehand, the basement stock terminal, the
// night manager's office, and the vault's tape robot.
//
// DESIGN RULES, all load-bearing:
//   * Every bot does a job you can already do BY HAND, slower and worse. None
//     of them does something new.
//   * Every rate is capped by level and every level is capped. Nothing here
//     scales without a ceiling.
//   * The strong ones FAIL UNDER DREAD. botFailChance() is zero below 40 dread
//     and climbs to a coin flip at 100 — a bot that never misfires deletes the
//     horror, so the moment you most need the Librarian is the moment it jams.
//   * Nothing may make a run unwinnable. No bot can press a WRONG key, no bot
//     adds dread, and every bot has an OFF switch that persists.
//   * The Keying Arm's output is BANK ONLY — it never touches s.segSig or
//     s.lifetimeSig, exactly like the manual strike it imitates, so automation
//     can never pay a quota or inflate prestige.
//
// PERSISTENCE. This file owns no fields on GameState and does not need any.
// Levels live in `s.prod` under "bot.<id>" (an int map that is saved verbatim
// and only ever read by explicit key elsewhere). The OFF switch and the beaten
// log live in `s.ups` under "bot.off.<id>" / "bot.beat.<id>" — note that
// GameState.readJson drops `false` values out of `ups`, so "disabled" is stored
// as the PRESENCE of a true key, never as false.
//
// Bots survive sign-off, like the one-time hardware in the HARDWARE tab. They
// are installed equipment, not stock.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'anomalies.dart';
import 'consts.dart';
import 'economy.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Save keys — prefixed so they can never collide with a producer / upgrade id.
// ---------------------------------------------------------------------------

String botLevelKey(String id) => 'bot.$id';
String botOffKey(String id) => 'bot.off.$id';
String botBeatKey(String anomId) => 'bot.beat.$anomId';

// ---------------------------------------------------------------------------
// The dread failure curve — the single knob that keeps automation frightening.
// ---------------------------------------------------------------------------

/// 0 below 40 dread, rising to 0.5 at 100. Every bot that could carry the night
/// on its own rolls against this.
double botFailChance(double dread) {
  if (dread <= 40) return 0;
  return clampD((dread - 40) / 60 * 0.5, 0, 0.5);
}

// ---------------------------------------------------------------------------
// Definitions
// ---------------------------------------------------------------------------

typedef BotReq = bool Function(GameState s);

class BotDef {
  const BotDef({
    required this.id,
    required this.nm,
    required this.ds,
    required this.cost,
    required this.mul,
    required this.maxLvl,
    required this.req,
    required this.reqNote,
  });

  final String id;
  final String nm;

  /// Where it is in the building and what it does, in fiction.
  final String ds;

  /// Cost of level 1. Level n costs `cost * mul^(n-1)`.
  final double cost;
  final double mul;
  final int maxLvl;

  /// Unlock predicate. Locked rows are still SHOWN, greyed, with [reqNote].
  final BotReq req;
  final String reqNote;
}

/// Six of them. Ordered by price, which is also roughly the order you need
/// them in.
final List<BotDef> kBots = <BotDef>[
  BotDef(
    id: 'arm',
    nm: 'KEYING ARM',
    ds: 'A solenoid arm off the old telecine, clamped to the bezel. It hits '
        'the tube where you hit it, forever, without getting bored.',
    cost: 450,
    mul: 3.4,
    maxLvl: 5,
    req: (s) => s.tune.strikes >= 15,
    reqNote: 'STRIKE THE TUBE 15 TIMES BY HAND',
  ),
  BotDef(
    id: 'eye',
    nm: 'THE WATCHER',
    ds: 'Loading-dock camera, patched to the spare monitor. Somebody has to '
        'look at the corridor, and it is not going to be you.',
    cost: 3.4e3,
    mul: 3.8,
    maxLvl: 3,
    req: (s) => s.stats.scared >= 1 || s.stats.banished >= 4,
    reqNote: 'LET ONE GET THROUGH, OR BANISH 4',
  ),
  BotDef(
    id: 'grip',
    nm: 'THE GRIP',
    ds: 'Night-shift stagehand. Re-racks the emergency key you fumbled and '
        're-cues the sponsor reel while you are still swearing.',
    cost: 2.4e4,
    mul: 4.2,
    maxLvl: 3,
    req: (s) => s.stats.wrong >= 2,
    reqNote: 'PRESS 2 WRONG KEYS (YOU WILL)',
  ),
  BotDef(
    id: 'store',
    nm: 'THE STOREMAN',
    ds: 'Basement stock terminal with a working requisition printer. It buys '
        'transmitters out of the float without asking you first.',
    cost: 1.8e5,
    mul: 4.6,
    maxLvl: 4,
    req: (s) => s.stats.banished >= 6,
    reqNote: 'BANISH 6',
  ),
  BotDef(
    id: 'mgr',
    nm: 'THE NIGHT MANAGER',
    ds: 'He has an office on three that nobody has seen inside. When the '
        'clock holds he puts your reserves on the air at a loss.',
    cost: 2.2e6,
    mul: 5.0,
    maxLvl: 3,
    req: (s) => s.night >= 2 || s.rp >= 1,
    reqNote: 'SURVIVE OR SIGN OFF ONE NIGHT',
  ),
  BotDef(
    id: 'libr',
    nm: 'THE LIBRARIAN',
    ds: "The vault's tape robot. It can only pull the counter-tape for "
        'something you have beaten yourself — it reads your log, not the '
        'manual.',
    cost: 2.6e7,
    mul: 5.6,
    maxLvl: 3,
    req: (s) => s.stats.banished >= 15,
    reqNote: 'BANISH 15',
  ),
];

final Map<String, BotDef> kBotBy = <String, BotDef>{
  for (final b in kBots) b.id: b,
};

// ---------------------------------------------------------------------------
// Tuning tables. One function per bot per knob, so every ceiling is visible.
// ---------------------------------------------------------------------------

/// KEYING ARM strikes per second. Hard ceiling 2.4/s at level 5.
double armRate(int lvl) => const <double>[0, 0.5, 0.9, 1.3, 1.8, 2.4][lvl];

/// Fraction of a hand strike each automated strike is worth. Never 1 — the arm
/// is a worse operator than you are.
double armEff(int lvl) => lvl <= 0 ? 0 : 0.34 + 0.02 * lvl;

/// THE WATCHER — extra telegraph seconds. Ceiling +1.2s.
double eyeBonus(int lvl) => 0.4 * lvl;

/// THE GRIP — extra sponsor-cooldown bleed, in seconds per second.
double gripSponsor(int lvl) => 0.22 * lvl;

/// THE GRIP — dread handed back per fumbled key (of the 3 it costs).
double gripDread(int lvl) => 0.5 * lvl;

/// THE GRIP — banish-window seconds handed back per fumbled key.
double gripTime(int lvl) => 0.14 * lvl;

/// THE STOREMAN — share of the bank one requisition may spend. Deliberately
/// kept a third or less: he must never be able to strip the float you are
/// saving with, and the switch is there for when he is.
double storeShare(int lvl) => 0.13 + 0.05 * lvl;

/// THE STOREMAN — seconds between requisitions.
double storeEvery(int lvl) => 26 - 4.5 * lvl;

/// THE NIGHT MANAGER — share of the bank he moves per second while stalled.
double mgrPull(int lvl) => 0.05 + 0.03 * lvl;

/// THE NIGHT MANAGER — how much of what he moves actually goes out. The rest
/// is what it costs to put reserves on air at four in the morning.
double mgrEff(int lvl) => 0.50 + 0.08 * lvl;

/// THE NIGHT MANAGER — he can only ever cover this share of one segment's
/// quota. The stall has to stay frightening.
const double kMgrSegCap = 0.55;

/// THE NIGHT MANAGER — above this dread he is simply not at his desk.
const double kMgrGoneAt = 88;

/// THE LIBRARIAN — how far through the banish window it waits before acting.
/// You always get the first half of every window yourself.
double librAt(int lvl) => 0.62 - 0.06 * lvl;

/// THE LIBRARIAN — seconds to rewind between pulls.
double librEvery(int lvl) => 90.0 - 18 * lvl;

/// THE LIBRARIAN — above this dread the vault browns out and it will not move.
const double kLibrBrownoutAt = 85;

// ---------------------------------------------------------------------------
// BotRuntime
// ---------------------------------------------------------------------------

/// Ticked once per frame, immediately after AnomalyRuntime.tick(). Everything
/// it needs it reads through the existing public API of GameState /
/// AnomalyRuntime / economy.dart; it owns no state on either.
class BotRuntime extends ChangeNotifier {
  BotRuntime(this.s, this.runtime) {
    _night = s.night;
    _seg = segIndex(s);
    _wrongSeen = s.stats.wrong;
    _banishedSeen = s.stats.banished;
  }

  final GameState s;
  final AnomalyRuntime runtime;

  static final Expando<BotRuntime> _attached = Expando<BotRuntime>();

  /// The one instance for this GameState. Lets the rack reach the runtime
  /// without a new constructor argument; main.dart still owns the tick.
  static BotRuntime of(GameState s, AnomalyRuntime runtime) =>
      _attached[s] ??= BotRuntime(s, runtime);

  // --- observers ---
  int _night = 1;
  int _seg = 0;
  int _wrongSeen = 0;
  int _banishedSeen = 0;
  String? _lastActiveId;

  // --- KEYING ARM ---
  double _armAcc = 0;
  double _armPaid = 0;
  int _armSkipped = 0;

  // --- THE WATCHER ---
  bool _warnHandled = false;
  int _eyeSaves = 0;
  int _eyeBlind = 0;

  // --- THE GRIP ---
  double _gripFlash = 0;
  int _gripCatches = 0;

  // --- THE STOREMAN ---
  double _storeCd = 4;
  int _storeBought = 0;
  final Set<String> _storeSeen = <String>{};

  // --- THE NIGHT MANAGER ---
  double _mgrGiven = 0;
  double _mgrPause = 0;
  bool _mgrOnAir = false;

  // --- THE LIBRARIAN ---
  double _librCd = 0;
  ActiveAnom? _librHandled;
  int _librPulls = 0;
  int _librJams = 0;

  // -------------------------------------------------------------------------
  // Ownership
  // -------------------------------------------------------------------------

  int levelOf(BotDef b) {
    final v = s.prod[botLevelKey(b.id)] ?? 0;
    return v < 0 ? 0 : (v > b.maxLvl ? b.maxLvl : v);
  }

  bool unlocked(BotDef b) => levelOf(b) > 0 || b.req(s);

  /// Absent key == running. See the note at the top of the file.
  bool enabled(BotDef b) => !(s.ups[botOffKey(b.id)] ?? false);

  bool live(BotDef b) => levelOf(b) > 0 && enabled(b);

  void setEnabled(BotDef b, bool on) {
    if (on) {
      s.ups.remove(botOffKey(b.id));
    } else {
      s.ups[botOffKey(b.id)] = true;
    }
    if (b.id == 'mgr' && !on) _mgrOnAir = false;
    s.save();
    s.bump();
    notifyListeners();
  }

  void toggle(BotDef b) => setEnabled(b, !enabled(b));

  bool maxed(BotDef b) => levelOf(b) >= b.maxLvl;

  /// Cost of the NEXT level. Infinity when maxed, so `s.sig >= costOf` is
  /// always false there.
  double costFor(BotDef b) {
    final lvl = levelOf(b);
    if (lvl >= b.maxLvl) return double.infinity;
    return b.cost * math.pow(b.mul, lvl);
  }

  bool canBuy(BotDef b) =>
      unlocked(b) && !maxed(b) && s.sig >= costFor(b);

  /// Spends and installs. Returns false and changes nothing if it cannot.
  bool buy(BotDef b) {
    if (!canBuy(b)) return false;
    final c = costFor(b);
    s.sig -= c;
    final lvl = levelOf(b) + 1;
    s.prod[botLevelKey(b.id)] = lvl;
    // A freshly patched machine does not fire on the same frame.
    if (b.id == 'store') _storeCd = math.max(_storeCd, 3);
    if (b.id == 'libr') _librCd = math.max(_librCd, 6);
    s.save();
    s.bump();
    notifyListeners();
    return true;
  }

  // -------------------------------------------------------------------------
  // The beaten log — what THE LIBRARIAN is allowed to touch
  // -------------------------------------------------------------------------

  bool beaten(String anomId) => s.ups[botBeatKey(anomId)] ?? false;

  int get beatenCount => kAnoms.where((a) => beaten(a.id)).length;

  // -------------------------------------------------------------------------
  // Frame
  // -------------------------------------------------------------------------

  /// Call once per frame from the shell, AFTER `runtime.tick(dt)`. Never call
  /// it from inside a listener on AnomalyRuntime — the Librarian presses a key,
  /// which notifies, and that would re-enter.
  void tick(double rawDt) {
    final double dt = rawDt > 0.1 ? 0.1 : (rawDt < 0 ? 0.0 : rawDt);
    if (dt <= 0) return;

    if (s.night != _night) {
      _night = s.night;
      _newNight();
    }

    _gripFlash = math.max(0, _gripFlash - dt);

    if (!(runtime.signedOn && !runtime.adPlaying && !runtime.lost)) {
      // Stay in sync so a spell behind a modal cannot be cashed in later.
      _wrongSeen = s.stats.wrong;
      _banishedSeen = s.stats.banished;
      _warnHandled = runtime.warn > 0;
      return;
    }

    final seg = segIndex(s);
    if (seg != _seg) {
      _seg = seg;
      _mgrGiven = 0;
      _mgrOnAir = false;
    }

    _observeFumbles();
    _observeBeaten();

    _tickArm(dt);
    _tickWatcher();
    _tickGrip(dt);
    _tickStoreman(dt);
    _tickManager(dt);
    _tickLibrarian(dt);
  }

  void _newNight() {
    // Levels persist — installed equipment. The transient half does not.
    _armAcc = 0;
    _armPaid = 0;
    _armSkipped = 0;
    _warnHandled = false;
    _storeCd = 4;
    _storeSeen.clear();
    _mgrGiven = 0;
    _mgrPause = 0;
    _mgrOnAir = false;
    _librCd = 0;
    _librHandled = null;
    _seg = segIndex(s);
  }

  // --- observers -----------------------------------------------------------

  /// THE GRIP catches the key you dropped. Reads the stats counter rather than
  /// hooking wrongPress(), so it needs nothing from anomalies.dart.
  void _observeFumbles() {
    final now = s.stats.wrong;
    if (now > _wrongSeen) {
      final b = kBotBy['grip']!;
      final lvl = levelOf(b);
      if (lvl > 0 && enabled(b)) {
        final n = now - _wrongSeen;
        s.dread = math.max(0, s.dread - gripDread(lvl) * n);
        final a = runtime.active;
        if (a != null) a.t = math.max(0, a.t - gripTime(lvl) * n);
        _gripCatches += n;
        _gripFlash = 0.9;
      }
    }
    _wrongSeen = now;
  }

  /// An anomaly that went away while `banished` went up is one you beat. That
  /// is the only thing THE LIBRARIAN is ever allowed to act on.
  void _observeBeaten() {
    final a = runtime.active;
    if (a != null) {
      _lastActiveId = a.def.id;
    } else {
      final id = _lastActiveId;
      if (id != null) {
        if (s.stats.banished > _banishedSeen && !beaten(id)) {
          s.ups[botBeatKey(id)] = true;
          s.toast('LOGGED AS BEATEN — ${kAnomBy[id]?.nm ?? id}', ToastKind.gold);
        }
        _lastActiveId = null;
      }
      _librHandled = null;
    }
    _banishedSeen = s.stats.banished;
  }

  // --- KEYING ARM ----------------------------------------------------------

  void _tickArm(double dt) {
    final b = kBotBy['arm']!;
    final lvl = levelOf(b);
    if (lvl <= 0 || !enabled(b)) return;

    _armAcc += dt * armRate(lvl);
    var guard = 0;
    while (_armAcc >= 1 && guard < 6) {
      _armAcc -= 1;
      guard++;
      if (rand() < botFailChance(s.dread)) {
        _armSkipped++;
        continue;
      }
      final g = tuneYield(s, runtime) * armEff(lvl);
      // BANK ONLY. Same contract as AnomalyRuntime.tuneStrike().
      s.sig += g;
      _armPaid += g;
      // It is visibly hitting the tube — but only while YOUR hand is off it,
      // so the arm can never pin the phosphor heat or drown your own feedback.
      if (s.tune.heat < 0.55) {
        s.tune.strike(
          rr(kScr.left + 46, kScr.left + 150),
          rr(kScr.bottom - 96, kScr.bottom - 34),
          '+${fmt(g)}',
          runtime.tGlobal,
        );
        runtime.audio.tune(s.tune.heat);
      }
    }
  }

  // --- THE WATCHER ---------------------------------------------------------

  void _tickWatcher() {
    final warning = runtime.warn > 0 && runtime.active == null;
    if (!warning) {
      _warnHandled = false;
      return;
    }
    if (_warnHandled) return;
    _warnHandled = true;

    final b = kBotBy['eye']!;
    final lvl = levelOf(b);
    if (lvl <= 0 || !enabled(b)) return;

    if (rand() < botFailChance(s.dread)) {
      _eyeBlind++;
      s.toast('CAMERA 2 IS NOTHING BUT SNOW', ToastKind.bad);
      return;
    }
    _eyeSaves++;
    runtime.warn += eyeBonus(lvl);
    // Re-issue the swell so the cue still lands on the manifest instead of
    // topping out early.
    runtime.audio.riser(runtime.warn);
  }

  // --- THE GRIP ------------------------------------------------------------

  void _tickGrip(double dt) {
    final b = kBotBy['grip']!;
    final lvl = levelOf(b);
    if (lvl <= 0 || !enabled(b)) return;
    if (s.sponsorEnd <= 0 && s.sponsorCd > 0) {
      s.sponsorCd = math.max(0, s.sponsorCd - dt * gripSponsor(lvl));
    }
  }

  // --- THE STOREMAN --------------------------------------------------------

  void _tickStoreman(double dt) {
    final b = kBotBy['store']!;
    final lvl = levelOf(b);
    if (lvl <= 0 || !enabled(b)) return;

    _storeCd -= dt;
    if (_storeCd > 0) return;
    _storeCd = storeEvery(lvl);

    if (s.dread >= 70 && rand() < 0.35) {
      _storeCd *= 0.5;
      s.toast('THE BASEMENT DOOR IS LOCKED TONIGHT', ToastKind.bad);
      return;
    }

    final budget = s.sig * storeShare(lvl);
    Producer? best;
    for (var i = 0; i < kProducers.length; i++) {
      if (!producerUnlocked(s, i)) continue;
      if (costOf(s, kProducers[i]) <= budget) best = kProducers[i];
    }
    if (best == null) return;
    if (!buyProducer(s, best, 1)) return;

    _storeBought++;
    runtime.audio.click();
    if (_storeSeen.add(best.id)) {
      s.toast('REQUISITION FILED — ${best.nm}', ToastKind.good);
      s.save();
    }
  }

  // --- THE NIGHT MANAGER ---------------------------------------------------

  void _tickManager(double dt) {
    final b = kBotBy['mgr']!;
    final lvl = levelOf(b);
    if (lvl <= 0 || !enabled(b)) return;

    if (!s.stalled || quotaMet(s)) {
      if (_mgrOnAir) {
        _mgrOnAir = false;
        s.toast('THE NIGHT MANAGER GOES BACK UPSTAIRS', ToastKind.plain);
      }
      return;
    }

    if (s.dread >= kMgrGoneAt) {
      if (_mgrOnAir) {
        _mgrOnAir = false;
        s.toast('THE NIGHT MANAGER IS NOT AT HIS DESK', ToastKind.bad);
      }
      return;
    }

    if (_mgrPause > 0) {
      _mgrPause -= dt;
      return;
    }
    if (rand() < botFailChance(s.dread) * dt * 0.9) {
      _mgrPause = rr(1.8, 3.6);
      return;
    }

    final seg = segOf(s);
    final left = seg.quota * kMgrSegCap - _mgrGiven;
    if (left <= 0) return;

    final eff = mgrEff(lvl);
    final need = seg.quota - s.segSig;
    if (need <= 0) return;

    var pull = s.sig * mgrPull(lvl) * dt;
    pull = math.min(pull, need / eff);
    pull = math.min(pull, left / eff);
    pull = math.min(pull, s.sig);
    if (pull <= 0) return;

    s.sig -= pull;
    final out = pull * eff;
    // Segment output ONLY. It was already counted as lifetime output when it
    // was earned; re-counting it here would launder the bank into prestige.
    s.segSig += out;
    _mgrGiven += out;

    if (!_mgrOnAir) {
      _mgrOnAir = true;
      s.toast('THE NIGHT MANAGER PUTS YOUR RESERVES ON THE AIR',
          ToastKind.gold);
    }
  }

  // --- THE LIBRARIAN -------------------------------------------------------

  void _tickLibrarian(double dt) {
    if (_librCd > 0) _librCd = math.max(0, _librCd - dt);

    final b = kBotBy['libr']!;
    final lvl = levelOf(b);
    if (lvl <= 0 || !enabled(b)) return;

    final a = runtime.active;
    if (a == null || identical(a, _librHandled)) return;
    // It cannot read a tape for something still wearing a mask. Stripping the
    // mask stays yours.
    if (a.masked && a.stage == 0) return;
    if (!beaten(a.def.id)) return;
    if (_librCd > 0) return;
    if (s.dread >= kLibrBrownoutAt) return;
    if (a.p < librAt(lvl)) return;

    _librHandled = a;

    if (rand() < botFailChance(s.dread)) {
      // It JAMS. It never pulls the wrong tape — a bot must not be able to
      // press a wrong key on your behalf — but you have lost the cooldown and
      // whatever is left of the window is yours.
      _librJams++;
      _librCd = librEvery(lvl) * 0.5;
      runtime.audio.env('square', 120, 0.18, 0.09, 70);
      s.toast('THE LIBRARIAN JAMMED — WRONG SHELF', ToastKind.bad);
      return;
    }

    _librPulls++;
    _librCd = librEvery(lvl);
    final c = kCounterBy[a.def.counter];
    s.toast('THE LIBRARIAN PULLS ${c?.nm ?? a.def.counter}', ToastKind.good);
    runtime.pressCounter(a.def.counter);
  }

  // -------------------------------------------------------------------------
  // Readouts for the panel
  // -------------------------------------------------------------------------

  /// What this bot does at [lvl]. `lvl` 0 means "what level 1 would do".
  String effectAt(BotDef b, int lvl) {
    final n = lvl <= 0 ? 1 : lvl;
    switch (b.id) {
      case 'arm':
        return '${armRate(n).toStringAsFixed(1)} strikes/s at '
            '${(armEff(n) * 100).round()}% of your hand · bank only';
      case 'eye':
        return '+${eyeBonus(n).toStringAsFixed(1)}s of telegraph before it '
            'manifests';
      case 'grip':
        return '-${gripDread(n).toStringAsFixed(1)} dread and '
            '+${gripTime(n).toStringAsFixed(2)}s back per wrong key · '
            'sponsor recharges ${(1 + gripSponsor(n)).toStringAsFixed(2)}x';
      case 'store':
        return 'buys 1 transmitter every ${storeEvery(n).toStringAsFixed(0)}s '
            'for up to ${(storeShare(n) * 100).round()}% of the bank';
      case 'mgr':
        return 'while the clock holds: ${(mgrPull(n) * 100).round()}% of bank/s '
            'to output at ${(mgrEff(n) * 100).round()}% · caps at '
            '${(kMgrSegCap * 100).round()}% of the quota';
      case 'libr':
        return 'auto-counters a BEATEN anomaly at '
            '${(librAt(n) * 100).round()}% of the window · '
            '${librEvery(n).toStringAsFixed(0)}s rewind';
    }
    return '';
  }

  /// The live right-hand readout: what it is doing this second.
  String statusOf(BotDef b) {
    final lvl = levelOf(b);
    if (lvl <= 0) return unlocked(b) ? 'NOT PATCHED' : 'SEALED';
    if (!enabled(b)) return 'OFF';
    final fail = botFailChance(s.dread);
    switch (b.id) {
      case 'arm':
        if (fail > 0.28) return 'STUTTERING';
        return '${armRate(lvl).toStringAsFixed(1)}/s · +${fmt(_armPaid)}';
      case 'eye':
        if (runtime.warn > 0) return 'SOMETHING IN THE HALL';
        return 'WATCHING · $_eyeSaves CALLS';
      case 'grip':
        if (_gripFlash > 0) return 'CAUGHT IT';
        return 'STANDING BY · $_gripCatches';
      case 'store':
        if (s.dread >= 70) return 'DOOR STICKS';
        return 'NEXT ${_storeCd.ceil()}s · $_storeBought FILED';
      case 'mgr':
        if (s.dread >= kMgrGoneAt) return 'NOT AT HIS DESK';
        if (_mgrOnAir) return 'ON THE AIR';
        if (_mgrPause > 0) return 'ON THE PHONE';
        return s.stalled ? 'WALKING DOWN' : 'AT HIS DESK';
      case 'libr':
        if (s.dread >= kLibrBrownoutAt) return 'VAULT BROWNOUT';
        if (_librCd > 0) return 'REWIND ${_librCd.ceil()}s';
        return 'READY · $beatenCount/${kAnoms.length} BEATEN';
    }
    return '';
  }

  /// A one-line warning about how this bot behaves as the night turns. Shown
  /// under the effect line so nobody is surprised by a jam.
  String? riskOf(BotDef b) {
    switch (b.id) {
      case 'arm':
        return 'MISSES STRIKES ABOVE 40 DREAD';
      case 'eye':
        return 'GOES TO SNOW ABOVE 40 DREAD';
      case 'grip':
        return null;
      case 'store':
        return 'SPENDS YOUR FLOAT — SWITCH HIM OFF TO SAVE   ·   '
            'REFUSES TO OPEN ABOVE 70 DREAD';
      case 'mgr':
        return 'LEAVES THE BUILDING ABOVE ${kMgrGoneAt.round()} DREAD';
      case 'libr':
        return 'JAMS ABOVE 40 DREAD · DEAD ABOVE '
            '${kLibrBrownoutAt.round()} · ONLY WHAT YOU HAVE BEATEN';
    }
    return null;
  }

  /// What the rack has actually done since the night began — including how
  /// often it let you down. Shown at the bottom of the AUTO tab.
  String tally() => 'ARM: ${fmt(_armPaid)} SIG, $_armSkipped MISSED   ·   '
      'WATCHER: $_eyeSaves CALLS, $_eyeBlind BLIND   ·   '
      'GRIP: $_gripCatches CAUGHT   ·   '
      'STOREMAN: $_storeBought FILED   ·   '
      'LIBRARIAN: $_librPulls PULLED, $_librJams JAMMED';

  /// 0..1 — how close the bank is to the next level, for the locked/unaffordable
  /// progress readout.
  int percentToward(BotDef b) {
    final c = costFor(b);
    if (!c.isFinite || c <= 0) return 100;
    return (s.sig / c * 100).floor().clamp(0, 99);
  }
}
