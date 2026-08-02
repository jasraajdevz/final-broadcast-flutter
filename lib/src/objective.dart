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

import 'dart:math' as math;

import 'anomalies.dart';
import 'consts.dart';
import 'economy.dart';
import 'meta.dart';
import 'state.dart';

/// How loud a directive should be shouted.
enum Urgency { calm, watch, urgent }

class Directive {
  const Directive(this.text, this.urgency);
  final String text;
  final Urgency urgency;
}

/// The standing order: what "winning tonight" means, in one line.
String nightOrder(GameState s) =>
    'HOLD THE TRANSMITTER FROM 23:00 TO 06:00.';

/// Why you are here at all, across nights. This is the long goal, and it is
/// deliberately a career and not a boss: nights are the unit, RP is the wage.
String careerLine(GameState s) {
  if (s.survived == 0) {
    return 'Survive one whole night. Nobody at this station has, lately.';
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

/// The two ways a night ends badly, stated flatly. These never change, which
/// is the point: a player should be able to recite them by night three.
const List<String> kLossConditions = <String>[
  'DREAD 100 — the signal is lost and the night ends where it stands.',
  'A MISSED QUOTA holds the clock. 06:00 never arrives while you are short.',
];

/// The single most important thing right now. Order matters: this is a
/// priority list, and only the top hit is ever shown.
Directive primeDirective(GameState s, AnomalyRuntime r) {
  final a = r.active;

  // 1. Something is on the tube. Nothing else exists.
  if (a != null && a.stage >= 1) {
    final known = s.seen[a.def.id] ?? false;
    return Directive(
      known
          ? 'ANSWER IT — ${a.def.nm} DIES TO ${a.def.counter.toUpperCase()}'
          : 'ANSWER IT — READ THE BEZEL, THEN THE MANUAL',
      Urgency.urgent,
    );
  }
  // 2. Something is coming.
  if (a != null) {
    return const Directive('SOMETHING IS ARRIVING — HANDS ON THE KEYS',
        Urgency.urgent);
  }
  // 3. Dread is about to take the night off you.
  if (s.dread >= 78) {
    return const Directive(
        'DREAD IS CRITICAL — BUY FROM THE CANTEEN NOW', Urgency.urgent);
  }
  if (s.dread >= 55) {
    return const Directive(
        'DREAD IS HIGH — THE CANTEEN SELLS IT BACK', Urgency.watch);
  }
  // 4. The clock is stalled on you.
  if (!quotaMet(s)) {
    final short = quotaShortfall(s);
    final rate = math.max(0.001, sigRateRaw(s));
    final eta = short / rate;
    if (eta > 45) {
      return Directive(
          'THE CLOCK IS HELD — BUY TRANSMITTERS, YOU ARE ${fmt(short)} SHORT',
          Urgency.watch);
    }
    return Directive('${fmt(short)} SHORT THIS SEGMENT — KEEP IT OUT',
        Urgency.watch);
  }
  // 5. Nothing is wrong. Bank the quiet.
  if (s.sig > 0 && affordSomething(s)) {
    return const Directive('ALL CLEAR — SPEND IT BEFORE IT COSTS YOU',
        Urgency.calm);
  }
  return const Directive('ALL CLEAR — STRIKE THE TUBE', Urgency.calm);
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
