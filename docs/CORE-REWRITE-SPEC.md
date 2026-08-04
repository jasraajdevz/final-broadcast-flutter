# FINAL BROADCAST — THE FINAL
## Implementable specification for the new core

Repo: `/Users/jasdevz/Downloads/final_broadcast_flutter` (verified 30,924 lines across `lib/` + `test/`, not 26k)

---

## 1. THE ONE-SENTENCE PITCH

You are the duty engineer on a 5 kW transmitter from 23:00 to 06:00, alone, holding five needles inside five bands with two hands while eight things climb into the signal and do impossible readings to your instruments — and every procedure that clears one of them breaks a different part of the machine, so the whole night is deciding which meter you are willing to lose next, against a four-drum mechanical counter bolted to the master recorder that ticks up every tenth of a second the county is hearing something that is not you.

---

## 1b. WHICH DESIGN WON, AND EVERY JUDGE DISAGREEMENT RESOLVED

**Ballots:** `brief` → D1 (THE FINAL). `feel` → D3 (DEAD AIR). `build` → D2 (HOLD THE CARRIER).
**Summed scores:** D4 = 22.5, D1 = 22, D3 = 21, D2 = 19.

**SPINE: DESIGN 1, THE FINAL.** Not because it has the highest total (D4 does), but because the `brief` judge is the one scoring against the user's own decoded requirements, and requirements #1 and #2 are the ones the user has now stated twice. D4 won on points while winning no ballot — it is a ranked-second-everywhere design, which is exactly the profile of something that satisfies nobody's actual complaint. D1 is the only design where the crowd comes from **coupling** (one control fought over by two systems; eight procedure keys that each damage a named third system) rather than from running more timers side by side.

D1's one real weakness is buildability (`build` gave it 5/10). That is the weakness a spec can fix, and this spec fixes it by importing D2's reuse discipline as a hard constraint and cutting D1's scope by roughly 40%. The disagreements, resolved one at a time:

