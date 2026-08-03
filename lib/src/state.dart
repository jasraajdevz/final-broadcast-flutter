// FINAL BROADCAST — game state.
//
// GameState is the JS `S` object, field for field, plus the two small runtime
// bags the original kept as separate globals but which are plainly state:
// TUNE (manual-strike feedback) and the toast queue.
//
// save()/load() write the IDENTICAL JSON shape under "finalbroadcast.v1", so a
// save made by the HTML build loads here and vice versa.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'consts.dart';
import 'meta.dart';
// Web-only local storage is quarantined behind this conditional import.
import 'storage_stub.dart' if (dart.library.js_interop) 'storage_web.dart';

// ---------------------------------------------------------------------------
// Toasts
// ---------------------------------------------------------------------------

enum ToastKind { plain, good, bad, gold }

class Toast {
  Toast(this.msg, this.kind);
  final String msg;
  final ToastKind kind;

  /// Age in seconds.
  double t = 0;
}

/// JS toast(): appended to a stack capped at 3, held 2.6s, then a 0.4s fade.
class ToastBus extends ChangeNotifier {
  static const double holdSeconds = 2.6;
  static const double fadeSeconds = 0.4;

  final List<Toast> items = <Toast>[];

  void push(String msg, [ToastKind kind = ToastKind.plain]) {
    items.add(Toast(msg, kind));
    while (items.length > 3) {
      items.removeAt(0);
    }
    notifyListeners();
  }

  /// JS `setTimeout(()=>toast(...), ms)`.
  void pushDelayed(int millis, String msg, [ToastKind kind = ToastKind.plain]) {
    Future<void>.delayed(Duration(milliseconds: millis), () => push(msg, kind));
  }

  /// Opacity for the fade-out, 1 -> 0 over the last 0.4s.
  double opacityOf(Toast t) {
    if (t.t <= holdSeconds) return 1;
    return clampD(1 - (t.t - holdSeconds) / fadeSeconds, 0, 1);
  }

  void tick(double dt) {
    if (items.isEmpty) return;
    var dirty = false;
    for (final t in items) {
      t.t += dt;
    }
    items.removeWhere((t) {
      final dead = t.t >= holdSeconds + fadeSeconds + 0.02;
      if (dead) dirty = true;
      return dead;
    });
    if (dirty) notifyListeners();
  }

