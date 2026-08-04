// FINAL BROADCAST — WHAT AM I ACTUALLY DOING.
//
// Every rule this game runs on was already implemented and none of them were
// ever STATED. You lose at DREAD 100; the clock stops dead on an unmet quota;
// the night ends at 06:00; RATINGS POINTS are what carry across. All true, all
// invisible, which is exactly what "it feels aimless" describes — not an
// absence of goals but an absence of anyone saying them out loud.
//
// This file is the single place that turns live state into three sentences:
// the standing order for the night, the one thing that matters this second,
// and the two ways the night can be taken off you.

import 'anomalies.dart';
import 'consts.dart';
import 'economy.dart';
import 'meta.dart';
import 'state.dart';
import 'story.dart';

/// How loud a directive should be shouted.
enum Urgency { calm, watch, urgent }

class Directive {
  const Directive(this.text, this.urgency);
  final String text;
  final Urgency urgency;
}

/// The standing order. It used to read "HOLD THE TRANSMITTER FROM 23:00 TO
/// 06:00", which is a rule with no reason attached — a fair player asks "or
/// what?" and the honest answer was "nothing". See story.dart.
String nightOrder(GameState s) => kStandingOrder;

/// Why you are here at all, across nights. This is the long goal, and it is
/// deliberately a career and not a boss: nights are the unit, RP is the wage.
String careerLine(GameState s) {
  if (s.survived == 0) {
    return 'Hold it until sunrise. The last operator managed 1,114 nights.';
  }
  final unowned = kStationNodes
      .where((n) => metaCost(s, n.id) != null)
      .toList()
    ..sort((a, b) => metaCost(s, a.id)!.compareTo(metaCost(s, b.id)!));
  if (unowned.isEmpty) {
    return 'Every standing order is on the books. Nothing is left but the run.';
  }
  final next = unowned.first;
  final cost = metaCost(s, next.id)!;
  final have = s.rp;
  if (have >= cost) {
    return '${next.nm} is paid for. Sign off and take it.';
  }
  return '${next.nm} — $have of $cost RATINGS POINTS.';
}

/// The two ways a night ends badly. These never change, which is the point:
/// a player should be able to recite them by night three. They now describe a
/// CONSEQUENCE rather than a scoring event — see story.dart.
const List<String> kLossConditions = kStakes;

