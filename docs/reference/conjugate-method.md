# Conjugate method implementation

Cadence's **Conjugate — Westside** template is a four-day strength program
derived from the Louie Simmons reference library reviewed for this project. It
is one pre-baked composition of the engine, not a new universal Cadence cycle.
Every lift keeps its own prescription, so max effort, dynamic effort, a classic
Cadence wave, 5/3/1, linear progression, and double progression can still be mixed in
one custom or imported program.

## Source-backed weekly plan

| Day | Primary work | Repetition / GPP work |
|---|---|---|
| Mon — Max Effort Lower | Low Box Squat; rotate to another special squat next week | Nordic curl · back extension · hanging knee raise |
| Wed — Max Effort Upper | Floor Press; rotate to another special press next week | Skull crusher · barbell row · face pulls |
| Fri — Dynamic Effort Lower | Speed Box Squat + Speed Deadlift | Nordic curl · back extension · hanging knee raise · easy sled pulls |
| Sun — Dynamic Effort Upper | Speed Bench Press | Triceps pushdown · lat pulldown · rear-delt fly |

This ordering keeps the two extreme lower sessions and the two extreme upper
sessions about 72 hours apart. The source schedule appears in *The Conjugate
Method* bundle, pp. 50–51, and *The Book of Methods*, p. 101.

## Max-effort prescription

- Use a special exercise rather than repeatedly testing the competition lift.
- After ordinary warm-ups, Cadence prescribes up to three distinct singles:
  about 90%, a near-max single, and the day's target.
- A clean made single sets that variation's anchor. When the variation returns,
  Cadence adds 10 lb for squat/hinge variations or 5 lb for presses. A miss
  does not raise the anchor.
- Change the special exercise weekly. After a completed max-effort exposure,
  Coach offers a reviewable rotation before the next max-effort day. The
  template supplies Low, Front, and Paused Box Squats plus Floor Press and
  Close-Grip Floor Press as starter pools; compatible custom variations remain
  available when those pools do not fit. The recommendation's identity is
  built from portable components only (cycle/rotation evidence key plus slot
  id) so a dismissal or apply recorded on one client survives a backup
  restore and matches the other client, like every other rotation rule.
- A returning variation targets its own clean completed single plus the
  smallest normal lower/upper increment. The supplied sources provide no valid
  conversion from a competition lift to an unseen variation. Until Cadence can
  store an explicit `Establish` exposure, the numeric plan shows 80% of the
  stable reference estimate as a conservative calibration ceiling—not a
  claimed variation max. Cadence never transfers one variation's max to another
  exercise merely because they share a program slot.
- After three max-effort exposures, Cadence's recovery bridge substitutes two
  moderate triples. This is the app's conservative implementation of the
  source recommendation to replace an exhausted max-effort session with
  repetition work.

The weekly exercise change and non-competition variations are described in
*Westside Barbell Book of Squat and Deadlift*, p. 31. Its max-effort loading
example uses three 90%+ singles and 2–4 following special exercises (p. 103).
The recovery substitution appears in *The Conjugate Method*, pp. 54–55.

## Dynamic-effort loops

The dynamic prescription owns a three-exposure loop independent of max effort:

| Slot | Week 1 | Week 2 | Week 3 | Rest |
|---|---:|---:|---:|---:|
| Speed Box Squat | 50% · 12×2 | 55% · 12×2 | 60% · 10×2 | 60 sec |
| Speed Deadlift | 50% · 6×1 | 55% · 6×1 | 60% · 6×1 | 60 sec |
| Speed Bench Press | 40% · 9×3 | 45% · 9×3 | 50% · 9×3 | 60 sec |

Percentages are based on the matching competition lift's recorded e1RM when
the template is created. The special exercise itself remains the saved slot.
Speed work holds its base and does not update e1RM; its purpose here is rate of
force development, not a max-strength estimate.

The squat wave and 12/12/10 set pattern are shown in *Westside Barbell Book of
Squat and Deadlift*, pp. 98–99. The bench manual prescribes nine triples around
40–50% with roughly one-minute rests and then triceps, upper-back, and rear/side
delt work (*Bench Press Manual*, pp. 13 and 26–27).

## Deliberate Cadence boundaries

- The template uses straight bar weight. Bands, chains, specialty bars, and
  their combined-tension percentages require equipment-specific coaching and
  are not fabricated by the app.
- The opening percentages derive from recorded competition-lift e1RMs and round
  down to the available plate step. With no history, conservative defaults
  stand.
- Sled work starts as four easy one-minute trips at RPE 5 and progresses by
  duration. Adjust load or duration in the editor to match the surface and
  available sled.
- This is an advanced template. A lifter who cannot select and execute special
  exercises consistently should use a simpler novice or intermediate template.

## Source map

The implementation was checked across the full supplied library. These were
the controlling programming references:

| Rule implemented | Primary source reviewed |
|---|---|
| Fri/Mon and Sun/Wed schedule; 72-hour separation | *The Conjugate Method*, pp. 50–51; *The Book of Methods*, p. 101 |
| Weekly special-exercise max effort | *Westside Barbell Book of Squat and Deadlift*, p. 31; *Bench Press Manual*, pp. 10–11 |
| Three singles at 90%+; 2–4 supplemental exercises | *Westside Barbell Book of Squat and Deadlift*, p. 103 |
| Three-week 50/55/60 squat wave; 12/12/10 doubles | *Westside Barbell Book of Squat and Deadlift*, pp. 98–99 |
| Nine speed-bench triples; 40–50%; one-minute rests | *Bench Press Manual*, p. 13 |
| Triceps, lat/upper-back, rear/side-delt assistance | *Bench Press Manual*, pp. 26–27 |
| Repetition work when max-effort fatigue accumulates | *The Conjugate Method*, pp. 54–55 |

The source library also contains sport- and population-specific manuals. They
were reviewed as boundary checks, not treated as permission to copy every
method into a general strength template:

| Supplied ebook reviewed | Contribution or implementation boundary |
|---|---|
| *The Book of Methods* | Primary system overview: ME/DE/repetition methods, weekly organization, special exercises, and GPP. |
| *Book of Methods* web/earlier edition | Cross-check of the system overview; treated as a variant edition, not independent evidence. |
| *The Conjugate Method* bundle | Four-day weekly structure, extreme-work spacing, rotation, and recovery substitutions. |
| *Westside Barbell Book of Squat and Deadlift* | Lower-body ME special-exercise rotation, high-intensity singles, and the three-week speed-squat wave. |
| *Bench Press Manual* | Upper-body ME/DE loading, speed-bench triples, and triceps/upper-back/delt repetition work. |
| *Iron Samurai* | Historical and practical corroboration of the ME/DE/repetition split, three-week waves, and GPP; anecdotes are not encoded as universal rules. |
| *Special Strength Development for All Sports* | Supports selecting special exercises by transfer and weak point; sport-specific exercises and ratios are not generalized blindly. |
| *Explosive Strength Development for Jumping* | Confirms the need for explosive/reactive qualities and event transfer; jumping prescriptions stay outside the base powerlifting template. |
| *Thrower's Book* | Confirms transfer-specific special strength and sequencing; throwing volumes and implements are not applied to non-throwers. |
| *Olympic Weightlifting Strength Manual* | Reinforces technical specificity and distinct strength qualities; Olympic programming remains in its separate technique-led template. |
| *Strength Manual for Running* | Reinforces running-specific transfer, GPP, and fatigue management; running ratios are not imposed on strength-only users. |
| *Children Exercise Book* | Establishes an age-specific boundary: broad GPP and development precede specialized loading; the advanced Conjugate template is not presented as youth programming. |