| # | Disagreement | Resolution | Why |
|---|---|---|---|
| **1** | `brief` says steal D2's brownout-as-**frequent** state (fire the 4× room render during every lockout). `feel` says explicitly do NOT — reserve it for **sustained** failure, because frequency without escalation habituates. | **Threshold, not frequency.** The 4× in-room render fires on ≥ **3.0 s of continuous off-air**, which is exactly a lockout or a dead-air spiral and nothing else. It escalates within a night: threshold drops 0.5 s per occurrence to a floor of 1.5 s, and the render scale ramps 2.2× → 4.0× over the duration. Expected 1–2/night competent, 4–6/night sloppy. | Satisfies `brief` (it fires during lockout, which is when D1 demands undivided attention) and `feel` (rare, earned, escalating — never a low-health vignette). |
| **2** | `brief` says steal D3's fists as the identification channel. `build` calls the fist mechanic **disqualifying** — not headlessly assertable, and its own mitigation is a second complete implementation. | **Fists are a redundant shortcut, never a gate.** Primary ID is the **panel twitch** (D1, visual, on the instrument about to be attacked) which narrows 8 → a **pair**. The fist separates the pair for free *if you are listening*. If you cannot hear or cannot tell, the **monitor rotary** resolves it in 0.90 s. Fists are authored as `List<double>` on/off intervals and **the same array** drives the audio (`env()`/`boxNote()`) and the visual twin (AUDIO VU needle envelope at `room.dart:880-908` + ON AIR filament) — one implementation, two channels. | `build`'s objection was double implementation and untestability; both vanish when the array is the single source. `brief` and `feel` get the user's literal word "FIST". The test plan asserts a deaf run lands within 12% of the hearing run. |
| **3** | `brief` says D1's "instruments lie above 70 dread" is *worse* than D3's rotary and the rotary should replace it. `feel` wants both. | **Both, stacked.** Instruments lie above 70 dread → the twitch becomes unreliable → the rotary becomes the only ground truth → the rotary is where the faces are. The difficulty curve physically drags the player's eye onto the monster. | `feel` is right that they compound. This is the single best structural inversion available and it costs nothing extra once the rotary exists. |
| **4** | `feel` says D4's six 5-second junction freezes are 7.4% of the run in a menu and evaporate dread. `brief` docks D4 for the same. Nobody defends them. | **The junction draft is cut entirely.** No in-night menus, no freezes, no card drafting. The meta is D1's **pre-shift triage board only**. | Unanimous. |
| **5** | `build` says D1's triage board is "an entire second screen" and a scope problem. `feel` calls it the best retention sentence in the set and the fix for D3's cliff. | **Kept, scoped to one screen with no new navigation.** Six rows on the existing sign-on screen, rendered with the row idiom lifted from the (deleted) `ui/rack.dart`. No tabs, no sub-panels. 40 minutes against 100 minutes of demand. | The board is the only thing in any design that lets the player *author which monsters show up*. Cutting it loses requirement #5. Scoping it to one list costs ~180 lines. |
| **6** | D1 lists six live systems; `build` calls six coupled integrators the hardest tuning problem in the set. | **Cut from six to five continuous systems + the eight.** D1's BEACON and EAS sub-clocks are deleted; **THE BOOK** becomes one clock and is implemented by **reusing `checks.dart` verbatim** (277 lines, already tickable, already tested by `checks_test.dart`) with three constant changes. The hand-entry-of-meter-readings UI is deleted and replaced by a rule that needs no UI at all (§2.5). | Honours `build`'s "keep checks.dart" steal and removes the biggest new-simulation surface D1 had. |
| **7** | D4 deletes two-stage/coupled encounter modifiers; `build` calls that a gratuitous loss of working tested code with a guarded invariant (`anomalies.dart:391-402`). | **Kept, and they now cost more.** TWO-STAGE = the same procedure runs twice, so you pay its subsystem damage twice. COUPLED = you pay both procedures' damage. | Free content that gets *better* under the new economy. |
| **8** | D2's SPACE-pumping: `brief` calls it the clicker re-costumed and scores it 4. `build` scores D2 9 for reuse. | **The pump is dead. No key anywhere in this game makes a resource go up.** D2 contributes only its reuse discipline, its brownout, its camera-adjacent thinking and its distribution-based test contract. | The user has asked twice. A refill key is a clicker with a skill gate. Non-negotiable. |
| **9** | `feel` wants the ledger strictly one-way (D3's odometer purity). `brief` wants D4's all-green reward so the player has something to chase. | **The drums never run backward. The ceiling rises instead.** Every 12.0 continuous IN-SPEC seconds adds **+1.0 s to the licence allowance**, capped at +40.0. Display reads `OFF AIR 041.2 / 186.0`. | Both get what they wanted. "Watching an eleven-second green stretch break because the reel tail arrived" is the near-miss shape D1 was missing, and the counter is still monotonic. |
| **10** | All three judges name ATTACHMENTS (D4), THE RERUN's ghost inputs (D4), and the death reconstruction (D4/D1) as steals. | **All three adopted wholesale.** Attachments are implemented by re-pointing the existing `sabotageTick` (`anomalies.dart:1746-1885`), exactly as `build` specified. | Unanimous across three independent lenses. |
| **11** | Not raised by any judge, found by inspection: **`lib/src/desk.dart` (334 lines) already exists**, is a prior attempt at this exact rewrite, is **orphaned** (nothing in `lib/` imports it), and ships with `test/desk_test.dart` (301 lines) and `test/demand_test.dart` — a complete divided-attention operator sim. | **`desk.dart` becomes the new core module.** Its `Attach`/`Rail` model, `strain`/`busy`/`wrongCount`/dread-breathing model, `shiftRamp()`, and its night-curve *shapes* are kept. Its `push()`/`kPushCarrier` refill is deleted — that is the D2 failure mode, and `desk.dart:104-109` already records the sim catching it ("The design was clicking with a new name"). | This is a ~600-line head start on exactly what `build` demanded be written first, including the operator-notice model at `desk_test.dart:117-120`. |

---

## 2. THE CONCURRENT SYSTEMS

All rates are per real second. The tick is `tick(double dt)` at 60 fps with `dt` clamped to 0.1 (existing behaviour, `anomalies.dart:2643`). `rr(a,b)` = uniform random in [a,b]. `d01` = `s.dread / 100`. `np` = `nightPressure(s)` = `n/(n+4)`, `n = max(0, night-1)` (existing, `encounter.dart:62-65`).

### 2.1 THE FINAL — plate current

```dart
double plate      = 1.700;  // amps, the reading
double drive      = 0.620;  // 0..1, the control position
double plateNoise = 0.0;    // OU process
double plateBias  = 0.0;    // signed slow drift
double biasFlipIn = 0.0;    // seconds until the bias reverses
double tripHeld   = 0.0;    // seconds above 2.05
int    overloads  = 0;      // 0..3, printed on the panel all night
bool   contactor  = true;   // false = LOCKOUT
```

**Update per tick:**
```
plateSet  = 1.700 + 0.90 * (drive - 0.620)
biasFlipIn -= dt; if (biasFlipIn <= 0) { biasSign = ±1; biasFlipIn = rr(16,42); }
kDrift    = (0.0075 + 0.0009*nightsSinceRetube).clamp(0, 0.0165)
            * (1 + 0.9*d01) * segDriftMul[seg] * driftDebt
plateBias += biasSign * kDrift * dt
plateNoise += -plateNoise/12.0*dt + 0.030*sqrt(dt)*gauss()   // OU, τ=12s, sd≈0.073 A
target    = plateSet + plateBias + plateNoise + (pumpRunning ? 0.060 : 0)
                                              + (cutActive ? -0.600 : 0)
plate    += (target - plate) * dt / 0.35      // 0.35 s mechanical lag
```
`driftDebt` starts 1.00 and gains **+0.12 permanently per missed log**, capped ×2.50.
`segDriftMul` by segment 0..6 = **1.00, 1.08, 1.16, 1.24, 1.32, 1.40, 1.48**.

**Bands:** green **1.55–1.85**; amber 1.35–1.55 and 1.85–2.05; `LOW DRIVE` below **1.35**; trip at **≥ 2.05 held 0.60 s**.

**Input:** `A` / `D` (also Left/Right). **Tap** (< 0.12 s held) = ±0.060 drive = ±0.054 A. **Held** = 0.30 drive/s. Edge → centre ≈ 2.8 taps. Mouse: drag the DRIVE knob at **(300, 570) r=26**, 1 px = 0.006 drive.

**Cost of servicing:** your left hand leaves `W`/`S` (gain) and `G` (pump). Any drive change moves reflected power by the square law *immediately* (§2.2) — this is the coupling that is the whole design.

**Failure:** `plate ≥ 2.05` for 0.60 s → **OVERLOAD RECYCLE**: carrier off 2.5 s, `overloads++`, **+2.5 s on the drums**. The **4th** trip (shared count with VSWR) → **LOCKOUT**: `contactor = false`, drums run at 1.0/s, hard deadline 30.0 s. Manual step-start: hold `G` 1.5 s (blower), hold `ENTER` 2.0 s (plate), then walk drive 0.00 → 0.62 with `D` (2.07 s at 0.30/s). Minimum 5.6 s of undivided attention; realistically 11 s.

---

### 2.2 THE LINE — reflected power and coax pressure

```dart
double refl      = 34.0;  // watts, derived
double psi       = 5.00;  // coax pressure
double lineFault = 1.00 + 0.55 * nightsSinceSweep.clamp(0,5);  // 1.00 .. 3.75
double iceMul    = 1.00;  // ramps to card.ice across the night
double reflSpike = 0.0;   // from DEGAUSS, decays 22 W/s
double leakRate  = 0.0;   // psi/s, > 0 while a leak is open
double leakIn    = rr(110,150);
```

**Update per tick:**
```
fwd        = 5.0 * clamp(plate / 1.700, 0, 1.6)          // kW
refl       = 34.0 * lineFault * pow(fwd/5.0, 2) * iceMul + reflSpike
reflSpike  = max(0, reflSpike - 22.0*dt)
iceMul    += (cardIce - iceMul) * dt / 240.0
lineFault += 0.0022*dt                                    // baseline, never decreases
if (psi < 2.00) lineFault += 0.040*dt                     // IRREVERSIBLE for the night
psi       += (pumpHeld ? 0.55 : 0)*dt - leakRate*dt
leakIn    -= dt; if (leakIn <= 0) { leakRate = rr(0.06,0.25)*leakMul; leakFor = rr(8,22); leakIn = rr(seg.leakLo, seg.leakHi); }
```
Leak interval by segment 0..6: **rr(110,150), rr(100,140), rr(90,130), rr(80,120), rr(72,108), rr(66,98), rr(60,90)**. `leakMul = 0.50` if the DEHYDRATOR job is at full health.

**Bands:** `psi` green **4.0–6.0**, red **< 2.0**. `refl` green **< 120 W**, amber 120–220, trip **≥ 220 W held 0.35 s**.

**Input:** `G` **held** = pump, +0.55 psi/s (≈ 4 s to recover 2 psi), and adds +0.060 A of ripple to the plate while running. `A` (foldback) is the only *fast* VSWR fix — refl scales with `fwd²`, so dropping drive 0.62 → 0.40 cuts refl by 47% and drags plate to 1.50 A, one amber band from `LOW DRIVE`. Mouse: press-and-hold the pump lever at **(450, 552, 22, 44)**.

**Cost of servicing:** pumping ripples the plate you just settled; folding back trades a VSWR trip for a low-power tariff. **One control, two systems, opposite goals.**

**Failure:** `refl ≥ 220 W` 0.35 s → **VSWR TRIP**, identical to an overload recycle and **spends one of the same three**. `psi < 2.0` → `lineFault` climbs 0.040/s permanently for the night; 137 s of low pressure alone reaches the trip threshold at nominal power.

---

### 2.3 THE CHAIN — modulation

```dart
double mod      = 92.0;   // percent
double gain     = 0.500;  // 0..1
double program  = 0.0;    // current source deviation
double stepIn   = rr(7,11);
double overHeld = 0.0;    // seconds above 112
double underAcc = 0.0;    // cumulative seconds below 60
double limiter  = 12.0;   // 18.0 if REBUILD THE LIMITER is at full health
```

**Update per tick:**
```
stepIn -= dt;
if (stepIn <= 0) { program = rr(-40, 40) * snowNarrow; stepIn = rr(seg.stepLo, seg.stepHi); }
raw      = 92.0 + program + (gain - 0.500) * 80.0
dev      = raw - 92.0
absorbed = min(dev.abs(), limiter)
mod      = 92.0 + sign(dev) * (dev.abs() - absorbed*0.85)
if (toneActive) mod = 100.0            // 1 TONE pins it for 3.0 s
```
Program step interval by segment 0..6: **rr(7,11), rr(6.5,10.5), rr(6,10), rr(5.5,9), rr(5,8.5), rr(4.5,8), rr(4,7)**.
A ±10 step surfaces as ±1.5 on the meter (constant harmless flicker). A ±36 step surfaces as ±25.8 (mod 66 or 118 — act now). ~68% of steps are absorbed entirely. **Learning which flickers are real is the skill.**

**Bands:** green **85–100**. `OVERMOD` above 100. `LOSS OF AUDIO` below 60.

**Input:** `W` / `S`. Tap = ±3.5 points of `mod`. Held = 22 points/s. Mouse: drag the GAIN fader at **(380, 548, 18, 48)**.

**Cost of servicing:** `W`/`S` and `A`/`D` are the same hand. You cannot trim drive and ride gain in the same 0.4 seconds.

**Failure:** `mod > 112` for 1.5 s → **SPLATTER VIOLATION**, flat **+25.0 s on the drums**, re-armable after 6.0 s. `mod < 60` cumulative 8.0 s → **+1.0 dread/s** and the next banish window ×0.85. Both directions punish — this is why it can never be automated away.

---

### 2.4 THE MACHINES — two decks, the reel, the seam

```dart
int    running   = 0;                 // 0 = deck A, 1 = deck B
List<double> reelLeft   = [rr(112,124), 0.0];
List<bool>   threaded   = [true, false];
double threadHeld = 0.0;              // R held, needs 2.2 s continuous
int    shelf     = 5;                 // reels remaining after the two decks
double deadAir   = 0.0;               // seconds of continuous silence
```

**Update:** `reelLeft[running] -= dt` while `contactor && !deadAir`. `deadAir += dt` when the running reel hits 0 and nothing has rolled.
Reel length by segment 0..6: **rr(112,124), rr(106,120), rr(100,116), rr(96,112), rr(92,108), rr(88,102), rr(84,96)**, `+35.0` if REEL MOTOR is at full health. Mean ≈ 103 s → **≈ 4.7 changeovers/night**.

**TAIL:** the last **6.0 s** — the take-up spool visibly thins, the tail leader slaps (audible), and the deck's own lamp flashes.

**Input:** `R` **held 2.2 s continuous** threads the idle deck. **While threading, `A`/`D` and `W`/`S` are dead.** Release early → the tape spills, hold restarts from zero. Then `SPACE` rolls it.

**THE SEAM — the near-miss engine.** `SPACE` is scored against `reelLeft[running]`:
- `|reelLeft| ≤ 0.70 s` → **CLEAN SPLICE**. One thump, **0.0 on the drums**, and the room's noise floor drops 4 dB for 3.0 s. This is the only purely-good sound in the game.
- Early by X s → the new reel is shortened by **0.5 × X** (hoarding safety is punished; you are forced to cut it fine).
- Late by Y s → **Y seconds of DEAD AIR at 1.0/s on the drums**, audible as a person's voice going out over the county.

Mouse: press-and-hold the idle spool at **(750, 572) r=17** or **(830, 572) r=17** to thread; click the ROLL plate at **(790, 596, 40, 12)**.

**Cost of servicing:** 2.2 s with your left hand gone and both analogue controls dead, at a moment you must *predict*. This is the only system with a fixed knowable deadline, so it is the beam every other clock is measured against.

**Failure:** DEAD AIR — **1.0/s on the drums**, **+9.0 dread/s**, and after **4.0 s of continuous silence DEAD AIR (the entity) manifests with no telegraph and no panel twitch**. Silence is the only thing in the design that both spends the licence and summons something.

---

### 2.5 THE BOOK — the transmitter log

**Implementation: reuse `lib/src/checks.dart` unchanged except three constants.** `CheckRuntime`, `pending`/`held`/`signing`, `CheckEventKind{raised, signed, missed, falseEntry}`, `resetForNight()` — all kept.

```dart
// checks.dart changes:
kSignSeconds       : 1.45 -> 1.20     // five live systems; 1.45 is a coin flip
nextCheckGap(s,d)  : rr(14,30) -> rr(seg.checkLo, seg.checkHi)
                     * (1 - 0.22*d01)
kCheckWindow       : 5.0 (7.0 if SERVICE THE LOGGER is at full health)
```
Check interval by segment 0..6: **rr(24,34), rr(22,32), rr(21,31), rr(20,30), rr(19,28), rr(18,27), rr(18,26)**.

**Input:** `ENTER` held **1.20 s**. **Digits 1–8 are dead for the whole hold.** Pressing a counter key abandons the signature (existing behaviour, `anomalies.dart:1284`). Mouse: press-and-hold the book at **(860, 640, 60, 50)**.

**THE SCOPE CUT THAT KEPT D1'S HORROR:** there is no numeric entry UI. Instead — **you may only legally sign while `plate` and `refl` are both in their green bands.** Completing a signature out of band is a **FALSE ENTRY**: you wrote down a number you knew was wrong. That is D1's "enter what they say" reduced to a rule with zero new interface, and it makes the log a *third* thing pulling on the drive control.

**Cost of servicing:** 1.20 s with your answering hand off the number row, at an interval deliberately incommensurable with every other clock.

**Failure:** missed check → **+20.0 s on the drums**, `+4 dread`, and **+0.12 permanent `driftDebt`** (cap ×2.50) — missing logs does not hurt now, it makes 04:00 onward unplayable. False entry → **+8.0 s**, `addMark(Mark.debt)`.

---

### 2.6 THE EIGHT — what is in the signal

The existing scheduler is kept **whole**. Verified: `beginWarn`, `manifest`, per-visit window stacking (`anomalies.dart:1205-1210`), cold-open roll (`1142-1146`), telegraph (`encounter.dart:204-223`), two-stage/coupled (`1332`, `391-402`), and the calm/aftermath/else branches (`3079-3111`) contain **zero** economy reads. Only six blocks touch the economy and all six are deleted (§4).

**Arrival gap** replaces `anomIntervalMean`:
```
gapMean(seg) = [22.0, 20.7, 19.3, 18.0, 16.7, 15.3, 14.0][seg]
             * (1 - 0.25*np) * (1 - 0.30*d01)
             * cardOf(s).gap * recordGapMul(s)
gap = gapMean * rr(0.86, 1.18)          // existing jitter
```
Opening ease `kNightOpening = [2.05, 1.62, 1.34, 1.15]` on the first four arrivals of a shift — **kept**. Surge branch kept, and `afterScare`/`afterBanish` are finally **passed true** at the six `scheduleNext()` call sites (the dead parameter from `encounter.dart:303-311`).

**Answer window:** `window(seg) = [6.50, 6.17, 5.83, 5.50, 5.17, 4.83, 4.50][seg] * cardOf(s).window * recordWindowMul(s)`, floor **4.20 s**. Per-visit multipliers (first sighting ×1.25, cold ×1.42, two-stage ×1.20, coupled ×1.65) all kept.

**Input:** digits **1–8**, single press. Mouse: the deck keycaps. Bindings unchanged — `snow→4 DEGAUSS, sleep→5 CUT, vert→3 V-HOLD, dead→1 TONE, card→2 BARS, rerun→6 TAPE, niel→7 PATTERN, call→8 HOOK`. Zero relearning.

**THE TELEGRAPH IS THE PANEL TWITCH.** Duration 1.6–2.6 s (per-entity, from `encounter.dart:110-183` profile values). The instrument the entity is about to attack shows a **physical impossibility**. There is no telegraph toast, no tell string, no bezel banner.

**THE PAIRS.** Four instruments, two attackers each. The twitch names the *instrument*, i.e. narrows 8 → 2.

| Instrument | Pair | The twitch |
|---|---|---|
| **THE FINAL** | `vert` (3), `snow` (4) | `vert`: the plate needle and the odometer drums both **roll** (reuse `gVertRoll`). `snow`: the plate reads **1.70 A with the drive at zero**. |
| **THE LINE** | `dead` (1), `call` (8) | `dead`: **`psi` RISING with the pump off and every valve shut** — something is pushing air back up the coax from the mast end, and the mast is a mile out in a field. `call`: **`refl` climbing with the plate contactor visibly open**. |
| **THE CHAIN** | `card` (2), `rerun` (6) | `card`: **140% modulation on a chain muted at the source**. `rerun`: the MOD needle **repeats its own envelope 0.5 s late**. |
| **THE BOOK** | `sleep` (5), `niel` (7) | `sleep`: `logDue` **counts up**. `niel`: **the page is already filled in, in your handwriting**. |

**Resolving the pair:** the **fist** (§5.3) separates them free if you are listening. Otherwise park the **monitor rotary** (§2.8) on the carrying source for **0.90 s** — during which the entity's baked face plate renders at **full 422×278**, eyes open. Above 70 dread the instruments lie and the twitch is unreliable, so the rotary becomes the only ground truth.

**ON A CORRECT PRESS:** the entity is cleared. It pays **nothing** — there is no currency. It costs you the procedure's damage:

| Key | Procedure | Damage |
|---|---|---|
| 1 | TONE | `mod` pinned at 100% for **3.0 s** (gain control dead) |
| 2 | BARS | program video killed **4.0 s** — the tube shows bars, so no tail leader, no picture |
| 3 | V-HOLD | `plate += 0.150 A` instantly |
| 4 | DEGAUSS | `reflSpike += 90.0 W`, decaying 22 W/s |
| 5 | CUT | forward power ×0.50 for **5.0 s** (plate −0.60 A → `LOW DRIVE` unless you push drive, and it snaps back when it ends). ×0.80 if RETUBE is at full health |
| 6 | TAPE | **−25.0 s** off the running reel |
| 7 | PATTERN | vents **1.4 psi** |
| 8 | HOOK | **the room goes deaf for 20.0 s** — no fists, no tail flap, no leak hiss, no heartbeat |

**A WRONG PRESS** costs you that key's damage, adds no dread beyond `+3`, produces **no toast of any kind**, and the window keeps draining. Two wrong keys in one window is where a night turns. `nightWrongs` and the `'DOES NOTHING TO THIS ONE'` / `'PRESS M'` pair (`anomalies.dart:1384-1388`) are deleted at the source.

**ON A MISS:** it **ATTACHES**.

---

### 2.7 ATTACHMENTS — what a miss leaves behind

Implemented by re-pointing the existing `sabotageTick` (`anomalies.dart:1746-1885`), which already runs per-entity distinct ongoing pressure on per-entity cadences. Each of the eight sabotages a **different system than the one it attacked**, so a miss makes you *more crowded*, not merely poorer.

```dart
class Attach { final String id; final double since; bool recovered; }
List<Attach> attached = [];   // max 3 simultaneous
```

| Entity | Attacked | Attaches to | Effect for the rest of the night |
|---|---|---|---|
| `vert` | THE FINAL | **THE BOOK** | Every gauge rolls while a signature is held → 35% false-entry chance per signing |
| `snow` | THE FINAL | **THE CHAIN** | Green mod band narrows 85–100 → **88–97** |
| `dead` | THE LINE | **THE MACHINES** | Reel counter hidden and the tail flap is silent. You change reels by feel |
| `call` | THE LINE | **THE BOOK** | Rings every **4.0 s**; each ring blocks `ENTER` for **0.6 s** |
| `card` | THE CHAIN | **THE MACHINES** | She holds the tape: the displayed remaining time **freezes** while the reel keeps draining |
| `rerun` | THE CHAIN | **YOUR HANDS** | **Ghost inputs.** Every 12.0 s it replays your last 12.0 s of keypresses at 0.55 strength |
| `sleep` | THE BOOK | **THE ANNUNCIATOR** | Lamps stop flashing. They still go amber/red but never flash, and `F` does nothing. **Silent failure** |
| `niel` | THE BOOK | **THE DOOR** | Door climbs an extra **+0.010/s**, and **every `ENTER` hold adds +0.02 door instantly** |

**Drip:** each attachment adds **0.12 s/s to the drums** (0.24 after a failed recovery).

**THE RECOVERY WINDOW** — the only way an attachment ever leaves. `rr(70,130)` s after it attaches, the same entity re-manifests with `window ×1.30`, `coldOpenChance = 0`, and a slate line `RECOVERY — <NAME>`. Clear it and the attachment is removed. Miss it and the drip doubles and `addMark(Mark.neglect)`.

**Hard cap: a 4th simultaneous attachment is LICENCE VOID immediately.** (`feel`'s requested countable second loss condition, D2's residue structure.)

---

### 2.8 THE MONITOR — the off-air rotary

`kScr = Rect(260,146,422,278)` **stops being a button** and becomes what it always should have been: the off-air monitor.

```dart
int  rotary   = 0;      // 0 PROGRAM (home), 1 OFF-AIR, 2 LINE, 3 MAST
double parked = 0.0;    // seconds continuously off home on the carrying source
```
**Input:** `TAB` steps one detent per tap; `TAB` held 0.4 s snaps home. Mouse: click the painted rotary at **(536, 570) r=20**.

Parked ≥ **0.90 s** on the source carrying the live entity → the entity renders **full 422×278 at scale 1.0** (the baked plate from `faces.dart:482-541`, not the 320×240 tube buffer), and the annunciator names it.

**Cost:** the door climbs at **×3** while `rotary != 0`; you lose the program picture, so no tail leader and no bars.

---

### 2.9 THE DOOR — the presence

Reuses the painted never-quite-shut door with two points of light in the gap (`room.dart:479-497`) and the existing `presence` dial (`anomalies.dart:2744-2794`).

```dart
double doorOpen = min(0.35, 0.03 * (night - 1));   // PERMANENT across the career
```
`doorStart` is stored in `GameState`, **never reset by anything**. Night 12 begins with the door a third open and the lights already at head height.

**Update:** `doorOpen += 0.0060 * dt * (deadAir > 0 ? 2.0 : 1.0) * (rotary != 0 ? 3.0 : 1.0) + nielExtra`.

**Input:** `C` **held 1.60 s** — you stand up. The view pans off the desk toward the door, **every control is dead**, the plate keeps drifting, the reel keeps running. `doorOpen -= 0.30`. Mouse: press-and-hold the door at **(60, 240, 60, 180)**.

**Failure:** `doorOpen ≥ 1.0` → **IT COMES ROUND THE FRONT**: full-screen `ScareOverlay` 2.5 s, **+40.0 s on the drums** (22% of the whole budget), **+1 attachment**, `doorOpen = 0.55`. Survivable exactly once.

---

### 2.10 THE LEDGER — the loss condition

**Four mechanical drums bolted to the master recorder**, painted in the room at **(790, 600)**, four digits, tenths, physical rotation. No bar, no percentage, no colour. Per-source accounting kept in `Map<String,double> offAirBy` for the death sheet and the balance tests.

```dart
double offAir  = 0.0;
double ceiling = 180.0;   // rises with IN SPEC time, max 220.0
double inSpec  = 0.0;     // continuous seconds all-green
```

| Source | Tariff |
|---|---|
| OVERLOAD RECYCLE / VSWR TRIP | **2.5 flat**, three allowed, printed `OVERLOADS 2/3` |
| LOCKOUT | **1.0/s** until the contactor is closed; hard deadline 30.0 s |
| DEAD AIR | **1.0/s** |
| LOW POWER (`plate < 1.35`) | **0.5/s** |
| SPLATTER (`mod > 112`, 1.5 s) | **25.0 flat** |
| LOG NOT SIGNED | **20.0 flat** |
| FALSE ENTRY | **8.0 flat** |
| PRESENCE ROUND THE FRONT | **40.0 flat** |
| EACH ATTACHMENT | **0.12/s** (0.24 after a failed recovery) |

**IN SPEC** = `plate`, `refl`, `psi`, `mod` all green **AND** no entity on the tube **AND** no attachment live **AND** not in tail. After 4.0 s continuous, every further **12.0 s adds +1.0 to `ceiling`**, capped +40.0. Display: `OFF AIR 041.2 / 186.0`. Score line at dawn: `IN SPEC 24.6%  ·  BEST 31.2%`.

**At `offAir ≥ ceiling`:** the licence is void. The station goes dark — **and the game does not cut. It runs for eleven more seconds** with no carrier, in the room, with the eight things that the carrier was holding now not being held in anything.

**THE DEATH SHEET** (D1's invoice + D4's forensic reconstruction, merged):
```
LICENCE VOID — 04:12:31

01:14  OVERLOAD RECYCLE                    2.5
01:16  OVERLOAD RECYCLE                    2.5
02:03  DEAD AIR — REEL 4 RAN OUT DURING A DEGAUSS   41.0
02:47  SPLATTER                           25.0
03:31  LOCKOUT                            28.4
...

AT 150.0 THE PANEL READ:
  PLATE ▲  VSWR ▲  LINE ·  LOW DRIVE ·  OVERMOD ▲
  LOSS OF AUDIO ·  LOG DUE ●  INTRUSION ●
YOUR LAST FIVE KEYS:  D  D  D  D  D
```

---

## 3. THE MINUTE-BY-MINUTE SHAPE OF A NIGHT

Night length unchanged: `kShiftMinutes 420 × kMinReal 1.15 = 483.0 real seconds`. Seven segments of **69.0 s**. `kRundown` names and prose kept (`consts.dart:649-679`); their quota fields are deleted.

### The ramp table (single source of truth)

| seg | clock | name | gapMean | window | driftMul | leak every | prog step | check every | reel |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 23:00 | STATION IDENT | 22.0 | 6.50 | 1.00 | rr(110,150) | rr(7,11) | rr(24,34) | rr(112,124) |
| 1 | 00:00 | THE LATE MOVIE | 20.7 | 6.17 | 1.08 | rr(100,140) | rr(6.5,10.5) | rr(22,32) | rr(106,120) |
| 2 | 01:00 | OVERNIGHT NEWS | 19.3 | 5.83 | 1.16 | rr(90,130) | rr(6,10) | rr(21,31) | rr(100,116) |
| 3 | 02:00 | THE DEAD HOUR | 18.0 | 5.50 | 1.24 | rr(80,120) | rr(5.5,9) | rr(20,30) | rr(96,112) |
| 4 | 03:00 | TEST TRANSMISSION | 16.7 | 5.17 | 1.32 | rr(72,108) | rr(5,8.5) | rr(19,28) | rr(92,108) |
| 5 | 04:00 | THE CHOIR HOUR | 15.3 | 4.83 | 1.40 | rr(66,98) | rr(4.5,8) | rr(18,27) | rr(88,102) |
| 6 | 05:00 | SIGN-OFF PREP | 14.0 | 4.50 | 1.48 | rr(60,90) | rr(4,7) | rr(18,26) | rr(84,96) |

`lineFault` climbs **+0.0022/s** all night and never falls: a swept line goes 1.00 → 2.06 (refl 34 → 70 W); an unswept line goes 3.75 → 4.81 (refl 128 → **163 W**, so one DEGAUSS at +90 trips it). **Whatever gets into the coax at 01:00 is still in it at 05:00.** This is the only irreversible thing in a night and it is why the first hour is holding four needles and the fifth hour is choosing which needle to lose.

### MINUTE 1 (23:00–23:52, night 3, dread ≈ 4)

Plate drift 0.0075 A/s → band edge in **20 s** → **3 drive corrections**. Gain: ~68% of program steps absorbed → **2.4 corrections**. First leak not yet due (0–1 pump). First reel has 112–124 s, so **no changeover**. Logs: **2 signatures**. Entities: opening ease spreads the first four gaps to **45 / 36 / 29 / 25 s** → **1 arrival**. Rotary: **0.5 looks** (nights 1–3 force one look per pair per night, §7).

**≈ 9.3 deliberate servicing events/min, ≈ 21 keypresses/min.** Already 2× the current build's night-1 rate of 4.7/min, and it is the easiest minute in the game.

### MINUTE 7 (05:00–06:00, night 3, dread ≈ 55, one attachment live)

Plate drift `0.0075 × 1.48 (seg) × 1.50 (dread) × 1.12 (driftDebt)` = **0.0186 A/s** → band edge in **8.1 s** → **6.2 drive corrections**. Gain: steps every 5.5 s, band narrowed to 88–97 if `snow` is attached → **4.9 corrections**. Leak every ~75 s plus PATTERN vents → **1.2 pump sessions**. Reel 84–96 s → **0.7 threads + 0.7 seams**. Logs every 15.9 s → **3.8 signatures**. Entities: gap `14.0 × 0.85 × 0.835` = 9.9 s → **6.1 arrivals** × 1.25 presses = **7.6**. Rotary: **1.5 looks** (instruments lying above 70 dread on a bad night).

**≈ 25.9 servicing events/min, ≈ 54 keypresses/min.** On a deep night (13+, `np` 0.75, unswept line, two attachments) this reaches **≈ 34/min, one decision every 1.8 seconds.**

**The ramp in one line:** minute 1 = 9.3 decisions/min → minute 7 = 25.9. A **2.8× within-night escalation**, driven by seven published multipliers rather than a difficulty curve. Compare the current build: 4.7/min on night 1 and 9.6/min at depth 120 — one decision every 6.3 seconds *at its hardest*.

### THE NIGHT-TO-NIGHT LOOP — the triage board

Rendered as **six rows on the existing sign-on screen**, using the row idiom lifted from the deleted `ui/rack.dart:236-248`. No tabs, no new navigation. **40 minutes of workshop time.** Each job has `health` 0..1, **−0.20/night**, set to 1.00 when done.

| Job | Cost | Effect at full health | Gateway pair |
|---|---|---|---|
| RETUBE THE FINAL | 25 | `kDrift ×0.50`; CUT drops to ×0.80 | `vert`, `snow` |
| SWEEP THE LINE | 15 | `lineFault` baseline ×0.55 | `dead`, `call` |
| REBUILD THE LIMITER | 20 | limiter 12 → 18 | `card`, `rerun` |
| SERVICE THE LOGGER | 18 | check window 5.0 → 7.0 s | `sleep`, `niel` |
| REEL MOTOR | 10 | +35 s per reel | — |
| DEHYDRATOR | 12 | `leakMul ×0.50` | — |

**100 minutes of demand against 40 of supply; each decays over 5 nights → 30 job-nights of demand against 7.5 supplied.** You permanently operate a rig that is 25% maintained and you choose which 25%.

**THE BOARD IS A MONSTER-SELECTION SCREEN.** `entityWeight(id) *= 1.0 + 1.6 * (1 - health[gatewayJob])`. At health 0 that pair is **2.6× as likely to be on tonight's roster**. "Tonight I'm skipping the line sweep and taking THE CALLER, because I can beat him" is the sentence this exists to produce.

**AT LARGE.** If the licence goes void, the entity on the tube (or the last attached) is at large. It opens the next night at **t = 8.0 s**, cold, **no telegraph and no panel twitch**, `window ×1.30`. It stays at large until banished clean. **Cap: exactly one at a time.** Shown on the sign-on screen next to the board and on the sign-off sheet, face-up, before you quit.

---

## 4. WHAT GETS DELETED

### Files removed entirely (~4,900 lines)
| File | Lines |
|---|---|
| `lib/src/bots.dart` | 897 |
| `lib/src/ui/rack.dart` | 770 |
| `lib/src/tools.dart` | 693 |
| `lib/src/ui/wings.dart` | 577 |
| `lib/src/ui/bots_panel.dart` | 387 |
| `lib/src/ui/status_bar.dart` | 364 |
| `lib/src/ui/tools_bar.dart` | 347 |
| `lib/src/ui/ad_break.dart` | 311 |
| `lib/src/meta.dart` | 293 |
| `lib/src/objective.dart` | all |
| `lib/src/ui/toasts.dart` | all |

Tests removed with them: `meta_test.dart`, `objective_test.dart`, `directive_test.dart`, `fightback_test.dart`, `lock_test.dart`, `ninth_test.dart`.

### THE PRODUCER ECONOMY AND EVERYTHING IT DRAGS

**State (`state.dart`):** `sig` (:299), `segSig` (:303), `lifetimeSig` (:336), `rp`, `prod`, `ups`, `toolCharges`, `sponsorEnd`, `sponsorCd`, `dawnBonus`, `revives`, `TuneState` in full (:102-225 — `kTierMult`, `kTierNeed` `[6,10,14,18]`, `kLockGrace 1.1`, `knockDown()`, `heat`, tier names), `resetForNewNight()` (:396-418).

**Producers (`consts.dart:344-415`):** the whole `kProducers` table — `rabbit` 15/1.13/0.8, `dipole` 140/1.13/5.4, `vhf` 1.3e3/1.14/34, `relay` 12e3/1.14/215, `head` 110e3/1.15/1.4e3, `sat` 1.0e6/1.15/9.2e3, `ghost` 9.5e6/1.16/64e3, `mirror` 90e6/1.16/480e3, `dead0` 850e6/1.17/4.0e6, `choir` 8.0e9/1.17/36e6. Plus `kProducerMarks = [25,50,100,200,300,500]` (`meta.dart:181`).

**Economy (`economy.dart`, 576 lines → replaced):** `costOf` (:34), `bulkCost` (:38), `maxAfford` (:44), `producerUnlocked` (:63), `upgradeVisible` (:72), `buyProducer` (:79), `buyUpgrade` (:87), `spendRp` (:96), `rpMultAt`/`kRpMultK 0.26`/`kRpMultExp 0.62` (:116-124), `rpMult` (:127), `sponsorMult` (:130), `sigMult` (:133-144), `sigRateRaw` (:157), `sigRate` (:166), `rpGain` (:178), `tuneYield` (:188-213), `offlineGrant` (:217), `quotaOf` (:545), `quotaScale` (:541), `segQuota` (:557), `quotaMet` (:560), `quotaShortfall` (:563), `kQuotaRamp 0.62` (`consts.dart:639`), `kStallDread 0.9` (:491), `kStallRepeat 8.5` (:494), `reviveDread`/`reviveSponsor`/`reviveGrace` (:515-521 — all three already had zero callers), `producerMarkMult` (`meta.dart:185`), `metaOutputMult` (`meta.dart:157`), `metaStallCap` (`meta.dart:166`), `keptTiers` (`meta.dart:148`).

**Upgrades (`consts.dart:447-520`):** all twelve — `ferrite`, `preheat`, `phosphor`, `autocue`, `halide`, `failsafe`, `watch`, `lead`, `comp`, `cam2`, `vault`, `halo` — and the whole HARDWARE tab. Their four genuinely good effects become triage jobs.

**Career (`career.dart:39-109`):** all eight RP STATION nodes — `standing`, `ferrite`, `memo`, `roster`, `pay`, `steady`, `second`, `union` — plus `buyMeta` (`meta.dart:137`).

**Anomaly runtime (`anomalies.dart`), the six economy blocks:** the passive tick (2894-2911), the stall block entire (2915-2965 — the held clock at :59, the 0.9/s bleed, the 19-second repeat, the three-line advice rotation, the UNION RULES exit), the banish payout (1677-1694), the sabotage currency drains (1834-1854), the jumpscare theft table (2217-2241), and `tuneStrike`'s idle-income branch plus the fight-back branch entire (1405-1479, including `kMaxBought 3.6` and `kBlowsPerStagger 4`). Also `takeSponsor` (2606-2618), `revive()` (2359-2388), `signOff()`'s RP conversion (2567-2598), `beginCarrier`/`endCarrier`/`dropCarrier` and the ninth key (1482-1554).

**Quota table:** the `quota` field on all seven `kRundown` entries (`consts.dart:649-679`). **The names and prose survive.**

**Dead code finally buried:** the MASKED CARRIER path (`anomalies.dart:392`, `1292-1303`, `1214`, `cam2Hint` at `923`); `softNext` and the untapered calm (`812`, `1150`, `1173`); the feed's masked overlay (`feed.dart:447-452`).

**HUD:** the whole status strip, both wings, `DirectiveStrip`, `primeDirective`, the feed ticker band (`feed.dart:370-379`), the feed tutorial box (`feed.dart:339-363`), the sponsor badge (`feed.dart:381-385`), the MANUAL HOLD readout (`feed.dart:364-367`), the `TunePop`/`TuneRipple` layers (`tube.dart:496-504`), the carrier-lock strap (`tube.dart:506-524`), and **the deck keycap sub-labels that print the entity's name from the frame it manifests** (`deck.dart:41-47`) — the game stops answering its own only question.

**Total removed:** ≈ 4,900 lines of whole files + ≈ 2,100 lines gutted from `anomalies.dart`, `state.dart`, `economy.dart`, `consts.dart`, `main.dart`. **≈ 7,000 lines out.**

---

## 5. WHAT GETS KEPT AND REWIRED

### 5.1 `lib/src/desk.dart` — PROMOTED FROM ORPHAN TO CORE
Currently 334 lines that **nothing in `lib/` imports** (verified). It is a prior attempt at this exact rewrite and it already contains:
- `class Attach` and `enum Rail` → **kept**, `Rail` extended to `{plate, line, chain, machines, book, hands, annunciator, door}`.
- `strain`, `busy` (τ = 3.0), `wrongCount`, `kDreadHold 0.315`, `kDreadGain 14.0`, `kDreadRecover 3.0` → **kept exactly**. Its comments record dread being tuned wrong twice in opposite directions and the asymmetric recovery that made it breathe. Do not re-derive this.
- `shiftRamp(p) = 0.72 + 0.62*p` → **kept**, applied to `kDrift` and `gapMean` instead of carrier decay.
- `carrierDecay(night) = 2.9 + pow(night,0.85)*0.42` → **kept as the shape** for `nightPressure`-adjacent scaling.
- `push()` / `kPushCarrier 13.0` / `kPushPlate 14.0` / `vent()` → **DELETED.** This is the D2 failure mode, and `desk.dart:104-109` already records the sim catching it: *"The design was clicking with a new name, which is precisely what it was written not to be."*

`Desk` is renamed `Rig`, gains the five system blocks from §2, and stays **pure Dart with no Flutter import** — which is what makes a whole night simulate in ~40 ms.

### 5.2 THE EIGHT ANOMALIES
Names, faces, voices, ids, tiers and counter keys **all unchanged**. `consts.dart:713-829` and `encounter.dart:110-183` survive; only the `tell` strings are unused (the twitch replaces them). Roster gating `unlockedAnoms()` (`economy.dart:452-461`) kept, `depth(s)` kept. Each entity gains three new fields: `Instrument attacks`, `Rail attachesTo`, `List<double> fist`. Their existing `sabotageTick` branches (`anomalies.dart:1746-1885`) are re-pointed from currency drains to the §2.7 attachment effects — this is the single largest structural reuse in the whole plan and it yields eight authored behaviours for the cost of eight edited function bodies.

### 5.3 THE AUDIO ENGINE (`ui/audio_web.dart`, 2,634 lines)
Kept whole. Reassigned:
- `thump()`, `impact()`, `relay()`, `hold()` move from combat feedback to **machine feedback** and get **+6 dB**. The plate contactor closing ducks the master bus 200 ms. The overload relay is the loudest sound in the game.
- `deadAir(true)` drives real silence on a reel run-out.
- `env()` (`:1656`) and `boxNote()` (`:2610`) render the **fists** from data.
- `tune(p)` is repurposed as the plate-error hum — pitch is the signed error — so the plate can be run by ear during a `C` door-close or a `R` thread.
- `setHeart(96 + d*30, 0.20 + d*0.16)` stays on `doorOpen` instead of `presence`.

**THE FISTS**, authored as `List<double>` alternating on/off seconds, looping. The **same array** drives the AUDIO VU needle envelope (`room.dart:880-908`) and the ON AIR filament brightness, so the game is beatable muted.

| id | fist |
|---|---|
| `dead` | `[]` — keys nothing; the room bed ducks 9 dB. A hole punched in the noise floor |
| `sleep` | 96 BPM in 3/4, `[0.10, 0.53]` ×3, **drops one note every 4th bar** |
| `niel` | `[0.08, 0.14]` ×5 then `1.10` rest — deliberate groups of five |
| `rerun` | your own last 2.4 s of program, delayed, played under itself |
| `call` | `[0.40, 0.20, 0.40, 2.00]` — a ring cadence |
| `card` | 1 kHz keyed `[0.40, 0.90]` — a test tone with a stammer |
| `vert` | 1.4 s rising sweep every 2.1 s → `[1.40, 0.70]` |
| `snow` | 12 Hz granular `[0.03, 0.05]` grouped in 3 + `0.24` rest — chatter resolving into triplets |

Rule (from `build`'s steal, adopted verbatim): **fists are data rendered by the synth, never synth code.** Otherwise a whole-night sim is untestable.

### 5.4 THE ROOM (`paint/room.dart`, 997 lines) — every new instrument lands on something already painted
| New instrument | Existing paint | Coords (verified) |
|---|---|---|
| PLATE meter | VU meter 1, relabel `CARRIER` → `PLATE` | `(40, 548, 96, 44)`, arc r=30, sweep π·1.15 + π·0.7 |
| MOD meter | VU meter 2, relabel `AUDIO` → `MOD` | `(152, 548, 96, 44)` |
| REFL meter | **third instance of the same primitive** | `(600, 548, 96, 44)` |
| PSI gauge + pump lever | new, same primitive | `(450, 548, 96, 44)` + lever `(450, 552, 22, 44)` |
| DRIVE knob | new | `(300, 570) r=26` |
| GAIN fader | new | `(380, 548, 18, 48)` |
| MONITOR ROTARY | new, 4 detents | `(536, 570) r=20` |
| THE ODOMETER (4 drums) | new, on the tape deck body | `(790, 600, 76, 20)` |
| Two decks + tape diameter | reel-to-reel, spin rate re-pointed | deck `(790, 572)` 168×52, spools at x=750, x=830, r=17 |
| THE DOOR | left-wall door in perspective | `room.dart:479-497`, hit rect `(60, 240, 60, 180)` |
| ANNUNCIATOR, 8 lamps | new, one strip in `kDeckRect` | `y=606`, 8 × `(20 + i*76, 606, 72, 22)` |

Free desk space between x=248 and x=706 at y=548–600 is **458 × 52 px**, which is where the new controls go. Nothing overlaps.

Kept and re-pointed: the studio clock off `s.airtime`, the ON AIR wall lamp, the reel spin rate (now off `reelLeft`), the 70 dust motes, the patch panel (`room.dart:533`), the flickering ceiling tube (now off `doorOpen`), the corridor monitors (`room.dart:656-808`, now off `doorOpen`).

### 5.5 THE PAINTERS
`paint/entities.dart` (2,227), `paint/faces.dart` (769) with its 45 baked plates, `paint/window.dart` (727), `paint/blood.dart` (569), `paint/booth.dart` (291), `bake.dart` (455) — **untouched**. `paint/tube.dart` and `paint/feed.dart` gain a 4-source router (`rotary`) and lose the bezel banner, the strap, the ticker, the badge and the tutorial box.

**BLOOD AND SCARS**: `blood.clear()` and `scars.clear()` at `startBroadcast()` (`anomalies.dart:1615-1616`) are **removed**. Blood persists across the night boundary and is wiped only by a night finishing with `offAir ≤ 20.0`. The room gets worse the worse you have been.

### 5.6 `checks.dart` (277) — kept whole, three constants changed (§2.5).
### 5.7 `encounter.dart` (411), `nights.dart`, `record.dart`, `archive.dart` (452), `career.dart` (381), `wallclock.dart`
- `encounter.dart`: telegraph/jitter/coldBias/windowMul tables kept; `afterScare`/`afterBanish` finally passed true.
- `nights.dart`: the seven card dials are re-pointed — `output`/`quota`/`rp`/`banishPay` die; `window`, `gap`, `dread` stay; three new: `ice` (1.00–1.35), `leakMul`, `programVolatility`.
- `record.dart`: the four Marks are **rebound** (they were tied to deleted actions and would silently become dead code). `Mark.hand` → forcing a lockout (the 4th trip). `Mark.panic` → pressing DEGAUSS when the twitch did not name THE FINAL. `Mark.debt` → a FALSE ENTRY. `Mark.neglect` → letting an attachment miss its recovery window. Thresholds retuned from `{3, 40, 4, 12}` to **`{3, 18, 4, 6}`** so they are crossable in five nights. `weightOf()` curve, `recordGapMul`, `recordWindowMul`, `recordDecayMul` all kept; `recordRpMul` deleted. `verdictLine()` moves onto the **death sheet**, not just dawn.
- `archive.dart`: **fix the index-0 bug** — `kUnlockAt['archive']` goes **2 → 1** (`career.dart:275-282`). On night 2 the player has survived 1, so `kArchive[0]` ('FROM THE DESK DRAWER — LOG OF R. HALLORAN') is currently unreachable on every playthrough and 'THE FILE IS COMPLETE' can never print. Called out independently by all three judges. Also lower `kPersonalFileNight` **12 → 5** and `personalFileOpen` with it, so `personalFile()` and `wallClockLine()` become reachable inside the window this rewrite is judged on.
- **The binder does not pause.** `_openManual()` (`main.dart:376`) stops setting `runtime.paused = true`. `M` overlays the lower third with the night running.
- `career.dart`'s 22-name roster: **kept intact as the career spine.** Nights survived is the number that goes up. The board is what you do, the roster is what you are.

### 5.8 DREAD — survives, stops being a health bar
`s.dread` 0–100 kept, `dreadFloor` kept (`economy.dart:500-505`). **It can no longer end a night.** Both `signalLost()` call sites (`anomalies.dart:2249`, `3113`) are deleted. Dread now drives: `kDrift ×(1 + 0.9·d01)`, `gapMean ×(1 − 0.30·d01)`, `window ×(1 − 0.20·d01)`, surge chance, `nextCheckGap ×(1 − 0.22·d01)`, presence rate — and **above 70 the instruments lie without an anomaly present**: one meter at a time freezes at nominal or stops responding to its control, rotating every `rr(8,16)` s. Above 85, two at a time. **The only ground truth left is the monitor, and the monitor is where the faces are.**

---

## 6. THE NOISE CUT

**THE RULE.** Text may appear on screen only if **both** of these hold:
1. it names something with **no physical representation in the room**, and
2. the player must act on it **within the next 5 seconds**.

Everything else becomes a lamp, a needle, a drum, a spool, a spinning reel, or a sound. `ToastBus`, `ToastLayer` and `kToastRect` are deleted outright.

**THE ANNUNCIATOR** replaces the notification system. Eight lamps, one horizontal strip in the deck at `y=606`, **fixed order**, three states: dark / steady / flashing-unacknowledged. `F` acknowledges (flashing → steady). Mouse: click any flashing lamp.

`PLATE OVERLOAD · VSWR · LINE PRESSURE · LOW DRIVE · OVERMOD · LOSS OF AUDIO · LOG DUE · INTRUSION`

**LAMP DISCIPLINE** (D4's rule, `brief`'s steal, adopted verbatim): one strip, fixed order, a single shared green/amber/red vocabulary, and **nothing else on screen may use those three colours**. Break this and the noise problem comes straight back in a new costume.

**THE SLATE.** One line at a time, 1.6 s, bottom of the tube bezel, **hard cap of one alive**, minimum 4.0 s between. **Six surviving sites, from 85** (a 93% cut):

| # | String | Trigger |
|---|---|---|
| 1 | `TWO-STAGE` | `manifest()` with `EncounterMod.twoStage` |
| 2 | `COUPLED — <A> <n> + <B> <n>` | `manifest()` with `EncounterMod.coupled` |
| 3 | `RECOVERY — <NAME>` | an attached entity re-manifests for its one clearance chance |
| 4 | `AT LARGE — <NAME>` | t = 8.0 s of a night opened with an at-large entity |
| 5 | `LICENCE VOID IN <n>` | once at `offAir ≥ ceiling − 15.0`, once at `≥ ceiling − 5.0` |
| 6 | `06:00` | end of shift, and THE LONG NIGHT's override |

**Explicitly killed at the source:** `anomalies.dart:1386` `'<KEY> DOES NOTHING TO THIS ONE'` and its 700 ms `'PRESS M — THE MANUAL NAMES THE KEY'` follow-up (`:1387-1388`) — the exact nag the user named — together with `wrongPress()`'s whole messaging path and the never-reset `nightWrongs` counter (`:844`). Also the five per-entity sabotage nags that repeat on a 0.85–3.0 s interval (`:1766, 1797, 1843, 1861`), the five-toast banish burst (`:1669/1688/1717/1709/1734`, which already exceeded the 3-item cap and was silently dropping its own messages), the two-per-19-seconds stall loop (`:2938 + 2945`), the seven `_deny`/`_sealed` refusals in `tools.dart`, and the unprompted restock timer (`tools.dart:675`).

**Retained non-toast overlays:** the `ScareOverlay`, the pre-shift board, the death sheet, the sign-off sheet, the binder (now non-pausing). **Deleted:** the bezel banner's warn and all-clear states, the ON AIR lamp's 8-state label (the wall lamp carries it), the `RotateNag`, the `ConfirmSheet`, both ad interstitials, and the pre-shift `LogSheet` gate (the archive is read at the desk, live, or not at all).

**Text on screen at any instant, hard cap: four strings** — the annunciator's captions are labels, not messages, and do not count.

---

## 7. THE HORROR PLAN

The current build's measured horror: **4.5 seconds of full-screen scare in 38.5 minutes of play (0.20%), 0 record marks, 0 verdict lines, 3 of 27 documents, 0 room-scares** across five nights of competent play. Every payload is attached to failure, so getting good is the mechanism by which the player turns the horror off. Three beats fix that, and all three are **guaranteed by construction, not by dice**.

### BEAT 1 — THE IMPOSSIBLE READING
**Trigger:** `beginWarn()`. **100% of arrivals. No gate, no roll, no unlock.**
**Frequency:** ≥ 17 per night on night 1, ≥ 24 on night 7+. **≈ 120 times across nights 1–5.**
**What happens:** for 1.6–2.6 s the instrument the entity is about to attack does something physically impossible — *reflected power climbing with the plate contactor visibly open; 140% modulation on a chain you muted at the source; the plate reading 1.70 A with the drive at zero; line pressure rising with the pump off and every valve shut, because something is pushing air back up the coax from the mast end, and the mast is a mile out in a field.*
**Why it lands:** the first hour of night 1 teaches the player that plate current comes from drive, that reflected power comes from forward power, that the contactor must be closed for any of it to exist. These are not lore, they are the controls, and you learn them because you have to. Then the impossible reading arrives at a player the game has spent ten minutes making competent enough to be frightened. This is the mechanism the current build lacks entirely: nothing is at stake in a face in a 12.7%-of-screen rectangle because the image has no relationship to anything you understand.

### BEAT 2 — YOU TURN THE KNOB AND IT IS FULL SIZE
**Trigger:** on **nights 1–3**, the panel twitch for the **first arrival of each pair each night** is deliberately ambiguous — it names the instrument but not which of the two. The fist is not yet learned. The only way to resolve it is the rotary.
**Frequency: ≥ 4 forced looks per night, by construction, guaranteed.** From night 4 the fist can disambiguate for free *if the player has learned it* — so the forced looks become **voluntary** looks, which is worse.
**What happens:** parked 0.90 s on the carrying source, the entity's baked face plate renders at **full 422×278, scale 1.0**, eyes open, looking back — not the 320×240 tube buffer, not a postage stamp. And the door is climbing at ×3 the whole time you look.
**Why it lands:** the player raises the monitor themselves, repeatedly, knowing exactly what is on it, because the alternative is worse. That is FNAF's actual trick and it is the most repetition-resistant horror structure there is. It fires ~24 times a night once the instruments start lying above 70 dread, versus twice per 38 minutes today.

### BEAT 3 — THE LOG IS ALREADY FILLED IN
**Trigger: scripted, 100%, on night 2 and night 4.** Thereafter a 1-in-3 roll per night whenever `niel` is on the roster.
**What happens:** the log falls due. You open the book to sign it and the entry is **already completed, correctly, in your own handwriting, for hours you have not yet worked**. On night 4 the entry is for a date in a year that has not happened. **You still have to hold `ENTER` for 1.20 seconds and sign it**, because an unsigned log is 20.0 seconds and you are at 140 of 180.
**Why it lands:** it is statutory, it is your handwriting, it is where the night's arithmetic is stored, and the tariff makes complicity mandatory. It is quiet, undramatic, and much worse than a face, because there is no explanation available that is better than the one you are already thinking of.

**Two further beats, frequent but not guaranteed:**
- **THE 4× IN THE ROOM.** ≥ 3.0 s of continuous off-air (a lockout, or a dead-air spiral) renders the live entity at 2.2× → 4.0× **in the room** through the existing `ScareOverlay`, for as long as the carrier is down. Threshold drops 0.5 s per occurrence to a floor of 1.5 s. Expected **1–2/night competent, 4–6/night sloppy**. It lands on top of the exact eleven seconds where the step-start demands undivided attention.
- **IT COMES ROUND THE FRONT.** `doorOpen ≥ 1.0`. On night 1 the door starts at 0.00 and climbs at 0.0060/s → 167 s of pure neglect. On night 12 it starts at 0.33. `doorStart` **never resets, for the whole career**. Nothing you earn makes you stronger; the only thing that can improve is you.

---

## 8. THE TEST PLAN

**HARD SEQUENCING RULE (D1's, `build`'s steal, non-negotiable): build the headless `NightSim` FIRST, before a single pixel changes.** Ship nothing until the bands below are met. Every number in this document is a first guess; the sim is what makes them real.

**The harness already exists in embryo.** `test/desk_test.dart:75-177` `playNight()` is a complete divided-attention operator: a priority stack over the systems, a `notice` latency that *scales with `wrongCount`* (`:117-120`), an action mix, a dead-time histogram, and a deterministic LCG (`:53-60`). Its header records that an omniscient operator made the design measure as balanced while producing **no dread at all** — a game tuned for a player who cannot exist. Extend this file; do not write a new one.

```dart
class Policy {
  double latency;        // seconds to first input after noticing
  double errorRate;      // wrong-key probability
  List<System> priority; // triage order
  double noticeBase;     // 0.35, scales +0.42 per extra wrongCount
  bool   deaf;           // fists channel disabled
  bool   mouseOnly;      // only mouse-reachable actions permitted
}
```
`GameAudio` is already an abstract interface (`anomalies.dart:61`) with `NullAudio` (`:184`), and `checks_test.dart` already constructs `AnomalyRuntime(s, audio: const NullAudio())`. A whole night is `while (t < 483.0) rig.tick(1/60)`.

### Assertions — the ledger

| # | Assertion | Band |
|---|---|---|
| 1 | **POLICY A** (`latency 250 ms`, `errorRate 8%`, correct priority), night 3, 200 seeds: median `offAir` | **30.0 – 70.0** of 180 |
| 2 | Policy A, night 3: p95 `offAir` | **< 110.0** |
| 3 | Policy A, nights 1–5: survival rate | **≥ 95%** |
| 4 | **POLICY B** (`600 ms`, `25%`): loses by night 5 | **≥ 70% of 200 runs** |
| 5 | Policy B, night 5: median death time | **210 s – 400 s** (late, not at 23:01) |
| 6 | **POLICY C** (`120 ms`, `0%`, perfect): `offAir` | **≤ 18.0**, and **≥ 22% of the night idle** |
| 7 | **Per-source accounting**: no single `offAirBy` key exceeds | **45% of Policy A's median** |

### Assertions — crowding (this is requirement #2 and it must be measured)

| # | Assertion | Band |
|---|---|---|
| 8 | Policy A, night 3: **median idle stretch** (current build: **20.0 s**) | **< 1.5 s** |
| 9 | Policy A, night 3: **worst idle stretch** | **< 6.0 s** |
| 10 | Policy A: mean **servicing events/min** over the night | **14 – 24** |
| 11 | Policy A: **keypresses/min** | **34 – 58** |
| 12 | Policy A: last-minute events ÷ first-minute events | **≥ 2.0×** |
| 13 | Policy A, night 3: fraction of the night with `wrongCount ≥ 2` | **22% – 40%** |
| 14 | Policy A: fraction of the night with `wrongCount ≥ 3` | **6% – 16%** |

### Assertions — feel

| # | Assertion | Band |
|---|---|---|
| 15 | Policy A: `OVERLOADS` at 06:00 — median / p90 | **1 / 2** |
| 16 | Policy A: lockouts per night | **≤ 0.15** |
| 17 | Policy B: lockouts per night | **≥ 1.2** |
| 18 | Policy A: IN SPEC seconds per night | **90 – 170** (18–35% of the shift) |
| 19 | Policy A: ceiling earned | **8.0 – 14.0** |
| 20 | Policy A: attachments at 06:00, median | **≤ 1.0** |
| 21 | Policy B: attachments at 06:00, median | **≥ 2.4** |
| 22 | Arrivals per night, night 1 / night 8+ | **17–21 / 24–29** |
| 23 | **All-green is reachable in segment 6** with one attachment live | true for **≥ 1 window ≥ 8.0 s** |
| 24 | Clean-splice rate, Policy A | **55% – 75%** (a near-miss must be a near-miss) |

### Assertions — accessibility and integrity

| # | Assertion | Band |
|---|---|---|
| 25 | **DEAF RUN** (`deaf: true`), nights 1–5 | within **12%** of Policy A's `offAir` |
| 26 | **MOUSE-ONLY RUN** (`mouseOnly: true`) | within **15%** of Policy A's `offAir` |
| 27 | **Determinism**: same seed + same policy, 200 runs | identical `offAir` to **0.1** |
| 28 | `docForNight(2)` is reachable at `survived == 1` | true (the archive[0] fix) |
| 29 | All 27 archive documents obtainable in one career | true |
| 30 | Marks crossable in 5 nights of Policy B play | `hand ≥ 3` **or** `panic ≥ 18` **or** `debt ≥ 4` in **≥ 60% of runs** |
| 31 | `verdictLine()` non-null by night 5 for Policy B | **≥ 60%** |
| 32 | No `s.sig`, `s.segSig`, `s.lifetimeSig`, `sigRate`, `kProducers` reference survives in `lib/` | grep returns 0 |

### Instrument-legibility gate (before wiring anything)
Prototype the five banded arc meters at **30% scale** and confirm "am I in trouble" is answerable pre-attentively from the **colour arc alone**, without reading a value. If a player must read a number to know a needle is bad, the panel has failed and the crowding becomes unfair rather than intense.

### Feel gate (before wiring anything)
Prototype **the drive control alone** — `A`/`D` tap-vs-hold against the OU + bias plate model — and confirm that feathering it feels like hands on a control rather than mush. There is no fallback: the click it replaces is deleted. Be willing to move to a held-key acceleration ramp if discrete taps do not land.

---

## 9. RISKS AND OPEN QUESTIONS

**R1 — FIVE COUPLED ANALOGUE INTEGRATORS IS A TUNING PROBLEM, NOT A CONTENT PROBLEM.** The failure mode is a rig that is either trivially stable or a death spiral, with no band between. This is why §8 is sequenced before implementation and why the ledger has per-source accounting from day one. *Mitigation already banked:* `desk.dart`'s comments record three tuning traps found only by measurement — flat plate cooling making the dilemma binary at exactly night 4, `kDreadHold` set wrong twice in opposite directions, and linear night-scaling producing a cliff rather than a wall. Do not re-derive those; port `kPlateCoolPerDeg`-style Newton's-law shapes and the asymmetric dread recovery directly.

**R2 — KEYBOARD LOAD.** `A/D, W/S, G, R, SPACE, TAB, C, F` (left) + `1-8, ENTER, M` (right). That is a large surface. It splits cleanly — left hand owns the analogue controls and the mechanical actions, right hand owns the number row — but it needs a **diegetic key card painted on the desk itself**, and it needs **every action mouse-reachable**, tested by assertion 26. If any action is keyboard-only the design fails its own constraint. The current build is mouse-primary (the only booth target today is the `kScr` click at `main.dart:258-267`), so a keyboard-only core would be a regression for existing players.

**R3 — IT COULD FEEL LIKE HOMEWORK.** This is a simulator now, and simulators can be dry — `feel` flagged this as D1's highest risk. The counterweight is that **every procedure key must be violent**: DEGAUSS is a magnetic bang and a whole-cabinet shake; the plate contactor closing is a physical thunk that ducks the master bus 200 ms; the overload relay is the loudest sound in the game. If a night is quiet it must be quiet *because the machine is behaving*, which should feel like held breath. Budget an explicit audio pass; do not treat this as polish.

**R4 — THE TWITCH MAY BLUNT ITSELF.** `feel`'s sharpest criticism of D1: making the impossible reading the *telegraph* risks converting the uncanny into a HUD element, so that by night 3 "reflected power with the contactor open" means "press 4," not "something is coming back down a line nothing is going up." Three counters are already in the spec — the twitch names only a **pair** (so it is never a complete answer), the **instruments lie above 70 dread** (so the twitch becomes unreliable exactly when it matters), and the **rotary** puts the face full-screen. **Open question: is that enough?** Watch specifically for players reporting that the twitch has become "just the tell." If it has, the fallback is to make the twitch *silent* for one entity per night, chosen at random, so the panel can no longer be fully trusted.

**R5 — PROGRESSION MAY FEEL LIKE IT GOES NOWHERE.** Entropy management gives you no number that rises, and `build` and `feel` both flagged the retention cliff at nights 5–15. Three threads carry it: the **22-name roster** (kept intact — nights survived is the number that goes up), the **triage board** (which is also the monster-selection screen), and **IN SPEC %** with a best-ever. **Open question: is a golf score plus a maintenance deficit enough at night 10?** If not, the cheapest addition is the binder-page structure from D3 — one entity's page fills in permanently the first time you clear it clean, and the eight pages are the only thing you own.

**R6 — THE 180-SECOND CEILING IS A SINGLE POINT OF BALANCE FAILURE.** Nine sources write to one counter at different rates. A small mistuning anywhere — the attachment drip at 0.12/s, low power at 0.5/s — compounds into a night nobody can lose or nobody can win. Assertion 7 (no source above 45% of the median) is the guard, and the per-source map must exist in the debug build from the first commit, not be retrofitted.

**R7 — THE LOCKOUT MAY BE UNRECOVERABLE RATHER THAN DRAMATIC.** 11 seconds of undivided attention against five systems that keep running, with the 4× entity in the room and a 30-second hard deadline, is either the best moment in the game or an unrecoverable spiral. **Open question: should the step-start suspend entity arrivals?** Current answer: **no** — but if assertion 5 shows Policy B deaths clustering inside lockouts rather than spread across the night, freeze `nextAt` for the duration of the step-start and re-measure.

**R8 — THE 3-ATTACHMENT CAP MAY MAKE THE RECOVERY WINDOW MANDATORY RATHER THAN OPTIONAL.** If a player at 3 attachments simply cannot service five systems, the 4th is a formality and the cap is theatre. Watch assertion 21: if Policy B's median attachments pins at exactly 3, the recovery window is not doing its job and its `×1.30` should widen.

**R9 — AT LARGE CAN COMPOUND INTO AN UNRECOVERABLE CAREER.** Capped at one at a time by design, and the cold opening **is** the clearance chance, so the debt is always payable on the night it is owed. Do not lift the cap.

**R10 — SCOPE.** This deletes ≈ 7,000 lines and rewrites `state.dart`, `economy.dart` and roughly a third of `anomalies.dart`. Every test that asserts on `sig`, `quota` or `RP` dies with them. Surviving untouched: `paint/entities.dart` (2,227), `paint/faces.dart` (769), `paint/window.dart` (727), `paint/blood.dart` (569), `ui/audio_web.dart` (2,634), `bake.dart` (455), `archive.dart` (452), `encounter.dart` (411), `career.dart` (381), `checks.dart` (277) — **≈ 8,900 lines of art, audio and content carried across with no changes at all.** That ratio is the argument for this plan over a from-scratch rebuild.