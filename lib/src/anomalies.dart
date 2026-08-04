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
//   * CALM — a correct counter opens a window whose head is GUARANTEED quiet:
//     nothing can manifest inside `calmGuard`, full stop. It is earned, it
//     compounds with the streak, and the UI can read it (`allClear`, `calmP`,
//     `airState`). Getting it right must BUY something. Past the guard the
//     window TAPERS — the gap timer is live again but an arrival inside the
//     taper comes in softened. See economy.dart's ALL CLEAR block.
//   * AFTERMATH — a jumpscare opens a longer forced-quiet window. A scare can
//     therefore never chain into another one, which is the guarantee that keeps
//     a bad night recoverable rather than a death spiral.
//   * The two are mutually exclusive except during the FALSE CLEAR scare beat,
//     which lights the ALL CLEAR lamp on purpose and then takes it away.
//
// And the reason a kill has a SHAPE. `resolve()` used to set `active = null` on
// its first line, so the loudest moment in the game was a deletion: being right
// produced 0px of shake, being wrong produced 6, and firing a tool produced 16.
// A kill now has a duration (`dying` / `dyingP`), a hit-stop the sim drains
// while `tGlobal` keeps running, and a punch that out-hits every other input in
// the game. Being right is now the biggest thing that happens on screen.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'consts.dart';
import 'career.dart';
import 'checks.dart';
import 'economy.dart';
import 'nights.dart';
import 'record.dart';
import 'wallclock.dart';
import 'paint/blood.dart';
import 'meta.dart';
import 'encounter.dart';
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

  /// Master stereo position, -1 (hard left) .. 1 (hard right).
  ///
  /// This game's tells arrive in ONE EAR before they arrive on the tube, which
  /// is why the hardware check exists and why the bed drifts. It is a mechanic,
  /// not decoration.
  void pan(double p);

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

  /// The kill. [fast] is a clean kill (inside 40% of the window, no fumbles);
  /// [streak] is the run of consecutive banishes INCLUDING this one, so the
  /// stinger can climb — a seventh kill in a row must not sound like a first.
  void banishStinger(bool fast, int streak);

  /// A partial kill: the TWO-STAGE flinch, or the first half of a COUPLED pair.
  /// Something gave, and something is still there.
  void relay();

  /// A save landed in the last sliver of the window. Deliberately not a bigger
  /// [banishStinger]: it is a different EVENT — the intake of breath after the
  /// near-miss — and it plays over the stinger, not instead of it.
  void clutchSting();

  /// A streak of [lost] consecutive banishes just ended. Play the loss of it,
  /// not just the scare on top.
  void streakBroken(int lost);

  /// A run milestone worth marking. [kind] is one of "streak" (new best
  /// streak), "banish" (every tenth banish of a career), "night" (a segment of
  /// the rundown survived) or "clean" (a run of flawless kills).
  void milestone(String kind, int n);

  void reject();
  void click();
  void tune(double p);
  void good();
  void bad();
  void buy();
  void warn();
  void scare();

  // --- THE HORROR LAYER ---------------------------------------------------
  //
  // The old bed was loud but not frightening: everything lived between 90Hz
  // and 4kHz, the room never went truly quiet, and the jumpscare was 120ms of
  // duck followed by harsh noise. Loudness is not fear. These five are.

  /// A breath, very close, hard to one ear. [side] is -1 or 1; [near] 0..1
  /// scales how close the mouth is. The single most effective thing in the
  /// build on headphones, and inaudible on a laptop speaker — which is what
  /// the line-up card exists to catch.
  void breath(double side, double near);

  /// Cut EVERYTHING to true silence for [ms], then let it back. Not a duck —
  /// a hole. The brain fills a hole with something worse than any sample.
  void hold(int ms);

  /// A reversed swell that ENDS on the beat you pass it. Play it [ms] before
  /// the thing it precedes and the arrival is heard before it is seen.
  void preEcho(int ms);

  /// The infrasonic bed, 0..1. 24-31Hz has no pitch you can name; it is felt
  /// in the chest as unease and reads on a meter as almost nothing.
  void setSub(double v);

  /// Someone screaming, somewhere else in the building.
  ///
  /// Not a threat and not a cue — nothing in the game responds to it and
  /// there is no key that answers it. That is the entire point: every scream
  /// in this build was gated behind FAILING, so a competent operator finished
  /// a whole career without hearing one, and the quiet they spent the night in
  /// was pleasant. A sound you cannot do anything about is disturbing; a sound
  /// that punishes you is just a penalty.
  void distantScream(double near, double side);

  /// A wet impact. [force] 0..1.
  void bloodImpact(double force);

  /// A single bead letting go and landing. [pan] -1..1 places it in the room,
  /// [size] 0..1 sets how big the drop was.
  ///
  /// The most recognisable sound in the horror vocabulary, and the reason it
  /// works is that it arrives from somewhere specific while you are looking
  /// somewhere else.
  void bloodDrip(double pan, double size);

  /// Something in the room says almost a word. Formants that nearly resolve.
  /// [near] 0..1 moves it from down the hall to directly behind you.
  void voice(double near, double side);

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
  void clutchSting() {}
  @override
  void init() {}
  @override
  void resume() {}
  @override
  void setVol(double v) {}
  @override
  void pan(double p) {}
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
  void banishStinger(bool fast, int streak) {}
  @override
  void relay() {}
  @override
  void streakBroken(int lost) {}
  @override
  void milestone(String kind, int n) {}
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
  void distantScream(double near, double side) {}
  @override
  void bloodImpact(double force) {}
  @override
  void bloodDrip(double pan, double size) {}
  @override
  void breath(double side, double near) {}
  @override
  void hold(int ms) {}
  @override
  void preEcho(int ms) {}
  @override
  void setSub(double v) {}
  @override
  void voice(double near, double side) {}
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
    required this.seed,
    this.cold = false,
    this.mod = EncounterMod.none,
    this.partner,
  });

  final Anom def;

  /// Seconds it has been on the tube.
  double t = 0;

  /// Seconds available to banish it. NOT final: the TWO-STAGE modifier refills
  /// it when the first correct press lands, which is the whole reason a split
  /// can never make a visit unwinnable.
  double window;

  /// Arrived wearing someone else's face (depth >= 28, 22% chance).
  final bool masked;

  /// 0 = masked and not yet stripped, 1 = present and sabotaging.
  int stage;

  /// 1 normally, 0.5 on a first sighting, 0.7 when it arrived inside the taper
  /// of an ALL CLEAR window.
  final double intensity;

  /// 0..1, stable for the whole visit and different every time. The painters
  /// thread it into the composition so the second sighting of an entity is not
  /// pixel-for-pixel the eighth. Costs no new art.
  final double seed;

  /// Arrived with NO telegraph at all. Paid for with a much longer [window].
  final bool cold;

  /// The extra rule this visit is carrying.
  final EncounterMod mod;

  /// COUPLED only: the second signature sharing the body. Its counter is a
  /// valid key for this visit, in either order with [def]'s own.
  final Anom? partner;

  /// TWO-STAGE: 0 = untouched, 1 = already split once.
  int modStage = 0;

  /// Generic per-visit sabotage cadence, for the five entities that had no
  /// live effect at all. Reused rather than adding five more timers.
  double sabIv = 1.2;

  /// Blows landed on the glass this visit. See [AnomalyRuntime.tuneStrike].
  int blows = 0;

  /// Seconds of window bought back by hitting it. Capped, because buying
  /// unlimited time would make knowing the counter optional.
  double bought = 0;

  /// Blows since the last stagger.
  int sinceStagger = 0;

  /// What THE RERUN and THE NIELSEN have taken so far this visit, so both are
  /// budgeted per visit rather than per second — a long window must not be
  /// arbitrarily more expensive than a short one.
  double takenSeg = 0;
  double takenLife = 0;

  /// Segment output at the moment it arrived. THE RERUN cannot push you back
  /// past this: it overwrites what you transmit WHILE it is on, and nothing
  /// you banked before it showed up.
  double segAtArrival = 0;

  /// COUPLED: which halves have been answered.
  bool selfDown = false;
  bool partnerDown = false;

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

  /// Every counter id that is still outstanding on this visit. Never empty
  /// while the thing is alive, and ALWAYS contains [def]'s own counter until it
  /// has actually been pressed — the invariant that stops a modifier from
  /// disabling the key that banishes its own entity.
  List<String> get liveKeys {
    if (masked && stage == 0) return const <String>['cut'];
    final out = <String>[];
    if (mod == EncounterMod.coupled) {
      if (!selfDown) out.add(def.counter);
      final pc = partner?.counter;
      if (pc != null && !partnerDown) out.add(pc);
      return out;
    }
    out.add(def.counter);
    return out;
  }

  /// True when [cid] does something useful right now.
  bool accepts(String cid) => liveKeys.contains(cid);

  /// How many more correct presses this visit needs.
  int get pressesLeft {
    if (mod == EncounterMod.coupled) {
      return (selfDown ? 0 : 1) + (partnerDown || partner == null ? 0 : 1);
    }
    if (mod == EncounterMod.twoStage) return modStage == 0 ? 2 : 1;
    return 1;
  }
}

// ---------------------------------------------------------------------------
// Scares
// ---------------------------------------------------------------------------

/// How a jumpscare is staged. One is chosen per entity when the window runs
/// out; each has a different shape in time, a different audio script and a
/// different thing for the painters to do.
/// A permanent mark a jumpscare leaves on the room for the rest of the night.
///
/// A scare that ends and leaves everything exactly as it was is a loud noise,
/// and a loud noise is forgettable — you brace, it happens, you carry on. What
/// is DISTURBING is the room not going back. These accumulate across a night,
/// so a bad shift is visibly, permanently wrong by 04:00, and nothing ever
/// says so out loud.
enum ScarKind {
  /// One of the corridor cameras keeps showing it. It does not move again.
  camGhost,

  /// The field outside will not go back. The figures stay at the glass.
  atTheGlass,

  /// Its face never fully leaves the phosphor.
  burnIn,

  /// One transmitter reads a name that is not its name.
  wrongName,
}

class Scar {
  Scar(this.kind, this.def, {this.slot = 0});

  final ScarKind kind;

  /// What left it.
  final Anom def;

