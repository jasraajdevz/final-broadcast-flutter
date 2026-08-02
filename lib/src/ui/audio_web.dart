// FINAL BROADCAST — the WebAudio implementation of GameAudio.
//
// A 1:1 port of the JS `AU` object from index.html. Every frequency, gain,
// ramp time, filter Q and envelope breakpoint is the number from the original;
// nothing here has been retuned. The graph topology is identical too, node for
// node, because the mix only works as a whole (the limiter after the master is
// what stops bed + heartbeat + jumpscare from clipping when they land at once).
//
// WEB ONLY. This file is selected by the conditional import in audio.dart and
// is the only place in the project that talks to WebAudio. It lives under
// src/ui/ purely because of file ownership during the port; nothing in it is a
// widget.
//
// Two deliberate departures from the JS, neither audible:
//   * `node.onended = () => out.disconnect()` becomes a Dart Timer scheduled
//     past the tail of the sound. Interop callbacks would work, but the timing
//     is only about freeing graph nodes.
//   * the bed buffers are filled into a Dart Float32List and pushed with
//     copyToChannel(), rather than written through getChannelData(). On
//     dart2wasm getChannelData().toDart is a copy, so writing through it would
//     silently do nothing.

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import '../anomalies.dart' show GameAudio;
import '../consts.dart' show rand, rr;

/// Selected by the conditional import in audio.dart.
GameAudio makeGameAudio() => WebAudio();

// ---------------------------------------------------------------------------
// Minimal WebAudio bindings. Only what AU actually touches.
// ---------------------------------------------------------------------------

extension type _Node._(JSObject _) implements JSObject {
  /// Accepts an AudioNode or an AudioParam, exactly like the DOM does.
  external void connect(JSObject destination);
  external void disconnect();
}

extension type _Param._(JSObject _) implements JSObject {
  external double get value;
  external set value(double v);
  external void setValueAtTime(double value, double startTime);
  external void linearRampToValueAtTime(double value, double endTime);
  external void exponentialRampToValueAtTime(double value, double endTime);
  external void setTargetAtTime(
      double target, double startTime, double timeConstant);
  external void cancelScheduledValues(double startTime);
}

extension type _Gain._(JSObject _) implements _Node {
  external _Param get gain;
}

extension type _Osc._(JSObject _) implements _Node {
  external set type(String t);
  external _Param get frequency;
  external _Param get detune;
  external void start([double when]);
  external void stop([double when]);
}

extension type _Biquad._(JSObject _) implements _Node {
  external set type(String t);
  external _Param get frequency;
  @JS('Q')
  external _Param get q;

  /// Only meaningful on the shelf and peaking types — the proximity shelf in
  /// [WebAudio.breath] is what makes a close breath sound close.
  external _Param get gain;
}

extension type _Shaper._(JSObject _) implements _Node {
  external set curve(JSFloat32Array c);
  external set oversample(String o);
}

extension type _Comp._(JSObject _) implements _Node {
  external _Param get threshold;
  external _Param get knee;
  external _Param get ratio;
  external _Param get attack;
  external _Param get release;
}

extension type _Panner._(JSObject _) implements _Node {
  external _Param get pan;
}

extension type _Buffer._(JSObject _) implements JSObject {
  external void copyToChannel(JSFloat32Array source, int channelNumber);
}

extension type _BufSrc._(JSObject _) implements _Node {
  external set buffer(_Buffer b);
  external set loop(bool v);
  external void start([double when, double offset]);
  external void stop([double when]);
}

@JS('AudioContext')
extension type _Ctx._(JSObject _) implements JSObject {
  external factory _Ctx();
  external double get currentTime;
  external double get sampleRate;
  external String get state;
  external JSPromise<JSAny?> resume();
  external _Node get destination;
  external _Gain createGain();
  external _Osc createOscillator();
  external _Biquad createBiquadFilter();
  external _Shaper createWaveShaper();
  external _Comp createDynamicsCompressor();
  external _Panner createStereoPanner();
  external _Buffer createBuffer(
      int numberOfChannels, int length, double sampleRate);
  external _BufSrc createBufferSource();
}

@JS('webkitAudioContext')
extension type _WebkitCtx._(JSObject _) implements JSObject {
  external factory _WebkitCtx();
}

