// THE HORROR LAYER, MEASURED.
//
// "the sounds arnet scary". The old bed was loud but never frightening: it
// lived between 90Hz and 4kHz, the room never went truly quiet, and the
// jumpscare was 120ms of duck followed by harsh noise. Loudness is not fear.
//
// Every cue below was originally scheduled inside the WebAudio backend, where
// the only way to check it was to measure a live browser — which is how it sat
// broken. Pacing now lives in the sim, so a fake engine can just count.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

/// Counts what the game asks the speakers to do.
class RecordingAudio implements GameAudio {
  final List<int> holds = <int>[];
  final List<double> breaths = <double>[];
  final List<double> subs = <double>[];
  final List<int> preEchoes = <int>[];
  final List<double> pans = <double>[];
  int scares = 0;
  final List<double> distantScreams = <double>[];
  int streakBreaks = 0;
  int clutches = 0;

  @override
  void hold(int ms) => holds.add(ms);
  @override
  void breath(double side, double near) => breaths.add(near);
  @override
  void setSub(double v) => subs.add(v);
  @override
  void preEcho(int ms) => preEchoes.add(ms);
  @override
  void voice(double near, double side) {}
  @override
  void pan(double p) => pans.add(p);
  @override
  void scare() => scares++;
  @override
  void distantScream(double near, double side) => distantScreams.add(near);
  @override
  void streakBroken(int lost) => streakBreaks++;
  @override
  void clutchSting() => clutches++;

  @override
  void noSuchMethod(Invocation i) {}
}

GameState _station() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  s.prod['dipole'] = 45;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