/// The single most important thing right now. Order matters: this is a
/// priority list, and only the top hit is ever shown.
Directive primeDirective(GameState s, AnomalyRuntime r) {
  // 0. The night is over. The wings sit outside the modal scrim on an
  // ultrawide, so without this the panel cheerfully advises you to spend your
  // signal next to the sheet explaining that the carrier has dropped.
  if (r.lost) {
    return const Directive('THE NIGHT IS OVER', Urgency.calm);
  }

  final a = r.active;

  // 1. THE TELEGRAPH. This branch did not exist: the function only inspected
  // r.active, which is null while the riser runs, so control fell all the way
  // through to the terminal ALL CLEAR cases and the loudest line on screen sat
  // calm-green saying "SPEND IT BEFORE IT COSTS YOU" while the ON AIR lamp two
  // dozen pixels above it pulsed red "!! DISTURBANCE". Measured at 65-72% of
  // telegraph frames across nights 1, 3 and 6.
  if (a == null && r.warn > 0) {
    return const Directive(
        'SOMETHING IS COMING — HANDS ON THE KEYS', Urgency.urgent);
  }

  // 2. Something is on the tube. Nothing else exists.
  if (a != null && a.stage >= 1) {
    final known = s.seen[a.def.id] ?? false;
    // Read the LIVE key, not def.counter. On a COUPLED pair liveKeys drops
    // def.counter the moment the first half is answered, and pressCounter
    // routes a repeat of that dead key to wrongPress() — so the strip was
    // naming a key that had just started costing 0.9s of window and 3 dread.
    final live = a.liveKeys;
    final Counter? c =
        live.isEmpty ? kCounterBy[a.def.counter] : kCounterBy[live.first];
    // and name it the way the keycap does: the raw id says "VHOLD" and
    // "HOOK" where the deck reads "V-HOLD" and "OFF-HOOK".
    return Directive(
      known && c != null
          ? 'ANSWER IT — ${a.def.nm} DIES TO ${c.nm}  (KEY ${c.key})'
          // The one moment the player has no idea what to press. Telling them
          // to go and read a manual under a live window was advice they could
          // not take; hitting the glass is something they can do RIGHT NOW.
          : 'HOLD THE CARRIER — THEN READ THE BEZEL',
      Urgency.urgent,
    );
  }
  // 3. Masked, and not yet stripped.
  if (a != null) {
    return const Directive('SOMETHING IS ARRIVING — HANDS ON THE KEYS',
        Urgency.urgent);
  }
  // 3. THE BOOK. It sits under a live anomaly — the tube always wins — but
  // above everything else, because it expires and nothing else here does.
  if (r.checks.pending) {
    return Directive('${r.checks.active!.nm} — PRESS ENTER', Urgency.watch);
  }
  if (r.checks.drift > 0.45) {
    return const Directive(
        'THE STATION IS DRIFTING — SIGN THE BOOK WHEN IT ASKS', Urgency.watch);
  }
  // 4. Dread is about to take the night off you.
  if (s.dread >= 78) {
    return const Directive(
        'DREAD IS CRITICAL — BUY FROM THE CANTEEN NOW', Urgency.urgent);
  }
  if (s.dread >= 55) {
    return const Directive(
        'DREAD IS HIGH — THE CANTEEN SELLS IT BACK', Urgency.watch);
  }
  // 4. The quota.
  //
  // This branch used to fire on `!quotaMet(s)` alone, which is TRUE on the
  // first frame of every segment — so the loudest element on screen opened
  // night one with "THE CLOCK IS HELD", a sentence that was not true (the
  // clock only holds at :59) about a state that is simply the start of a
  // segment. A warning that is on by default is not a warning.
  if (s.stalled) {
    return Directive(
        'THE CLOCK IS HELD — ${fmt(quotaShortfall(s))} MORE OUTPUT',
        Urgency.urgent);
  }
  // 5. THE BOOTSTRAP. With nothing on air, sigRateRaw is 0, so "on pace" is
  // false by construction and the strip opened the game on a warning. A
  // station that has not started is not behind — it has not started. Say the
  // first action instead.
  final int owned = kProducers.fold<int>(0, (a, p) => a + (s.prod[p.id] ?? 0));
  if (owned == 0) {
    final double first = costOf(s, kProducers.first);
    return Directive(
        s.sig >= first
            ? 'BUY ${kProducers.first.nm} — THE RACK IS ON YOUR RIGHT'
            : 'THE CARRIER IS FALLING — UP RAISES THE DRIVE',
        Urgency.calm);
  }

  // 6. Behind, with the segment running out.
  if (!quotaMet(s) && !onPaceForQuota(s)) {
    return Directive('BEHIND THE QUOTA — ${fmt(quotaShortfall(s))} TO GO',
        Urgency.watch);
  }
  // 5. Nothing is wrong. Bank the quiet.
  if (s.sig > 0 && affordSomething(s)) {
    return const Directive('ALL CLEAR — SPEND IT BEFORE IT COSTS YOU',
        Urgency.calm);
  }
  return const Directive('ALL CLEAR — MIND THE NEEDLES', Urgency.calm);
}

/// Will the station clear this segment's quota before the clock reaches :59
/// at the current rate? Being short early in a segment is the normal state and
/// must not read as an alarm; being short with no time left is the alarm.
bool onPaceForQuota(GameState s) {
  if (quotaMet(s)) return true;
  final double minsLeft = 60 - (s.shiftMin % 60);
  final double secsLeft = minsLeft * kMinReal;
  final double rate = sigRateRaw(s);
  if (rate <= 0) return false;
  // 25% headroom: "just barely on pace" should still nudge.
  return quotaShortfall(s) / rate <= secsLeft * 0.75;
}

/// Is anything at all in the rack currently affordable? Cheap enough to run
/// every frame — it stops at the first hit.
bool affordSomething(GameState s) {
  for (var i = 0; i < kProducers.length; i++) {
    if (!producerUnlocked(s, i)) continue;
    if (s.sig >= costOf(s, kProducers[i])) return true;
  }
  return false;
}

/// Progress through the night, 0..1, for anything that wants a single number.
double nightProgress(GameState s) =>
    (s.shiftMin / (7 * 60)).clamp(0.0, 1.0);
