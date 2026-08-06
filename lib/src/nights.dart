// FINAL BROADCAST — THE NIGHT CARD.
//
// "It feels good at first then it starts to get boring" is a structural
// complaint, not a content one. Night 6 was night 1 with bigger numbers:
// same rundown, same roster, same seven segments, same everything, scaled by
// nightPressure(). Nothing about a night was ever ABOUT anything.
//
// The card is what a night is about. It is drawn deterministically from the
// night number — the same night is the same card for every player, so it can
// be talked about, learned, and dreaded — it is announced by name before you
// sign on, and it pulls the dials in opposite directions. Every card is both
// a gift and a bill, so none of them is a night you would rather skip.
//
// Night one draws nothing. The tutorial shift must be the game as documented.

import 'state.dart';

class NightCard {
  const NightCard({
    required this.id,
    required this.nm,
    required this.ds,
    this.output = 1.0,
    this.quota = 1.0,
    this.window = 1.0,
    this.gap = 1.0,
    this.rp = 1.0,
    this.dread = 1.0,
    this.banishPay = 1.0,
    this.decay = 1.0,
    this.drift = 1.0,
    this.ceiling = 1.0,
  });

  final String id;
  final String nm;

  /// One sentence, in the station's voice, that also states the mechanics.
  final String ds;

  /// Multiplier on everything the transmitters put out.
  final double output;

  /// Multiplier on every segment quota tonight.
  final double quota;

  /// Multiplier on the banish window. Below 1 is a shorter answer.
  final double window;

  /// Multiplier on the gap between arrivals. Below 1 is a busier night.
  final double gap;

  /// Multiplier on RATINGS POINTS banked at sign-off.
  final double rp;

  /// Multiplier on how fast DREAD accumulates.
  final double dread;

  /// Multiplier on the SIGNAL a banish pays.
  final double banishPay;

  // --- WHAT A CARD DOES TO THE RIG ---
  //
  // OUTPUT, QUOTA and BANISH PAY are all multipliers on the producer economy,
  // and every card in the deck printed at least one of them on its face. With
  // the economy gone they are numbers about nothing — a card promising
  // "OUTPUT x1.5" is telling the operator a lie in the same breath as it tells
  // them what tonight is. They stay on the class because the sign-off sheets
  // still read them; nothing sets them any more.
  //
  // These three are the honest replacements, and they are the rig's own dials.

  /// How fast the carrier falls tonight.
  final double decay;

  /// How much the programme audio wanders.
  final double drift;

  /// How many seconds off the air the licence allows.
  final double ceiling;
}

/// Seven cards. Small on purpose — a deck you can memorise is a deck you can
/// plan around, and planning is the thing that was missing.
const List<NightCard> kNightCards = <NightCard>[
  NightCard(
    id: 'storm',
    nm: 'STORM FRONT',
    ds: 'Weather over the mast all night. The carrier will not stay where you '
        'put it and everything arrives faster — but nobody drives out to a '
        'transmitter in this. RP x1.4, CARRIER DECAY x1.35, GAP x0.75.',
    gap: 0.75,
    decay: 1.35,
    rp: 1.4,
  ),
  NightCard(
    id: 'skeleton',
    nm: 'SKELETON CREW',
    ds: 'Nobody else came in. Head office is not watching the log as closely, but '
        'you answer everything alone. LICENCE x1.25, WINDOW x0.85.',
    window: 0.85,
    ceiling: 1.25,
  ),
  NightCard(
    id: 'sweep',
    nm: 'RATINGS SWEEP',
    ds: 'Head office is measuring tonight. Everything counts double and everything '
        'costs you more. RP x2.0, DREAD x1.35.',
    rp: 2.0,
    dread: 1.35,
  ),
  NightCard(
    id: 'quiet',
    nm: 'A QUIET NIGHT',
    ds: 'Long stretches of nothing. You will have time to think, which is worse. '
        'GAP x1.4, MODULATION DRIFT x0.7, DREAD x1.2.',
    gap: 1.4,
    drift: 0.7,
    dread: 1.2,
  ),
  NightCard(
    id: 'bounty',
    nm: "THE ENGINEER'S STANDING BOUNTY",
    ds: 'He left money in the drawer for anything you put down, and spent the rest '
        'of it on himself. RP x1.8, LICENCE x0.8.',
    rp: 1.8,
    ceiling: 0.8,
  ),
  NightCard(
    id: 'ferrite',
    nm: 'FRESH CORES',
    ds: 'The store room was restocked for once. Every answer has room to breathe, '
        'and the mains sags for it. WINDOW x1.3, CARRIER DECAY x1.15.',
    window: 1.3,
    decay: 1.15,
  ),
  NightCard(
    id: 'openline',
    nm: 'OPEN LINE',
    ds: 'The phones are live and it is not the public calling. Head office '
        'counts a night like this for more than it is worth. RP x1.5, '
        'GAP x0.7, MODULATION DRIFT x1.3, WINDOW x0.9.',
    gap: 0.7,
    drift: 1.3,
    window: 0.9,
    rp: 1.5,
  ),
];

/// The card with no effects — night one, and any state that has not started.
const NightCard kNoCard = NightCard(
  id: 'none',
  nm: 'YOUR FIRST SHIFT',
  ds: 'No standing conditions. The station as it is written down.',
);

/// NIGHTMARE's standing conditions. ONE card, always the same, instead of
/// whatever the career happened to be holding.
///
/// Measured before this existed: NIGHTMARE inherited the career deck and then
/// multiplied it, so the first NIGHTMARE most players ever see (night 2) drew
/// STORM FRONT and ran the carrier at 1.35 x 1.30 = 1.755 on the one axis
/// that was already 81% of the death invoice — while a player whose career
/// sat on a gentler card got a mode nearly twice as survivable. Medians
/// across career nights ran 13.3 to 7.1 minutes: a 1.9x swing on a variable
/// the player never chose. A mode with its own name gets its own weather.
///
/// decay 1.20 rather than the old effective 1.755, because the deaths have to
/// leave room for everything else in this mode to be what kills you.
const NightCard kNightmareCard = NightCard(
  id: 'nightmare',
  nm: 'NIGHTMARE',
  ds: 'It does not end.',
  decay: 1.20,
  drift: 1.35,
  ceiling: 0.70,
);

/// Tonight's card, from the night number alone.
///
/// Deterministic and stateless: night 4 is FRESH CORES for everyone, forever.
/// The stride is coprime with the deck size so a career walks the whole deck
/// before it repeats, and consecutive nights are never the same card.
NightCard cardForNight(int night) {
  if (night <= 1) return kNoCard;
  final int i = ((night - 2) * 3) % kNightCards.length;
  return kNightCards[i];
}

NightCard cardOf(GameState s) =>
    s.nightmare ? kNightmareCard : cardForNight(s.night);
