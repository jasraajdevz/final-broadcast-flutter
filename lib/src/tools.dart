// FINAL BROADCAST — TOOLS.
//
// Five consumables with charges, used against whatever is on the tube. They are
// the PANIC button, never the main verb: the eight emergency keys are the game,
// and every tool here is deliberately worse value than pressing the right one.
//
// The invariant, by construction:
//   * no tool pays SIGNAL, and every tool costs SIGNAL to load
//   * only the MIRROR removes an anomaly, and it pays nothing for it — no
//     bonus, no streak, no dread relief, no `perfect`
//   * everything else buys TIME or INFORMATION, and still leaves you needing
//     the correct key
// So "flare then press 4" is always strictly worse than "press 4", and the
// eight-key core loop survives contact with a rich player.
//
// Charges are scarce and mostly EARNED: a CLEAN KILL (the `perfect` stat, i.e.
// a banish inside 40% of the window) restocks the emptiest tool, and the stock
// room trickles one more in every few minutes. Buying is the expensive fallback
// and is priced in SECONDS OF YOUR OWN OUTPUT, so it never inflates away.
//
// ---------------------------------------------------------------------------
// HOW THE EFFECTS ARE IMPLEMENTED
//
// This file owns no state on GameState and patches nothing in AnomalyRuntime.
// Everything is done through the existing public API, and [Tools.tick] MUST be
// called from the frame loop IMMEDIATELY AFTER `runtime.tick(dt)`, with the
// same dt. Two effects depend on that ordering:
//
//   FLARE  — a real freeze. The runtime has already advanced `active.t` by dt
//            this frame; the stun subtracts the same dt back off, so the ring
//            stands still. The initial 0.35s knock-back guarantees headroom, so
//            a single frame can never carry `t` past `window` mid-stun.
//   MIRROR — intercepts the jumpscare one frame early. It fires at
//            `t >= window - 0.2`, and dt is clamped to 0.1 upstream, so the
//            runtime can never reach `window` before this check runs.
//
// Charges are session-scoped: state.dart is not ours, so nothing here is
// written to the save blob. That is a deliberate side effect and a good one —
// you cannot bank a shelf of panic buttons across sessions.

import 'dart:math' as math;

import 'anomalies.dart';
import 'consts.dart';
import 'economy.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Tuning
// ---------------------------------------------------------------------------

/// Cheapest a charge can ever be, so the opening minutes are not free.
const double kToolFloor = 25;

/// FLARE — knock-back on impact, then a hard freeze.
const double kFlareKnock = 0.35;
const double kFlareStun = 2.2;

/// DEGAUSSING WAND — seconds returned, and how long the room stays clean.
const double kWandRelief = 1.4;
const double kWandCalm = 3.0;

/// EMP — seconds returned, fraction of the bank burned, fraction of the
/// SURPLUS segment output burned. Surplus only: an EMP can never un-meet a
/// quota it has already met, and can never touch an unmet one.
const double kEmpRelief = 4.5;
const double kEmpBank = 0.45;
const double kEmpBurn = 0.60;

/// MIRROR — how far ahead of the window it intercepts, and how much of the
/// Test Card Girl's pile survives the reflection.
const double kMirrorLead = 0.20;
const double kMirrorSalvage = 0.60;

/// Lockout after any use, so a fat-fingered double press cannot burn two.
const double kToolLock = 0.5;

/// The stock room. Real seconds on air per free charge — about six a night.
const double kToolCribSeconds = 210;

/// Clean kills per free charge. Restocking on EVERY clean kill would keep a
/// competent operator permanently full, and a panic button you always have is
/// not a panic button.
const int kToolPerfectPer = 3;

// ---------------------------------------------------------------------------
// The table
// ---------------------------------------------------------------------------

class ToolDef {
  const ToolDef({
    required this.id,
    required this.nm,
    required this.key,
    required this.cap,
    required this.rateSecs,
    required this.taps,
    required this.needsTarget,
    required this.ds,
  });

  final String id;

  /// Short name on the chip. Kept to seven characters so the bar never wraps.
  final String nm;

