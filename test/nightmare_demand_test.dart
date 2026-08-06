// WHAT NIGHTMARE ACTUALLY ASKS OF THE PLAYER WHO CAN ACTUALLY START IT.
//
// Every prior measurement of this mode ran GameState()..night = 1 with `seen`
// empty — a configuration NO PLAYER CAN REACH. home_screen.dart gates the
// NIGHTMARE tile behind `if (s.survived > 0)`, survived++ happens in dawn(),
// and night++ in resetForNewNight() — so every NIGHTMARE a player ever starts
// runs at night >= 2 with the roster already seen. Measured at the reachable
// configuration the mode was a NINE-minute licence game, not the twelve-minute
// dread game the unreachable config reported, and it inherited its difficulty
// from whatever night card the CAREER happened to be holding: a 1.9x survival
// swing on a variable the player never chose.
//
// TWENTY seeds, because five is inside this game's noise floor (measured
// spread 6.95-10.28 minutes on the shipped build), and because addGlass's
// bounded rejection sampling consumes a state-dependent number of rand()
// draws, so seeded before/after comparisons are not paired and only the
// distribution is trustworthy.
//
// THE SKILL SWEEP IS THE POINT. Shipped: answer latency 0.2s bought 10.2
// minutes and never answering bought 5.9 — a 1.7x span with the whole
// competent range inside one minute of noise. A mode where skill cannot buy
// time is not hard, it is a timer. The sweep is asserted, not printed:
// best-over-never must stay above 2.2x, because that ratio is the number that
// says the death is the player's fault.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/wallclock.dart';

import 'operator.dart';

/// One full run of the REACHABLE NIGHTMARE.
class Run {
  Run(this.life, this.how, this.dpm, this.onTube, this.occupancy, this.arrivals,
      this.firstManifest, this.invoice);

  final double life;
  final String how;
  final double dpm;

  /// Fraction of the run with a LIVE anomaly on the tube.
  final double onTube;

  /// Fraction with a live anomaly OR a corpse. The columns differ because the
  /// death rattle exists — a harness reading only `r.active` is structurally
  /// blind to the corpse channel and measures the rattle as exactly zero.
  final double occupancy;

  final double arrivals;
  final double firstManifest;
  final Map<String, double> invoice;
}

Run playNightmare(int seed, {double latency = 1.2, bool wipe = true}) {
  seedRandom(seed);
  final DateTime t0 = DateTime(2026, 8, 5, 2, 30);
  var wall = t0;
  gNow = () => wall;
  resetSession();

  // THE CONFIGURATION home_screen.dart ACTUALLY PRODUCES: one night survived,
  // roster seen. Not night 1, not a blank catalogue.
  final s = GameState()
    ..night = 2
    ..survived = 1
    ..endless = true
    ..nightmare = true;
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }

  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();

  const double dt = 1 / 30.0;
  var t = 0.0, onTube = 0.0, occ = 0.0, dec = 0;
  var first = -1.0;
  var arrivals = 0;
  var wasActive = false;
  while (t < 45 * 60 && !r.lost) {
    if (mindTheDesk(r)) dec++;
    r.tick(dt);
    final a = r.active;
    if (a != null && !wasActive) {
      arrivals++;
      if (first < 0) first = t;
    }
    wasActive = a != null;
    if (a != null) onTube += dt;
    if (a != null || r.dying != null) occ += dt;
    if (a != null && latency > 0 && a.t > latency) {
      r.pressCounter(a.def.counter);
      dec++;
    }
    if (wipe) {
      for (var k = 0; k < 4; k++) {
        final double tk = t + dt * k / 4;
        if ((tk * 1.6) % 1.0 < 0.5) {
          final double u = ((tk * 3.2) % 1.0) * 2 - 1;
          r.wipeGlass(kScr.center.dx + u * 110, kRead.center.dy);
        }
      }
    }
    t += dt;
    wall = t0.add(Duration(milliseconds: (t * 1000).round()));
  }
  gNow = DateTime.now;
  final String how = s.dread >= 99.5
      ? 'DREAD'
      : (r.rig.voided ? 'LICENCE' : 'ALIVE AT 45');
  return Run(t / 60, how, dec / (t / 60), onTube / t, occ / t,
      arrivals / (t / 60), first, Map<String, double>.from(r.rig.offAirBy));
}

