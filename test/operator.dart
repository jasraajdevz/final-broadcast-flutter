// A PAIR OF HANDS FOR THE TEST HARNESSES.
//
// Not a test. `flutter test` only collects *_test.dart, so this is a helper.
//
// When the rig landed, every harness in the suite drove a night by ticking the
// runtime and pressing counter keys and NEVER TOUCHING THE DESK — which was a
// complete description of playing the old game, and under the new core is a
// description of a man watching a transmitter drift off frequency with his
// hands in his lap. They were not wrong about the mechanisms they guard; they
// were simulating a game that no longer exists.
//
// So rather than loosen a hundred assertions, the harnesses get an operator.
//
// This one has HUMAN REFLEXES, and that has already been necessary once: the
// first version serviced the desk every frame — thirty corrections a second —
// which nailed every needle to its mark, held strain permanently under the
// dread hold point, and flatlined dread at zero for 99.9% of every night.
// dread_test caught it. That is the same omniscience failure the balancing sim
// hit, arriving from a completely different direction.
//
// It is still not a model of a real player and must never be used to decide
// whether a night is FAIR — that is what test/desk_test.dart is for, with its
// divided attention and its notice delays. This exists so that a test about
// blood, or the ninth key, or what the room sounds like, is not also
// accidentally a test of whether somebody remembered to hold the drive up.

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/desk.dart';

const double _reflex = 0.28;
final Map<AnomalyRuntime, double> _nextHand = <AnomalyRuntime, double>{};

/// Keeps the transmitter inside its limits for one frame. Call once per frame,
/// before `tick`. Services the most urgent thing only, so it costs one action
/// at a time in the way a player's hands do.
///
/// Returns whether it actually put a hand on something, so demand_test can
/// count desk work as work — which it is, and which the instrument's first
/// version did not, because it defined "something to do" as "an anomaly is on
/// the tube" and that was a complete description of the old game only.
bool mindTheDesk(AnomalyRuntime r) {
  final rig = r.rig;
  if (rig.voided) return false;
  final now = rig.t;
  if ((_nextHand[r] ?? 0) > now) return false;
  _nextHand[r] = now + _reflex;

  if (rig.logDue <= 0) {
    rig.sign();
    return true;
  }
  if (rig.plate > 88) {
    rig.trim(-1);
    return true;
  }
  if (rig.carrier < kLowPower + 4 && rig.plate < 86) {
    rig.trim(1);
    return true;
  }
  if (rig.modulation < 50 - kModGreen + 2) {
    rig.nudge(1);
    return true;
  }
  if (rig.modulation > 50 + kModGreen - 2) {
    rig.nudge(-1);
    return true;
  }
  if (rig.carrier > kLowPower + 20 && rig.plate > 62) {
    rig.trim(-1);
    return true;
  }
  return false;
}