  /// Keyboard binding, lower case. 1-8 belong to the counters, M to the manual.
  final String key;

  /// Maximum charges held at once.
  final int cap;

  /// Price, expressed as seconds of unsabotaged output.
  final double rateSecs;

  /// Price floor, expressed in manual strikes — keeps it meaningful before you
  /// own a single transmitter.
  final double taps;

  /// True if it needs something on the tube. Only the MIRROR does not.
  final bool needsTarget;

  final String ds;

  String get keyCap => key.toUpperCase();
}

const List<ToolDef> kTools = <ToolDef>[
  ToolDef(
    id: 'flare',
    nm: 'FLARE',
    key: 'q',
    cap: 3,
    rateSecs: 12,
    taps: 22,
    needsTarget: true,
    ds: 'FLARE GUN — fire it into the tube. Whatever is in there is stunned: '
        'the banish window stops dead for 2.2s and it stops taking from you. '
        'It does not banish anything. Buys you the time to think of the key.',
  ),
  ToolDef(
    id: 'wand',
    nm: 'WAND',
    key: 'w',
    cap: 2,
    rateSecs: 18,
    taps: 32,
    needsTarget: true,
    ds: 'DEGAUSSING WAND — a hard magnetic wipe across the desk. Strips a mask, '
        'puts the transmitters back on air, makes her hand the pile back, and '
        'stops the lines ringing. It does not banish anything.',
  ),
  ToolDef(
    id: 'splice',
    nm: 'SPLICE',
    key: 'e',
    cap: 2,
    rateSecs: 15,
    taps: 26,
    needsTarget: true,
    ds: 'SPLICER — cuts the frame it entered on out of the tape and reads it. '
        'Strips a mask and names the one key that kills this thing. You still '
        'have to press it.',
  ),
  ToolDef(
    id: 'emp',
    nm: 'EMP',
    key: 'r',
    cap: 1,
    rateSecs: 30,
    taps: 55,
    needsTarget: true,
    ds: 'EMP CHARGE — buys 4.5s back on the window and takes the whole rack off '
        'air until the intrusion clears. Costs 45% of the bank and most of your '
        'surplus output. It cannot cost you a quota you have already met.',
  ),
  ToolDef(
    id: 'mirror',
    nm: 'MIRROR',
    key: 't',
    cap: 1,
    rateSecs: 40,
    taps: 70,
    needsTarget: false,
    ds: 'MIRROR — stand it against the glass and leave it. The next thing that '
        'runs the clock out sees itself and goes instead of you. No jumpscare, '
        'nothing stolen — and no payout either. Insurance, not a kill.',
  ),
];

final Map<String, ToolDef> kToolBy = <String, ToolDef>{
  for (final d in kTools) d.id: d,
};

/// The keys the shell must route here before it looks at the counter digits.
final Set<String> kToolKeys = <String>{for (final d in kTools) d.key};

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

class Tools {
  Tools(this.runtime) {
    for (final d in kTools) {
      _charge[d.id] = 0;
    }
    // Enough to see them work once, not enough to lean on.
    _charge['flare'] = 1;
    _charge['splice'] = 1;
    _lastPerfect = runtime.s.stats.perfect;
    _night = runtime.s.night;
  }

  final AnomalyRuntime runtime;
  GameState get s => runtime.s;

  final Map<String, int> _charge = <String, int>{};
  final Map<String, double> _flash = <String, double>{};

  double _stun = 0;
  bool _mirror = false;
  ActiveAnom? _revealOn;
  String? _revealCid;
  double _lock = 0;
  double _crib = 0;
  int _lastPerfect = 0;
  int _perfAcc = 0;
  int _night = 1;

  // --- read-out for the bar ---------------------------------------------

  int chargesOf(String id) => _charge[id] ?? 0;

  /// 0..1 press flash, for the chip highlight.
  double flashOf(String id) => _flash[id] ?? 0;

  /// True while the FLARE has the tube frozen.
  bool get stunned => _stun > 0;

  /// Seconds of freeze left.
  double get stunLeft => _stun;

  /// 0..1 for a freeze meter.
  double get stunP => (_stun / kFlareStun).clamp(0.0, 1.0);