  /// Which camera / which rack row, depending on [kind].
  final int slot;
}

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
// The kill
// ---------------------------------------------------------------------------

/// Seconds a banished thing stays on the tube, coming apart.
const double kDyingSpan = 0.35;

/// The same, for a kill nobody earned (a bot assist, the MIRROR). Shorter,
/// because it is not the player's moment.
const double kDyingSpanQuiet = 0.18;

/// Frozen seconds on a clean kill — inside 40% of the window, no fumbles.
const double kHitstopClean = 0.07;

/// Frozen seconds on any other successful banish.
const double kHitstopHit = 0.045;

/// Frozen seconds on a partial — the TWO-STAGE flinch, half a COUPLED pair.
const double kHitstopPartial = 0.035;

/// A save landed in the last 14% of the window. Longer than a clean kill on
/// purpose: the near-loss is the moment worth feeling, and worth clipping.
const double kHitstopClutch = 0.115;

/// Shake on a clean kill. For scale: a wrong key is 11, a tool is 16, the
/// LUNGE jumpscare is 34. Being RIGHT has to out-punch being wrong.
const double kShakeClean = 26;

/// Shake on any other successful banish.
const double kShakeHit = 18;

/// Shake on a wrong key. Was 6, which read as nothing at all.
const double kShakeWrong = 11;

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

  /// How long this telegraph started out as, so the painters can express it
  /// as progress. Without it the cams could only flicker on `warn > 0`, which
  /// is why the figure in the hallway used to hop between monitors three
  /// times a second instead of standing there getting closer.
  double warnSpan = 0;

  /// Which camera it is standing in. Fixed for the whole telegraph — a thing
  /// that moves between cameras is a glitch; a thing that does not move at
  /// all, in one camera, while the clock runs down, is a problem.
  int warnCam = 0;
  double shake = 0;
  double flash = 0;
  double glitch = 0;
  double scare = 0;
  Anom? scareDef;
  double banishFx = 0;
  double wrongFx = 0;

  /// 1 -> 0 after a last-second save. Read by the painters for the flare.
  double clutchFx = 0;

  /// THE STATION CHECKS. The job you do in the quiet, and the only thing in
  /// the game that competes with the tube for your attention.
  final CheckRuntime checks = CheckRuntime();

  /// What is on the glass. Accumulates across a night and is only ever
  /// cleaned by sunrise. See paint/blood.dart.
  final BloodLayer blood = BloodLayer();

  /// What tonight has left on the room. Cleared at sign-on, never inside a
  /// night. The painters read it; nothing announces it.
  final List<Scar> scars = <Scar>[];

  bool hasScar(ScarKind k) => scars.any((s) => s.kind == k);

  /// The camera a [ScarKind.camGhost] is standing in, or -1.
  int get ghostCam {
    for (final s in scars) {
      if (s.kind == ScarKind.camGhost) return s.slot;
    }
    return -1;
  }

  Anom? get ghostDef {
    for (final s in scars) {
      if (s.kind == ScarKind.camGhost) return s.def;
    }
    return null;
  }

  /// 0..1 — THE VERTICAL MAN's hold on the instruments. Every numeric readout
  /// in the rack and the status strip rolls by this much. He takes nothing;
  /// he just makes the desk unreadable, which is a cost no other entity has.
  double vertRoll = 0;

  /// Which counter was pressed in error, so the painters can flash THAT key
  /// rather than the whole deck. Cleared with [wrongFx].
  String? wrongFxKey;
  bool lost = false;

  /// Set by the shell (WS5) while a modal owns the screen — the manual, mostly.
  /// The simulation freezes completely: no clock, no economy, no scheduler, no
  /// dread, no anomaly progress. `tGlobal` keeps running so the room still
  /// breathes behind the sheet.
  bool paused = false;

  /// 0..1, written by the window scene every frame from the things standing in
  /// the field (`WindowScene.lurk` / `lurkClose`). Feeds an atmospheric DREAD
  /// inflow, so the field is pressure rather than wallpaper. Defensively
  /// clamped on read; leaving it at 0 simply removes the inflow.
  double lurkPressure = 0;

  /// How long the current hold has lasted, for UNION RULES' 45-second cap.
  double _stallHeld = 0;

  /// 0..1 — something is standing behind the operator's chair.
  ///
  /// It is never on the tube, it is never announced, no key addresses it and
  /// no meter counts it. It arrives, it is there for a while, and it goes. The
  /// entire horror vocabulary of this game was on a 422x278 screen the player
  /// stares at directly; nothing had ever happened in the ROOM, which is the
  /// one place a person cannot look at in a fixed first-person shot.
  double presence = 0;
  double presenceIn = 88;
  double presenceSpan = 0;

  /// How many times it has stood behind the chair and then left.
  ///
  /// A presence that is guaranteed harmless is only frightening until the
  /// player notices it is guaranteed harmless — which takes about three
  /// nights, and after that it is weather. This counts the times it has been
  /// merciful, and feeds the chance that the next one is not.
  int presenceVisits = 0;

  /// True while the current visit is the one that turns.
  bool presenceTurning = false;

  // -------------------------------------------------------------------------
  // THE NINTH KEY
  //
  // A. VOSS's roster entry has promised this since the ladder was written —
  // "a ninth key, it is not on the deck yet" — and H. VANCE's entry records
  // what it is for: "the only one who ever turned the carrier down. For nine
  // seconds."
  //
  // It has no label, no manual page, and nothing in the game ever explains it.
  // It is not pressed, it is HELD, and holding it takes the station off air.
  //
  // The premise of the whole game is that the carrier is a lid. This is the
  // handle on the lid. It works — whatever is on the tube leaves immediately,
  // because the thing keeping it in there has stopped — and the cost is that
  // for a few seconds nothing at all is holding the rest of it down.
  //
  // A pure lose-button would be pressed once and never again. This is a real
  // emergency release with a catastrophic price, which is a different thing:
  // you WILL use it, and you will hate that you did.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // THE LONG NIGHT
  //
  // The last safe harbour in this game is that 06:00 always comes. Everything
  // else has been taken away — the calm window turns, the presence comes round
  // the front, the paperwork is about you, the clock on the wall is the real
  // one — but sunrise has never once failed to arrive, and a player can endure
  // any amount of dread while knowing the night is finite.
  //
  // R. HALLORAN's entry has said what this is since the roster was written:
  // "did not sign off on the morning of the 1,115th night."
  //
  // Once in a career, deep in, 06:00 passes and the sheet does not come up.
  // The clock keeps counting — 06:01, 06:02 — into an hour the rundown has no
  // segment for. It is finite, because an unwinnable night is a bug rather
  // than a scare, and surviving it is the largest thing in the game.
  // -------------------------------------------------------------------------

  /// True once the shift has run past its own end.
  bool longNight = false;

  /// Minutes of overtime survived.
  double overMin = 0;

  /// How much overtime this one demands.
  double overNeed = 0;

  /// 0..1 for anything that wants to draw it.
  double get overP => overNeed <= 0 ? 0 : (overMin / overNeed).clamp(0.0, 1.0);

  /// 0..1 — how far the operator's hand has taken the carrier down.
  double carrierHold = 0;
  bool carrierHolding = false;

  /// Times it has been taken down tonight. Each one is worse than the last.
  int carrierDrops = 0;

  /// Seconds of hold before the lid actually comes off.
  static const double kCarrierHoldSeconds = 2.4;

  /// Which camera is showing THIS ROOM, or -1.
  ///
  /// The cameras watch the corridor and the mast. There is no camera in the
  /// booth, there has never been a camera in the booth, and nothing in the
  /// game ever remarks on the fact that one of them is looking at the back of
  /// your chair. It is the cheapest genuinely upsetting image available,
  /// because the player supplies the meaning themselves.
  int mirrorCam = -1;
  double mirrorIn = 150;
  double mirrorLeft = 0;

  /// 0..1 — how far the figure in that chair has turned round.
  double mirrorTurn = 0;

  /// Seconds until somebody screams somewhere else in the building.
  ///
  /// Deliberately independent of the anomaly scheduler and of dread: it is not
  /// a cue, it is weather. Every scream in this build fired only from
  /// _scareHit(), so a competent operator finished a whole career without
  /// hearing one and spent the night in a pleasant hum. The horror was gated
  /// behind losing.
  double screamIn = 42;

  /// Seconds until the room tone next STOPS dead for a beat.
  ///
  /// Silence that arrives with no cause is the cheapest dread in the game and
  /// the bed never once used it: the room hummed at a constant level from
  /// 23:00 to 06:00, and a room that hums constantly is a room you stop
  /// hearing. This lives in the SIM rather than in the audio backend because
  /// it is pacing, and pacing is testable — the version that lived inside
  /// WebAudio.tick() could only be verified by measuring a live browser.
  double roomStop = 26;

  /// Phase clock for the binaural drift.
  double _drift = 0;

  // --- the kill ---

  /// The thing that just died, still on the tube for [dyingSpan] seconds. A
  /// deletion cannot have a shape; a corpse can.
  ActiveAnom? dying;

  /// Seconds into the death.
  double dyingT = 0;

  /// Total seconds the death takes.
  double dyingSpan = kDyingSpan;

  /// Seconds of frozen simulation left. `tick()` drains it against the frame
  /// delta and hands `_simulate` whatever is left, while `tGlobal` keeps
  /// advancing — so the picture keeps moving and the WORLD stops. This is the
  /// impact frame the climactic input never had.
  double hitstop = 0;

  /// Seconds of ABSOLUTE quiet left inside the current calm window. Nothing may
  /// telegraph or manifest while this is above zero. This is the promise.
  double calmGuard = 0;

  /// The full length [calmGuard] was granted at.
  double calmGuardSpan = 0;

  /// True when the roll that armed [nextAt] was a SURGE — a quick follow-up.
  /// Read-only for the UI; the carrier readout may hint, but must not say when.
  bool surgeIncoming = false;

  /// The next arrival was scheduled inside the taper of an ALL CLEAR window and
  /// comes in softened: longer riser, longer window, reduced intensity.
  bool softNext = false;

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

  /// Wrong keys pressed this night. The FIRST one of every night names the
  /// manual, because the measured blind run pressed nothing at all for five
  /// minutes and was never once told what the deck was for.
  int nightWrongs = 0;

  /// True when the last thing to leave the tube got through. Feeds the surge
  /// roll — blood in the water.
  bool lastWasScare = false;

  /// Seconds until the held-clock toast restates itself. A stall used to
  /// announce itself exactly once, into silence, with no figure attached.
  double _stallSay = 0;

  /// Which piece of advice the stall toast gives next.
  int _stallAdvice = 0;

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
    // On a COUPLED visit it reads whichever half is still outstanding.
    final live = a.liveKeys;
    if (live.isEmpty) return null;
    return kCounterBy[live.first];
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

  /// True while the booth is inside the window earned by a correct counter.
  /// Covers BOTH halves of it — see [calmGuaranteed] for the part that is an
  /// absolute promise and [calmTapering] for the part that is only a lean.
  bool get allClear => calm > 0 && active == null && warn <= 0 && !lost;

  /// True while NOTHING can manifest, full stop. This is the promise a correct
  /// answer buys, and `sim_test.dart` asserts it across whole nights.
  bool get calmGuaranteed => calmGuard > 0 && active == null && !lost;

  /// True in the tail of a calm window: the gap is live again, but anything
  /// that arrives now arrives softened.
  bool get calmTapering => calm > 0 && calmGuard <= 0 && active == null;

  /// 0..1 of the calm window left, for a draining meter.
  double get calmP => calmSpan <= 0 ? 0 : clampD(calm / calmSpan, 0, 1);

  /// 0..1 of the GUARANTEED head left, for a second, brighter meter inside the
  /// first one.
  double get calmGuardP =>
      calmGuardSpan <= 0 ? 0 : clampD(calmGuard / calmGuardSpan, 0, 1);

  /// Whole seconds of calm left, for a countdown.
  int get calmSeconds => calm <= 0 ? 0 : calm.ceil();

  /// Whole seconds of GUARANTEED calm left.
  int get calmGuardSeconds => calmGuard <= 0 ? 0 : calmGuard.ceil();

  /// 0..1 through the death of the last thing you killed. 0 at the instant of
  /// the kill, 1 when the corpse is gone. Painters: this is the dissolve.
  double get dyingP =>
      dying == null || dyingSpan <= 0 ? 0 : clampD(dyingT / dyingSpan, 0, 1);

  /// True on the frames the world is frozen for the impact.
  bool get frozen => hitstop > 0;

  /// Every counter id that would do something right now: the live entity's
  /// outstanding keys, or "cut" against a mask. Empty when nothing is on the
  /// tube. The deck may light these; it must never HIDE the digits.
  List<String> get liveKeys => active?.liveKeys ?? const <String>[];

  /// The modifier on the live visit, for a badge on the deck.
  EncounterMod get activeMod => active?.mod ?? EncounterMod.none;

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
    if (calmGuard > 0 || aftermath > 0) return 0;
    if (gapSpan <= 0) return 0;
    return clampD(1 - nextAt / gapSpan, 0, 1);
  }

  /// 0..1 — how far into the career this shift is. The one number every
  /// night-over-night escalation reads; a HUD that wants to show the player
  /// that the job is getting worse should show this.
  double get pressure => nightPressure(s);

  /// A word for [pressure], for a readout that has one line to say it in.
  String get pressureLabel {
    final p = pressure;
    if (p < 0.10) return 'ROUTINE';
    if (p < 0.28) return 'ELEVATED';
    if (p < 0.45) return 'HEAVY';
    if (p < 0.62) return 'SEVERE';
    return 'TERMINAL';
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
        // Two different promises, said in two different ways. The guaranteed
        // head counts down in seconds; the taper says only that it is fading,
        // because in the taper the booth is no longer certain.
        return calmGuard > 0
            ? 'ALL CLEAR ${calmGuardSeconds}s'
            : 'CLEAR — FADING';
      case AirState.recovering:
        return 'RECOVERING ${recoverSeconds}s';
      case AirState.onAir:
        return 'ON AIR';
    }
  }

  // -------------------------------------------------------------------------
  // Scheduler
  // -------------------------------------------------------------------------

  /// Rolls the next gap, bimodally: mostly the long legible interval, sometimes
  /// a SURGE. The gap timer runs during a calm window but cannot FIRE inside
  /// the guaranteed head — see [_simulate].
  void scheduleNext({bool afterScare = false, bool afterBanish = false}) {
    final roll = rollGap(s, nightAnoms,
        afterScare: afterScare, afterBanish: afterBanish);
    nextAt = roll.seconds;
    gapSpan = roll.seconds;
    surgeIncoming = roll.surge;
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
    final guardWas = calmGuard, guardSpanWas = calmGuardSpan;
    resolve(true, true);
    s.lifetimeSig = before;
    s.stats.streak = streak;
    calm = calmWas;
    calmSpan = calmSpanWas;
    calmGuard = guardWas;
    calmGuardSpan = guardSpanWas;
  }

  /// Opens the quiet window a correct answer just bought: a GUARANTEED head in
  /// which nothing can manifest, then a taper in which the gap is live again
  /// but an arrival comes in softened.
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
    final g = calmGuardOf(calm) + metaCalmBonus(s); // STEADY HAND, permanent
    if (g > calmGuard) {
      calmGuard = g;
      calmGuardSpan = g;
    }
  }

  void beginWarn() {
    // Belt and braces: the caller already checked, but nothing may telegraph
    // inside the GUARANTEED head of a calm window under any circumstances.
    if (calmGuard > 0 || aftermath > 0 || lost) return;
    final pool = unlockedAnoms(s);
    final def = pick(pool);
    warnDef = def;

    // --- the cold open ---
    // No riser at all. Rises with dread and with the night, never on a debut,
    // never in the opening minutes of a shift, and paid back with a much
    // longer window when it fires.
    if (rand() < coldOpenChance(s, def, nightAnoms)) {
      warn = 0;
      manifest(cold: true);
      return;
    }

    warn = telegraphFor(s, def);
    // An arrival inside the taper of an ALL CLEAR window comes in gently.
    if (softNext) warn *= 1.35;
    warnSpan = warn;
    warnCam = (rand() * 4).floor().clamp(0, 3);
    audio.warn();
    audio.riser(warn);
    // THE PRE-ECHO. A swell that ends on the manifest, so the arrival is
    // heard a beat before it is seen. This is the difference between "a thing
    // appeared" and "something is coming" — and it costs one call.
    audio.preEcho((warn * 1000).round().clamp(400, 4000));
    // and something takes a breath, on one side of you, while you wait
    audio.breath(rand() < 0.5 ? -1 : 1, 0.35 + s.dread / 100 * 0.5);
    // The tell is per-entity flavour that HINTS at what is coming without
    // naming it, and only once you have met the thing. Learning the eight
    // tells is the skill ceiling; a debut still gets the generic warning.
    s.toast(tellFor(s, def), ToastKind.bad);
  }

  /// 0 -> 1 across the telegraph. 1 is "it is about to be on the tube".
  double get warnP =>
      warnSpan <= 0 ? 0 : (1 - (warn / warnSpan)).clamp(0.0, 1.0);

  void manifest({bool cold = false}) {
    final Anom def = warnDef ?? pick<Anom>(unlockedAnoms(s));
    final bool soft = softNext;
    softNext = false;
    warnDef = null;
    warn = 0;
    calm = 0;
    calmSpan = 0;
    calmGuard = 0;
    calmGuardSpan = 0;
    nightAnoms++;
    // MASKED CARRIER is off. It arrived wearing another entity's face and had
    // to be CUT before it could be answered, which meant a fifth of deep-night
    // arrivals were a mandatory two-key ritual before the actual encounter
    // started — a delay dressed as a mechanic. The code paths stay (tools.dart
    // strips a mask, bots skip one, liveKeys handles stage 0) so nothing has
    // to be unpicked, and nothing rolls one any more.
    final first = !(s.seen[def.id] ?? false);

    // --- the modifier ---
    // Never on a debut, never on top of a mask. COUPLED only ever picks a
    // partner the player has already catalogued, so it can never ask for a key
    // there was no way to know.
    final pool = unlockedAnoms(s);
    var mod = rollMod(s,
        first: first,
        masked: false,
        hasPartner: hasCouplePartner(s, pool, def));
    Anom? partner;
    if (mod == EncounterMod.coupled) {
      partner = pickPartner(s, pool, def);
      if (partner == null) mod = EncounterMod.twoStage;
    }

    var w = banishWindow(s) * profileOf(def.id).windowMul;
    if (first) w *= 1.25;
    if (cold) w *= kColdOpenWindowMul;
    if (soft) w *= 1.25;
    if (mod == EncounterMod.twoStage) w *= kTwoStageWindowMul;
    if (mod == EncounterMod.coupled) w *= kCoupledWindowMul;

    active = ActiveAnom(
      def: def,
      window: w,
      masked: false,
      stage: 1,
      // THE NIGHT PORTER softens the night's opening arrival.
      intensity: first
          ? 0.5
          : (soft ? 0.7 : (nightAnoms == 0 && metaHasPorter(s) ? 0.65 : 1)),
      seed: rand(),
      cold: cold,
      mod: mod,
      partner: partner,
    );
    // THE RERUN overwrites what you transmit WHILE it is on. It must never be
    // able to walk back output you had already banked before it arrived.
    active!.segAtArrival = s.segSig;
    if (cold) s.toast(coldTellFor(s, def), ToastKind.bad);
    if (mod == EncounterMod.twoStage) {
      s.toast('TWO-STAGE SIGNATURE — ONE HIT WILL NOT DO IT', ToastKind.bad);
    } else if (mod == EncounterMod.coupled && partner != null) {
      final a = kCounterBy[def.counter], b = kCounterBy[partner.counter];
      s.toast(
          'COUPLED CARRIER — TWO KEYS: '
          '${a?.nm ?? def.counter} ${a?.key ?? ""} + '
          '${b?.nm ?? partner.counter} ${b?.key ?? ""}',
          ToastKind.bad);
    }
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
    // You have one pair of hands. Reaching for a banish key takes them off the
    // book, and an abandoned signature is worth nothing — that trade IS the
    // mechanic. The station does not care that you were busy.
    if (checks.signing) endSign(checks);
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
    // --- COUPLED: two signatures, two keys, either order ---
    if (a.mod == EncounterMod.coupled && a.partner != null) {
      final own = a.def.counter;
      final other = a.partner!.counter;
      if (cid == own && !a.selfDown) {
        a.selfDown = true;
      } else if (cid == other && !a.partnerDown) {
        a.partnerDown = true;
      } else {
        wrongPress(cid);
        return;
      }
      flashKey(cid, true);
      if (a.selfDown && a.partnerDown) {
        resolve(true, false);
        return;
      }
      _partialHit(a, 'HALF OF IT IS GONE');
      return;
    }

    if (cid == a.def.counter) {
      // --- TWO-STAGE: the same key, twice ---
      if (a.mod == EncounterMod.twoStage && a.modStage == 0) {
        a.modStage = 1;
        // Refilled, not merely extended: a split can never make a visit
        // unwinnable, however late the first press landed.
        a.window += banishWindow(s) * kTwoStageRefill;
        flashKey(cid, true);
        final c = kCounterBy[a.def.counter];
        _partialHit(a, 'IT SPLITS — ${c?.nm ?? ""} AGAIN, KEY ${c?.key ?? ""}');
        return;
      }
      flashKey(cid, true);
      resolve(true, false);
    } else {
      wrongPress(cid);
    }
  }

  /// A correct press that did not finish the job. Real impact, real feedback,
  /// and a little of the clock back — but the thing is still on the tube.
  void _partialHit(ActiveAnom a, String msg) {
    a.t = math.max(0, a.t - 0.35);
    hitstop = math.max(hitstop, kHitstopPartial);
    shake = math.max(shake, 15);
    banishFx = math.max(banishFx, 0.6);
    glitch = 1;
    audio.relay();
    audio.env('square', 340, 0.12, 0.10, 660);
    s.toast(msg, ToastKind.bad);
    notifyListeners();
  }

  void wrongPress(String cid) {
    flashKey(cid, false);
    audio.reject();
    s.stats.wrong++;
    nightWrongs++;
    wrongFx = 1;
    // A fumble puts a little of it on the glass too. Being wrong should cost
    // something you can SEE for the rest of the night, not just a number.
    blood.add(0.12,
        ox: kScr.center.dx + (rand() - 0.5) * 500,
        oy: kScr.bottom + 30 + rand() * 80,
        count: 1);
    audio.bloodImpact(0.18);
    wrongFxKey = cid;
    final pen = (s.ups['autocue'] ?? false) ? 0.45 : 0.9;
    active?.wrongs++;
    active?.t += pen;
    // A wrong key used to be 6px of shake and a channel nothing read. It now
    // punches the picture as well, through `glitch`, which the tube painter
    // has always read.
    shake = math.max(shake, kShakeWrong);
    glitch = math.max(glitch, 1);
    s.dread = math.min(100, s.dread + 3 * cardOf(s).dread);
    // The first fumble of every night names the manual. The measured blind run
    // went five minutes without ever being told what the deck was for.
    if (nightWrongs == 1) {
      final c = kCounterBy[cid];
      s.toast('${c?.nm ?? "THAT"} DOES NOTHING TO THIS ONE', ToastKind.bad);
      s.toasts.pushDelayed(
          700, 'PRESS M — THE MANUAL NAMES THE KEY', ToastKind.gold);
    }
    notifyListeners();
  }

  /// Strike the CRT by hand. Coordinates are in 1280x720 cabinet space and are
  /// expected to be inside SCR — the caller hit-tests, exactly as the HTML's
  /// pointerdown handler does.
  /// The maximum seconds one visit can be held off by hand.
  ///
  /// Bounded on purpose. Fighting has to be a way to survive not knowing the
  /// answer for a few more seconds, never a replacement for knowing it.
  static const double kMaxBought = 3.6;

  /// Blows needed to make it flinch.
  static const int kBlowsPerStagger = 4;

  void tuneStrike(double x, double y) {
    if (!signedOn || adPlaying || lost) return;
    audio.init();
    audio.resume();

    // ---------------------------------------------------------------------
    // YOU CAN FIGHT BACK.
    //
    // Striking the tube used to pay exactly the same whether the screen was
    // empty or something was standing on it, so the instant a thing arrived
    // the player's ONLY available action was pressing the correct one of eight
    // keys. If you did not know which, there was nothing to do but watch it
    // happen. That is not a horror encounter, it is a quiz — and being unable
    // to do anything at all while something walks toward you is the specific
    // thing the player described as not being able to fight back.
    //
    // The verb already existed and it is the right one: you hit the glass. It
    // does not kill anything — only the counter does — it buys you SECONDS,
    // and it costs you, because you are beating on live transmission equipment
    // instead of broadcasting.
    final act = active;
    if (act != null && act.stage >= 1) {
      act.blows++;
      act.sinceStagger++;
      addMark(s, Mark.panic);
      // push the window back, up to a hard ceiling per visit
      final double room = kMaxBought - act.bought;
      if (room > 0) {
        final double push = math.min(room, 0.42);
        act.t = math.max(0, act.t - push);
        act.bought += push;
      }
      // it is not free: this is panic, not work
      s.dread = math.min(100, s.dread + 0.9 * cardOf(s).dread);
      s.tune.strike(x, y, 'HIT', tGlobal);
      audio.impact();
      shake = math.max(shake, 6.5);
      wrongFx = math.max(wrongFx, 0.22);

      if (act.sinceStagger >= kBlowsPerStagger) {
        // IT FLINCHES. The whole point — a visible, felt answer to the blow,
        // so hitting it is something you DO rather than something you hope.
        act.sinceStagger = 0;
        hitstop = math.max(hitstop, kHitstopPartial);
        shake = math.max(shake, 16);
        flash = math.max(flash, 0.18);
        audio.relay();
        audio.env('sawtooth', 150, 0.28, 0.16, 52);
        blood.add(0.14,
            ox: kScr.center.dx + (rand() - 0.5) * 420,
            oy: kScr.bottom + 30 + rand() * 70,
            count: 1);
        s.toast(
            act.bought >= kMaxBought
                ? 'IT WILL NOT BE PUSHED BACK ANY FURTHER'
                : 'IT GIVES GROUND — ANSWER IT',
            ToastKind.gold);
      }
      notifyListeners();
      return;
    }

    final g = tuneYield(s, this);
    s.sig += g;
    s.tune.strike(x, y, '+${fmt(g)}', tGlobal);
    // Heard, not just tracked: the click steps up a fifth per lock tier, and
    // reaching a new one gets its own rising sting.
    audio.tune(s.tune.heat + s.tune.tier * 0.25);
    if (s.tune.lastStrikePromoted) {
      audio.milestone('lock', s.tune.tier);
      s.toast('${s.tune.tierName} — x${s.tune.tierMult.toStringAsFixed(1)} BY HAND',
          ToastKind.gold);
    }
    notifyListeners();
  }

  /// The hand goes on the ninth key.
  void beginCarrier() {
    if (!signedOn || lost || paused || !unlocked(s, 'ninth')) return;
    if (carrierHolding) return;
    carrierHolding = true;
    audio.init();
    audio.env('square', 90, 0.5, 0.12, 60);
    // no toast. It has never been explained and it is not going to be now.
    notifyListeners();
  }

  /// The hand comes off it.
  void endCarrier() {
    if (!carrierHolding) return;
    carrierHolding = false;
    if (carrierHold > 0.1 && carrierHold < 1.0) {
      // Let go in time. Nothing happened, and knowing that it nearly did is
      // its own cost.
      s.dread = math.min(100, s.dread + 4 * cardOf(s).dread);
      audio.env('sine', 220, 0.3, 0.07, 300);
      s.toast('THE NEEDLE COMES BACK UP', ToastKind.gold);
    }
    notifyListeners();
  }

  /// THE LID COMES OFF.
  void dropCarrier() {
    addMark(s, Mark.hand);
    carrierHolding = false;
    carrierHold = 0;
    carrierDrops++;

    // Whatever was on the tube leaves at once. It was only ever in the signal
    // because there was a signal.
    final a = active;
    if (a != null) {
      active = null;
      dying = a;
      dyingT = 0;
      dyingSpan = kDyingSpanQuiet;
      glitch = 0;
      s.toast('IT IS NOT IN THE SIGNAL ANY MORE', ToastKind.bad);
    }

    // And for a few seconds nothing is holding the rest of it down. Each drop
    // costs more than the last, so this can never become a rotation.
    final double bite = 26.0 + carrierDrops * 14.0;
    s.dread = math.min(100, s.dread + bite * cardOf(s).dread);
    calm = 0;
    calmSpan = 0;
    calmGuard = 0;
    calmGuardSpan = 0;

    audio.deadAir(true);
    audio.hold(520);
    audio.setSub(1.0);
    _later(560, () => audio.distantScream(0.95, rand() < 0.5 ? -1 : 1));
    _later(1400, () => audio.deadAir(false));
    blood.add(0.6,
        ox: kScr.center.dx + (rand() - 0.5) * 500,
        oy: kScr.bottom + 20 + rand() * 90);
    shake = math.max(shake, 26);
    blackout = math.max(blackout, 1);

    // it comes into the room while the lid is off
    presence = 1;
    presenceSpan = rr(6, 12);
    presenceTurning = carrierDrops >= 2 && rand() < 0.35;
    audio.setHeart(140, 0.30);

    s.toasts.pushDelayed(900, 'KBLK-7 IS OFF THE AIR', ToastKind.bad);
    s.toasts.pushDelayed(2200, 'PUT IT BACK UP', ToastKind.bad);
    notifyListeners();
  }

  /// ENTER — the operator signs the book.
  ///
  /// One key, always the same, because the check is an ATTENTION test and not
  /// a memory test. Pressing it when nothing was asked is a false entry, which
  /// is what stops it being mashed.
  void pressCheck() {
    if (!signedOn || lost || paused) return;
    final ev = beginSign(checks, s);
    if (ev != null && ev.kind == CheckEventKind.falseEntry) {
      audio.env('square', 180, 0.22, 0.07, 120);
      shake = math.max(shake, 3);
      s.toast('## NOBODY ASKED YOU TO SIGN ANYTHING', ToastKind.bad);
    }
    notifyListeners();
  }

  /// The hand comes off the book. Either you let go, or a key needed it —
  /// pressing any banish key abandons a signature in progress, which is the
  /// whole point: you cannot do both at once.
  void releaseCheck() {
    if (checks.signing) {
      endSign(checks);
      notifyListeners();
    }
  }

  /// The SIGN ON button.
  void startBroadcast() {
    // a new shift does not remember what it said on the last one
    s.toasts.newNight();
    audio.init();
    audio.resume();
    audio.setVol(s.sfx);

    // IT WAS ON THE WHOLE TIME. Real hours, not shift minutes. It never says
    // welcome back — nobody at this station is pleased to see you.
    final back = returnLine(s);
    if (back != null) {
      s.toasts.pushDelayed(2600, back, ToastKind.bad);
      _later(2700, () => audio.distantScream(0.25, rand() < 0.5 ? -1 : 1));
    }
    signedOn = true;
    s.started = true;
    // Coming back to the desk — mid-night or not — earns the slow opening.
    checks.resetForNight();
    screamIn = rr(30, 70);
    presence = 0;
    presenceIn = rr(70, 150);
    presenceSpan = 0;
    presenceVisits = 0;
    presenceTurning = false;
    carrierHold = 0;
    carrierHolding = false;
    carrierDrops = 0;
    longNight = false;
    overMin = 0;
    overNeed = 0;
    mirrorCam = -1;
    mirrorIn = rr(120, 260);
    mirrorLeft = 0;
    mirrorTurn = 0;
    scars.clear();
    blood.clear();
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
    // THE KILL GETS A DURATION. `active = null` on its own deletes the thing
    // between two frames, which is why being RIGHT used to produce 0px of shake
    // while being WRONG produced 6. It now leaves a body for the painters to
    // blow out, and stops the world for a moment on the way.
    // THE CLUTCH SAVE. A kill landed with 0.4s left and a kill landed with 4s
    // left were the same event: same shake, same sting, same toast. That is
    // the "last second loop" the game was missing — the moment worth clipping
    // is the one you nearly lost, and it has to be LOUDER than a clean kill,
    // not quieter.
    final bool clutch = success && a.t > a.window * 0.86;
    if (success) {
      final clean = a.t < a.window * 0.4;
      dying = a;
      dyingT = 0;
      dyingSpan = silent ? kDyingSpanQuiet : kDyingSpan;
      if (!silent) {
        hitstop = math.max(
            hitstop, clutch ? kHitstopClutch : (clean ? kHitstopClean : kHitstopPartial));
        shake = math.max(shake, clutch ? 13.0 : (clean ? 10.0 : 6.5));
        flash = math.max(flash, clutch ? 0.42 : (clean ? 0.34 : 0.2));
        if (clutch) clutchFx = 1;
      }
    }
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
      bonus *= cardOf(s).banishPay;
      // A save pays like a clean kill. It is harder than a clean kill; it was
      // paying the partial rate purely because the timer had run down.
      if (clutch) bonus *= 1.6;
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
      if (clutch) {
        s.stats.clutch++;
        // THE NEAR MISS IS THE HOOK. "Short misses and the feeling of a little
        // more" is exactly what a clutch save is, and it was scored in silence
        // and filed in a stat nobody reads. It now announces the margin — the
        // actual milliseconds you had left — because a number that small is
        // the thing a player screenshots and the thing that makes them start
        // another night.
        final int ms = ((a.window - a.t) * 1000).round().clamp(0, 99999);
        s.lastClutchMs = ms;
        if (ms < s.bestClutchMs || s.bestClutchMs == 0) s.bestClutchMs = ms;
        if (!silent) audio.clutchSting();
        s.toasts.pushDelayed(
            420,
            ms <= s.bestClutchMs
                ? 'CLOSEST YET — ${ms}ms LEFT'
                : '${ms}ms LEFT',
            ToastKind.gold);
      }
      if (!silent) audio.banishStinger(fast || clutch, s.stats.streak);
      // NO TOAST FOR A KILL. The player watched it die, heard its stinger and
      // saw the flash — a line of text arriving afterwards to confirm it is
      // the game reading its own screen aloud. Measured, the kill family was
      // roughly a fifth of all 103 interruptions in a night. A clutch kill
      // still speaks, because beating a window by 200ms is a thing the player
      // cannot see and deserves to be told.
      if (clutch) {
        s.toast('LAST SECOND — ${a.def.nm}', ToastKind.gold);
      }

      // --- the ALL CLEAR ---
      // The whole point of the deck: if you got it right, you are SAFE, and
      // the game says so in as many words. Length scales with how clean the
      // kill was and compounds with the streak; a jumpscare resets the streak,
      // so the compounding has to be defended every time.
      grantCalm(calmWindow(s,
          cleanliness: a.cleanliness,
          streak: s.stats.streak,
          fumbles: a.wrongs,
          meanGap: anomIntervalMean(s, nightAnoms)));
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

    // -----------------------------------------------------------------------
    // THE FIVE THAT DID NOTHING
    //
    // sabotageTick had bodies for exactly two ids, and _simulate handled a
    // third. Measured on the shipped build, THE SNOW CRAWLER, MR. SLEEPWELL,
    // THE VERTICAL MAN, THE RERUN and THE NIELSEN left sigRate at 40118 ->
    // 40118 with muted=0, held=0, rings=0 — five of eight entities were a
    // picture and a key, identical to each other in every way that matters.
    // That is what "it's too simple" is: eight signatures, one encounter.
    //
    // Each now applies a DIFFERENT pressure, so which one is on the tube
    // changes what you should be doing about it. All five are budgeted per
    // visit, not per second, so a long window is not arbitrarily worse.
    // -----------------------------------------------------------------------

    // THE SNOW CRAWLER — snow eats the picture, and the picture is the lock.
    // It knocks the CARRIER LOCK down a tier at a time. Hurts precisely the
    // player who has been playing well, and DEGAUSS is the answer to snow.
    if (a.def.id == 'snow') {
      a.sabIv -= dt;
      if (a.sabIv <= 0) {
        a.sabIv = math.max(1.1, 2.4 - p * 1.2);
        if (s.tune.tier > 0) {
          s.tune.knockDown();
          audio.env('sawtooth', 180, 0.35, 0.10, 60);
          shake = math.max(shake, 5);
          s.toast('## THE LOCK IS SLIPPING — ${s.tune.tier > 0 ? s.tune.tierName : "CARRIER LOST"}',
              ToastKind.bad);
        }
      }
    }

    // MR. SLEEPWELL — you are still transmitting. You are transmitting HIM.
    // Output keeps arriving in the bank and stops counting toward the quota,
    // which threatens the clock without touching your money. Distinct from
    // DEAD AIR, which cuts the rate itself.
    if (a.def.id == 'sleep') {
      if (a.rings == 0) {
        a.rings = 1;
        s.toast('## YOU ARE OFF THE RUNDOWN — NOTHING IS COUNTING',
            ToastKind.bad);
      }
    }

    // THE VERTICAL MAN — vertical hold. The instruments stop being readable:
    // every figure in the rack and the strip rolls. Nothing is taken from you
    // at all, which is the point — you simply cannot see what you have.
    if (a.def.id == 'vert') {
      vertRoll = math.min(1.0, vertRoll + dt * 1.6);
    }

    // THE RERUN — its own manual page promises it "will overwrite anything you
    // transmit with itself", and it did nothing. It now walks this segment's
    // output backward, but never past what you had banked when it arrived.
    if (a.def.id == 'rerun') {
      // Measured: a budget-based drain was SLOWER than live output, so the
      // segment counter never actually fell — it just grew more slowly, which
      // reads as nothing at all. It has to outrun you, or "it will overwrite
      // anything you transmit" is a sentence and not a mechanic. Pegged to
      // your own output rate, so it scales with the station and stays
      // frightening at every depth, and floored at 55% of what you had when
      // it arrived so it can never zero a segment outright.
      final double floor = a.segAtArrival * 0.55;
      final double take = sigRateRaw(s) * 1.35 * sabK() * dt;
      if (s.segSig > floor) {
        s.segSig = math.max(floor, s.segSig - take);
        a.takenSeg += take;
      }
      a.sabIv -= dt;
      if (a.sabIv <= 0) {
        a.sabIv = 2.6;
        audio.env('triangle', 96, 0.4, 0.08, 70);
        s.toast('## THE RERUN IS GOING OUT INSTEAD OF YOU', ToastKind.bad);
      }
    }

    // THE NIELSEN — he is measuring, and what he measures he keeps. He is the
    // only thing in the game that touches the CAREER: lifetimeSig is what
    // rpGain() reads, so a visit from him costs you tomorrow, not tonight.
    if (a.def.id == 'niel') {
      final double budget = s.lifetimeSig * 0.06 * sabK();
      final double take = math.min(budget - a.takenLife, budget * dt / 6.0);
      if (take > 0) {
        s.lifetimeSig = math.max(0, s.lifetimeSig - take);
        a.takenLife += take;
      }
      a.sabIv -= dt;
      if (a.sabIv <= 0) {
        a.sabIv = 3.0;
        audio.env('square', 320, 0.18, 0.06, 240);
        s.toast('## HE IS WRITING YOUR NUMBERS DOWN', ToastKind.bad);
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
          s.dread = math.min(100, s.dread + pay * cardOf(s).dread);
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

  /// Marks the room. Each kind lands at most once a night, and they are drawn
  /// in an order that escalates: the first bad thing is a face in a corridor
  /// you can look away from, the last one is your own equipment lying to you.
  void _leaveScar(Anom def) {
    final List<ScarKind> open = <ScarKind>[
      if (!hasScar(ScarKind.camGhost)) ScarKind.camGhost,
      if (!hasScar(ScarKind.atTheGlass)) ScarKind.atTheGlass,
      if (!hasScar(ScarKind.burnIn)) ScarKind.burnIn,
      if (!hasScar(ScarKind.wrongName)) ScarKind.wrongName,
    ];
    if (open.isEmpty) return;
    final ScarKind k = open.first;
    // The glass remembers it too. AT THE GLASS is the one that gets hands:
    // there is nothing out in that field that has hands, and the game never
    // remarks on it.
    if (k == ScarKind.atTheGlass) {
      for (var i = 0; i < 3; i++) {
        blood.addHand(
          kWin.left + 14 + rand() * (kWin.width - 28),
          kWin.top + 40 + rand() * (kWin.height - 90),
        );
      }
      // hard right, where the window is
      _later(220, () => audio.bloodImpact(0.35));
      _later(760, () => audio.bloodDrip(0.85, 0.8));
    } else if (k == ScarKind.burnIn) {
      blood.add(0.5, ox: kScr.center.dx, oy: kScr.top - 55, count: 3);
    }
    scars.add(Scar(
      k,
      def,
      slot: k == ScarKind.wrongName
          ? (rand() * kProducers.length).floor().clamp(0, kProducers.length - 1)
          : (rand() * 4).floor().clamp(0, 3),
    ));
  }

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
  /// A scare that did not come from the tube.
  ///
  /// jumpscare() operates on `active` and returns immediately without one, so
  /// nothing in the game could frighten the player except a missed anomaly.
  /// This is the room doing it, with no window, no counter and nothing the
  /// player could have pressed.
  void jumpscareFromRoom() {
    if (lost) return;
    final Anom def = pick(unlockedAnoms(s));
    _scareSerial++;
    scareBeat = ScareBeat.lunge;
    _scareHit(def, ScareBeat.lunge, _scareSerial, 0);
    // It costs nothing but dread — it did not rob you, it just came round.
    s.dread = math.min(100, s.dread + 18 * cardOf(s).dread);
    s.toast('## IT WAS NOT BEHIND YOU ANY MORE', ToastKind.bad);
  }

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
    // THE STREAK. streakBroken() is declared, documented ("play the loss of
    // it, not just the scare on top") and fully implemented in the audio
    // engine — a descending three-saw glissando through a closing lowpass
    // onto a floor thud, scaled by how long the run was — and had no call site
    // anywhere. The game shouts your streak from five places and then took a
    // mean 7.3-kill run away in silence.
    //
    // Captured HERE, before the zeroing, and not in _scareHit: that runs after
    // this line, so it would have read 0 every time and never fired.
    final int lostStreak = s.stats.streak;
    s.stats.streak = 0;
    if (lostStreak > 2) {
      // in the quiet recovery tail, where the CARRIER RECOVERED toast sits —
      // the scare is over and this is what it cost you
      _later(5200, () => audio.streakBroken(lostStreak));
      s.toasts.pushDelayed(5200, 'STREAK LOST — $lostStreak GONE', ToastKind.bad);
    }

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
        // THE LIE HAS TO BE PERFECT.
        //
        // This sets calm but never calmGuard, and airLabel branches on exactly
        // that: `calmGuard > 0 ? 'ALL CLEAR Ns' : 'CLEAR - FADING'`. Since a
        // real banish always goes through grantCalm(), which always sets a
        // guard, the lamp read 'ALL CLEAR Ns' on every real banish and
        // 'CLEAR - FADING' on every fake one — a 100% reliable tell, measured
        // 19/19 fake and 82/82 real. The one second of staged relief that is
        // supposed to make you believe was pre-labelled as a fake.
        //
        // MR. SLEEPWELL, THE TEST CARD GIRL and THE CALLER all draw this as
        // their signature beat, so this is three of eight entities' best
        // moment. The guard is also given a plausible LENGTH: a flat 4s
        // against a real distribution of 13-15s was its own tell.
        falseClear = true;
        banishFx = 1;
        final double lie = rr(11.5, 15.5);
        calm = lie;
        calmSpan = lie;
        calmGuard = lie;
        calmGuardSpan = lie;
        audio.deadAir(false);
        audio.setStatic(0.03);
        audio.setDrone(0, 42);
        audio.setHeart(52, 0.04);
        audio.banishStinger(false, s.stats.streak);
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
    // the staged guard goes with it, or the lamp keeps counting down a
    // promise of safety over the top of the jumpscare that broke it
    calmGuard = 0;
    calmGuardSpan = 0;

    // IT LEAVES SOMETHING BEHIND.
    //
    // A scare that ends with the room exactly as it was is a loud noise, and a
    // loud noise is forgettable: you brace, it happens, you carry on. The room
    // not going back is the part that sits with you. Nothing announces these —
    // you are supposed to notice on your own, later, that a camera has had
    // someone standing in it for twenty minutes.
    _leaveScar(def);
    // AND IT MARKS THE GLASS. Not a red flash that fades — something lands on
    // the pane between you and the room and is still there at 05:00, running.
    // Around the bezel and up the walls, NOT at the centre of the picture.
    // Spawning at kScr.center piled every mark onto the screen.
    final double spray = 0.55 + rand() * 0.45;
    for (var i = 0; i < 2; i++) {
      blood.add(
        spray * 0.6,
        ox: rand() < 0.5 ? kScr.left - 40 - rand() * 120 : kScr.right + 30 + rand() * 150,
        oy: kScr.top - 30 + rand() * (kScr.height + 120),
        count: 2,
      );
    }
    blood.add(spray * 0.5,
        ox: kScr.center.dx + (rand() - 0.5) * 260,
        oy: kScr.bottom + 40 + rand() * 90,
        count: 2);
    audio.bloodImpact(spray);

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
    s.dread = math.min(100, s.dread + 26 * cardOf(s).dread);
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
    dying = null;
    dyingT = 0;
    hitstop = 0;
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
    // rpMult was made sub-linear (1 + 0.26*rp^0.62) and rpMultAt() exists
    // precisely so the sheets can quote what a bank WOULD be worth — it had
    // no callers, and all three sales pitches still ran the retired linear
    // formula. The status bar printed the correct figure on the same frame:
    // measured x37.51 in the HUD against x2213.88 on the sheet.
    final mult = (rpMultAt(s.rp + rg) / rpMultAt(s.rp)).toStringAsFixed(2);
    endScreen = EndScreen.signalLost;
    endScreenModel = EndScreenModel(
      win: false,
      title: '## THE CARRIER DROPPED',
      reviveLabel: 'EMERGENCY SPONSOR — STAY ON AIR',
      acceptLabel:
          rg > 0 ? 'SIGN OFF — BANK ${fmt(rg)} RP' : 'SIGN OFF (0 RP)',
      body: <EndPara>[
        // A failure screen that reads as a scoreboard is a failure screen a
        // player shrugs at. This one states the consequence the premise set up:
        // the carrier was the lid, and you were the one holding it.
        EndPara(<String>[
          'KBLK-7 is off the air for the first time since 1963.',
        ]),
        EndPara(<String>[
          '',
          'IT IS NOT IN THE SIGNAL ANY MORE.',
          ' Every monitor in the building is showing the same room, and it is '
              'this one. The window in the booth has never opened. It is open.',
        ]),
        EndPara(<String>[
          'The clock stopped at ',
          shiftClock(s),
          ' during ${segOf(s).nm}. Sunrise was at 06:00 and it was not close.',
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
      addMark(s, Mark.debt);
      // SECOND SHIFT (35 RP) bought nothing: metaFreeRevives() had no callers,
      // and revive() hardcoded the same numbers every time, so eight deaths in
      // one night returned byte-identical state while the sheet counted
      // "#8 tonight" at you. The free ones come back clean; after that each
      // one leaves you deeper in it than the last.
      final int free = metaFreeRevives(s);
      final int over = math.max(0, s.revives - 1 - free);
      s.dread = math.min(88, 45 + over * 12.0);
      lost = false;
      s.sponsorEnd = math.max(s.sponsorEnd, 45 / (1 + over * 0.45));
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
  /// The roster lines on the 06:00 sheet. Built here rather than in the UI so
  /// they are frozen with the rest of the model at the moment it opens.
  List<EndPara> _rosterParas() {
    final out = <EndPara>[];
    // s.survived has already been incremented by the time this runs
    final justPassed = passedBetween(s.survived - 1, s.survived);
    for (final o in justPassed) {
      out.add(EndPara(<String>[
        'You have outlasted ',
        o.name,
        ', who lasted ${o.nights} '
            '${o.nights == 1 ? "night" : "nights"}. ${o.fate}',
      ]));
      if (o.unlock != null) {
        out.add(EndPara(<String>['', o.unlock!, '']));
      }
    }
    final next = nextOnRoster(s);
    if (next != null) {
      final left = next.nights - s.survived;
      out.add(EndPara(<String>[
        'Next on the roster: ',
        next.name,
        ' at ${next.nights} nights — '
            '${left == 1 ? "one more shift" : "$left more shifts"}.',
      ], ParaStyle.dim));
    }
    return out;
  }

  /// Is this the one? Once per career, deep enough in that the player has
  /// stopped counting the minutes to 06:00 and started trusting it.
  bool _longNightDue() {
    if (s.longNightDone) return false;
    if (s.survived < 8) return false;
    // certain by night 14, so it is a promise the career keeps rather than a
    // lottery the player may never see
    return s.survived >= 14 || rand() < 0.22;
  }

  void _beginLongNight() {
    longNight = true;
    overMin = 0;
    overNeed = rr(55, 95); // roughly one to one and a half more hours
    s.longNightDone = true;

    // No sheet. No sun. The clock simply does not stop.
    audio.hold(900);
    audio.setSub(1.0);
    audio.deadAir(true);
    _later(950, () => audio.deadAir(false));
    _later(1000, () => audio.distantScream(0.6, rand() < 0.5 ? -1 : 1));
    blackout = math.max(blackout, 1);
    shake = math.max(shake, 22);

    s.toast('06:00', ToastKind.bad);
    s.toasts.pushDelayed(1800, 'THE SUN IS NOT UP', ToastKind.bad);
    s.toasts.pushDelayed(4200, 'NOBODY IS COMING TO TAKE THE DESK',
        ToastKind.bad);

    // and everything gets worse at once
    s.dread = math.min(100, math.max(s.dread, 40));
    calm = 0;
    calmSpan = 0;
    calmGuard = 0;
    calmGuardSpan = 0;
    presence = 1;
    presenceSpan = rr(9, 16);
    scheduleNext();
    notifyListeners();
  }

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
    // Was 523 / 659 / 784 — C, E, G, ascending. A victory fanfare.
    //
    // Sunrise is the one moment of relief this game grants and it should keep
    // being relief, or the horror has nothing to be measured against. But
    // relief here is not a jingle, it is the sound of a shift ENDING: the
    // 1kHz line-up tone going out over the test card, held flat and steady,
    // and the transmitter dropping to standby underneath it.
    audio.env('sine', 1000, 1.5, 0.10, 1000);
    _later(120, () => audio.relay());
    _later(900, () => audio.env('sine', 50, 1.8, 0.09, 40));
    s.survived++;
    s.dawnBonus = 6; // surviving is worth more than bailing out
    final g = rpGain(s) + s.dawnBonus;
    // rpMult was made sub-linear (1 + 0.26*rp^0.62) and rpMultAt() exists
    // precisely so the sheets can quote what a bank WOULD be worth — it had
    // no callers, and all three sales pitches still ran the retired linear
    // formula. The status bar printed the correct figure on the same frame:
    // measured x37.51 in the HUD against x2213.88 on the sheet.
    final mult = (rpMultAt(s.rp + g) / rpMultAt(s.rp)).toStringAsFixed(2);
    endScreen = EndScreen.dawn;
    endScreenModel = EndScreenModel(
      win: true,
      title: s.longNightDone && overNeed > 0
          ? '☀ THE SUN CAME UP EVENTUALLY'
          : '☀ 06:00 — SIGN-OFF',
      reviveLabel: null,
      acceptLabel: 'SIGN THE LOG AND TAKE THE NEXT SHIFT  ·  ${fmt(g)} RP',
      body: <EndPara>[
        if (overNeed > 0)
          EndPara(<String>[
            'It took ',
            '${overMin.round()} minutes',
            ' longer than it was supposed to. Nobody has said why, nobody is '
                'going to, and the log has no line for the hour you have just '
                'sat through — so you will write it in the margin, the way '
                'HALLORAN did, and the next operator will read it.',
          ])
        else
          EndPara(<String>[
            'The test card comes up on its own and the sun takes over the '
                'holding. Whatever was in the signal goes back down into it, '
                'the way it does every morning, and the room is just a room '
                'again.',
          ]),
        EndPara(<String>[
          '',
          'YOU MADE IT TO 06:00.',
          ' Night ${s.night} survived — ${s.stats.banished} banished, '
              '${s.stats.scared} got through, best streak '
              '${s.stats.bestStreak}'
              '${s.stats.clutch > 0 ? ", ${s.stats.clutch} on the buzzer" : ""}.',
        ]),
        EndPara(<String>[
          'Sign the log and hand over. Bank ',
          '${fmt(g)} ratings points',
          ' (permanent ×$mult to everything) and open NIGHT ${s.night + 1}: ',
          cardForNight(s.night + 1).nm,
          '. It starts at 23:00.',
        ]),
        // THE RETENTION MOMENT. This sheet is where the player decides whether
        // there is a tomorrow, and it used to close on a bare count. It now
        // says who you just outlasted, what that opened, and who is next with
        // a distance — the three things that make someone take one more shift.
        // WHAT THE STATION HAS DECIDED ABOUT YOU. Only ever from things the
        // operator CHOSE, and only once it is a pattern rather than an
        // incident — being judged for bad luck is unfair, being judged for
        // your own repeated decisions is the entire point.
        if (verdictLine(s) != null)
          EndPara(<String>[
            'The file has started calling you ',
            verdictLine(s)!,
            '.',
          ], ParaStyle.dim),
        ..._rosterParas(),
        EndPara(<String>['Nights survived: ${s.survived}'], ParaStyle.fine),
      ],
    );
    notifyListeners();
  }

  /// Prestige. Banks RP, wipes the run, starts the next night.
  /// Sign off and go straight back on.
  ///
  /// "the feeling of a little more" dies at a menu. The end sheet used to drop
  /// the operator back to the front desk, where they had to read a rank, find
  /// a button and take a shift — three deliberate acts between wanting another
  /// night and having one. This is the same sign-off with the next shift
  /// already started.
  void signOffAndBack() {
    signOff();
    startBroadcast();
  }

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
      // was a 440 -> 880 octave sweep, which is a jingle. A commercial break
      // starts with the leader beep off the cart machine and the tape catching.
      audio.env('square', 1000, 0.09, 0.11, 1000);
      audio.relay();
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

    // `paused` is the manual. The game's ONE instruction is "Press M", the
    // manual page for an entity is a ~29s read, and a first-sighting window is
    // 9.4s — so following the instruction used to guarantee the jumpscare.
    if (signedOn && !adPlaying && !lost && !paused) {
      _simulate(dt);
    }

    // The room keeps breathing behind modals, the manual and the ad break.
    audio.tick(dt);
    audio.setDread(s.dread / 100);
    // The floor under the room. Dread sets the bed; an anomaly on the tube
    // pushes it most of the way up on its own, so the room gets HEAVY the
    // moment something is present even on a calm night.
    audio.setSub(math.min(
        1.0, s.dread / 100 * 0.75 + (active != null && active!.stage >= 1 ? 0.55 : 0)));

    // THE STATION CHECKS. Runs on its own clock, deliberately unsynchronised
    // with the anomaly scheduler — the collision is the interesting part.
    if (signedOn && !lost) {
      final done = tickSign(checks, s, dt);
      if (done != null) {
        audio.relay();
        s.toast('${done.check!.nm} — SIGNED', ToastKind.good);
      }
      final ev = tickChecks(checks, s, dt, canRaise: scare <= 0 && !paused);
      if (ev != null) {
        switch (ev.kind) {
          case CheckEventKind.raised:
            audio.env('square', 660, 0.10, 0.055, 660);
            _later(110, () => audio.env('square', 880, 0.10, 0.045, 880));
            s.toast('${ev.check!.nm} — ${ev.check!.ds}   [ENTER]',
                ToastKind.gold);
          case CheckEventKind.signed:
            audio.relay();
          case CheckEventKind.missed:
            s.dread = math.min(100, s.dread + kMissDread * cardOf(s).dread);
            audio.env('sawtooth', 120, 0.5, 0.10, 44);
            shake = math.max(shake, 6);
            // The book going unsigned is ALREADY on the screen, in the room,
            // as the thing you did not do. Measured over one night this fired
            // nine times against nine of the matching "[ENTER]" prompt: the
            // game asked for the same chore nine times and told the player off
            // nine times for not doing it. That is what "there's too much shit
            // popping up" was describing.
            // A book left unsigned while something was in the room leaves a
            // mark. Nobody says whose.
            if (active != null) {
              addMark(s, Mark.neglect);
              blood.add(0.2,
                  ox: 60 + rand() * 140, oy: 180 + rand() * 300, count: 2);
            }
          case CheckEventKind.falseEntry:
            break; // signBook() handles it; nothing is raised here
        }
      }
      // drift is a continuous tax on a neglected station
      if (checks.drift > 0) {
        s.dread = math.min(100, s.dread + driftDread(checks) * dt);
      }
    }

    // THE HAND ON THE CARRIER. Nothing explains this and nothing ever will.
    if (signedOn && !lost) {
      if (carrierHolding) {
        carrierHold = math.min(1.0, carrierHold + dt / kCarrierHoldSeconds);
        // the room goes with it — the bed thins, the floor drops away
        audio.setSub(math.min(1.0, 0.3 + carrierHold * 0.7));
        audio.setStatic(0.03 + (1 - carrierHold) * 0.10);
        shake = math.max(shake, carrierHold * 9);
        if (carrierHold >= 1.0) dropCarrier();
      } else if (carrierHold > 0) {
        carrierHold = math.max(0, carrierHold - dt * 1.6);
      }
    }

    // ONE OF THE CAMERAS IS POINTED AT THIS ROOM.
    //
    // Never while anything else is happening — it needs the quiet, because the
    // whole effect depends on the player noticing it themselves on a monitor
    // they had stopped reading twenty minutes ago.
    if (signedOn && !lost) {
      if (mirrorCam >= 0) {
        mirrorLeft -= dt;
        // it turns round very slowly, and it is never finished turning
        mirrorTurn = math.min(0.85, mirrorTurn + dt * 0.035);
        if (mirrorLeft <= 0) {
          mirrorCam = -1;
          mirrorTurn = 0;
        }
      } else {
        mirrorIn -= dt;
        if (mirrorIn <= 0) {
          final double d = s.dread / 100;
          mirrorIn = rr(150, 300) - d * 60;
          if (active == null && scare <= 0 && presence <= 0 && !paused) {
            mirrorCam = (rand() * 4).floor().clamp(0, 3);
            mirrorLeft = rr(14, 34);
            mirrorTurn = 0;
            // no toast, no sound, no lamp. If you are not looking, you miss it.
          }
        }
      }
    }

    // SOMETHING IS BEHIND YOU.
    //
    // Not an anomaly. It has no counter, it takes nothing, it cannot be
    // banished and it is never mentioned by any readout in the game. It simply
    // arrives in the room, stays between eight and twenty seconds, and leaves.
    // The only trace is that the light changes and your own heartbeat comes up
    // in your ears — which the player will find on their own, or not.
    if (signedOn && !lost) {
      if (presence > 0) {
        presence -= dt / math.max(0.5, presenceSpan);
        if (presence <= 0.42 && presenceTurning) {
          // IT DOES NOT LEAVE.
          //
          // Every other visit has been harmless and the player has learned
          // that. This is the one that comes round the front, with no
          // telegraph, no window and no key — because the entire value of a
          // hundred safe visits is what it buys for the one that is not.
          presenceTurning = false;
          presence = 0;
          audio.setHeart(150, 0.30);
          jumpscareFromRoom();
        } else if (presence <= 0) {
          presence = 0;
          presenceVisits++;
          audio.setHeart(46, 0);
          // it does not leave quietly
          if (rand() < 0.4) _later(300, () => audio.creak());
        }
      } else {
        presenceIn -= dt;
        if (presenceIn <= 0) {
          final double d = s.dread / 100;
          presenceIn = rr(80, 190) - d * 40;
          if (active == null && scare <= 0 && !paused) {
            presenceSpan = rr(8, 20);
            presence = 1;
            // The longer it has been merciful, the worse the odds. Never on
            // the first two visits of a night — the player has to be allowed
            // to learn that it is safe before that is taken away.
            presenceTurning = presenceVisits >= 2 &&
                rand() < 0.06 + presenceVisits * 0.035 + d * 0.10;
            // no toast, no lamp, no meter. The heart is the only tell, and it
            // is YOUR heart, so it reads as the player's own reaction rather
            // than as a notification.
            audio.setHeart(96 + d * 30, 0.20 + d * 0.16);
            audio.breath(rand() < 0.5 ? -1 : 1, 0.9);
            audio.setSub(math.min(1.0, 0.55 + d * 0.45));
          }
        }
      }
    }

    // SOMEBODY IS SCREAMING. Elsewhere, through a wall, and there is no key
    // that answers it. It never costs anything and it never means anything,
    // which is exactly why it is disturbing rather than punishing: the player
    // cannot make it stop and cannot make it not have happened.
    if (signedOn && !lost) {
      screamIn -= dt;
      if (screamIn <= 0) {
        final double d = s.dread / 100;
        screamIn = rr(34, 82) - d * 16;
        if (scare <= 0 && !paused) {
          audio.distantScream(0.15 + d * 0.55, rand() < 0.5 ? -1 : 1);
          // and the room notices, very slightly
          shake = math.max(shake, 1.6);
        }
      }
    }

    // THE ROOM STOPS. No cause, no consequence, nothing to react to — just a
    // beat where the world is not there. Never while something is on the tube
    // (that beat belongs to the encounter) and never inside a scare.
    roomStop -= dt;
    if (roomStop <= 0) {
      final double d = s.dread / 100;
      roomStop = rr(40 - d * 16, 92 - d * 34);
      if (active == null && scare <= 0 && !lost) {
        audio.hold((240 + rand() * 420).round());
        // and sometimes something is in the hole with you
        if (rand() < 0.22 + d * 0.35) {
          _later(120 + (rand() * 180).round(),
              () => audio.breath(rand() < 0.5 ? -1 : 1, 0.55 + d * 0.4));
        }
      }
    }

    s.tune.tick(dt, tGlobal);

    // The corpse fades on its own clock; the hit-stop drains in real time so it
    // cannot be extended by a second kill landing inside it.
    if (dying != null) {
      dyingT += dt;
      if (dyingT >= dyingSpan) {
        dying = null;
        dyingT = 0;
      }
    }
    hitstop = math.max(0, hitstop - dt);
    shake = math.max(0, shake - dt * 36);
    flash = math.max(0, flash - dt * 3.2);
    // The false clear holds its green wash until the beat takes it away.
    if (!falseClear) banishFx = math.max(0, banishFx - dt * 2.4);
    clutchFx = math.max(0, clutchFx - dt * 1.6);
    if (active?.def.id != 'vert') {
      vertRoll = math.max(0, vertRoll - dt * 1.1);
    }
    // published to the formatter so every readout in the game rolls at
    // once, without any call site knowing he exists
    gVertRoll = vertRoll;
    blood.tick(dt);
    // Every bead that lets go is a sound, panned to WHERE it is on the glass.
    // A drip you hear from off to your left while you are watching the tube is
    // the cheapest and oldest trick in the genre, and it works because it is
    // information about a place you are not looking.
    if (blood.drips.isNotEmpty) {
      for (final d in blood.drips) {
        audio.bloodDrip(
            ((d.x / kRoom.width) * 2 - 1).clamp(-1.0, 1.0), d.size);
      }
      blood.drips.clear();
    }
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
    //
    // MR. SLEEPWELL is the exception: you are still transmitting, but what is
    // going out is him. The money still arrives; none of it is on the rundown.
    final out = sr * dt;
    if (!sabOn('sleep')) s.segSig += out;
    s.lifetimeSig += out;
    s.airtime += dt;

    // --- the shift clock ---
    // Runs freely to :59 then HOLDS until the segment's quota is met.
    final seg0 = segIndex(s);
    // UNION RULES promises "the clock cannot hold you for more than 45 seconds
    // at a stretch" and metaStallCap() had no callers, so real played nights
    // recorded holds of 280-508s. It is the priciest node on the board.
    final double? cap = metaStallCap(s);
    final bool capped = cap != null && s.stalled && _stallHeld >= cap;
    if (s.shiftMin % 60 >= 59 && !quotaMet(s) && !capped) {
      if (!s.stalled) {
        s.stalled = true;
        _stallHeld = 0;
        _stallSay = 0;
        _stallAdvice = 0;
      }
      _stallHeld += dt;
      // A held clock used to announce itself exactly once, into silence, with
      // no figure attached — a traced blind night ends frozen at 23:59 with
      // nothing on screen naming the action that would unfreeze it. It now
      // restates the exact shortfall and cycles through what to do about it.
      _stallSay -= dt;
      if (_stallSay <= 0) {
        _stallSay = 19;
        final short = quotaShortfall(s); // TONIGHT's, not the printed table
        s.toast('CLOCK HELD — ${fmt(short)} MORE OUTPUT NEEDED THIS SEGMENT',
            ToastKind.bad);
        const advice = <String>[
          'STRIKE THE TUBE — EVERY HIT COUNTS TOWARD THE QUOTA',
          'BANISH SOMETHING — A CLEAN KILL PAYS STRAIGHT INTO OUTPUT',
          'BUY A TRANSMITTER — THE RACK IS ON YOUR RIGHT',
        ];
        s.toasts.pushDelayed(
            1200, advice[_stallAdvice % advice.length], ToastKind.gold);
        _stallAdvice++;
      }
      s.dread = math.min(100, s.dread + dt * 0.9 * cardOf(s).dread);
    } else {
      if (s.stalled) {
        s.stalled = false;
        s.toast(
            capped
                ? 'UNION RULES — THEY CANNOT HOLD YOU ANY LONGER'
                : 'QUOTA MET — CLOCK RUNNING',
            ToastKind.good);
      }
      _stallHeld = 0;
      s.shiftMin += dt / kMinReal;
      if (segIndex(s) != seg0 && s.shiftMin < kShiftMinutes) {
        // A quota measures what you broadcast DURING its segment. Without this
        // reset the thresholds silently became cumulative, which is not what
        // the HUD ("BROADCAST / THIS SEGMENT") or the Nielsen's restatement say.
        s.segSig = 0;
        final sg = segOf(s);
        s.toast('▶ ${shiftClock(s)}  ${sg.nm}', ToastKind.gold);
        s.toasts.pushDelayed(1100, sg.line, ToastKind.gold);
        // was 392 then 523 — G up to C, a rising fourth, i.e. a little
        // "next chapter" sting. A segment change is a cart machine handing
        // over: the outgoing tape stopping and the incoming one catching.
        audio.relay();
        _later(300, () => audio.env('square', 1000, 0.07, 0.07, 1000));
      }
      if (s.shiftMin >= kShiftMinutes) {
        if (longNight) {
          // the clock keeps counting into an hour with no segment
          overMin += dt / kMinReal;
          if (overMin >= overNeed) {
            longNight = false;
            dawn();
          }
        } else if (_longNightDue()) {
          _beginLongNight();
        } else {
          dawn();
        }
      }
    }

    // --- dread decay ---
    // Bleeds off much faster inside a protection window. Recovering from a
    // scare is supposed to be something you can watch happen, and the calm you
    // bought with a clean kill should visibly pay for the last one.
    // an hour nobody wrote down does not bleed off the way the others do
    var dec = ((s.ups['failsafe'] ?? false) ? 1.6 : 0.8) * recordDecayMul(s);
    if (aftermath > 0) {
      dec *= 2.6;
    } else if (calm > 0) {
      dec *= 1.5;
    }
    // THE FLOOR. dreadFloor() and kDreadFloorClimb were written, documented
    // with a worked table, and never called: decay clamped at 0 instead, so
    // DREAD returned to empty after every single encounter.
    //
    // Measured on the shipped build: over a competently played night, DREAD
    // sat under 1.0/100 for 96.4% of frames on night 1 and 99.6% on night 6.
    // The widest gauge in the status strip — the thing the home screen names
    // as the loss condition — was a flat empty rectangle for the whole game,
    // and everything hanging off it (the canteen, the red room wash, the
    // lights going out, the bot failures) was unreachable dead code.
    //
    // The night now has a rising tide under it. It is capped at
    // kDreadFloorCap = 42 so atmosphere can never kill you on its own —
    // SIGNAL LOST still has to be something you did.
    if (active == null) {
      final double floor = dreadFloor(s);
      if (s.dread > floor) {
        s.dread = math.max(floor, s.dread - dec * dt);
      } else if (s.dread < floor) {
        s.dread = math.min(floor, s.dread + kDreadFloorClimb * dt);
      }
    }

    // (b) THE WINDOW IS A THREAT. lurkPressure was declared and written by
    // nobody; the field full of figures was scenery you could safely ignore.
    if (lurkPressure > 0) {
      s.dread = math.min(
          100, s.dread + kLurkDread * lurkPressure.clamp(0.0, 1.0) * dt);
    }

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
      // Saturated. This was the only depth() consumer in the codebase
      // without a ceiling, so with the floor now live a deep career
      // would cross 0->100 inside one ordinary encounter.
      s.dread = math.min(
          100,
          s.dread +
              dt * (1.2 + math.min(2.4, depth(s) * 0.02)) * cardOf(s).dread);
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
      // BINAURAL DRIFT. The complaint was that the game leans on one loud
      // panic and has nothing underneath it. The room now MOVES: a slow
      // wander that widens with dread, so long before anything reaches the
      // tube the space around you stops sitting still. Amplitude is small on
      // purpose — if you notice it consciously it has already failed.
      _drift += dt;
      final double wander =
          math.sin(_drift * 0.21) * 0.30 + math.sin(_drift * 0.083) * 0.22;
      audio.pan(wander * (0.35 + s.dread / 100 * 0.65));
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
      // The GUARANTEED head of the window drains on its own clock, outside the
      // calm branch — it is granted on every banish and beginWarn() hard-returns
      // while it is up, so failing to drain it here stopped the game dead after
      // the player's first kill. Measured: 1 manifest per 21-minute night.
      if (calmGuard > 0) {
        calmGuard -= dt;
        if (calmGuard <= 0) {
          calmGuard = 0;
          calmGuardSpan = 0;
        }
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