({RecordingAudio audio, GameState s, AnomalyRuntime r}) _night({
  required bool play,
  double seconds = 21 * 60,
  int seed = 90210,
}) {
  seedRandom(seed);
  final s = _station();
  final a = RecordingAudio();
  final r = AnomalyRuntime(s, audio: a);
  r.startBroadcast();
  var t = 0.0;
  const dt = 1 / 60.0;
  while (t < seconds && !r.lost) {
    r.lurkPressure = 0.3;
    r.tick(dt);
    t += dt;
    final act = r.active;
    if (play && act != null && act.stage == 1 && act.p > 0.3) {
      r.pressCounter(act.def.counter);
    }
  }
  return (audio: a, s: s, r: r);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the room stops on its own, repeatedly, across a night', () {
    // A room that hums at a constant level from 23:00 to 06:00 is a room you
    // stop hearing. This fires every 40-90s with no cause and nothing to
    // react to — the cheapest dread in the game, and it was never once used.
    final n = _night(play: true);
    expect(n.audio.holds.length, greaterThan(8),
        reason: 'the room never went quiet on its own');
    for (final ms in n.audio.holds) {
      expect(ms, greaterThanOrEqualTo(240));
      expect(ms, lessThanOrEqualTo(700));
    }
  });

  test('a hole is never opened over the top of an encounter', () {
    // The silence belongs to the empty room. Taking the world away WHILE
    // something is on the tube would read as a bug, not as dread.
    seedRandom(5150);
    final s = _station();
    final a = RecordingAudio();
    final r = AnomalyRuntime(s, audio: a);
    r.startBroadcast();
    var t = 0.0;
    var holdsDuringEncounter = 0;
    const dt = 1 / 60.0;
    while (t < 21 * 60 && !r.lost) {
      final before = a.holds.length;
      r.tick(dt);
      t += dt;
      if (a.holds.length > before && r.active != null) holdsDuringEncounter++;
    }
    expect(holdsDuringEncounter, 0);
  });

  test('the arrival is heard before it is seen', () {
    // preEcho ends ON the manifest, so the ear registers it a beat before the
    // eye does. That is what "I knew something was coming" is made of.
    final n = _night(play: true);
    expect(n.audio.preEchoes.length, greaterThan(6));
    for (final ms in n.audio.preEchoes) {
      expect(ms, greaterThanOrEqualTo(400));
      expect(ms, lessThanOrEqualTo(4000));
    }
  });

  test('the infrasonic floor tracks the night rather than sitting flat', () {
    final n = _night(play: true);
    expect(n.audio.subs, isNotEmpty);
    final lo = n.audio.subs.reduce((a, b) => a < b ? a : b);
    final hi = n.audio.subs.reduce((a, b) => a > b ? a : b);
    expect(hi - lo, greaterThan(0.3),
        reason: 'the floor never moved — it is a constant, not a mood');
    expect(hi, lessThanOrEqualTo(1.0));
    expect(lo, greaterThanOrEqualTo(0.0));
  });

  test('something breathes at you, and gets closer as dread climbs', () {
    final n = _night(play: false);
    expect(n.audio.breaths.length, greaterThan(5),
        reason: 'nothing ever breathed in the room');
    final maxNear = n.audio.breaths.reduce((a, b) => a > b ? a : b);
    // Was 0.5. An abandoned night now ENDS sooner — missed station checks add
    // dread on top of everything else — so it never reaches the depth it used
    // to before the carrier drops, and proximity is driven by depth. The
    // assertion is that it gets close, not that the night lasts.
    expect(maxNear, greaterThan(0.42),
        reason: 'it never got close — proximity is the whole effect');
  });

  test('the stereo field is driven, not decorative', () {
    final n = _night(play: true);
    expect(n.audio.pans.length, greaterThan(100));
    final lo = n.audio.pans.reduce((a, b) => a < b ? a : b);
    final hi = n.audio.pans.reduce((a, b) => a > b ? a : b);
    expect(lo, lessThan(-0.15), reason: 'nothing ever came from the left');
    expect(hi, greaterThan(0.15), reason: 'nothing ever came from the right');
  });

  test('losing a long streak is audible', () {
    // streakBroken() was declared, documented ("play the loss of it, not just
    // the scare on top") and fully implemented in the audio engine with no
    // call site anywhere. The game shouts your streak from five places and
    // then took a mean 7.3-kill run away in silence.
    //
    // The cue deliberately lands 5.2s in, in the quiet recovery tail where the
    // CARRIER RECOVERED toast sits — so the test has to run the clock.
    fakeAsync((async) {
      seedRandom(31);
      final s = _station();
      final a = RecordingAudio();
      final r = AnomalyRuntime(s, audio: a);
      r.startBroadcast();
      // jumpscare() operates on the ACTIVE anomaly and returns immediately
      // without one, so the night has to actually produce something first.
      var el = 0.0;
      while (el < 21 * 60 && r.active == null) {
        r.tick(1 / 60.0);
        el += 1 / 60.0;
      }
      expect(r.active, isNotNull, reason: 'nothing ever manifested');
      s.stats.streak = 9;

      r.jumpscare();
      async.elapse(const Duration(seconds: 8));

      expect(s.stats.streak, 0, reason: 'the scare must take the run');
      expect(a.streakBreaks, 1, reason: 'and it must be audible');
      expect(a.scares, greaterThan(0));
    });
  });

  test('a player who never fails still hears screaming', () {
    // The whole point. Answer every anomaly correctly, never get hit, and the
    // building should still be screaming at you from somewhere else.
    final n = _night(play: true);
    expect(n.s.stats.scared, 0,
        reason: 'this run was supposed to be clean — retune the harness');
    expect(n.audio.distantScreams.length, greaterThan(6),
        reason: 'a flawless night was silent: the horror is still gated '
            'behind losing');
  });

  test('and they get closer as the night turns', () {
    final n = _night(play: false);
    expect(n.audio.distantScreams, isNotEmpty);
    final worst = n.audio.distantScreams.reduce((a, b) => a > b ? a : b);
    final first = n.audio.distantScreams.first;
    expect(worst, greaterThan(first),
        reason: 'every scream came from the same distance all night');
    expect(worst, lessThan(1.0),
        reason: 'it must never actually reach the door');
  });

  test('a short streak is not mourned', () {
    fakeAsync((async) {
      seedRandom(31);
      final s = _station();
      final a = RecordingAudio();
      final r = AnomalyRuntime(s, audio: a);
      r.startBroadcast();
      var el = 0.0;
      while (el < 21 * 60 && r.active == null) {
        r.tick(1 / 60.0);
        el += 1 / 60.0;
      }
      s.stats.streak = 1;
      r.jumpscare();
      async.elapse(const Duration(seconds: 8));
      expect(a.streakBreaks, 0,
          reason: 'losing one kill is not a loss worth scoring');
    });
  });
}

// --- appended: the screams -------------------------------------------------
//
// "the sounds got no screams". Literally true in practice: scream() was called
// from exactly one place, _scareHit(), so it only ever fired when the player
// FAILED. A competent operator finished an entire career without hearing a
// single one, and spent every night in a pleasant hum. The horror was gated
// behind losing, which is the one state a good player never reaches.