  /// True while the MIRROR is standing against the glass.
  bool get mirrorArmed => _mirror;

  /// The counter id the SPLICER read off the tape, while it is still relevant.
  String? get revealedCounterId => _revealCid;

  Counter? get revealedCounter =>
      _revealCid == null ? null : kCounterBy[_revealCid];

  /// 0..1 progress of the stock room's next free charge.
  double get cribP => (_crib / kToolCribSeconds).clamp(0.0, 1.0);

  /// Tools only work on a live shift.
  bool get ready => runtime.signedOn && !runtime.lost && !runtime.adPlaying;

  /// Cost of one more charge, in SIGNAL. Priced off the player's own output so
  /// it is exactly as scarce on night nine as it was on night one.
  double priceOf(ToolDef d) {
    final byRate = sigRateRaw(s) * d.rateSecs;
    final byHand = tuneYield(s, runtime) * d.taps;
    final p = byRate > byHand ? byRate : byHand;
    return p < kToolFloor ? kToolFloor : p;
  }

  bool canAfford(ToolDef d) => s.sig >= priceOf(d);

  bool isFull(ToolDef d) => chargesOf(d.id) >= d.cap;

  // --- input -------------------------------------------------------------

  /// Routes a keystroke. Returns true if `ch` is one of ours, whether or not
  /// the tool actually did anything.
  bool pressKey(String ch, {bool purchase = false}) {
    for (final d in kTools) {
      if (d.key != ch) continue;
      if (purchase) {
        buy(d.id);
      } else {
        fire(d.id);
      }
      return true;
    }
    return false;
  }

  /// Loads one charge. Returns false and changes nothing if it cannot.
  bool buy(String id) {
    final d = kToolBy[id];
    if (d == null || !runtime.signedOn) return false;
    if (isFull(d)) {
      _deny('${d.nm} — RACK IS FULL');
      return false;
    }
    final p = priceOf(d);
    if (s.sig < p) {
      _deny('${d.nm} — NEEDS ${fmt(p)} SIG');
      return false;
    }
    s.sig -= p;
    _charge[d.id] = chargesOf(d.id) + 1;
    _flash[d.id] = 1;
    runtime.audio.buy();
    s.toast('${d.nm} CHARGE LOADED — -${fmt(p)} SIG');
    return true;
  }

  /// Uses one charge. Returns false and changes nothing if it cannot.
  bool fire(String id) {
    final d = kToolBy[id];
    if (d == null) return false;
    if (!ready || _lock > 0) return false;
    if (chargesOf(d.id) <= 0) {
      _deny('${d.nm} — NO CHARGE '
          '(SHIFT+${d.keyCap} BUYS ONE, ${fmt(priceOf(d))} SIG)');
      return false;
    }
    final ActiveAnom? a = runtime.active;
    if (d.needsTarget && a == null) {
      _deny('${d.nm} — NOTHING ON THE TUBE');
      return false;
    }
    if (d.id == 'mirror' && _mirror) {
      _deny('THE MIRROR IS ALREADY UP');
      return false;
    }

    _charge[d.id] = chargesOf(d.id) - 1;
    _flash[d.id] = 1;
    _lock = kToolLock;

    switch (d.id) {
      case 'flare':
        _fireFlare(a!);
      case 'wand':
        _fireWand(a!);
      case 'splice':
        _fireSplice(a!);
      case 'emp':
        _fireEmp(a!);
      case 'mirror':
        _armMirror();
    }
    return true;
  }

  // --- the five ----------------------------------------------------------

  void _fireFlare(ActiveAnom a) {
    // The knock-back is what makes the freeze safe: it guarantees at least
    // 0.35s of headroom, and dt is clamped to 0.1, so no single frame inside
    // the stun can carry `t` past `window`.
    a.t = math.max(0, a.t - kFlareKnock);
    _stun = math.max(_stun, kFlareStun);
    runtime.shake = math.max(runtime.shake, 12);
    if (s.flash) runtime.flash = math.max(runtime.flash, 0.35);
    runtime.audio.env('sawtooth', 880, 0.16, 0.22, 140);
    runtime.audio.impact();
    s.toast('FLARE — IT IS HELD FOR ${kFlareStun.toStringAsFixed(1)}s',
        ToastKind.good);
  }

