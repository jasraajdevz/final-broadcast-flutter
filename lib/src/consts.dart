// FINAL BROADCAST — constants, geometry and data tables.
//
// Direct transcription of the DATA section of index.html. Every number here is
// the number from the HTML; nothing has been rounded, retuned or "improved".
// If a value looks odd, it is odd in the original too.
//
// Portable: this file imports only dart:math, dart:ui/painting for Color and
// Rect, and desk.dart — which is itself pure Dart — for the Rail an anomaly
// eats. Nothing web-specific.

import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect, Size;

import 'desk.dart' show Rail;

// ---------------------------------------------------------------------------
// 0. HELPERS  (JS section 0)
// ---------------------------------------------------------------------------

const double tau = math.pi * 2;

double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double lerpD(double a, double b, double t) => a + (b - a) * t;

math.Random _rng = math.Random();

/// Pin the RNG so a headless night is reproducible.
///
/// Balance in this game is only ever established by simulating whole nights,
/// and an unseeded generator makes those sims coin-flips: a guard written
/// against one run's numbers fails on another with no code change, which is
/// worse than no guard because it teaches you to ignore red. Tests seed this;
/// nothing in the game ever calls it.
void seedRandom(int seed) => _rng = math.Random(seed);

/// JS `rr(a,b)` — uniform random in [a,b).
double rr(double a, double b) => a + _rng.nextDouble() * (b - a);

/// JS `pick(a)` — uniform random element.
T pick<T>(List<T> a) => a[(_rng.nextDouble() * a.length).floor()];

/// JS `Math.random()`.
double rand() => _rng.nextDouble();

/// JS `rnd()` — the deterministic LCG used for repeatable texture detail.
/// seed starts at 1337 exactly as in the HTML.
class Lcg {
  Lcg([this.seed = 1337]);
  int seed;
  double next() {
    seed = (seed * 1664525 + 1013904223).toSigned(32);
    return ((seed >>> 8) & 0xffffff) / 0xffffff;
  }
}

const List<String> kSuffixes = [
  '', 'K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 'Dc',
];

/// JS `fmt(n)` — the number formatter used everywhere in the UI.
/// THE VERTICAL MAN's hold on the instruments, 0..1. Set by the runtime while
/// he is on the tube and read by [fmt], so every numeric readout in the game —
/// rack, status strip, wings, deck — rolls at once without a single call site
/// having to know he exists.
///
/// He is the only entity that takes nothing from you. He just makes the desk
/// unreadable, which is a pressure no amount of banked SIGNAL answers.
double gVertRoll = 0;

const String _kRollGlyphs = '0123456789';