const List<int> kSeeds = <int>[
  20260805, 7, 99991, 4242, 1, 31, 88, 555, 1234, 9090, //
  17, 23, 404, 777, 2024, 3131, 5555, 8080, 11111, 424242,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('READOUT — the reachable NIGHTMARE, twenty seeds', () {
    final List<Run> runs = kSeeds.map(playNightmare).toList();
    final List<double> lives = runs.map((Run r) => r.life).toList()..sort();
    final Map<String, int> deaths = <String, int>{};
    for (final Run r in runs) {
      deaths[r.how] = (deaths[r.how] ?? 0) + 1;
    }
    double mean(Iterable<double> xs) =>
        xs.reduce((double a, double b) => a + b) / xs.length;
    // ignore: avoid_print
    print('survival  min ${lives.first.toStringAsFixed(1)}  '
        'median ${lives[lives.length ~/ 2].toStringAsFixed(1)}  '
        'max ${lives.last.toStringAsFixed(1)}');
    // ignore: avoid_print
    print('deaths    $deaths');
    // ignore: avoid_print
    print('decisions ${mean(runs.map((Run r) => r.dpm)).toStringAsFixed(1)}/min  '
        'onTube ${(mean(runs.map((Run r) => r.onTube)) * 100).toStringAsFixed(1)}%  '
        'occupancy ${(mean(runs.map((Run r) => r.occupancy)) * 100).toStringAsFixed(1)}%  '
        'arrivals ${mean(runs.map((Run r) => r.arrivals)).toStringAsFixed(2)}/min  '
        'first ${mean(runs.map((Run r) => r.firstManifest)).toStringAsFixed(1)}s');
    final Map<String, double> inv = <String, double>{};
    for (final Run r in runs) {
      r.invoice.forEach((String k, double v) => inv[k] = (inv[k] ?? 0) + v);
    }
    inv.updateAll((_, double v) => v / runs.length);
    // ignore: avoid_print
    print('invoice   $inv');
  });

  test('skill buys time — the death is the player\'s fault', () {
    // Eight seeds per latency keeps this file under a minute; the ratio is
    // stable well inside that.
    final List<int> seeds = kSeeds.take(8).toList();
    double med(double latency) {
      final List<double> xs = seeds
          .map((int s) => playNightmare(s, latency: latency).life)
          .toList()
        ..sort();
      return xs[xs.length ~/ 2];
    }

    final double best = med(0.2);
    final double sloppy = med(4.0);
    final double never = med(-1);
    // ignore: avoid_print
    print('skill sweep  0.2s ${best.toStringAsFixed(1)}  '
        '4.0s ${sloppy.toStringAsFixed(1)}  never ${never.toStringAsFixed(1)}  '
        'ratio ${(best / never).toStringAsFixed(2)}x');
    expect(best / never, greaterThan(2.2),
        reason: 'skill buys ${(best / never).toStringAsFixed(2)}x — shipped '
            'was 1.7x and the whole competent range sat inside noise. A mode '
            'skill cannot buy time in is a timer, not a game.');
    expect(best, greaterThan(sloppy + 2.0),
        reason: 'answering at 0.2s and at 4.0s must be different games');
  });

  test('the entities are ON SCREEN, not a rumour', () {
    final List<Run> runs = kSeeds.take(8).map(playNightmare).toList();
    final double occ = runs.map((Run r) => r.occupancy).reduce((a, b) => a + b) /
        runs.length;
    // Shipped reachable: 9.9%. The death rattle is what moves it, and a
    // harness that reads only r.active measures the rattle as zero.
    expect(occ, greaterThan(0.16),
        reason: 'something is on the tube ${(occ * 100).toStringAsFixed(1)}% '
            'of the run — the horror is a rumour again');
    // Two-sided: past ~40% the tube is never quiet and quiet is where dread
    // lives. This jaw catches the next "more is better" retune.
    expect(occ, lessThan(0.40));
  });

  test('the run is long enough for the escalation to land', () {
    final List<double> lives =
        kSeeds.take(8).map((int s) => playNightmare(s).life).toList()..sort();
    final double median = lives[lives.length ~/ 2];
    // Shipped reachable: median 9.01, and the glass curve's teeth start
    // around minute 9. Two-sided: shorter than 11 and the escalation is
    // content nobody sees; longer than 18 and the mode has gone soft.
    expect(median, greaterThan(11.0),
        reason: 'median survival ${median.toStringAsFixed(1)} min — the '
            'escalation lands after the player is dead');
    expect(median, lessThan(18.0),
        reason: 'median survival ${median.toStringAsFixed(1)} min — NIGHTMARE '
            'has gone soft');
  });

  test('wiping is a real choice: it costs licence, and not wiping costs sight',
      () {
    final List<int> seeds = kSeeds.take(8).toList();
    final List<Run> wipers = seeds.map((int s) => playNightmare(s)).toList();
    final List<Run> blind =
        seeds.map((int s) => playNightmare(s, wipe: false)).toList();
    final double cleaning = wipers
            .map((Run r) => r.invoice['CLEANING THE GLASS'] ?? 0)
            .reduce((a, b) => a + b) /
        wipers.length;
    expect(cleaning, greaterThan(8.0),
        reason: 'cleaning cost ${cleaning.toStringAsFixed(1)}s of licence — '
            'the wipe is free and the choice does not exist');
    expect(cleaning, lessThan(63.0),
        reason: 'cleaning cost ${cleaning.toStringAsFixed(1)}s of a 126s '
            'ceiling — a player can be killed by cleaning, and that death is '
            'not theirs');
    // The blind operator must live LONGER — the licence they did not spend on
    // cleaning — which is exactly the trade the mode is about. MEANS, not
    // medians: at eight seeds a median is one run, and this file's own header
    // records why single runs are not trustworthy here.
    double mean(List<Run> rs) =>
        rs.map((Run r) => r.life).reduce((double a, double b) => a + b) /
        rs.length;

    expect(mean(blind), greaterThan(mean(wipers) + 0.5),
        reason: 'seeing and surviving are supposed to be different purchases — '
            'blind ${mean(blind).toStringAsFixed(1)} vs wiping '
            '${mean(wipers).toStringAsFixed(1)} min');
    for (final Run r in blind) {
      expect(r.invoice['CLEANING THE GLASS'], isNull,
          reason: 'the blind operator was charged for cleaning they never did');
    }
  });
}