  void _fireWand(ActiveAnom a) {
    if (a.masked && a.stage == 0) {
      a.stage = 1;
      s.toast('THE WIPE TAKES THE MASK OFF', ToastKind.gold);
    }
    a.t = math.max(0, a.t - kWandRelief);
    if (a.mute.isNotEmpty) {
      a.mute.clear();
      s.toast('TRANSMITTERS BACK ON AIR', ToastKind.good);
    }
    if (a.held > 0) {
      s.sig += a.held;
      s.toast('SHE PUTS THE PILE DOWN — +${fmt(a.held)} SIG', ToastKind.good);
      a.held = 0;
    }
    // The Caller's dread budget is spent out, so no further ring can charge for
    // it. `pay` goes non-positive and the runtime skips the payment.
    a.dreadPaid = 1e9;
    a.bite = math.max(a.bite, kWandCalm);
    a.ringIv = math.max(a.ringIv, kWandCalm);
    s.dread = math.max(0, s.dread - 4);
    runtime.shake = math.max(runtime.shake, 8);
    runtime.audio.env('sine', 60, 0.7, 0.22, 300);
    runtime.audio.burst(0.35, 0.20, 1400, 120);
    s.toast('DEGAUSS — THE ROOM IS CLEAN. IT IS STILL THERE.',
        ToastKind.good);
  }

  void _fireSplice(ActiveAnom a) {
    if (a.masked && a.stage == 0) a.stage = 1;
    _revealOn = a;
    _revealCid = a.def.counter;
    final Counter? c = kCounterBy[a.def.counter];
    runtime.audio.env('square', 520, 0.10, 0.12, 780);
    runtime.audio.env('square', 780, 0.10, 0.10, 1040);
    if (c != null) {
      s.toast('SPLICE — ${a.def.nm} DIES TO ${c.nm}  (KEY ${c.key})',
          ToastKind.gold);
    }
  }

  void _fireEmp(ActiveAnom a) {
    a.t = math.max(0, a.t - kEmpRelief);

    // The whole rack goes dark until the intrusion clears. Riding on the
    // ActiveAnom's own mute list means this cannot outlive the thing that
    // caused it, and resolve() announces the recovery for us.
    for (final p in kProducers) {
      if ((s.prod[p.id] ?? 0) > 0 && !a.mute.contains(p.id)) {
        a.mute.add(p.id);
      }
    }

    // Burn output — but only SURPLUS. If the segment's quota is already met the
    // burn floors on the quota, and if it is not met yet segSig is untouched.
    // An EMP can therefore never stall the clock or undo a quota.
    final q = segOf(s).quota;
    // Floor on the NEXT quota, not this one: everything above the current
    // threshold is principal on the next segment, which is ~14x bigger.
    final floorAt = s.segSig >= q ? q : s.segSig;
    s.segSig = floorAt + (s.segSig - floorAt) * (1 - kEmpBurn);

    final lost = s.sig * kEmpBank;
    s.sig = math.max(0, s.sig - lost);

    runtime.shake = math.max(runtime.shake, 16);
    runtime.audio.env('square', 2000, 0.30, 0.20, 60);
    runtime.audio.burst(0.5, 0.26, 60, 2400);
    runtime.audio.duck(0.25, 900);
    s.toast('EMP — ${kEmpRelief.toStringAsFixed(1)}s BOUGHT, -${fmt(lost)} SIG',
        ToastKind.bad);
    if (a.mute.isNotEmpty) {
      s.toasts.pushDelayed(700, 'THE RACK IS DARK UNTIL IT LEAVES',
          ToastKind.bad);
    }
  }

  void _armMirror() {
    _mirror = true;
    runtime.audio.env('sine', 1320, 0.5, 0.10, 1320);
    s.toast('MIRROR UP — THE NEXT ONE GOES INSTEAD OF YOU', ToastKind.gold);
  }

  // --- frame -------------------------------------------------------------