  void clear() {
    items.clear();
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Manual tuning — striking the set
// ---------------------------------------------------------------------------

class TunePop {
  TunePop(this.x, this.y, this.v);
  final double x;
  final double y;

  /// Pre-formatted "+123" string.
  final String v;
  double t = 0;
}

class TuneRipple {
  TuneRipple(this.x, this.y);
  final double x;
  final double y;
  double t = 0;
}

/// JS `TUNE = {pops:[],ripples:[],heat:0,strikes:0,rate:0,recent:[]}`.
class TuneState {
  final List<TunePop> pops = <TunePop>[];
  final List<TuneRipple> ripples = <TuneRipple>[];
  double heat = 0;
  int strikes = 0;

  // --- CARRIER LOCK -------------------------------------------------------
  // The most-repeated verb in the game used to be flat: `heat` saturated after
  // four strikes and paid nothing at all, so the thing you do several hundred
  // times a night had no arc. Keeping a rhythm now builds a LOCK, in four
  // visible, audible steps, and letting the rhythm go drops it.

  /// 0..4. Multiplies the strike payout and drives the pop's size and colour.
  int tier = 0;

  /// Progress toward the next tier, 0..1.
  double lockP = 0;

  /// Seconds since the last strike. The lock decays once you stop.
  double idle = 0;

  /// Payout multiplier for the current lock.
  static const List<double> kTierMult = <double>[1.0, 1.3, 1.7, 2.2, 3.0];

  /// Strikes needed to reach each tier from the one below.
  static const List<int> kTierNeed = <int>[6, 10, 14, 18];

  /// How long a gap is forgiven before the lock starts falling apart.
  static const double kLockGrace = 1.1;

  int _held = 0;

  /// THE SNOW CRAWLER takes a tier off the lock. Drops to the FOOT of the tier
  /// below rather than the top of it, so a knock costs real strikes to undo —
  /// otherwise one more hit puts it straight back and the threat is theatre.
  void knockDown() {
    if (tier <= 0) return;
    tier--;
    lockP = 0;
    _held = 0;
  }

  double get tierMult => kTierMult[tier.clamp(0, 4)];

  /// The name printed on the lock meter.
  String get tierName => const <String>[
        '', 'CARRIER LOCK', 'STEADY', 'HOT', 'PEAKING',
      ][tier.clamp(0, 4)];

  /// Strikes in the last second (the "MANUAL HOLD n/s" readout).
  int rate = 0;
  final List<double> recent = <double>[];

  /// True when this strike pushed the lock up a step — the caller uses it to
  /// fire the escalation sting, so the step is heard as well as seen.
  bool lastStrikePromoted = false;

  void strike(double x, double y, String label, double tGlobal) {
    strikes++;
    recent.add(tGlobal);
    idle = 0;
    lastStrikePromoted = false;
    if (tier < 4) {
      _held++;
      final need = kTierNeed[tier];
      lockP = (_held / need).clamp(0.0, 1.0);
      if (_held >= need) {
        tier++;
        _held = 0;
        lockP = 0;
        lastStrikePromoted = true;
      }
    } else {
      lockP = 1;
    }
    heat = heat + 0.28 > 1 ? 1 : heat + 0.28;
    pops.add(TunePop(x, y, label));
    ripples.add(TuneRipple(x, y));
    if (pops.length > 16) pops.removeAt(0);
    if (ripples.length > 12) ripples.removeAt(0);
  }

  /// JS main-loop decay block. `tGlobal` is the global animation clock.
  void tick(double dt, double tGlobal) {
    heat = heat - dt * 0.55;
    if (heat < 0) heat = 0;
    // The lock is a rhythm, so it is held by CONTINUING, not by having once
    // reached it. A short gap is forgiven; a long one walks it back a step at
    // a time rather than dumping you to zero, which would feel like a punish.
    idle += dt;
    if (idle > kLockGrace && tier > 0) {
      final over = idle - kLockGrace;
      if (over > 0.85) {
        tier--;
        _held = 0;
        lockP = 0;
        idle = kLockGrace;
      }
    }
    for (final p in pops) {
      p.t += dt;
    }
    pops.removeWhere((p) => p.t >= 0.9);
    for (final r in ripples) {
      r.t += dt;
    }
    ripples.removeWhere((r) => r.t >= 0.55);
    recent.removeWhere((t) => tGlobal - t >= 1);
    rate = recent.length;
  }

  void reset() {
    tier = 0;
    lockP = 0;
    idle = 0;
    _held = 0;
    lastStrikePromoted = false;
    pops.clear();
    ripples.clear();
    recent.clear();
    heat = 0;
    rate = 0;
  }
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

/// JS `S.stats`.
class Stats {
  int banished = 0;
  int wrong = 0;
  int scared = 0;
  int perfect = 0;

  /// Saves landed in the last sliver of the window. The stat a player brags
  /// about, and the one the sign-off sheet leads with.
  int clutch = 0;
  int streak = 0;
  int bestStreak = 0;
  int ads = 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'banished': banished,
        'wrong': wrong,
        'scared': scared,
        'perfect': perfect,
        'clutch': clutch,
        'streak': streak,
        'bestStreak': bestStreak,
        'ads': ads,
      };

  void readJson(Map<String, dynamic> o) {
    banished = _int(o['banished'], banished);
    wrong = _int(o['wrong'], wrong);
    scared = _int(o['scared'], scared);
    perfect = _int(o['perfect'], perfect);
    clutch = _int(o['clutch'], clutch);
    streak = _int(o['streak'], streak);
    bestStreak = _int(o['bestStreak'], bestStreak);
    ads = _int(o['ads'], ads);
  }
}

int _int(dynamic v, int fallback) =>
    v is num ? v.round() : (v is String ? (int.tryParse(v) ?? fallback) : fallback);
double _dbl(dynamic v, double fallback) =>
    v is num ? v.toDouble() : (v is String ? (double.tryParse(v) ?? fallback) : fallback);
bool _bool(dynamic v, bool fallback) => v is bool ? v : fallback;
String _str(dynamic v, String fallback) => v is String ? v : fallback;

// ---------------------------------------------------------------------------
// GameState — the JS `S` object
// ---------------------------------------------------------------------------

class GameState extends ChangeNotifier {
  GameState();

  /// Loads from local storage, falling back to a fresh state. Applies the two
  /// post-load fixups the HTML does at module scope:
  ///   * every producer id present in `prod`
  ///   * timed buffs (sponsorEnd / sponsorCd) zeroed, because they are only
  ///     decremented by the running loop
  factory GameState.boot() {
    final s = GameState();
    s.load();
    for (final p in kProducers) {
      s.prod.putIfAbsent(p.id, () => 0);
    }
    s.sponsorEnd = 0;
    s.sponsorCd = 0;
    return s;
  }

  // --- resources ---
  double sig = 0;
  /// Output broadcast during the CURRENT run-down segment. Quotas are met by
  /// TRANSMITTING, not by holding a balance, so spending never un-meets one.
  double segSig = 0;

  /// Tool charges, by ToolDef.id. Owned by Tools, persisted here — buying a
  /// charge spends SIGNAL, and a purchase that evaporates on reload is a bug
  /// the player experiences as theft.
  final Map<String, int> toolCharges = <String, int>{};

  /// Permanent station upgrades bought with RATINGS POINTS, by node id.
  /// Survives sign-off — that is the entire point of it.
  final Map<String, int> meta = <String, int>{};

  /// Has the operator been through the line-up card? Asked ONCE, then never
  /// again — a wall between a player and the game is worse than a bad mix.
  bool hardwareChecked = false;

  /// Which of the previous operator's log pages have been found. Keyed by the
  /// night that hands them over, so it survives a save that predates the log.
  final Map<int, bool> log = <int, bool>{};
  int rp = 0;
  double lifetimeSig = 0;

  // --- owned ---
  final Map<String, int> prod = <String, int>{};
  final Map<String, bool> ups = <String, bool>{};
  final Map<String, bool> seen = <String, bool>{};

  // --- the night ---
  int night = 1;
  double airtime = 0;
  double dread = 0;
  double shiftMin = 0;
  bool stalled = false;
  int survived = 0;

  /// Set to 6 by dawn(), consumed by signOff(). Not present in a fresh JS save
  /// until the first dawn; written unconditionally here, which the JS loader
  /// tolerates (`S.dawnBonus||0`).
  int dawnBonus = 0;

  // --- log ---
  final Stats stats = Stats();

  // --- sponsor ---
  double sponsorEnd = 0;
  double sponsorCd = 0;
  int revives = 0;

  // --- settings / ui ---
  bool flash = true;
  double sfx = 0.7;
  double ui = 1.15;
  int lastSave = DateTime.now().millisecondsSinceEpoch;

  bool started = false;

  /// "tx" | "hw" | "st"
  String tab = 'tx';

  /// An anomaly id, or "k_" + counter id for the emergency-desk pages.
  String manPage = 'snow';

  // --- runtime bags that are state, not scenery ---
  final TuneState tune = TuneState();
  final ToastBus toasts = ToastBus();

  /// Rack buy mode: 1, 10 or -1 for MAX (JS used the string "max").
  int buyMode = 1;
  static const int buyModeMax = -1;

  /// Convenience so anything holding a GameState can talk to the player.
  void toast(String msg, [ToastKind kind = ToastKind.plain]) =>
      toasts.push(msg, kind);

  /// Convenience for `notifyListeners()` from outside the class.
  void bump() => notifyListeners();

  // -------------------------------------------------------------------------
  // Reset used by signOff(): wipes the run, keeps rp / stats / seen / settings.
  // -------------------------------------------------------------------------
  void resetForNewNight() {
    shiftMin = 0;
    stalled = false;
    night++;
    sig = 0;
    segSig = 0;
    lifetimeSig = 0;
    // STANDING ORDER: the cheapest N tiers survive sign-off, so prestige buys
    // a floor to start from rather than a slightly larger multiplier on zero.
    final kept = keptTiers(this);
    for (var i = 0; i < kProducers.length; i++) {
      if (i < kept) continue;
      prod[kProducers[i].id] = 0;
    }
    dread = 0;
    airtime = 0;
    revives = 0;
    stats.streak = 0;
    sponsorEnd = 0;
    sponsorCd = 0;
    // NOTE: TUNE is deliberately NOT reset — the HTML does not reset it either,
    // so TUNE.strikes stays non-zero and the "CLICK ANYWHERE" hint stays gone.
  }

  /// Hard reset — ERASE ALL TAPES. Clears the save and reloads on web.
  void eraseAllTapes() {
    storageRemove(kSaveKey);
    storageReload();
  }

  // -------------------------------------------------------------------------
  // Persistence — identical JSON shape to the HTML build.
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    lastSave = DateTime.now().millisecondsSinceEpoch;
    return <String, dynamic>{
      'sig': sig,
      'segSig': segSig,
      'rp': rp,
      'lifetimeSig': lifetimeSig,
      'prod': Map<String, dynamic>.from(prod),
      'ups': Map<String, dynamic>.from(ups),
      'seen': Map<String, dynamic>.from(seen),
      'night': night,
      'airtime': airtime,
      'dread': dread,
      'shiftMin': shiftMin,
      'stalled': stalled,
      'survived': survived,
      'stats': stats.toJson(),
      'sponsorEnd': sponsorEnd,
      'sponsorCd': sponsorCd,
      'revives': revives,
      'flash': flash,
      'sfx': sfx,
      'ui': ui,
      'lastSave': lastSave,
      'started': started,
      'tab': tab,
      'manPage': manPage,
      'toolCharges': toolCharges,
      'meta': meta,
      'hardwareChecked': hardwareChecked,
      'log': log.map((k, v) => MapEntry(k.toString(), v)),
      'dawnBonus': dawnBonus,
    };
  }

  void readJson(Map<String, dynamic> o) {
    sig = _dbl(o['sig'], sig);
    segSig = _dbl(o['segSig'], segSig);
    rp = _int(o['rp'], rp);
    lifetimeSig = _dbl(o['lifetimeSig'], lifetimeSig);

    final rawProd = o['prod'];
    if (rawProd is Map) {
      prod.clear();
      rawProd.forEach((k, v) => prod['$k'] = _int(v, 0));
    }
    final rawUps = o['ups'];
    if (rawUps is Map) {
      ups.clear();
      rawUps.forEach((k, v) {
        if (v == true) ups['$k'] = true;
      });
    }
    final rawSeen = o['seen'];
    if (rawSeen is Map) {
      seen.clear();
      rawSeen.forEach((k, v) {
        if (v == true) seen['$k'] = true;
      });
    }

    night = _int(o['night'], night);
    airtime = _dbl(o['airtime'], airtime);
    dread = _dbl(o['dread'], dread);
    shiftMin = _dbl(o['shiftMin'], shiftMin);
    stalled = _bool(o['stalled'], stalled);
    survived = _int(o['survived'], survived);
    dawnBonus = _int(o['dawnBonus'], dawnBonus);

    final rawStats = o['stats'];
    if (rawStats is Map) stats.readJson(Map<String, dynamic>.from(rawStats));

    sponsorEnd = _dbl(o['sponsorEnd'], sponsorEnd);
    sponsorCd = _dbl(o['sponsorCd'], sponsorCd);
    revives = _int(o['revives'], revives);

    flash = _bool(o['flash'], flash);
    sfx = _dbl(o['sfx'], sfx);
    ui = _dbl(o['ui'], ui);
    lastSave = _int(o['lastSave'], lastSave);
    started = _bool(o['started'], started);
    tab = _str(o['tab'], tab);
    manPage = _str(o['manPage'], manPage);
    hardwareChecked = _bool(o['hardwareChecked'], hardwareChecked);
    final lg = o['log'];
    if (lg is Map) {
      log.clear();
      lg.forEach((k, v) {
        final n = int.tryParse('$k');
        if (n != null && v == true) log[n] = true;
      });
    }
    final mt = o['meta'];
    if (mt is Map) {
      meta.clear();
      mt.forEach((k, v) {
        final n = v is num ? v.toInt() : 0;
        if (n > 0) meta['$k'] = n;
      });
    }
    final tc = o['toolCharges'];
    if (tc is Map) {
      toolCharges.clear();
      tc.forEach((k, v) {
        final n = v is num ? v.toInt() : 0;
        if (n > 0) toolCharges['$k'] = n;
      });
    }
  }

  /// JS save(): stamps lastSave and writes the blob. Never throws.
  void save() {
    try {
      storageWrite(kSaveKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  /// JS load(): merges the stored blob over a fresh state. Returns true if a
  /// save was found and applied.
  bool load() {
    try {
      final raw = storageRead(kSaveKey);
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      readJson(Map<String, dynamic>.from(decoded));
      return true;
    } catch (_) {
      return false;
    }
  }
}