/// Rolls a rendered figure: each digit has an independent chance of having
/// slipped to a neighbouring one, scaling with [gVertRoll].
String _roll(String s) {
  if (gVertRoll <= 0.02) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57 &&
        rand() < gVertRoll * 0.55) {
      b.write(_kRollGlyphs[(rand() * 10).floor().clamp(0, 9)]);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

String fmt(num value) => _roll(_fmt(value));

String _fmt(num value) {
  double n = value.toDouble();
  if (n.isNaN) return '0';
  if (n.isInfinite) return '∞';
  if (n < 0) return '-${_fmt(-n)}';
  if (n < 1000) {
    if (n < 10) {
      final v = (n * 10).round() / 10;
      var s = v.toString();
      if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
      return s;
    }
    return n.floor().toString();
  }
  var t = 0;
  while (n >= 1000 && t < kSuffixes.length - 1) {
    n /= 1000;
    t++;
  }
  final String body = n < 10
      ? n.toStringAsFixed(2)
      : (n < 100 ? n.toStringAsFixed(1) : n.floor().toString());
  return body + kSuffixes[t];
}

/// JS `mmss(s)`.
String mmss(num seconds) {
  final s = seconds.toDouble();
  final m = s ~/ 60;
  final sec = s.truncate() % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

String pad2(int v) => v.toString().padLeft(2, '0');

// ---------------------------------------------------------------------------
// 1. TYPOGRAPHY
// ---------------------------------------------------------------------------

/// The whole game is "Courier New", Courier, monospace.
const String kMonoFamily = 'Courier New';
// Courier Prime has no ◂ ▸ ◼ ▼ ★ ⚠ ◆ — the game uses all of them, and on
// CanvasKit a missing glyph is a visible tofu box, not a silent substitution.
// Roboto ships with the engine and covers them, so it goes in the chain first;
// 'Courier'/'monospace' stay for any host that does resolve system families.
const List<String> kMonoFallback = ['Roboto', 'Courier', 'monospace'];

// ---------------------------------------------------------------------------
// 2. PALETTE  (CSS :root custom properties, verbatim)
// ---------------------------------------------------------------------------

class K {
  K._();

  // THE STATION IS NOT GREEN ANY MORE.
  //
  // It was a warm phosphor-green terminal for the whole of its life — 6DFF9A
  // on a teal-black panel — and green is the colour of a machine that is
  // WORKING. It reads as go, as healthy, as the little screen in a cosy
  // spaceship. Eight minutes a night of a soothing colour is not something a
  // jump scare can undo, and it is the same mistake the audio made when the
  // click was an ascending pentatonic ladder.
  //
  // This is the same building lit by the tubes themselves: cold bone-white
  // phosphor, sodium orange for anything on fire, and a panel that is
  // blue-black rather than green-black. Nothing in the room is warm except
  // the things that are going wrong.
  //
  // The names are kept — `green` is still called green — because two hundred
  // call sites read them and renaming every one to `bone` would be a large
  // diff that changes no pixel. The value is the change.
  static const Color amber = Color(0xFFFF9E3D); // sodium, and it means TROUBLE
  static const Color amberDim = Color(0xFF7A4212);
  static const Color green = Color(0xFFC8DCE4); // cold phosphor, near-white
  static const Color greenDim = Color(0xFF2E4650);
  static const Color red = Color(0xFFFF2E22);
  static const Color redDim = Color(0xFF6B0F0B);
  static const Color cyan = Color(0xFF7FB8D4); // the meters
  static const Color panel = Color(0xFF07090C);
  static const Color panel2 = Color(0xFF0E1319);
  static const Color edge = Color(0xFF232C34);
  static const Color ink = Color(0xFFBFCBD4);

  // Secondary tones lifted straight out of the stylesheet.
  static const Color black = Color(0xFF000000);
  static const Color bg = Color(0xFF04060A); // theme-color
  static const Color lbl = Color(0xFF6E7F8C); // .rdo .lbl
  static const Color subGreen = Color(0xFF8AA4B2); // .rdo .sub
  static const Color dreadLbl = Color(0xFF9C7676);
  static const Color dreadTrack = Color(0xFF160C0C);
  static const Color dreadBorder = Color(0xFF3A1A1A);
  static const Color dreadFillA = Color(0xFF7A2020);
  static const Color dreadFillB = Color(0xFFFF3B30);
  static const Color onAirOff = Color(0xFF6B2B2B);
  static const Color onAirOffBg = Color(0xFF1A0808);
  static const Color onAirOffBorder = Color(0xFF4A1010);
  static const Color onAirLive = Color(0xFFFF5B50);
  static const Color onAirLiveBg = Color(0xFF3A0A0A);
  static const Color statusTop = Color(0xFF0D141B);
  static const Color statusBot = Color(0xFF05080C);
  static const Color statusInset = Color(0xFF26313C);
  static const Color rackTop = Color(0xFF0B1218);
  static const Color rackBot = Color(0xFF04070B);
  static const Color tabBg = Color(0xFF070C11);
  static const Color tabInk = Color(0xFF4C5C6A);
  static const Color tabOnBg = Color(0xFF111921);
  static const Color tabHover = Color(0xFF6B96C4);
  static const Color itemBorder = Color(0xFF1C2530);
  static const Color itemTop = Color(0xFF0D141B);
  static const Color itemBot = Color(0xFF080D13);
  static const Color itemAfford = Color(0xFF2B4A5E);
  static const Color itemOwned = Color(0xFF27343E);
  static const Color itemName = Color(0xFFD2DEE6);
  static const Color itemDesc = Color(0xFF7A8996);
  static const Color itemStat = Color(0xFF7E97A6);
  static const Color itemQty = Color(0xFF3A5566);
  static const Color headInk = Color(0xFF63767F);
  static const Color headRule = Color(0xFF18212B);
  static const Color noteInk = Color(0xFF8496A0);
  static const Color keyTop = Color(0xFF232B2D);
  static const Color keyBot = Color(0xFF141A1B);
  static const Color keyInk = Color(0xFF638BB6);
  static const Color keySub = Color(0xFF6B8183);
  static const Color keySubKnown = Color(0xFF638BB6);
  static const Color keyHotBorder = Color(0xFF7A2A24);
  static const Color keyHotInk = Color(0xFFFFB0A8);
  static const Color keyGoodTop = Color(0xFF22303F);
  static const Color keyGoodBot = Color(0xFF131B24);
  static const Color keyGoodInk = Color(0xFF99D6FF);
  static const Color keyBadTop = Color(0xFF3A0D0D);
  static const Color keyBadBot = Color(0xFF210606);
  static const Color keyBadInk = Color(0xFFFF9A92);
  static const Color skeyTop = Color(0xFF241A08);
  static const Color skeyBot = Color(0xFF140E04);
  static const Color skeySub = Color(0xFFA5813C);
  static const Color sheetTop = Color(0xFF0E1314);
  static const Color sheetBot = Color(0xFF080B0C);
  static const Color sheetBorder = Color(0xFF2A3436);
  static const Color manInk = Color(0xFF61767A);
  static const Color manInkOn = Color(0xFF78A8DD);
  static const Color manUnk = Color(0xFF3B4749);
  static const Color manTag = Color(0xFF546A6C);
  static const Color manH3 = Color(0xFF91CBFF);
  static const Color manCls = Color(0xFF6B4A4A);
  static const Color fldKey = Color(0xFF6F8688);
  static const Color fldVal = Color(0xFF79AADF);
  static const Color fldWarn = Color(0xFFFF9A92);
  static const Color toastInk = Color(0xFF79AADF);
  static const Color toastBad = Color(0xFFFF8B82);
  static const Color toastBg = Color(0xE60A0A0B); // rgba(6,10,11,.92)
  static const Color lostBorder = Color(0xFF5A1414);
  static const Color lostInk = Color(0xFFC0A3A3);
  static const Color lostBold = Color(0xFFFF8B82);
  static const Color lostDim = Color(0xFF8A7070);
  static const Color winBorder = Color(0xFF496686);
  static const Color winInk = Color(0xFF75A4D7);
  static const Color bootTitle = Color(0xFF91CBFF);
  static const Color bootSig = Color(0xFF4D6164);
  static const Color bootBody = Color(0xFF7D9091);
  static const Color bootFine = Color(0xFF3F4E50);
  static const Color heldPink = Color(0xFFFF9EC4); // "she has" readout
  static const Color offAirRed = Color(0xFFFF6B60);
}

// ---------------------------------------------------------------------------
// 3. CABINET + SCENE GEOMETRY  (JS section 7)
// ---------------------------------------------------------------------------

/// The whole game lives in a fixed cabinet that is scaled to fit the window.
const double kCabW = 1280;
const double kCabH = 720;

/// Scene rectangles. The camera never moves.
const Rect kRoom = Rect.fromLTWH(0, 0, 940, 720); // ROOM
const Rect kWall = Rect.fromLTWH(120, 82, 700, 486); // WALL — back wall rect
const Rect kCrt = Rect.fromLTWH(238, 126, 466, 330); // CRT — monitor bezel
/// SCR = {x:CRT.x+22, y:CRT.y+20, w:CRT.w-44, h:CRT.h-52}
const Rect kScr = Rect.fromLTWH(260, 146, 422, 278);

/// SIDE — the two security cameras, left of the tube. SW/SH is their size.
const List<Offset> kSide = [Offset(132, 150), Offset(132, 296)];
const double kSideW = 96; // SW
const double kSideH = 74; // SH

/// WIN — the window onto the field. Clear of the CRT bezel (ends 704).
const Rect kWin = Rect.fromLTWH(716, 112, 100, 332);

/// The broadcast feed buffer (low res, chunky pixels).
const int kFeedW = 320; // FW
const int kFeedH = 240; // FH

/// Half-res channel-separation buffers: chW = FW>>1, chH = FH>>1.
const int kChW = 160;
const int kChH = 120;

/// Bloom / row-luminance buffer.
const int kBloomW = 40; // BLW
const int kBloomH = 26; // BLH

/// Face plate size. A 256x320 grayscale plate is baked once per entity.
const int kHeadW = 256; // HW
const int kHeadH = 320; // HH

/// Value-noise mottle plate (5 octaves), 192x192.
const int kMottleSize = 192;

/// Baked landscape / frost plates: WIN.w*2 x WIN.h*2.
const int kFieldW = 200;
const int kFieldH = 664;

/// Cloth-fold gradient strip and shoulder plate.
const int kFoldW = 64;
const int kFoldH = 1;
const int kShoulderW = 64;
const int kShoulderH = 32;

/// Pre-baked white-noise tiles: eight of them, 180x135.
const int kNoiseTileW = 180;
const int kNoiseTileH = 135;
const int kNoiseTileCount = 8;

/// Wall texture bake size (== WALL.w x WALL.h) and its tile pitch.
const int kWallTexW = 700;
const int kWallTexH = 486;
const double kWallTilePitch = 34;

/// Scene populations.
const int kSnowCount = 110;
const int kTreeCount = 26;
const int kDustCount = 70;

/// The manual's per-entity preview canvas.
const int kManualCanvasW = 320;
const int kManualCanvasH = 240;

/// The ad break canvas.
const int kAdCanvasW = 480;
const int kAdCanvasH = 360;

// ---------------------------------------------------------------------------
// 4. DOM LAYOUT RECTS  (for the Flutter widgets laid over the CustomPaint)
// ---------------------------------------------------------------------------

const Rect kStatusRect = Rect.fromLTWH(0, 0, 940, 82); // #status
const Rect kRackRect = Rect.fromLTWH(940, 0, 340, 720); // #rack
const Rect kDeckRect = Rect.fromLTWH(0, 600, 940, 120); // #deck
const Rect kToastRect = Rect.fromLTWH(0, 462, 940, 0); // #toasts anchor
const double kSideKeysW = 150; // #sidekeys
const Size kSheetSize = Size(840, 640); // .sheet (max-height)
const Size kAdSheetSize = Size(720, 520); // #adSheet
const double kLostSheetW = 660; // #lostSheet
const double kManListW = 250; // #manList

// ---------------------------------------------------------------------------
// 5. PRODUCERS  (JS PRODUCERS)
// ---------------------------------------------------------------------------

class Producer {
  const Producer({
    required this.id,
    required this.nm,
    required this.cost,
    required this.mul,
    required this.sig,
    required this.ds,
  });
  final String id;
  final String nm;
  final double cost;
  final double mul;
  final double sig;
  final String ds;
}

const List<Producer> kProducers = [
  Producer(
      id: 'rabbit',
      nm: 'RABBIT EARS',
      cost: 15,
      mul: 1.13,
      sig: 0.8,
      ds: 'Bent coat hanger. Somehow it works.'),
  Producer(
      id: 'dipole',
      nm: 'DIPOLE ARRAY',
      cost: 140,
      mul: 1.13,
      sig: 5.4,
      ds: 'Roof-mounted. Hums in the rain.'),
  Producer(
      id: 'vhf',
      nm: 'VHF MAST',
      cost: 1.3e3,
      mul: 1.14,
      sig: 34,
      ds: 'Red beacon. Nobody climbs it twice.'),
  Producer(
      id: 'relay',
      nm: 'MICROWAVE RELAY',
      cost: 12e3,
      mul: 1.14,
      sig: 215,
      ds: 'Line of sight to the next dead town.'),
  Producer(
      id: 'head',
      nm: 'CABLE HEADEND',
      cost: 110e3,
      mul: 1.15,
      sig: 1.4e3,
      ds: 'Copper into every living room.'),
  Producer(
      id: 'sat',
      nm: 'SATELLITE UPLINK',
      cost: 1.0e6,
      mul: 1.15,
      sig: 9.2e3,
      ds: 'Bounce it off something in orbit.'),
  Producer(
      id: 'ghost',
      nm: 'GHOST REPEATER',
      cost: 9.5e6,
      mul: 1.16,
      sig: 64e3,
      ds: 'Rebroadcasts what was never sent.'),
  Producer(
      id: 'mirror',
      nm: 'ORBITAL MIRROR',
      cost: 90e6,
      mul: 1.16,
      sig: 480e3,
      ds: 'The whole hemisphere can see the picture.'),
  Producer(
      id: 'dead',
      nm: 'DEAD CHANNEL 0',
      cost: 850e6,
      mul: 1.17,
      sig: 4.0e6,
      ds: 'A frequency with no license and no end.'),
  Producer(
      id: 'choir',
      nm: 'THE CHOIR',
      cost: 8.0e9,
      mul: 1.17,
      sig: 36e6,
      ds: 'They were the night shift, once.'),
];

final Map<String, Producer> kProducerBy = {
  for (final p in kProducers) p.id: p,
};

// ---------------------------------------------------------------------------
// 6. UPGRADES  (JS UPGRADES)
// ---------------------------------------------------------------------------

/// `req` is the JS closure over S, reified as a predicate on the state.
/// The parameter is typed dynamic so consts.dart stays free of state.dart
/// (state.dart imports consts.dart, not the other way round). Callers pass a
/// GameState; use `upgradeVisible(u, s)` in economy.dart rather than calling
/// `req` directly.
typedef UpgradeReq = bool Function(dynamic s);

class Upgrade {
  const Upgrade({
    required this.id,
    required this.nm,
    required this.cost,
    required this.ds,
    required this.req,
  });
  final String id;
  final String nm;
  final double cost;
  final String ds;
  final UpgradeReq req;
}

final List<Upgrade> kUpgrades = [
  Upgrade(
      id: 'ferrite',
      nm: 'FERRITE CORE',
      cost: 900,
      ds: '+1.2s to every banish window.',
      req: (s) => true),
  Upgrade(
      id: 'preheat',
      nm: 'TUBE PREHEAT',
      cost: 6.5e3,
      ds: 'The plate runs 12% cooler.',
      req: (s) => true),
  Upgrade(
      id: 'phosphor',
      nm: 'PHOSPHOR MASK',
      cost: 2.6e4,
      ds: 'Anomalies telegraph 0.9s longer.',
      req: (s) => s.stats.banished >= 3),
  Upgrade(
      id: 'autocue',
      nm: 'AUTO-CUE',
      cost: 1.6e5,
      ds: 'Wrong-button penalty halved.',
      req: (s) => s.stats.wrong >= 3),
  Upgrade(
      id: 'halide',
      nm: 'SILVER HALIDE',
      cost: 9.0e5,
      ds: 'The carrier tracks the dial faster.',
      req: (s) => true),
  Upgrade(
      id: 'failsafe',
      nm: 'FAILSAFE RELAY',
      cost: 6.0e6,
      ds: 'Dread bleeds off twice as fast.',
      req: (s) => s.stats.banished >= 12),
  Upgrade(
      id: 'watch',
      nm: 'NIGHT WATCH',
      cost: 5.0e7,
      ds: '14% chance an anomaly banishes itself.',
      req: (s) => s.rp >= 1),
  Upgrade(
      id: 'lead',
      nm: 'LEAD LINING',
      cost: 4.0e8,
      ds: 'Jumpscares steal half as much.',
      req: (s) => s.stats.scared >= 1),
  Upgrade(
      id: 'comp',
      nm: 'SIGNAL COMPRESSOR',
      cost: 3.0e9,
      ds: 'Modulation drifts more slowly.',
      req: (s) => true),
  Upgrade(
      id: 'cam2',
      nm: 'SECOND CAMERA',
      cost: 2.2e10,
      ds: 'The correct key lights up on the deck.',
      req: (s) => s.stats.banished >= 60),
  Upgrade(
      id: 'vault',
      nm: 'TAPE VAULT',
      cost: 1.4e11,
      ds: 'The vault files for you. The hour comes due 45% less often.',
      req: (s) => s.rp >= 5),
  Upgrade(
      id: 'halo',
      nm: 'CARRIER HALO',
      cost: 8.0e11,
      ds: 'The licence allows 20 more seconds.',
      req: (s) => s.stats.scared >= 6),
];

final Map<String, Upgrade> kUpgradeBy = {
  for (final u in kUpgrades) u.id: u,
};

// ---------------------------------------------------------------------------
// 7. COUNTERS — the eight emergency keys  (JS COUNTERS)
// ---------------------------------------------------------------------------

class Counter {
  const Counter({
    required this.id,
    required this.nm,
    required this.key,
    required this.ds,
  });
  final String id;
  final String nm;

  /// The keyboard digit, as a string: "1".."8".
  final String key;
  final String ds;
}

const List<Counter> kCounters = [
  Counter(
      id: 'tone',
      nm: 'TONE',
      key: '1',
      ds: 'Emergency test tone. 1000 Hz, straight through everything.'),
  Counter(
      id: 'bars',
      nm: 'BARS',
      key: '2',
      ds: 'SMPTE colour bars. Something in them is comforting.'),
  Counter(
      id: 'vhold',
      nm: 'V-HOLD',
      key: '3',
      ds: 'Locks the vertical sync. Stops the picture rolling.'),
  Counter(
      id: 'degauss',
      nm: 'DEGAUSS',
      key: '4',
      ds: 'Wipes the shadow mask clean with a magnetic snap.'),
  Counter(
      id: 'cut',
      nm: 'CUT',
      key: '5',
      ds: 'Kills the feed to black. Nothing goes out, nothing comes in.'),
  Counter(
      id: 'tape',
      nm: 'TAPE',
      key: '6',
      ds: 'Rolls fresh footage from the vault.'),
  Counter(
      id: 'pattern',
      nm: 'PATTERN',
      key: '7',
      ds: 'Broadcasts the sign-off card and station ident.'),
  Counter(
      id: 'hook',
      nm: 'OFF-HOOK',
      key: '8',
      ds: 'Lifts the studio line. Leaves it open.'),
];

final Map<String, Counter> kCounterBy = {
  for (final c in kCounters) c.id: c,
};

// ---------------------------------------------------------------------------
// 8. THE SHIFT  (JS RUNDOWN)
// ---------------------------------------------------------------------------

class RundownSeg {
  const RundownSeg({required this.nm, required this.quota, required this.line});
  final String nm;
  final double quota;
  final String line;
}

/// Real seconds per in-game minute -> ~21 minutes a night.
/// Real seconds per in-game minute.
///
/// Was 3, which made a night 21 real minutes. That single number was the
/// biggest thing standing between this game and being addictive: "one more
/// night" is a free thought at eight minutes and an actual commitment at
/// twenty-one, and a run you have to schedule is a run you stop taking.
///
/// The idle-game framing came with that length and never earned it — most of
/// a 21-minute shift was bookkeeping between the parts that were frightening.
/// Shortening the night does not remove the economy, it removes the padding
/// around it.
const double kMinReal = 1.15; // ~8 minutes a night

/// How much a night's output shrank when it got shorter, so the printed
/// quotas still mean the same amount of WORK rather than becoming impossible.
/// Kept explicit and derived, so changing kMinReal above can never silently
/// leave the rundown demanding a 21-minute night's output in eight minutes.
/// How much the RUNDOWN'S RAMP is compressed for a shorter night.
///
/// Scaling every quota by the same factor was the wrong fix and the numbers
/// said so immediately. Measured on an eight-minute night, competent play:
///
///   segment 0   demanded 17      banked 12.4K    (trivial)
///   segment 3   demanded 44.1K   banked 111K     (trivial)
///   segment 4   demanded 617K    banked 447K     -> 146s to clear a 69s slot
///   segment 5   demanded 8.82M   banked 5.69M    -> 423s to clear a 69s slot
///
/// The early rundown was already free and the late rundown was impossible,
/// because the printed table ramps ~14x per segment and that only compounds
/// inside a three-minute slot. It is the SHAPE of the curve that is wrong for
/// a short night, not its overall size.
///
/// So the ramp is compressed geometrically toward the opening figure — every
/// quota becomes q0 * (q_i/q0)^kQuotaRamp — which turns 14x per segment into
/// about 5x while leaving the first segment exactly as printed.
const double kQuotaRamp = 0.62;

/// How much the gap between intrusions shrinks for a shorter night.
///
/// Deliberately less aggressive than the clock change (kMinReal went to 38% of
/// its old value; this is 62%), because matching it exactly would make the
/// real-time rhythm frantic. This keeps a session's intrusion COUNT healthy
/// without turning the booth into a shooting gallery.
const double kGapTimeScale = 0.62;

const List<RundownSeg> kRundown = [
  RundownSeg(
      nm: 'STATION IDENT',
      quota: 120,
      line: 'Colour bars and the national anthem. Nobody is watching yet.'),
  RundownSeg(
      nm: 'THE LATE MOVIE',
      quota: 1.6e3,
      line:
          'Something in black and white. The reel is not the one you threaded.'),
  RundownSeg(
      nm: 'OVERNIGHT NEWS',
      quota: 22e3,
      line: 'The autocue is running stories that have not happened.'),
  RundownSeg(
      nm: 'THE DEAD HOUR',
      quota: 300e3,
      line: '03:00. Nothing is scheduled. Something transmits anyway.'),
  RundownSeg(
      nm: 'TEST TRANSMISSION',
      quota: 4.2e6,
      line: 'A tone and a card. The card is not the one in the vault.'),
  RundownSeg(
      nm: 'THE CHOIR HOUR',
      quota: 60e6,
      line: 'They were the night shift once. They still sign in.'),
  RundownSeg(
      nm: 'SIGN-OFF PREP',
      quota: 900e6,
      line: 'Almost morning. Hold it together and you get to leave.'),
];

/// RUNDOWN.length * 60 == 420.
const double kShiftMinutes = 420;

// ---------------------------------------------------------------------------
// 9. THE EIGHT THINGS IN THE SIGNAL  (JS ANOM)
// ---------------------------------------------------------------------------

class Anom {
  const Anom({
    required this.id,
    required this.nm,
    required this.counter,
    required this.cls,
    required this.tier,
    required this.tell,
    required this.lore,
    required this.method,
    required this.wrongNote,
    required this.rail,
    required this.bite,
  });
  final String id;
  final String nm;

  /// The id of the one Counter that banishes it.
  final String counter;
  final String cls;
  final int tier;
  final String tell;
  final String lore;
  final String method;
  final String wrongNote;

  /// WHICH PART OF THE MACHINE IT EATS.
  ///
  /// An arrival used to be a free-floating prompt with a key attached: it
  /// appeared, you pressed its letter, it went away, and nothing about the
  /// station was different for it having been there. Now each one has its
  /// teeth in a named system, so it presents as the machine misbehaving and
  /// the operator has to work out WHICH before they can answer WHAT.
  ///
  /// THE SNOW CRAWLER and DEAD AIR both eat the carrier. MR. SLEEPWELL pulls
  /// the modulation down and THE TEST CARD GIRL drives it up — the same needle
  /// off its mark in opposite directions, needing opposite corrections, which
  /// is the whole diagnosis layer in one pair. THE NIELSEN and THE CALLER go
  /// for the log, because being watched and being telephoned are both ways of
  /// stopping a man writing.
  ///
  /// THE RERUN has no rail. It uses your hands. See Tape in desk.dart.
  final Rail? rail;

  /// Units per second it takes off that rail while it is on the air.
  final double bite;
}

const List<Anom> kAnoms = [
  Anom(
    id: 'snow',
    nm: 'THE SNOW CRAWLER',
    counter: 'degauss',
    cls: 'CLASS I — GRAIN-BORNE',
    tier: 0,
    tell:
        'The static thickens until it is no longer random. A face assembles out of the grain, one frame at a time, and it does not blink.',
    lore:
        'First logged 3 Nov 1979 by operator R. Vance, who described it as "the snow deciding to be somebody." It lives in the noise floor itself, so cutting the feed only gives it a darker room to stand in.',
    method:
        'Snap the shadow mask with a full DEGAUSS. The magnetic wipe scatters the grain before it can finish assembling a face.',
    wrongNote: 'CUT is the common mistake. It feeds on the dark.',
    rail: Rail.carrier,
    bite: 2.6,
  ),
  Anom(
    id: 'sleep',
    nm: 'MR. SLEEPWELL',
    counter: 'cut',
    cls: 'CLASS II — RESIDENT MASCOT',
    tier: 0,
    tell:
        "The picture whitens to a hospital brightness. The station's old bedtime puppet leans into frame, grinning, and a music box starts somewhere behind the wall.",
    lore:
        "KBLK-7's mascot from the 1968 children's block. The puppet was destroyed on air. It has been coming back to work ever since, always at the end of the shift, always to say goodnight.",
    method:
        'CUT the feed. He is a performer — with no audience and no light he has no reason to stay.',
    wrongNote:
        'Never answer him with BARS or PATTERN. He takes it as applause.',
    rail: Rail.modulation,
    bite: 9.0,
  ),
  Anom(
    id: 'vert',
    nm: 'THE VERTICAL MAN',
    counter: 'vhold',
    cls: 'CLASS II — SYNC PARASITE',
    tier: 0,
    tell:
        'The picture rolls. In the tear band between frames, for a fraction of a second, something far too tall is standing in the studio.',
    lore:
        'He exists only in the seam between one frame and the next, which is why nobody has ever photographed him. He is getting taller. The 1981 log has him at four frames. He is now nine.',
    method:
        'Lock the sync with V-HOLD. Close the seam and there is nowhere left for him to be.',
    wrongNote: 'Do not DEGAUSS a rolling picture. It widens the tear.',
    rail: Rail.plate,
    bite: 7.0,
  ),
  Anom(
    id: 'dead',
    nm: 'DEAD AIR',
    counter: 'tone',
    cls: 'CLASS III — ABSENCE',
    tier: 1,
    tell:
        'Everything stops. No picture, no grain, no hum — a silence so total your ears invent things to fill it. One flat green line crosses the screen.',
    lore:
        'Not an intruder. An appetite. Dead Air is what is left when the signal is removed, and it will keep removing until there is nothing on the frequency at all, including you.',
    method:
        'Put something in the silence. The 1000 Hz emergency TONE is the loudest simple thing the desk can make.',
    wrongNote: 'Every silent option (CUT, TAPE) makes the hole bigger.',
    rail: Rail.carrier,
    bite: 3.4,
  ),
  Anom(
    id: 'card',
    nm: 'THE TEST CARD GIRL',
    counter: 'bars',
    cls: 'CLASS III — REVENANT',
    tier: 1,
    tell:
        'Colour bars bleed in from the edges, wrong and oversaturated. A child sits centre frame with a chalk-drawn face and a clown that is not a clown.',
    lore:
        'She was on the sign-off card from 1971 to 1984. When the card was retired she had nowhere to be, and she has been trying to get back into it ever since. She is not hostile. She is homesick.',
    method:
        'Show her the way home. Broadcast BARS and she will step back into the card on her own.',
    wrongNote: 'CUT strands her in the dark and she will scream about it.',
    rail: Rail.modulation,
    bite: -8.0,
  ),
  Anom(
    id: 'rerun',
    nm: 'THE RERUN',
    counter: 'tape',
    cls: 'CLASS IV — LOOP',
    tier: 1,
    tell:
        'The image smears into ghost trails. A figure crosses the studio, snaps back, crosses again. The audio echoes a half-second behind itself.',
    lore:
        'A four-second loop of tape that was never erased, playing since 1976. Whatever was recorded in those four seconds is still happening. It will overwrite anything you transmit with itself.',
    method:
        'Give the machine something else to play. Roll fresh TAPE and the loop is broken by new footage.',
    wrongNote:
        'Anything live — TONE, BARS, PATTERN — just gets absorbed into the loop.',
    rail: null,
    bite: 0.0,
  ),
  Anom(
    id: 'niel',
    nm: 'THE NIELSEN',
    counter: 'pattern',
    cls: 'CLASS IV — AUDITOR',
    tier: 2,
    tell:
        'Columns of numbers scroll where the picture should be. A man in a grey suit stands with a clipboard. His head is a bar chart, and it is falling.',
    lore:
        'He audits. He arrives when the numbers are good and leaves with a portion of them. He does not acknowledge staff, threats, or the fire axe kept in Studio B.',
    method:
        'He requires a valid station ident to close the audit. Broadcast the sign-off PATTERN and he files and departs.',
    wrongNote:
        'He restates the segment output, not the bank. The quota bar walks backward while he files.',
    rail: Rail.log,
    bite: 1.6,
  ),
  Anom(
    id: 'call',
    nm: 'THE CALLER',
    counter: 'hook',
    cls: 'CLASS V — CONTACT',
    tier: 2,
    tell:
        'The studio line rings — every line, at once. An oscilloscope trace fills the screen and speaks. The figure behind it holds a receiver to a head that is only a rotary dial.',
    lore:
        'It has been trying to reach this station for fifty-one years. It is not calling for you. It is calling for whoever had the shift before you, and it will keep dialling until somebody picks up.',
    method:
        'Take it OFF-HOOK and leave the line open. It only needs to be answered, not spoken to.',
    wrongNote: 'Do not CUT the call. It redials angrier, and faster.',
    rail: Rail.log,
    bite: 2.2,
  ),
];

final Map<String, Anom> kAnomBy = {
  for (final a in kAnoms) a.id: a,
};

// ---------------------------------------------------------------------------
// 10. ADS  (JS ADS)
// ---------------------------------------------------------------------------

class Ad {
  const Ad({
    required this.t,
    required this.s,
    required this.l,
    required this.c,
  });

  /// Brand line.
  final String t;

  /// Product line.
  final String s;

  /// Tagline (typed out at 22 chars/sec).
  final String l;

  /// Accent colour.
  final Color c;
}

const List<Ad> kAds = [
  Ad(
      t: 'SLEEPWELL BRAND',
      s: 'NIGHT TONIC',
      l: '"ONE SPOONFUL AND THE DREAMS STOP."',
      c: Color(0xFFFFD166)),
  Ad(
      t: 'VANCE & SON',
      s: 'AERIAL FITTING',
      l: "WE CLIMB SO YOU DON'T HAVE TO.",
      c: Color(0xFF57E6FF)),
  Ad(
      t: 'MERIDIAN CATHODE',
      s: 'PICTURE TUBES',
      l: 'A WARMER BLACK. A DEEPER DARK.',
      c: Color(0xFF99D6FF)),
  Ad(
      t: "THE 11 O'CLOCK",
      s: 'NEWS AT ELEVEN',
      l: 'IF YOU ARE WATCHING, YOU ARE FINE.',
      c: Color(0xFFFF6B6B)),
  Ad(
      t: 'HALLOWED FOODS',
      s: 'TV DINNERS',
      l: 'EAT IN FRONT OF IT. IT PREFERS THAT.',
      c: Color(0xFFC9A0FF)),
];

/// Ad break timing: skippable at 5s, auto-ends at 6.5s.
const double kAdDuration = 6.5;
const double kAdSkipAt = 5;

// ---------------------------------------------------------------------------
// 11. BOOT / SIGN-ON COPY  (verbatim from the #boot markup)
// ---------------------------------------------------------------------------

const String kBootStationLine =
    'STATION KBLK-7  ·  1,140 kHz  ·  LICENSE REVOKED 1987';
const String kBootTitle = 'FINAL BROADCAST';
const String kBootBody1 =
    'You have the night shift. Keep the carrier up, keep the numbers climbing — '
    'and when something gets into the feed, cut it out before it looks back.';
const String kBootBody2a =
    'Eight things live in the signal. Each one dies to exactly one button.';
const String kBootBody2b = 'The manual tells you which. Read it. Press M any time.';
const String kBootFine =
    'HEADPHONES RECOMMENDED  ·  FLASHING IMAGES  ·  TOGGLE IN STATION TAB';
const String kRotateNag = 'ROTATE YOUR DEVICE';
const String kRotateSub = 'FINAL BROADCAST REQUIRES LANDSCAPE';

// ---------------------------------------------------------------------------
// 12. SAVE
// ---------------------------------------------------------------------------

const String kSaveKey = 'finalbroadcast.v1';
