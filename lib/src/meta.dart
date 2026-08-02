// FINAL BROADCAST — THE CAREER.
//
// RATINGS POINTS were written in exactly one place and decremented nowhere: a
// score, not a budget. A headless 15-night run held the clock 866s on night 1
// and 0s on nights 2-15, because every unlock in the game fires during night
// one and nothing about night N is different.
//
// This is the sink. Nodes are permanent, survive sign-off, and are priced so
// that a first night's earnings already buy three or four — the choice has to
// bite on the FIRST prestige or the ladder may as well not exist.

import 'state.dart';

/// A permanent station upgrade, bought with RATINGS POINTS.
class StationNode {
  const StationNode({
    required this.id,
    required this.nm,
    required this.ds,
    required this.cost,
    required this.maxLvl,
    this.step = 2.0,
  });

  final String id;
  final String nm;

  /// What it does, written for the STATION board.
  final String ds;

  /// Level-1 price in RP. Level n costs `cost * step^(n-1)`, rounded.
  final int cost;
  final int maxLvl;
  final double step;
}

/// Eight nodes. Deliberately small — the point is that the first four RP go
/// somewhere that changes tomorrow night, not that there is a skill forest.
const List<StationNode> kStationNodes = <StationNode>[
  StationNode(
    id: 'standing',
    nm: 'STANDING ORDER',
    ds: 'Keep your cheapest transmitters through sign-off. '
        'One more tier survives per level.',
    cost: 2,
    maxLvl: 4,
    step: 2.6,
  ),
  StationNode(
    id: 'ferrite',
    nm: 'FERRITE STOCK',
    ds: 'The store room keeps spare cores. '
        '+0.35s on every banish window, permanently.',
    cost: 3,
    maxLvl: 3,
    step: 2.8,
  ),
  StationNode(
    id: 'memo',
    nm: 'THE OVERNIGHT MEMO',
    ds: '+1 to the shelf capacity of every tool.',
    cost: 3,
    maxLvl: 2,
    step: 3.0,
  ),
  StationNode(
    id: 'roster',
    nm: 'STAFF ROSTER',
    ds: 'Automation you have paid for once comes back on shift at level 1.',
    cost: 5,
    maxLvl: 1,
  ),
  StationNode(
    id: 'pay',
    nm: 'NIGHT SHIFT PAY',
    ds: '+12% output per level. It is not a raise, it is a retainer.',
    cost: 4,
    maxLvl: 5,
    step: 2.2,
  ),
  StationNode(
    id: 'steady',
    nm: 'STEADY HAND',
    ds: '+1.2s of guaranteed quiet after every correct answer.',
    cost: 6,
    maxLvl: 3,
    step: 2.6,
  ),
  StationNode(
    id: 'second',
    nm: 'SECOND SHIFT',
    ds: 'One extra revive a night before the sponsors start asking questions.',
    cost: 8,
    maxLvl: 2,
    step: 3.4,
  ),
  StationNode(
    id: 'union',
    nm: 'UNION RULES',
    ds: 'The clock cannot hold you for more than 45 seconds at a stretch.',
    cost: 12,
    maxLvl: 1,
  ),
];

final Map<String, StationNode> kStationBy = <String, StationNode>{
  for (final n in kStationNodes) n.id: n,
};

/// How many levels of [id] the station owns.
int metaLevel(GameState s, String id) => s.meta[id] ?? 0;

/// Price of the NEXT level, or null when maxed.
int? metaCost(GameState s, String id) {
  final n = kStationBy[id];
  if (n == null) return null;
  final lvl = metaLevel(s, id);
  if (lvl >= n.maxLvl) return null;
  var c = n.cost.toDouble();
  for (var i = 0; i < lvl; i++) {
    c *= n.step;
  }
  return c.round();
}

bool canBuyMeta(GameState s, String id) {
  final c = metaCost(s, id);
  return c != null && s.rp >= c;
}

/// Buys one level. Returns false and changes nothing if unaffordable or maxed.
bool buyMeta(GameState s, String id) {
  final c = metaCost(s, id);
  if (c == null || s.rp < c) return false;
  s.rp -= c;
  s.meta[id] = metaLevel(s, id) + 1;
  return true;
}

// --- the effects, read from everywhere ------------------------------------

/// How many producer tiers survive sign-off.
int keptTiers(GameState s) => metaLevel(s, 'standing');

/// Extra seconds on every banish window.
double metaWindowBonus(GameState s) => metaLevel(s, 'ferrite') * 0.35;

/// Extra capacity on every tool shelf.
int metaToolCapBonus(GameState s) => metaLevel(s, 'memo');

/// Output multiplier from NIGHT SHIFT PAY.
double metaOutputMult(GameState s) => 1 + metaLevel(s, 'pay') * 0.12;

/// Extra guaranteed quiet after a correct answer.
double metaCalmBonus(GameState s) => metaLevel(s, 'steady') * 1.2;

/// Extra revives before the sponsor escalation bites.
int metaFreeRevives(GameState s) => metaLevel(s, 'second');

/// Longest a quota shortfall may hold the clock, or null for "no limit".
double? metaStallCap(GameState s) =>
    metaLevel(s, 'union') > 0 ? 45.0 : null;

/// Do owned bots come back at level 1 after sign-off?
bool metaKeepsRoster(GameState s) => metaLevel(s, 'roster') > 0;
