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
}

/// Seven cards. Small on purpose — a deck you can memorise is a deck you can
/// plan around, and planning is the thing that was missing.
const List<NightCard> kNightCards = <NightCard>[
  NightCard(
    id: 'storm',
    nm: 'STORM FRONT',
    ds: 'Weather over the mast all night. The carrier runs hot and everything '
        'arrives faster. OUTPUT x1.5, GAP x0.75.',
    output: 1.5,
    gap: 0.75,
  ),
  NightCard(
    id: 'skeleton',
    nm: 'SKELETON CREW',
    ds: 'Nobody else came in. The rundown was cut to match, but you answer '
        'everything alone. QUOTA x0.7, WINDOW x0.85.',
    quota: 0.7,
    window: 0.85,
  ),
  NightCard(
    id: 'sweep',
    nm: 'RATINGS SWEEP',
    ds: 'Head office is measuring tonight. Everything counts double and '
        'everything costs you more. RP x2.0, DREAD x1.35.',
    rp: 2.0,
    dread: 1.35,
  ),
  NightCard(
    id: 'quiet',
    nm: 'A QUIET NIGHT',
    ds: 'Long stretches of nothing. You will have time to think, which is '
        'worse. GAP x1.4, OUTPUT x0.75, DREAD x1.2.',
    gap: 1.4,
    output: 0.75,
    dread: 1.2,
  ),
  NightCard(
    id: 'bounty',
    nm: "THE ENGINEER'S STANDING BOUNTY",
    ds: 'He left money in the drawer for anything you put down. BANISH PAY '
        'x2.2, QUOTA x1.25.',
    banishPay: 2.2,
    quota: 1.25,
  ),
  NightCard(
    id: 'ferrite',
    nm: 'FRESH CORES',
    ds: 'The store room was restocked for once. Every answer has room to '
        'breathe. WINDOW x1.3, OUTPUT x0.85.',
    window: 1.3,
    output: 0.85,
  ),
  NightCard(
    id: 'openline',
    nm: 'OPEN LINE',
    ds: 'The phones are live and it is not the public calling. GAP x0.7, '
        'BANISH PAY x1.6, WINDOW x0.9.',
    gap: 0.7,
    banishPay: 1.6,
    window: 0.9,
  ),
];

/// The card with no effects — night one, and any state that has not started.
const NightCard kNoCard = NightCard(
  id: 'none',
  nm: 'YOUR FIRST SHIFT',
  ds: 'No standing conditions. The station as it is written down.',
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

NightCard cardOf(GameState s) => cardForNight(s.night);