  /// One frame. Call IMMEDIATELY AFTER `runtime.tick(dt)` with the same dt.
  void tick(double dt) {
    if (_flash.isNotEmpty) {
      _flash.updateAll((_, v) => v - dt * 3.2);
      _flash.removeWhere((_, v) => v <= 0);
    }
    if (_lock > 0) _lock = math.max(0, _lock - dt);

    // A new night wipes the run; nothing mid-intrusion should survive it.
    if (s.night != _night) {
      _night = s.night;
      _stun = 0;
      _revealOn = null;
      _revealCid = null;
    }

    final ActiveAnom? a = runtime.active;
    if (a == null || !identical(a, _revealOn)) {
      _revealOn = null;
      _revealCid = null;
    }
    if (a == null) _stun = 0;

    // CLEAN KILLS restock. Tools come out of playing the core loop well, which
    // is the whole point of them — the eight keys pay for the panic buttons.
    final perf = s.stats.perfect;
    if (perf > _lastPerfect) {
      _perfAcc += perf - _lastPerfect;
      _lastPerfect = perf;
      while (_perfAcc >= kToolPerfectPer) {
        _perfAcc -= kToolPerfectPer;
        _restock('CLEAN KILLS');
      }
    } else if (perf < _lastPerfect) {
      _lastPerfect = perf;
    }

    if (!ready) return;

    // --- FLARE: cancel the runtime's own advance for this frame ---
    if (_stun > 0 && a != null) {
      _stun -= dt;
      a.t = math.max(0, a.t - dt);
      s.dread = math.max(0, s.dread - dt * (1.2 + depth(s) * 0.02));
      a.bite = math.max(a.bite, 0.4);
      a.ringIv = math.max(a.ringIv, 0.4);
      if (runtime.sabOn('card')) {
        // Put back exactly what she just took, so a stunned Test Card Girl is
        // paying you again rather than filling her lap.
        final give = sigRate(s, runtime) * dt * runtime.sabK();
        a.held = math.max(0, a.held - give);
        s.sig += give;
      }
      if (_stun <= 0) {
        _stun = 0;
        runtime.audio.env('square', 220, 0.12, 0.10, 90);
        s.toast('THE FLARE BURNS OUT', ToastKind.bad);
      }
    }

    // --- MIRROR: take the jumpscare one frame before it lands ---
    if (_mirror && a != null && a.t >= a.window - kMirrorLead) {
      _mirror = false;
      _stun = 0;
      if (a.held > 0) s.sig += a.held * kMirrorSalvage;
      final nm = a.def.nm;
      runtime.shake = math.max(runtime.shake, 14);
      if (s.flash) runtime.flash = math.max(runtime.flash, 0.7);
      runtime.audio.env('triangle', 1180, 0.55, 0.16, 300);
      runtime.audio.impact();
      // resolve(false, ...) clears the intrusion, un-mutes the rack and
      // reschedules WITHOUT paying a bonus, touching the streak or moving
      // dread. Exactly what a reflection is worth.
      runtime.resolve(false, true);
      s.toast('THE MIRROR TAKES $nm — NOTHING STOLEN, NOTHING EARNED',
          ToastKind.gold);
    }

    // --- the stock room ---
    _crib += dt;
    if (_crib >= kToolCribSeconds) {
      _crib = 0;
      _restock('STOCK ROOM');
    }
  }

  // --- plumbing ----------------------------------------------------------

  /// Gives one charge to the emptiest tool. Ties break in table order, so the
  /// FLARE — the workhorse — fills first.
  void _restock(String why) {
    ToolDef? best;
    var bestP = 2.0;
    for (final d in kTools) {
      final have = chargesOf(d.id);
      if (have >= d.cap) continue;
      final p = have / d.cap;
      if (p < bestP) {
        bestP = p;
        best = d;
      }
    }
    if (best == null) return;
    _charge[best.id] = chargesOf(best.id) + 1;
    _flash[best.id] = 1;
    s.toast('$why — ${best.nm} RECHARGED', ToastKind.good);
  }

  void _deny(String msg) {
    runtime.audio.reject();
    s.toast(msg, ToastKind.bad);
  }
}