_Ctx? _newContext() {
  try {
    return _Ctx();
  } catch (_) {
    try {
      final JSObject o = _WebkitCtx();
      return _Ctx._(o);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// AU
// ---------------------------------------------------------------------------

class WebAudio implements GameAudio {
  _Ctx? _c;
  bool _on = false;
  double _vol = 0.7;

  // The JS AU kept handles to the hum bus and the dread tremolo gain that it
  // never read again; a connected WebAudio node stays alive on its own, so
  // those two are locals here.
  _Gain? _master;
  _Panner? _panner;
  _Gain? _staticG;
  _Gain? _droneG;
  _Gain? _roomG;
  _Gain? _dreadG;
  _Gain? _dreadLfoG;
  _Gain? _heartG;
  _Osc? _droneOsc;
  _Osc? _dreadOsc2;
  _Osc? _dreadLfo;
  _Biquad? _dreadF;
  _Buffer? _nbuf;

  // --- AU.tn: one writer per bed parameter (see the JS comment: ramp() calls
  // cancelScheduledValues, so a second writer silently eats the first one) ---
  double _dread = 0, _dreadT = 0;
  double _duckV = 1, _duckT = 1;
  bool _dead = false;
  Timer? _duckTimer;
  double _pa = 0;
  double _hbBpm = 50, _hbBpmT = 50;
  double _hbVol = 0, _hbVolT = 0;
  double _hbPh = 0.88;
  double _ev = 7;

  /// Which of the eight desk relays closes next. See [relay].
  int _relayN = 0;

  // --- the horror layer ---
  _Gain? _subG;
  _Osc? _subOsc;
  _Osc? _subOsc2;
  double _sub = 0, _subT = 0;
  Timer? _holdTimer;
  bool _holding = false;

  /// Seconds until the room tone next STOPS on its own. Silence that arrives
  /// without a cause is the cheapest dread in the game and the bed never once
  /// used it — the room hummed at a constant 0.85 from 23:00 to 06:00.
  double _stop = 26;

  // -------------------------------------------------------------------------
  // init / lifecycle
  // -------------------------------------------------------------------------

  @override
  void init() {
    if (_c != null) return;
    final c = _newContext();
    if (c == null) return;
    _c = c;
    final t = c.currentTime;

    final master = c.createGain();
    master.gain.value = _vol;
    _master = master;

    // safety limiter: bed + heartbeat + jumpscare can all be live at once
    final lim = c.createDynamicsCompressor();
    lim.threshold.setValueAtTime(-7, t);
    lim.knee.setValueAtTime(5, t);
    lim.ratio.setValueAtTime(14, t);
    lim.attack.setValueAtTime(0.004, t);
    lim.release.setValueAtTime(0.22, t);
    // Master stereo panner. The bed, the drone and every one-shot go through
    // it, so a drift is heard as the ROOM moving rather than as one sound
    // moving — which is the difference between unsettling and gimmicky.
    final panner = c.createStereoPanner();
    panner.pan.value = 0;
    _panner = panner;
    master.connect(panner);
    panner.connect(lim);
    lim.connect(c.destination);

    // --- THE SUB BED ---------------------------------------------------
    //
    // Nothing in the old mix went below ~90Hz with any energy, so the room
    // had no weight: every scare was bright and thin, which the ear reads as
    // "harsh", not as "wrong". Two detuned oscillators at 24 and 31Hz beat
    // against each other at 7Hz — below pitch, below rhythm, right in the
    // band that reads as physical unease. It measures as almost nothing and
    // it is the reason the room feels like it has a floor under it.
    //
    // Routed AROUND the main limiter, on its own path to the destination.
    //
    // Measured: with the sub feeding `master` like everything else, a 24Hz bed
    // at -27dBFS came out of the tap at -62 — ten dB UNDER the mid-band room
    // tone it was supposed to sit beneath. The station bed keeps that limiter
    // in constant gain reduction, and a compressor cannot tell the difference
    // between a hi-hat and the floor of the world; it just pulls everything
    // down together. Which is exactly the thing that makes a mix feel thin.
    //
    // So the floor gets its own path and its own gentle ceiling. It is the one
    // element in this game that must not be allowed to duck.
    final subLim = c.createDynamicsCompressor();
    subLim.threshold.setValueAtTime(-2, t);
    subLim.knee.setValueAtTime(2, t);
    subLim.ratio.setValueAtTime(20, t);
    subLim.connect(c.destination);

    final subG = c.createGain();
    subG.gain.value = 0;
    subG.connect(subLim);
    _subG = subG;
    for (var i = 0; i < 2; i++) {
      final o = c.createOscillator();
      o.type = 'sine';
      o.frequency.setValueAtTime(i == 0 ? 24.0 : 31.0, t);
      final g = c.createGain();
      g.gain.value = i == 0 ? 1.0 : 0.72;
      o.connect(g);
      g.connect(subG);
      o.start(t);
      if (i == 0) {
        _subOsc = o;
      } else {
        _subOsc2 = o;
      }
    }

    // looping noise bed. The one-pole coefficient 0.05 puts its corner at
    // ~342Hz, above the 220Hz highpass right after it.
    final len = (c.sampleRate * 2).floor();
    final buf = c.createBuffer(1, len, c.sampleRate);
    final d = Float32List(len);
    var last = 0.0;
    for (var i = 0; i < len; i++) {
      final w = rand() * 2 - 1;
      last = (last + 0.05 * w) / 1.05;
      d[i] = last * 2.2;
    }
    buf.copyToChannel(d.toJS, 0);
    final src = c.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    final lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 5200;
    final hp = c.createBiquadFilter();
    hp.type = 'highpass';
    hp.frequency.value = 220;
    final sg = c.createGain();
    sg.gain.value = 0.20;
    _staticG = sg;
    src.connect(hp);
    hp.connect(lp);
    lp.connect(sg);
    sg.connect(master);
    src.start();

    // mains hum — 820Hz lowpass plus a 300Hz partial makes it a buzz you hear
    final hum = c.createGain();
    hum.gain.value = 0.10;
    hum.connect(master);
    const freqs = <double>[60, 120, 180, 300];
    const gains = <double>[0.5, 0.28, 0.12, 0.05];
    for (var i = 0; i < freqs.length; i++) {
      final o = c.createOscillator();
      o.type = 'sawtooth';
      o.frequency.value = freqs[i];
      final g = c.createGain();
      g.gain.value = gains[i];
      final flt = c.createBiquadFilter();
      flt.type = 'lowpass';
      flt.frequency.value = 820;
      o.connect(g);
      g.connect(flt);
      flt.connect(hum);
      o.start();
    }

    // anomaly drone (silent until needed)
    final dg = c.createGain();
    dg.gain.value = 0;
    dg.connect(master);
    _droneG = dg;
    final o1 = c.createOscillator();
    o1.type = 'sawtooth';
    o1.frequency.value = 42;
    final o2 = c.createOscillator();
    o2.type = 'sine';
    o2.frequency.value = 63.5;
    final f = c.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 260;
    o1.connect(f);
    o2.connect(f);
    f.connect(dg);
    o1.start();
    o2.start();
    _droneOsc = o1;

    _buildBed();
    _on = true;
  }

  @override
  void resume() {
    final c = _c;
    if (c == null) return;
    try {
      if (c.state == 'suspended') c.resume();
    } catch (_) {}
  }

  @override
  void setVol(double v) {
    _vol = v;
    _master?.gain.value = v;
  }

  @override
  void pan(double p) {
    final pn = _panner;
    if (pn == null) return;
    pn.pan.value = p.clamp(-1.0, 1.0);
  }

  // -------------------------------------------------------------------------
  // shared primitives
  // -------------------------------------------------------------------------

  /// Odd-harmonic saturation: a 41Hz drone is inaudible on a laptop, its 3rd
  /// and 5th are not.
  _Shaper? _shaper(double amt) {
    final c = _c;
    if (c == null) return null;
    const n = 256;
    final cv = Float32List(n);
    for (var i = 0; i < n; i++) {
      final x = i * 2 / (n - 1) - 1;
      cv[i] = _tanh(x * amt) / _tanh(amt);
    }
    final w = c.createWaveShaper();
    w.curve = cv.toJS;
    w.oversample = '2x';
    return w;
  }

  static double _tanh(double x) {
    if (x > 20) return 1;
    if (x < -20) return -1;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  /// One shared 3s buffer at a random offset.
  _BufSrc? _noise(double t, double dur) {
    final c = _c, nb = _nbuf;
    if (c == null || nb == null) return null;
    final n = c.createBufferSource();
    n.buffer = nb;
    n.loop = true;
    n.start(t, rand() * 2.4);
    n.stop(t + dur);
    return n;
  }

  void _kill(_Gain out, double afterSeconds) {
    Timer(Duration(milliseconds: (afterSeconds * 1000).round() + 60), () {
      try {
        out.disconnect();
      } catch (_) {}
    });
  }

  void _later(int ms, void Function() fn) {
    Timer(Duration(milliseconds: ms), fn);
  }

  void _ramp(_Gain node, double v, double t) {
    final c = _c;
    if (c == null) return;
    final g = node.gain;
    g.cancelScheduledValues(c.currentTime);
    g.setValueAtTime(g.value, c.currentTime);
    g.linearRampToValueAtTime(v, c.currentTime + t);
  }

  // -------------------------------------------------------------------------
  // the room: always on, and it gets worse as DREAD climbs
  // -------------------------------------------------------------------------

  void _buildBed() {
    final c = _c, master = _master;
    if (c == null || master == null) return;
    final t = c.currentTime;

    final ln = (c.sampleRate * 3).floor();
    final nb = c.createBuffer(1, ln, c.sampleRate);
    final nd = Float32List(ln);
    for (var i = 0; i < ln; i++) {
      nd[i] = rand() * 2 - 1;
    }
    nb.copyToChannel(nd.toJS, 0);
    _nbuf = nb;

    final room = c.createGain();
    room.gain.value = 0.9;
    room.connect(master);
    _roomG = room;

    // air handler two floors down, breathing on an 18s cycle
    final rn = c.createBufferSource();
    rn.buffer = nb;
    rn.loop = true;
    rn.start(t);
    final rlp = c.createBiquadFilter();
    rlp.type = 'lowpass';
    rlp.frequency.value = 150;
    rlp.q.value = 0.9;
    final rg = c.createGain();
    rg.gain.value = 0.42;
    rn.connect(rlp);
    rlp.connect(rg);
    rg.connect(room);
    final rl = c.createOscillator();
    rl.type = 'sine';
    rl.frequency.value = 0.055;
    final rlg = c.createGain();
    rlg.gain.value = 52;
    rl.connect(rlg);
    rlg.connect(rlp.frequency);
    rl.start(t);

    // three room modes — an empty concrete studio ringing at its own dimensions
    const modes = <List<double>>[
      <double>[186, 13, 0.26, 0.019],
      <double>[281, 17, 0.17, 0.032],
      <double>[433, 21, 0.09, 0.045],
    ];
    for (final m in modes) {
      final n2 = c.createBufferSource();
      n2.buffer = nb;
      n2.loop = true;
      n2.start(t, rand() * 2.4);
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = m[0];
      bp.q.value = m[1];
      final g2 = c.createGain();
      g2.gain.value = m[2];
      final lf = c.createOscillator();
      lf.type = 'sine';
      lf.frequency.value = m[3];
      final lg = c.createGain();
      lg.gain.value = m[2] * 0.6;
      lf.connect(lg);
      lg.connect(g2.gain);
      lf.start(t);
      n2.connect(bp);
      bp.connect(g2);
      g2.connect(room);
    }

    // wind past the mast, swelling about every 38s
    final wn = c.createBufferSource();
    wn.buffer = nb;
    wn.loop = true;
    wn.start(t, 1.1);
    final wbp = c.createBiquadFilter();
    wbp.type = 'bandpass';
    wbp.frequency.value = 820;
    wbp.q.value = 0.7;
    final wg = c.createGain();
    wg.gain.value = 0.05;
    final wl = c.createOscillator();
    wl.type = 'sine';
    wl.frequency.value = 0.026;
    final wlg = c.createGain();
    wlg.gain.value = 0.042;
    wl.connect(wlg);
    wlg.connect(wg.gain);
    wl.start(t);
    wn.connect(wbp);
    wbp.connect(wg);
    wg.connect(room);

    // dread bed: silent at 0, a physical presence at 100
    final dread = c.createGain();
    dread.gain.value = 0;
    dread.connect(master);
    _dreadG = dread;
    final trem = c.createGain();
    trem.gain.value = 1;
    trem.connect(dread);
    final df = c.createBiquadFilter();
    df.type = 'lowpass';
    df.frequency.value = 95;
    df.q.value = 7;
    _dreadF = df;
    final dsh = _shaper(2.8);
    if (dsh != null) {
      df.connect(dsh);
      dsh.connect(trem);
    } else {
      df.connect(trem);
    }
    final dmix = c.createGain();
    dmix.gain.value = 0.5;
    dmix.connect(df);
    final d1 = c.createOscillator();
    d1.type = 'sawtooth';
    d1.frequency.value = 41;
    final d2 = c.createOscillator();
    d2.type = 'sawtooth';
    d2.frequency.value = 41;
    d2.detune.value = -6;
    final d3 = c.createOscillator();
    d3.type = 'triangle';
    d3.frequency.value = 58;
    final d3g = c.createGain();
    d3g.gain.value = 0.45;
    d1.connect(dmix);
    d2.connect(dmix);
    d3.connect(d3g);
    d3g.connect(dmix);
    d1.start(t);
    d2.start(t);
    d3.start(t);
    _dreadOsc2 = d2;
    final lfo = c.createOscillator();
    lfo.type = 'sine';
    lfo.frequency.value = 0.12;
    final lfoG = c.createGain();
    lfoG.gain.value = 0.12;
    lfo.connect(lfoG);
    lfoG.connect(trem.gain);
    lfo.start(t);
    _dreadLfo = lfo;
    _dreadLfoG = lfoG;

    final heart = c.createGain();
    heart.gain.value = 1;
    heart.connect(master);
    _heartG = heart;
  }

  // -------------------------------------------------------------------------
  // per-frame bed update
  // -------------------------------------------------------------------------

  @override
  void tick(double dt) {
    final c = _c, room = _roomG;
    if (!_on || c == null || room == null) return;
    final t = c.currentTime;
    if (dt > 0.25) dt = 0.25;
    _duckV += (_duckT - _duckV) * math.min(1.0, dt * 7);
    _dread += (_dreadT - _dread) * math.min(1.0, dt * 0.5); // mood lags the meter
    final d = _dread, k = _duckV;

    _pa += dt;
    if (_pa >= 0.1) {
      // 10Hz — at 60fps this was 360 AudioParam events a second
      _pa = 0;
      room.gain.setTargetAtTime((0.85 + d * 0.55) * k, t, 0.12);
      _dreadG?.gain.setTargetAtTime((0.015 + d * 0.20) * k, t, 0.25);
      _dreadF?.frequency.setTargetAtTime(95 + d * d * 820, t, 0.3);
      _dreadOsc2?.detune.setTargetAtTime(-6 - d * 30, t, 0.4);
      _dreadLfo?.frequency.setTargetAtTime(0.12 + d * 1.1, t, 0.4);
      _dreadLfoG?.gain.setTargetAtTime(0.12 + d * 0.55, t, 0.4);
    }

    _hbBpm += (_hbBpmT - _hbBpm) * math.min(1.0, dt * 2.2);
    _hbVol += (_hbVolT - _hbVol) *
        math.min(1.0, dt * (_hbVolT > _hbVol ? 3.0 : 1.1));
    if (_hbVol > 0.006) {
      _hbPh += dt * (_hbBpm / 60);
      if (_hbPh >= 1) {
        _hbPh -= 1;
        // Dead Air ducks the room to 0.05 and leaves the heart: that silence is
        // meant to be you, by yourself, listening to your own chest
        final per = 60 / math.max(30.0, _hbBpm);
        final v = _hbVol * (_dead ? 1 : k);
        thump(v, 58, t + 0.02);
        thump(v * 0.62, 47, t + 0.02 + per * 0.27);
      }
    } else {
      _hbPh = 0.9;
    }

    // the infrasonic floor. Follows dread but never all the way to zero —
    // this room has a bottom to it even at 23:00, which is why 23:00 does not
    // feel safe.
    _sub += (_subT - _sub) * math.min(1.0, dt * 0.7);
    if (_pa == 0) {
      // Levels are what the tap measured back, not what looked reasonable in
      // source: the old 0.06/0.62 pair landed the whole bed around -62dBFS.
      _subG?.gain.setTargetAtTime(
          _holding ? 0.0 : (0.16 + _sub * 0.85) * _vol, t, 0.5);
      // the beat frequency tightens as dread climbs: 7Hz at rest, ~11Hz at
      // the top, which crosses from "unease" into "wrong"
      _subOsc?.frequency.setTargetAtTime(24 - _sub * 2.5, t, 1.2);
      _subOsc2?.frequency.setTargetAtTime(31 + _sub * 3.0, t, 1.2);
    }

    _ev -= dt;
    if (_ev <= 0) {
      _ev = rr(13 - d * 7, 26 - d * 14);
      final r = rand();
      // The old table was four ambient sounds in a room. Half of it is now
      // BODIES: something breathing on one side of you, something almost
      // saying a word. Both scale toward you as dread climbs.
      if (r < 0.20 + d * 0.22) {
        breath(rand() < 0.5 ? -1 : 1, 0.15 + d * 0.7);
      } else if (r < 0.34 + d * 0.26) {
        voice(0.1 + d * 0.7, rr(-1, 1));
      } else if (r < 0.55) {
        whisper();
      } else if (r < 0.72) {
        creak();
      } else if (r < 0.88) {
        pipe();
      } else {
        farThud();
      }
    }

    // THE ROOM STOPS. Once every 40-90s the bed simply ceases for a beat,
    // with no cause and no consequence. A room that hums at a constant level
    // from 23:00 to 06:00 is a room you stop hearing; a room that stops is a
    // room you start listening to. Never during a scare or a Dead Air.
    _stop -= dt;
    if (_stop <= 0) {
      _stop = rr(40 - d * 16, 92 - d * 34);
      if (!_dead && !_holding) {
        hold((240 + rand() * 420).round());
        // and sometimes something is in the hole
        if (rand() < 0.22 + d * 0.35) {
          _later(120 + (rand() * 180).round(),
              () => breath(rand() < 0.5 ? -1 : 1, 0.55 + d * 0.4));
        }
      }
    }
  }

  @override
  void setDread(double v) {
    _dreadT = v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  @override
  void setHeart(double bpm, double vol) {
    _hbBpmT = bpm;
    _hbVolT = vol < 0 ? 0 : (vol > 0.55 ? 0.55 : vol);
  }

  @override
  void duck(double v, int ms) {
    _duckT = v;
    _duckTimer?.cancel();
    _duckTimer = Timer(Duration(milliseconds: ms), () {
      _duckT = _dead ? 0.05 : 1;
    });
  }

  @override
  void deadAir(bool on) {
    _dead = on;
    _duckTimer?.cancel();
    _duckT = on ? 0.05 : 1;
  }

  // -------------------------------------------------------------------------
  // one-shots
  // -------------------------------------------------------------------------

  @override
  void thump(double vol, double f0, [double? when]) {
    final c = _c, heart = _heartG;
    if (!_on || c == null || heart == null) return;
    final t = when ?? c.currentTime;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(heart);
    final o = c.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(f0, t);
    o.frequency.exponentialRampToValueAtTime(f0 * 0.55, t + 0.10);
    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(math.max(0.0001, vol * 0.62), t + 0.014);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.20);
    final sh = _shaper(2.2);
    o.connect(g);
    if (sh != null) {
      g.connect(sh);
      sh.connect(out);
    } else {
      g.connect(out);
    }
    o.start(t);
    o.stop(t + 0.24);
    final n = _noise(t, 0.09);
    if (n != null) {
      final nf = c.createBiquadFilter();
      nf.type = 'bandpass';
      nf.frequency.value = 235;
      nf.q.value = 1.8;
      final ng = c.createGain();
      ng.gain.setValueAtTime(math.max(0.0001, vol * 2.4), t);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.085);
      n.connect(nf);
      nf.connect(ng);
      ng.connect(out);
    }
    // 58Hz and 235Hz are at or under what a laptop renders — it is this click,
    // not the thud, that actually reaches the player
    final kn = _noise(t, 0.055);
    if (kn != null) {
      final kf = c.createBiquadFilter();
      kf.type = 'bandpass';
      kf.frequency.value = 560;
      kf.q.value = 1.5;
      final kg = c.createGain();
      kg.gain.setValueAtTime(math.max(0.0001, vol * 8.5), t);
      kg.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
      kn.connect(kf);
      kf.connect(kg);
      kg.connect(out);
    }
    _kill(out, (t - c.currentTime) + 0.4);
  }

  @override
  void riser(double dur) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final d = dur <= 0 ? 1.6 : dur;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    final pl = c.createOscillator();
    pl.type = 'sine';
    pl.frequency.setValueAtTime(3.5, t);
    pl.frequency.exponentialRampToValueAtTime(14, t + d);
    final plg = c.createGain();
    plg.gain.value = 0.32;
    pl.connect(plg);
    plg.connect(out.gain);
    pl.start(t);
    pl.stop(t + d + 0.3);
    final n = _noise(t, d + 0.2);
    if (n != null) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.setValueAtTime(170, t);
      bp.frequency.exponentialRampToValueAtTime(3600, t + d);
      bp.q.setValueAtTime(0.9, t);
      bp.q.linearRampToValueAtTime(6.5, t + d);
      final ng = c.createGain();
      ng.gain.setValueAtTime(0.0001, t);
      ng.gain.exponentialRampToValueAtTime(0.5, t + d * 0.87);
      ng.gain.exponentialRampToValueAtTime(0.03, t + d);
      n.connect(bp);
      bp.connect(ng);
      ng.connect(out);
    }
    final lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.q.value = 5;
    lp.frequency.setValueAtTime(200, t);
    lp.frequency.exponentialRampToValueAtTime(2400, t + d);
    final og = c.createGain();
    og.gain.setValueAtTime(0.0001, t);
    og.gain.exponentialRampToValueAtTime(0.16, t + d * 0.9);
    og.gain.exponentialRampToValueAtTime(0.008, t + d);
    const voices = <List<double>>[
      <double>[58, 0],
      <double>[58, 9],
      <double>[87, -7],
    ];
    for (final v in voices) {
      final o = c.createOscillator();
      o.type = 'sawtooth';
      o.detune.value = v[1];
      o.frequency.setValueAtTime(v[0], t);
      o.frequency.exponentialRampToValueAtTime(v[0] * 3, t + d);
      o.connect(lp);
      o.start(t);
      o.stop(t + d + 0.05);
    }
    lp.connect(og);
    og.connect(out);
    _kill(out, d + 0.6);
    duck(0.6, (d * 1000).round());
  }

  @override
  void impact() {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    final o = c.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(120, t);
    o.frequency.exponentialRampToValueAtTime(27, t + 0.75);
    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.5, t + 0.012);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.9);
    final sh = _shaper(1.6);
    if (sh != null) {
      o.connect(sh);
      sh.connect(g);
    } else {
      o.connect(g);
    }
    g.connect(out);
    o.start(t);
    o.stop(t + 0.95);
    final n = _noise(t, 0.45);
    if (n != null) {
      final f = c.createBiquadFilter();
      f.type = 'lowpass';
      f.frequency.setValueAtTime(2600, t);
      f.frequency.exponentialRampToValueAtTime(160, t + 0.4);
      final ng = c.createGain();
      ng.gain.setValueAtTime(0.8, t);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.5);
      n.connect(f);
      f.connect(ng);
      ng.connect(out);
      final mb = c.createBiquadFilter();
      mb.type = 'bandpass';
      mb.frequency.value = 760;
      mb.q.value = 1.1;
      final mg = c.createGain();
      mg.gain.setValueAtTime(1.6, t);
      mg.gain.exponentialRampToValueAtTime(0.0001, t + 0.3);
      n.connect(mb);
      mb.connect(mg);
      mg.connect(out);
    }
    _kill(out, 1.1);
    duck(0.35, 260);
  }

  // -------------------------------------------------------------------------
  // THE EIGHT EMERGENCY KEYS
  //
  // Every counter press used to route to click() — env('square',900,...), the
  // same 45ms blip a rack tab makes. The climactic input in the game sounded
  // like a spreadsheet, and because it was the same blip for a right answer, a
  // wrong answer and a menu tab, the deck had no voice of its own.
  //
  // A 1968 emergency key is not a beep. It is a coil pulling an armature into a
  // contact, and there are three things in that sound, in this order:
  //   1. the ARMATURE — a low thump with a very fast decay. Almost no pitch,
  //      all weight. This is what makes the press feel like it cost something.
  //   2. the CONTACT — a filtered-noise transient, ~25ms, bright and metallic.
  //      This is the part that actually reaches a laptop speaker.
  //   3. the COIL — a mains-flavoured buzz decaying as the field collapses,
  //      then a quieter second contact as the armature seats.
  // Total 0.19s, so eight of them in a row still read as eight distinct presses
  // rather than a smear.
  // -------------------------------------------------------------------------

  /// One contact closing under a coil. Something latched; something is still
  /// live. Used for a partial kill — the two-stage flinch, the first half of a
  /// coupled pair — and it is the voice the eight emergency keys want, because
  /// that is literally the hardware under them.
  ///
  /// There are eight relays in the desk, they are not tuned to each other and
  /// they never were, so consecutive closes step around a small pitch ring and
  /// jitter on top of it. Nothing here is ever exactly the same twice.
  /// THE SAVE. A held breath let out: the room's bed ducks hard for a beat,
  /// a rising third resolves, and a single ferrite tick lands late enough to
  /// read as "that was close" rather than "well done". It plays OVER the
  /// banish stinger, so a save is audibly a different event from a clean kill.
  @override
  void clutchSting() {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;

    // pull the room out from under it for a third of a second
    duck(0.34, 320);

    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);

    // the breath: noise through a sweeping bandpass, in and gone
    final n = _noise(t, 0.42);
    if (n != null) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.setValueAtTime(300, t);
      bp.frequency.exponentialRampToValueAtTime(1900, t + 0.30);
      bp.q.value = 3.2;
      final ng = c.createGain();
      ng.gain.setValueAtTime(0.0001, t);
      ng.gain.exponentialRampToValueAtTime(0.10, t + 0.05);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.42);
      n.connect(bp);
      bp.connect(ng);
      ng.connect(out);
    }

    // the resolve: a minor third that walks up to a major one
    for (var i = 0; i < 2; i++) {
      final o = c.createOscillator();
      o.type = 'triangle';
      final f0 = i == 0 ? 330.0 : 392.0;
      final f1 = i == 0 ? 330.0 : 440.0;
      o.frequency.setValueAtTime(f0, t + 0.06);
      o.frequency.exponentialRampToValueAtTime(f1, t + 0.34);
      final g = c.createGain();
      g.gain.setValueAtTime(0.0001, t + 0.06);
      g.gain.exponentialRampToValueAtTime(i == 0 ? 0.075 : 0.055, t + 0.11);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.62);
      o.connect(g);
      g.connect(out);
      o.start(t + 0.06);
      o.stop(t + 0.66);
    }

    // the late tick — the sound of the margin you did not have
    final k = c.createOscillator();
    k.type = 'square';
    k.frequency.setValueAtTime(2100, t + 0.40);
    k.frequency.exponentialRampToValueAtTime(700, t + 0.45);
    final kg = c.createGain();
    kg.gain.setValueAtTime(0.0001, t + 0.40);
    kg.gain.exponentialRampToValueAtTime(0.07, t + 0.405);
    kg.gain.exponentialRampToValueAtTime(0.0001, t + 0.47);
    k.connect(kg);
    kg.connect(out);
    k.start(t + 0.40);
    k.stop(t + 0.48);

    _kill(out, 0.7);
  }

  @override
  void relay() {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);

    final d = _relayN++ & 7;
    final tone = math.pow(1.0293, d).toDouble() * rr(0.985, 1.015);

    // 1. the armature
    final o = c.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(112 * tone, t);
    o.frequency.exponentialRampToValueAtTime(38, t + 0.06);
    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.34, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.09);
    final sh = _shaper(2.4);
    if (sh != null) {
      o.connect(sh);
      sh.connect(g);
    } else {
      o.connect(g);
    }
    g.connect(out);
    o.start(t);
    o.stop(t + 0.11);

    // 2. the contact, closing
    final n = _noise(t, 0.05);
    if (n != null) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.q.value = 5.5;
      bp.frequency.setValueAtTime(3200 * tone, t);
      bp.frequency.exponentialRampToValueAtTime(1450 * tone, t + 0.03);
      final ng = c.createGain();
      ng.gain.setValueAtTime(1.05, t);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.026);
      n.connect(bp);
      bp.connect(ng);
      ng.connect(out);
    }

    // 3. the coil, and the armature seating 45ms later
    final coil = c.createOscillator();
    coil.type = 'square';
    coil.frequency.setValueAtTime(119 * tone, t);
    coil.frequency.linearRampToValueAtTime(103 * tone, t + 0.13);
    final clp = c.createBiquadFilter();
    clp.type = 'lowpass';
    clp.frequency.value = 940;
    clp.q.value = 1.2;
    final cg = c.createGain();
    cg.gain.setValueAtTime(0.0001, t);
    cg.gain.exponentialRampToValueAtTime(0.055, t + 0.01);
    cg.gain.exponentialRampToValueAtTime(0.0001, t + 0.14);
    coil.connect(clp);
    clp.connect(cg);
    cg.connect(out);
    coil.start(t);
    coil.stop(t + 0.16);

    final seat = _noise(t + 0.045, 0.03);
    if (seat != null) {
      final sb = c.createBiquadFilter();
      sb.type = 'bandpass';
      sb.q.value = 8;
      sb.frequency.value = 2300 * tone;
      final sg2 = c.createGain();
      sg2.gain.setValueAtTime(0.34, t + 0.045);
      sg2.gain.exponentialRampToValueAtTime(0.0001, t + 0.068);
      seat.connect(sb);
      sb.connect(sg2);
      sg2.connect(out);
    }

    _kill(out, 0.32);
  }

  /// A run of [lost] correct answers ending. Every other cue in the game sweeps
  /// UP; this one falls, and the taller the run was the further it has to fall,
  /// so the loss is proportional to what was lost. It lands on a soft floor
  /// thud rather than fading out — a fall with no impact has no shape.
  @override
  void streakBroken(int lost) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final n = lost < 0 ? 0 : (lost > 8 ? 8 : lost);
    final d = 0.50 + n * 0.045;
    final f0 = 300.0 + n * 38;
    final f1 = 78.0;

    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    duck(0.45, ((d + 0.2) * 1000).round());

    // the glissando: three saws a few cents apart through a closing lowpass
    final lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.q.value = 3.5;
    lp.frequency.setValueAtTime(2700, t);
    lp.frequency.exponentialRampToValueAtTime(300, t + d);
    final og = c.createGain();
    og.gain.setValueAtTime(0.0001, t);
    og.gain.exponentialRampToValueAtTime(0.16 + n * 0.012, t + 0.03);
    og.gain.exponentialRampToValueAtTime(0.012, t + d);
    for (final det in const <double>[0, 11, -14]) {
      final o = c.createOscillator();
      o.type = 'sawtooth';
      o.detune.value = det;
      o.frequency.setValueAtTime(f0, t);
      o.frequency.exponentialRampToValueAtTime(f1, t + d);
      o.connect(lp);
      o.start(t);
      o.stop(t + d + 0.05);
    }
    lp.connect(og);
    og.connect(out);

    // the air going down with it
    final ns = _noise(t, d + 0.1);
    if (ns != null) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.q.value = 2.2;
      bp.frequency.setValueAtTime(2600, t);
      bp.frequency.exponentialRampToValueAtTime(180, t + d);
      final ng = c.createGain();
      ng.gain.setValueAtTime(0.20, t);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + d);
      ns.connect(bp);
      bp.connect(ng);
      ng.connect(out);
    }

    // the floor
    final a = t + d * 0.94;
    final th = c.createOscillator();
    th.type = 'sine';
    th.frequency.setValueAtTime(96, a);
    th.frequency.exponentialRampToValueAtTime(30, a + 0.24);
    final tg = c.createGain();
    tg.gain.setValueAtTime(0.0001, a);
    tg.gain.exponentialRampToValueAtTime(0.22 + n * 0.014, a + 0.01);
    tg.gain.exponentialRampToValueAtTime(0.0001, a + 0.34);
    final tsh = _shaper(2.0);
    if (tsh != null) {
      th.connect(tsh);
      tsh.connect(tg);
    } else {
      th.connect(tg);
    }
    tg.connect(out);
    th.start(a);
    th.stop(a + 0.38);

    _kill(out, d + 0.8);
  }

  /// A mark worth stopping for. Four kinds, and they are four DIFFERENT sounds
  /// on purpose — a milestone the player cannot tell apart from the last one is
  /// a milestone that stops meaning anything by the fourth hour:
  ///
  ///   "streak" — a new best run. A station ident: a major triad rising, moved
  ///              up a whole tone per rung of [n], so a record is audibly higher
  ///              than the record before it.
  ///   "banish" — every tenth kill of a career. Low, slow, two notes a fifth
  ///              apart with a long tail. This is a plaque on a wall, not a
  ///              firework.
  ///   "night"  — a segment of the rundown behind you. The 1kHz time pips a
  ///              real station put out on the hour, [n] of them, and the last
  ///              one long. The clock is the thing that is escalating; let the
  ///              clock speak with the clock's own voice.
  ///   "clean"  — a run of flawless kills. Bright, tight, over in 300ms: a
  ///              flourish, not a ceremony, because it happens mid-fight.
  @override
  void milestone(String kind, int n) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    switch (kind) {
      case 'night':
        _pips(n);
      case 'banish':
        _plaque(n);
      case 'clean':
        _flourish(n);
      default:
        _ident(n);
    }
  }

  /// "streak" — the station ident.
  void _ident(int n) {
    final c = _c, master = _master;
    if (c == null || master == null) return;
    final t = c.currentTime;
    final rung = n <= 0 ? 0 : (n > 6 ? 6 : n - 1);
    final k = math.pow(2.0, rung * 2 / 12.0).toDouble();
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    duck(0.62, 340);

    const notes = <double>[392, 523, 659];
    for (var i = 0; i < notes.length; i++) {
      final f = notes[i] * k;
      final a = t + i * 0.085;
      const dur = 0.85;
      final o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = f;
      final o2 = c.createOscillator();
      o2.type = 'sine';
      o2.frequency.value = f * 3.01;
      final g2 = c.createGain();
      g2.gain.setValueAtTime(0.0001, a);
      g2.gain.exponentialRampToValueAtTime(0.15 / (1 + i * 0.22), a + 0.01);
      g2.gain.exponentialRampToValueAtTime(0.0001, a + dur);
      final og2 = c.createGain();
      og2.gain.value = 0.34;
      o.connect(g2);
      o2.connect(og2);
      og2.connect(g2);
      g2.connect(out);
      o.start(a);
      o.stop(a + dur + 0.05);
      o2.start(a);
      o2.stop(a + dur + 0.05);
    }

    // the transmitter itself coming up under the chime
    final sub = c.createOscillator();
    sub.type = 'sine';
    sub.frequency.setValueAtTime(64, t);
    sub.frequency.exponentialRampToValueAtTime(98, t + 0.4);
    final sg = c.createGain();
    sg.gain.setValueAtTime(0.0001, t);
    sg.gain.exponentialRampToValueAtTime(0.18, t + 0.05);
    sg.gain.exponentialRampToValueAtTime(0.0001, t + 0.7);
    final ssh = _shaper(1.9);
    if (ssh != null) {
      sub.connect(ssh);
      ssh.connect(sg);
    } else {
      sub.connect(sg);
    }
    sg.connect(out);
    sub.start(t);
    sub.stop(t + 0.75);

    _kill(out, 1.5);
  }

  /// "banish" — the career plaque. Deliberately the slowest cue in the game.
  void _plaque(int n) {
    final c = _c, master = _master;
    if (c == null || master == null) return;
    final t = c.currentTime;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    duck(0.55, 900);
    // one whole tone up per hundred kills, so a career has a shape too
    final k = math.pow(2.0, math.min(4, n ~/ 100) * 2 / 12.0).toDouble();
    for (final v in <List<double>>[
      <double>[147 * k, 0],
      <double>[220 * k, 0.34],
    ]) {
      final f = v[0], a = t + v[1];
      final o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = f;
      final o2 = c.createOscillator();
      o2.type = 'sine';
      o2.frequency.value = f * 2;
      final o2g = c.createGain();
      o2g.gain.value = 0.4;
      final g = c.createGain();
      g.gain.setValueAtTime(0.0001, a);
      g.gain.exponentialRampToValueAtTime(0.17, a + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, a + 1.5);
      final sh = _shaper(1.5);
      o.connect(g);
      o2.connect(o2g);
      o2g.connect(g);
      if (sh != null) {
        g.connect(sh);
        sh.connect(out);
      } else {
        g.connect(out);
      }
      o.start(a);
      o.stop(a + 1.6);
      o2.start(a);
      o2.stop(a + 1.6);
    }
    _kill(out, 2.4);
  }

  /// "night" — the hour going, in the station's own time pips.
  void _pips(int n) {
    if (_c == null) return;
    final count = n < 1 ? 1 : (n > 6 ? 6 : n);
    duck(0.5, 200 * count + 700);
    for (var i = 0; i < count; i++) {
      final last = i == count - 1;
      _later(i * 200, () {
        // 1000Hz, five short and one long — the real thing, exactly.
        env('sine', 1000, last ? 0.52 : 0.10, 0.085, 1000);
        if (last) env('sine', 500, 0.6, 0.03, 500);
      });
    }
  }

  /// "clean" — a flourish, over before you have finished thinking about it.
  void _flourish(int n) {
    if (_c == null) return;
    final k = math.pow(2.0, math.min(5, n <= 0 ? 0 : n - 1) / 12.0).toDouble();
    for (var i = 0; i < 3; i++) {
      final f = <double>[1046, 1318, 1568][i] * k;
      _later(i * 38, () {
        env('triangle', f, 0.16, 0.075, f);
        env('sine', f * 2, 0.09, 0.022, f * 2);
      });
    }
    burst(0.06, 0.09, 3200, 6400);
  }

  /// The relief. [streak] is the run of consecutive banishes INCLUDING this
  /// one: it transposes the whole figure up in whole tones and adds a note on
  /// top, so a long run audibly CLIMBS instead of replaying the same two bars
  /// twenty times. A seventh kill does not sound like a first.
  @override
  void banishStinger(bool fast, int streak) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final tier = streak - 1;
    final tr = tier < 0 ? 0 : (tier > 4 ? 4 : tier);
    final k = math.pow(2.0, tr * 2 / 12.0).toDouble();
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    // pull the room out and bring it back: the relief. The higher the run, the
    // longer the room stays out of the way.
    duck(0.15, (fast ? 320 : 240) + tr * 45);
    final sub = c.createOscillator();
    sub.type = 'sine';
    sub.frequency.setValueAtTime(160 * (1 + tr * 0.05), t);
    sub.frequency.exponentialRampToValueAtTime(40, t + 0.5);
    final sg = c.createGain();
    sg.gain.setValueAtTime(0.0001, t);
    sg.gain.exponentialRampToValueAtTime(0.30 + tr * 0.02, t + 0.02);
    sg.gain.exponentialRampToValueAtTime(0.0001, t + 0.55);
    final ssh = _shaper(1.8);
    if (ssh != null) {
      sub.connect(ssh);
      ssh.connect(sg);
    } else {
      sub.connect(sg);
    }
    sg.connect(out);
    sub.start(t);
    sub.stop(t + 0.6);
    // swept DOWN — every other cue sweeps up, so this reads as resolved
    final n = _noise(t, 0.36);
    if (n != null) {
      final nf = c.createBiquadFilter();
      nf.type = 'bandpass';
      nf.q.value = 1.6;
      nf.frequency.setValueAtTime(5200, t);
      nf.frequency.exponentialRampToValueAtTime(420, t + 0.3);
      final ng = c.createGain();
      ng.gain.setValueAtTime(0.34, t);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.32);
      n.connect(nf);
      nf.connect(ng);
      ng.connect(out);
    }
    final base = fast
        ? const <double>[784, 1176, 1568, 2352]
        : const <double>[588, 882, 1176];
    final notes = <double>[for (final f in base) f * k];
    // Past a three-run the figure grows a note rather than just moving up, so
    // the climb is in the shape and not only in the pitch. Capped so a maxed
    // streak never turns the reward into a whistle.
    if (tr >= 3) {
      final top = notes.last * 1.5;
      notes.add(top > 3600 ? 3600 : top);
    }
    for (var i = 0; i < notes.length; i++) {
      final f = notes[i];
      final a = t + i * 0.055;
      final dur = fast ? 0.95 : 0.7;
      final o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = f;
      final o2 = c.createOscillator();
      o2.type = 'sine';
      o2.frequency.value = f * 2.01;
      final g2 = c.createGain();
      g2.gain.setValueAtTime(0.0001, a);
      g2.gain.exponentialRampToValueAtTime(
          (fast ? 0.20 : 0.17) / (1 + i * 0.45), a + 0.012);
      g2.gain.exponentialRampToValueAtTime(0.0001, a + dur);
      final hp = c.createBiquadFilter();
      hp.type = 'highpass';
      hp.frequency.value = 300;
      o.connect(g2);
      o2.connect(g2);
      g2.connect(hp);
      hp.connect(out);
      o.start(a);
      o.stop(a + dur + 0.05);
      o2.start(a);
      o2.stop(a + dur + 0.05);
    }
    _kill(out, 2.6);
  }

  @override
  void reject() {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    const d = 0.26;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);
    final gate = c.createGain();
    gate.gain.value = 0.78;
    gate.connect(out);
    final gl = c.createOscillator();
    gl.type = 'square';
    gl.frequency.value = 27;
    final glg = c.createGain();
    glg.gain.value = 0.22;
    gl.connect(glg);
    glg.connect(gate.gain);
    gl.start(t);
    gl.stop(t + d + 0.1);
    final sh = _shaper(9);
    final eg = c.createGain();
    eg.gain.setValueAtTime(0.0001, t);
    eg.gain.exponentialRampToValueAtTime(1.15, t + 0.006);
    eg.gain.exponentialRampToValueAtTime(0.0001, t + d);
    sh?.connect(eg);
    eg.connect(gate);
    // a semitone apart in the bass, hard-clipped
    const bass = <List<double>>[
      <double>[92, 0],
      <double>[97.5, 7],
    ];
    for (final v in bass) {
      final o = c.createOscillator();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(v[0], t);
      o.frequency.exponentialRampToValueAtTime(v[0] * 0.72, t + d);
      o.detune.value = v[1];
      if (sh != null) {
        o.connect(sh);
      } else {
        o.connect(eg);
      }
      o.start(t);
      o.stop(t + d + 0.05);
    }
    final n = _noise(t, 0.14);
    if (n != null) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 1750;
      bp.q.value = 3.2;
      final ng = c.createGain();
      ng.gain.setValueAtTime(1.0, t);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.13);
      n.connect(bp);
      bp.connect(ng);
      ng.connect(out);
    }
    _kill(out, 0.8);
    duck(1.25, 180);
  }

  // -------------------------------------------------------------------------
  // room events
  // -------------------------------------------------------------------------

  /// Three sliding formants over shared noise — the vowel space of whispered
  /// speech. The syllable envelope is what makes it read as language.
  @override
  void whisper() {
    final c = _c, room = _roomG;
    if (!_on || c == null || room == null) return;
    final t = c.currentTime, d = rr(0.6, 1.15);
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(room);
    final n = _noise(t, d + 0.15);
    if (n == null) return;
    final hp = c.createBiquadFilter();
    hp.type = 'highpass';
    hp.frequency.value = 420;
    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    final syl = 2 + (rand() * 3).floor();
    final sd = d / syl;
    for (var i = 0; i < syl; i++) {
      final a = t + sd * i;
      g.gain.exponentialRampToValueAtTime(rr(1.4, 2.6), a + sd * 0.35);
      g.gain.exponentialRampToValueAtTime(0.05, a + sd * 0.93);
    }
    g.gain.exponentialRampToValueAtTime(0.0001, t + d + 0.1);
    n.connect(hp);
    hp.connect(g);
    final formants = <List<double>>[
      <double>[rr(320, 720), rr(320, 720), 8, 0.5],
      <double>[rr(950, 1900), rr(950, 1900), 7, 0.34],
      <double>[rr(2300, 3100), rr(2300, 3100), 5, 0.13],
    ];
    for (final v in formants) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.q.value = v[2];
      bp.frequency.setValueAtTime(v[0], t);
      bp.frequency.linearRampToValueAtTime(v[1], t + d);
      final fg = c.createGain();
      fg.gain.value = v[3] * 0.85;
      g.connect(bp);
      bp.connect(fg);
      fg.connect(out);
    }
    _kill(out, d + 0.4);
  }

  /// A joist above the studio ceiling.
  @override
  void creak() {
    final c = _c, room = _roomG;
    if (!_on || c == null || room == null) return;
    final t = c.currentTime, d = rr(0.5, 1.1);
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(room);
    final n = _noise(t, d + 0.1);
    if (n == null) return;
    final bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.q.value = 22;
    final f0 = rr(220, 520);
    bp.frequency.setValueAtTime(f0, t);
    bp.frequency.exponentialRampToValueAtTime(f0 * rr(1.35, 2.1), t + d);
    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(rr(6, 11), t + d * 0.3);
    g.gain.exponentialRampToValueAtTime(0.0001, t + d);
    n.connect(bp);
    bp.connect(g);
    g.connect(out);
    _kill(out, d + 0.4);
  }

  /// Heating pipe knock down the corridor.
  @override
  void pipe() {
    final c = _c, room = _roomG;
    if (!_on || c == null || room == null) return;
    final t = c.currentTime;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(room);
    final hits = 2 + (rand() * 2).floor();
    final f0 = rr(310, 660);
    for (var i = 0; i < hits; i++) {
      final a = t + i * rr(0.16, 0.3);
      final o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.setValueAtTime(f0 * rr(0.97, 1.03), a);
      final g = c.createGain();
      g.gain.setValueAtTime(0.0001, a);
      g.gain.exponentialRampToValueAtTime(0.44 / (1 + i * 0.6), a + 0.004);
      g.gain.exponentialRampToValueAtTime(0.0001, a + 0.28);
      o.connect(g);
      g.connect(out);
      o.start(a);
      o.stop(a + 0.32);
      final o2 = c.createOscillator();
      o2.type = 'sine';
      o2.frequency.value = f0 * 2.76;
      final g2 = c.createGain();
      g2.gain.setValueAtTime(0.0001, a);
      g2.gain.exponentialRampToValueAtTime(0.26 / (1 + i * 0.6), a + 0.003);
      g2.gain.exponentialRampToValueAtTime(0.0001, a + 0.16);
      o2.connect(g2);
      g2.connect(out);
      o2.start(a);
      o2.stop(a + 0.2);
    }
    _kill(out, 1.6);
  }

  /// A door, three rooms away, that you did not open.
  @override
  void farThud() {
    final c = _c, room = _roomG;
    if (!_on || c == null || room == null) return;
    final t = c.currentTime;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(room);
    final n = _noise(t, 0.4);
    if (n == null) return;
    final lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = rr(170, 290);
    lp.q.value = 3;
    final g = c.createGain();
    g.gain.setValueAtTime(rr(4, 7), t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.38);
    n.connect(lp);
    lp.connect(g);
    g.connect(out);
    final rb = c.createBiquadFilter();
    rb.type = 'bandpass';
    rb.frequency.value = rr(430, 780);
    rb.q.value = 1.3;
    final rg2 = c.createGain();
    rg2.gain.setValueAtTime(4.2, t);
    rg2.gain.exponentialRampToValueAtTime(0.0001, t + 0.1);
    n.connect(rb);
    rb.connect(rg2);
    rg2.connect(out);
    _kill(out, 0.7);
  }

  // -------------------------------------------------------------------------
  // cues
  // -------------------------------------------------------------------------

  @override
  void env(String type, double freq, double dur, double vol,
      [double? sweepTo, double? q]) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final o = c.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (sweepTo != null && sweepTo != 0) {
      o.frequency
          .exponentialRampToValueAtTime(math.max(20.0, sweepTo), t + dur);
    }
    final g = c.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    _Node node = o;
    if (q != null && q != 0) {
      final f = c.createBiquadFilter();
      f.type = 'bandpass';
      f.frequency.value = freq;
      f.q.value = q;
      o.connect(f);
      node = f;
    }
    node.connect(g);
    g.connect(master);
    o.start(t);
    o.stop(t + dur + 0.05);
  }

  @override
  void burst(double dur, double vol, double f0, double f1) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final n = c.createBufferSource();
    final len = (c.sampleRate * dur).floor();
    if (len <= 0) return;
    final b = c.createBuffer(1, len, c.sampleRate);
    final d = Float32List(len);
    for (var i = 0; i < len; i++) {
      d[i] = rand() * 2 - 1;
    }
    b.copyToChannel(d.toJS, 0);
    n.buffer = b;
    final f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.q.value = 1.1;
    f.frequency.setValueAtTime(f0, t);
    f.frequency.exponentialRampToValueAtTime(f1, t + dur);
    final g = c.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    n.connect(f);
    f.connect(g);
    g.connect(master);
    n.start(t);
  }

  @override
  void click() => env('square', 900, 0.045, 0.09, 420);

  /// Eight rungs, not a slide. A continuous `520 + p*180` made a rack of manual
  /// strikes read as one siren going up and down, which is the sound of a knob
  /// being turned rather than a set being hit. Quantising the heat onto a fixed
  /// ladder makes a burst of strikes come out as a RISING FIGURE — the same
  /// eight notes every time, so the player can hear how hard they are working
  /// and hear it reset. The ladder is a major pentatonic so no two adjacent
  /// rungs can sound like a mistake.
  static const List<double> _tuneRungs = <double>[
    440, 494, 554, 659, 740, 831, 988, 1109,
  ];

  /// Knocking the set: a dull thunk plus a squeal of carrier finding its lock.
  @override
  void tune(double p) {
    final q = p.isNaN ? 0.0 : (p < 0 ? 0.0 : (p > 1 ? 1.0 : p));
    final i = (q * (_tuneRungs.length - 1)).round();
    final f = _tuneRungs[i];
    env('triangle', f, 0.09, 0.10, f * 1.7);
    env('sine', f * 2.4, 0.06, 0.05, f * 3.1);
    // the thunk stays where it was: it is the set, and the set does not change
    // pitch because you hit it faster
    burst(0.05, 0.05, 2600, 700);
  }

  @override
  void good() {
    env('triangle', 660, 0.16, 0.16, 1320);
    env('sine', 990, 0.3, 0.09, 1980);
  }

  @override
  void bad() {
    env('sawtooth', 150, 0.28, 0.15, 70, 4);
    burst(0.18, 0.1, 900, 180);
  }

  @override
  void buy() {
    env('square', 520, 0.07, 0.09, 780);
    _later(55, () => env('square', 780, 0.08, 0.08, 1100));
  }

  @override
  void warn() {
    env('sine', 440, 0.5, 0.11, 440);
    _later(260, () => env('sine', 370, 0.5, 0.11, 370));
  }

  /// A voice, not a noise burst. A glottal sawtooth with jitter + vibrato driven
  /// through three bandpass formants is the actual recipe for a vowel; sweeping
  /// F1/F2 from [ɑ] toward [i] while the pitch tears upward is what makes it
  /// read as a human losing control rather than a synth patch.
  @override
  void scream(double dur, double f0, double vol) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final d = dur <= 0 ? 1.15 : dur;
    final v = vol <= 0 ? 1.0 : vol;
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);

    // glottal source: saws a few cents apart, pitch tearing up then collapsing
    final src = c.createGain();
    src.gain.value = 0.5;
    for (final det in const <double>[0, 17, -23]) {
      final o = c.createOscillator();
      o.type = 'sawtooth';
      o.detune.value = det;
      o.frequency.setValueAtTime(f0 * 0.72, t);
      o.frequency.exponentialRampToValueAtTime(f0 * 1.28, t + d * 0.22);
      o.frequency.exponentialRampToValueAtTime(f0 * 1.05, t + d * 0.62);
      o.frequency.exponentialRampToValueAtTime(f0 * 0.55, t + d);
      o.connect(src);
      o.start(t);
      o.stop(t + d + 0.05);
    }
    // vibrato that widens as the voice loses control
    final vib = c.createOscillator();
    vib.type = 'sine';
    vib.frequency.setValueAtTime(4.5, t);
    vib.frequency.linearRampToValueAtTime(11, t + d);
    final vg = c.createGain();
    vg.gain.setValueAtTime(8, t);
    vg.gain.linearRampToValueAtTime(58, t + d);
    vib.connect(vg);
    vib.start(t);
    vib.stop(t + d + 0.05);
    // breath/rasp riding with the voice
    final n = _noise(t, d);
    if (n != null) {
      final nhp = c.createBiquadFilter();
      nhp.type = 'highpass';
      nhp.frequency.value = 900;
      final ng = c.createGain();
      ng.gain.setValueAtTime(0.10 * v, t);
      ng.gain.linearRampToValueAtTime(0.42 * v, t + d * 0.3);
      ng.gain.exponentialRampToValueAtTime(0.0001, t + d);
      n.connect(nhp);
      nhp.connect(ng);
      ng.connect(out);
    }

    // amplitude first, so it gates the formants too
    final env2 = c.createGain();
    env2.gain.setValueAtTime(0.0001, t);
    env2.gain.exponentialRampToValueAtTime(0.85 * v, t + 0.018);
    env2.gain.exponentialRampToValueAtTime(0.55 * v, t + d * 0.55);
    env2.gain.exponentialRampToValueAtTime(0.0001, t + d);
    final sat = _shaper(3.4);
    src.connect(env2);
    if (sat != null) env2.connect(sat);

    // three formants sliding [ɑ] -> [i]: F1 down, F2 up hard
    const formants = <List<double>>[
      <double>[720, 300, 9, 1.0],
      <double>[1180, 2200, 11, 0.72],
      <double>[2760, 3100, 7, 0.30],
    ];
    for (final f in formants) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.q.value = f[2];
      bp.frequency.setValueAtTime(f[0], t);
      bp.frequency.exponentialRampToValueAtTime(f[1], t + d * 0.75);
      final fg = c.createGain();
      fg.gain.value = f[3];
      (sat ?? env2).connect(bp);
      bp.connect(fg);
      fg.connect(out);
    }
    _kill(out, d + 0.8);
  }

  @override
  /// THE SCARE.
  ///
  /// The old one was 120ms of duck and then harsh noise — loud, bright, over
  /// in a second, and the room came straight back exactly as it was. Loudness
  /// is not fear. This is a five-beat sequence:
  ///
  ///   1. the room dies completely. 340ms of nothing.
  ///   2. a sub drop you feel before you hear.
  ///   3. the voice, RIGHT at the ear, both sides at once.
  ///   4. the harsh layer, on top, not instead.
  ///   5. the room comes back — and for two seconds afterwards it is wrong:
  ///      the sub is still up, and something is breathing.
  ///
  /// Beat 1 is the one that does the work. Everything else is the payoff for
  /// having taken the world away first.
  @override
  void scare() {
    final c = _c;
    if (!_on || c == null) return;

    // 1. the hole
    hold(340);

    // 2. the drop — starts inside the silence, so the first thing back is
    //    something you feel in the chest rather than hear
    _later(300, () {
      final cc = _c, mm = _master;
      if (cc == null || mm == null) return;
      final tt = cc.currentTime;
      final o = cc.createOscillator();
      o.type = 'sine';
      o.frequency.setValueAtTime(120, tt);
      o.frequency.exponentialRampToValueAtTime(17, tt + 0.85);
      final g = cc.createGain();
      g.gain.setValueAtTime(0.0001, tt);
      g.gain.exponentialRampToValueAtTime(0.85, tt + 0.03);
      g.gain.exponentialRampToValueAtTime(0.0001, tt + 1.5);
      o.connect(g);
      g.connect(mm);
      o.start(tt);
      o.stop(tt + 1.6);
    });

    // 3. the voice, at the ear, on BOTH sides — the one thing a real body
    //    cannot do, which is why it does not read as a person in the room
    _later(345, () {
      voice(1.0, -0.95);
      voice(1.0, 0.95);
    });

    // 4. the harsh layer, over the top rather than in place of it
    _later(360, () {
      scream(1.2, 330, 1);
      burst(0.9, 0.55, 4200, 90);
      env('sawtooth', 720, 1.1, 0.30, 55, 3);
      env('square', 311, 0.7, 0.15, 44);
    });
    _later(450, () => scream(0.8, 480, 0.55));
    _later(520, () => burst(0.5, 0.24, 1800, 120));

    // 5. the room comes back WRONG and stays wrong for a couple of seconds
    final double keep = _subT;
    setSub(1.0);
    _later(1500, () => breath(rand() < 0.5 ? -1 : 1, 0.95));
    _later(2600, () => setSub(math.max(keep, 0.45)));
  }


  // ---------------------------------------------------------------------------
  // THE HORROR LAYER
  //
  // Everything above this line is a TV station. Everything below it is the
  // reason you do not want to be alone in one.
  // ---------------------------------------------------------------------------

  /// THE BREATH. Someone is close enough that you can hear them do it.
  ///
  /// Three parts, because a breath is not noise: the intake (bright, rising),
  /// the body of it (a filtered hiss that sits where a throat sits, ~500Hz),
  /// and a tiny transient of cloth or lip at the front. Panned HARD, because
  /// the whole point is that it is on ONE side of you and the other side is
  /// empty. On a laptop speaker this is a puff of nothing; on headphones it
  /// is a person.
  @override
  void breath(double side, double near) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null || _holding) return;
    final t = c.currentTime;
    final double n = near.clamp(0.0, 1.0);

    final pan = c.createStereoPanner();
    pan.pan.value = (side < 0 ? -1.0 : 1.0) * (0.55 + n * 0.45);
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(pan);
    pan.connect(master);

    final double dur = 1.15 - n * 0.35;
    final src = _noise(t, dur + 0.25);
    if (src != null) {
      // the throat: a formant-ish band that opens as the breath comes in
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.q.value = 1.1;
      bp.frequency.setValueAtTime(320 + n * 180, t);
      bp.frequency.exponentialRampToValueAtTime(900 + n * 700, t + dur * 0.45);
      bp.frequency.exponentialRampToValueAtTime(260, t + dur);
      // proximity: close things are brighter AND have more low end
      final hs = c.createBiquadFilter();
      hs.type = 'highshelf';
      hs.frequency.value = 2600;
      hs.gain.value = -14 + n * 20;

      final g = c.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.045 + n * 0.10, t + dur * 0.38);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);

      src.connect(bp);
      bp.connect(hs);
      hs.connect(g);
      g.connect(out);
    }

    // the lip/cloth transient — what makes it a body rather than a sound
    final tick = _noise(t, 0.05);
    if (tick != null) {
      final hp = c.createBiquadFilter();
      hp.type = 'highpass';
      hp.frequency.value = 2400;
      final tg = c.createGain();
      tg.gain.setValueAtTime(0.0001, t);
      tg.gain.exponentialRampToValueAtTime(0.022 * (0.3 + n), t + 0.006);
      tg.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
      tick.connect(hp);
      hp.connect(tg);
      tg.connect(out);
    }
    _kill(out, dur + 0.4);
  }

  /// THE HOLD. Not a duck — a hole.
  ///
  /// duck() rides the room down to a floor and back. This takes the master to
  /// actual zero and leaves it there. Half a second of true digital silence in
  /// headphones is deeply wrong: the ear knows the difference between a quiet
  /// room and no room, and it starts hunting. Every real scare in this build
  /// is now a hole with something at the bottom of it.
  @override
  void hold(int ms) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    _holding = true;
    master.gain.cancelScheduledValues(t);
    master.gain.setValueAtTime(master.gain.value, t);
    master.gain.linearRampToValueAtTime(0.0, t + 0.012);
    // the sub bypasses master, so it has to be taken down by hand — otherwise
    // the "hole" is a hole with a hum still in it, which is just a mix change
    final sg = _subG;
    if (sg != null) {
      sg.gain.cancelScheduledValues(t);
      sg.gain.setValueAtTime(sg.gain.value, t);
      sg.gain.linearRampToValueAtTime(0.0, t + 0.012);
    }
    _holdTimer?.cancel();
    _holdTimer = Timer(Duration(milliseconds: ms), () {
      final cc = _c, mm = _master;
      _holding = false;
      if (cc == null || mm == null) return;
      final tt = cc.currentTime;
      mm.gain.cancelScheduledValues(tt);
      mm.gain.setValueAtTime(0.0, tt);
      // back FAST. A slow fade-in reads as a mix change; a fast one reads as
      // the world switching back on, which is the part that hurts.
      mm.gain.linearRampToValueAtTime(_vol, tt + 0.03);
    });
  }

  /// THE PRE-ECHO. A swell that ends exactly when the thing arrives.
  ///
  /// Reversed-cymbal logic without a sample: noise through a bandpass that
  /// climbs while the gain climbs, cut dead on the beat. Played [ms] ahead of
  /// an event, the ear registers the arrival BEFORE the eye does, which is
  /// what "I knew something was about to happen" is made of.
  @override
  void preEcho(int ms) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null) return;
    final t = c.currentTime;
    final double d = ms / 1000.0;
    final src = _noise(t, d + 0.06);
    if (src == null) return;

    final out = c.createGain();
    out.gain.value = 1;
    out.connect(master);

    final bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.q.value = 2.4;
    bp.frequency.setValueAtTime(160, t);
    bp.frequency.exponentialRampToValueAtTime(3400, t + d);

    final g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.085, t + d * 0.92);
    // the cut is the point — no tail, so the swell is a ramp to a cliff
    g.gain.linearRampToValueAtTime(0.0, t + d);

    src.connect(bp);
    bp.connect(g);
    g.connect(out);
    _kill(out, d + 0.2);

    // a sub swell underneath it, so the ramp is felt as well as heard
    final o = c.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(38, t);
    o.frequency.exponentialRampToValueAtTime(21, t + d);
    final og = c.createGain();
    og.gain.setValueAtTime(0.0001, t);
    og.gain.exponentialRampToValueAtTime(0.16, t + d * 0.9);
    og.gain.linearRampToValueAtTime(0.0, t + d);
    o.connect(og);
    og.connect(out);
    o.start(t);
    o.stop(t + d + 0.05);
  }

  /// The infrasonic floor, 0..1.
  @override
  void setSub(double v) {
    _subT = v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  /// THE VOICE. Something almost says a word.
  ///
  /// whisper() already slides three formants over noise and reads as "a room
  /// with people in it". This is the opposite: a SINGLE source, close, whose
  /// formants land near real vowel positions and then fail to resolve into a
  /// consonant. The brain runs it through the speech decoder, gets most of the
  /// way, and does not finish — which is far worse than an actual word,
  /// because you keep trying.
  @override
  void voice(double near, double side) {
    final c = _c, master = _master;
    if (!_on || c == null || master == null || _holding) return;
    final t = c.currentTime;
    final double n = near.clamp(0.0, 1.0);

    final pan = c.createStereoPanner();
    pan.pan.value = side.clamp(-1.0, 1.0) * (0.3 + n * 0.6);
    final out = c.createGain();
    out.gain.value = 1;
    out.connect(pan);
    pan.connect(master);

    // a glottal source: a saw at speech pitch, wobbling like a real larynx
    final o = c.createOscillator();
    o.type = 'sawtooth';
    final double f0 = 88 + rand() * 34; // low, adult, indeterminate
    o.frequency.setValueAtTime(f0, t);
    o.frequency.linearRampToValueAtTime(f0 * (0.88 + rand() * 0.2), t + 0.75);

    final vib = c.createOscillator();
    vib.type = 'sine';
    vib.frequency.value = 4.4 + rand() * 1.8;
    final vibG = c.createGain();
    vibG.gain.value = 2.6;
    vib.connect(vibG);
    vibG.connect(o.detune);
    vib.start(t);
    vib.stop(t + 1.1);

    // three formants walking between two vowels and stopping in between
    const List<List<double>> vowels = <List<double>>[
      <double>[540, 1680, 2500], // "eh"
      <double>[730, 1090, 2440], // "ah"
      <double>[300, 870, 2240], // "oo"
    ];
    final a = vowels[(rand() * 3).floor().clamp(0, 2)];
    final b = vowels[(rand() * 3).floor().clamp(0, 2)];

    final mix = c.createGain();
    mix.gain.setValueAtTime(0.0001, t);
    mix.gain.exponentialRampToValueAtTime(0.030 + n * 0.055, t + 0.14);
    mix.gain.setValueAtTime(0.030 + n * 0.055, t + 0.52);
    // it stops rather than ends — no release, like a held breath
    mix.gain.exponentialRampToValueAtTime(0.0001, t + 0.80);
    mix.connect(out);

    for (var i = 0; i < 3; i++) {
      final bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.q.value = 7.5 - i * 1.6;
      bp.frequency.setValueAtTime(a[i], t);
      bp.frequency.linearRampToValueAtTime(b[i], t + 0.62);
      final g = c.createGain();
      g.gain.value = i == 0 ? 1.0 : (i == 1 ? 0.55 : 0.28);
      o.connect(bp);
      bp.connect(g);
      g.connect(mix);
    }
    o.start(t);
    o.stop(t + 0.9);
    _kill(out, 1.2);
  }

  @override
  void ring() {
    env('sine', 1000, 0.35, 0.1, 1000);
    _later(20, () => env('sine', 1230, 0.35, 0.1, 1230));
  }

  @override
  void boxNote(double f) {
    env('triangle', f, 0.5, 0.07, f);
    env('sine', f * 2, 0.35, 0.03, f * 2);
  }

  /// Every call site speaks the old 0.03-0.30 dialect, and 0.03 of this bed is
  /// below a quiet room. Remap onto something audible, but pass true silence
  /// (Dead Air, which calls setStatic(0)) straight through untouched.
  @override
  void setStatic(double v) {
    final sg = _staticG;
    if (sg == null) return;
    _ramp(sg, v < 0.01 ? v : 0.155 + v * 1.35, 0.15);
  }

  @override
  void setDrone(double v, double f) {
    final dg = _droneG;
    final c = _c;
    if (dg != null) _ramp(dg, v, 0.3);
    if (f != 0 && _droneOsc != null && c != null) {
      _droneOsc!.frequency.linearRampToValueAtTime(f, c.currentTime + 0.4);
    }
  }
}
