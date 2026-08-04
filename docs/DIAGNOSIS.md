# FINAL BROADCAST — what is actually wrong, measured

All figures from headless whole-night simulation (seeded), 8-minute nights.

## 1. The game is empty, and playing well makes it emptier

| player | share of night with anything on the tube |
|---|---|
| passive (never presses) | 15–24% |
| competent (answers instantly) | ~3% |

An anomaly arrives roughly **every 23 seconds** and is dealt with in **~2 seconds**.
Competence is punished with boredom — the better you are, the more dead air you get.

## 2. The difficulty ramp does not reduce dead air

| night | arrivals | one every | median dead stretch | worst |
|---|---|---|---|---|
| 1 | 20 | 24.0s | 21.1s | 41.8s |
| 2 | 30 | 16.0s | 15.1s | 36.8s |
| 3 | 17 | 28.2s | 25.8s | 54.2s |
| 5 | 37 | 13.0s | 19.0s | 36.8s |
| 8 | 51 | 9.4s | 19.2s | 35.8s |
| 12 | 31 | 12.0s | 19.0s | 37.2s |

Median silence is **~20 seconds at every difficulty**. Harder nights add more
isolated pokes; they never make a moment busier. **Two things are never
happening at once** — which is exactly the user's "you're supposed to be in
multiple things."

## 3. The game talks 5x more than the player acts

One competent night:

- **103 interruptions** (12.9/min — one every 4.7 seconds)
- **21 player decisions** (2.6/min)
- 58 distinct toast strings

Worst offender is a nag loop: **9x "TURN THE TAPE … [ENTER]"** paired with
**9x "TURN THE TAPE — NOT SIGNED. THE STATION IS DRIFTING."** The game asks for
the same chore nine times and scolds nine times for not doing it.

## 4. Controls are shown that cannot be used, and nag when pressed

Night 1 presents 5 tool chips (Q W E R T); only FLARE works.
`_sealed()` at lib/src/tools.dart:687 fires
"— SEALED. THE STOCK ROOM SIGNS IT OUT ON NIGHT n." on every press.
Plus 8 counter keys of which exactly one is ever correct.

This is the user's "notifications telling me that I don't have a key —
which I don't believe." They are correct: the button is right there.

## 5. I ratified the defect in a test

`test/tempo_test.dart:98` — "the tube is not empty for the whole night" —
asserts `onTubeFrac > 0.06`. The threshold was set just above the measured
value, so the guard **permits 94% emptiness** rather than catching it. The
header even records the measurement ("2.3–4.1% of a night") as though it were
acceptable.

This is the root cause of "it is wooden": measured, ratified, moved on.

## 6. The horror does not execute

Competent player, nights 1-5:

| night | scares fired | presence events | peak dread | %time dread>60 | %time dread>85 |
|---|---|---|---|---|---|
| 1 | 0 | 3 | 48 | 0% | 0% |
| 2 | 0 | 2 | 32 | 0% | 0% |
| 3 | 1 | 4 | 87 | 24% | 0% |
| 4 | 0 | 3 | 41 | 0% | 0% |
| 5 | 0 | 3 | 75 | 4% | 0% |

**One scare in five nights.** Dread never once exceeds 85 on any of the first
five nights, so every beat gated behind 85 and 100 — which is where all the
real horror lives — never runs. Peak dread on night 1 is 48, barely half the bar.

"Nothing is scary" is not a matter of taste. The frightening content does not
execute.

## 7. There is no discovery curve

Anomalies first met, fresh career:

| entity | first met |
|---|---|
| THE SNOW CRAWLER | night 1 |
| MR. SLEEPWELL | night 1 |
| THE VERTICAL MAN | night 1 |
| DEAD AIR | night 1 |
| THE TEST CARD GIRL | night 1 |
| THE RERUN | night 1 |
| THE NIELSEN | night 1 |
| THE CALLER | night 2 |

Seven of eight arrive in the first eight minutes; all eight by night 2.
**Nothing is ever revealed after night 2.** There is no "what comes next"
— which is a direct cause of "this wouldn't be addictive".

## 8. The Cookie Clicker core is undisguised

The rack is a literal incrementing shop: RABBIT EARS 15 → DIPOLE ARRAY 140 →
VHF MAST 1.30K → MICROWAVE RELAY 12.0K → CABLE HEADEND 110K → SATELLITE 1.00M.
Signal accumulates; you buy sig/s. Asked to be removed twice now.

Blast radius if removed: 10 files, ~250 references
(`s.sig` 63, `quota` 88, `kProducers` 23, `tune.` 40, `s.prod[` 15).

## Targets any redesign must hit

| metric | now | target |
|---|---|---|
| median dead stretch | ~20s | < 3s |
| concurrent live demands | 1 | 3–6 |
| player actions / min | 2.6 | 25+ |
| interruptions / min | 12.9 | < 2 |
| controls shown but unusable | 4 of 5 tools | 0 |

## Assets worth keeping

- 40+ live-synthesised audio sources with **continuous** parameters
  (`setDread`, `setHeart`, `setSub`, `duck`, `deadAir`, `pan`, `breath`,
  `voice`) — gauges can be *heard* rather than displayed, which answers both
  "too much on screen" and "make the mechanic the horror".
- The 8 anomalies, the room/CRT/booth painters, the blood and face systems.
- `NightCard` — 7 deterministic per-night multiplier cards, a clean modifier
  framework that survives the core swap.
