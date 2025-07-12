Flashlights in the Dark
─────────────────────────────────────────
Electro‑acoustic score
for 54‑piece concert choir, 28 smartphones, computer, & closed‑network
~9 min duration

Macbook
Controller            ←→   Closed Network (offline)
                            WiFi Router
(arrow group of radiating lines aimed toward stage)

Choir Layout
─────────────────────────────────────────
[semi‑circular stage map – individual labels shown clockwise]

A3   A3   A3                                                   B2   B2
A2   A2                                                        S2   S2
A2                                                             Alto (×3)
Soprano (×9)   Soprano (×9)   …                                Soprano (×9)

[central front row]
B1   B1   B1   S3   S3   S3   Ten/Bass   Ten/Bass   …   T1   B2   B2   …

(large teal double‑ring singer)
Ten/Bass  
Proxy Controller Client / Tapper

─────────────────────────────────────────
Conductor’s
KEY
─────────────────────────────────────────
Singers with traditional choir roles:
          ↓                         ↓                         ↓
   Soprano                   Ten/Bass                    Alto
   9 Sops Reading Score      9 Men Reading Score         9 Altos Reading Score

                    (arched rainbow bracket)
               Singers with SMARTPHONES
           (nine groups of three smartphone singers each)

 (nine coloured thick‑ring icons, left‑to‑right)
 A3   S3   B1   T1   B2   S1   S2   A2   A1
Legend for colours / icons

Small cyan‑filled circle with profile silhouette = singer following a printed, traditional SATB part.

Thick coloured ring + magenta square (phone icon) inside = singer whose contribution is driven by a smartphone app (sound and/or flashlight).

Double‑ring teal circle = the “proxy” Tenor/Bass who uses a phone but also cues others (tap‑tempo).

Rainbow ribbon under the smartphone roster indicates nine distinct trios (27 devices) plus the single proxy phone → 28 smartphones total.

2. Analytical commentary
2.1 Macro‑structure & forces
Element    Quantity    Function
Traditional choir voices    27 singers (9 Sopranos, 9 Altos, 9 Tenors/Basses)    Read from a notated score; supply choral textures, text, harmony.
Smartphone choir voices    27 singers in 9 colour‑coded trios    Trigger phone loudspeakers & flashlights; produce electro‑acoustic and visual layers.
Proxy controller singer    1 Tenor/Bass with phone    Acts as on‑stage “time‑base” (tap tempo) and emergency control.
Off‑stage tech    1 MacBook + offline Wi‑Fi router    Runs the master patch / lighting engine; transmits OSC or WebSocket cues to every phone.

Total human performers = 54.
Total phones = 28 (27 performers + 1 proxy).
Performance length ≈ 9 minutes.

2.2 Spatial design
Half‑circle layout keeps all singers visible to both audience and conductor, but places the phone trios slightly forward (inner arc) so their light beams project cleanly.

Grid‑like black lines provide reference points for precise standing positions and visually echo the PCB/network theme.

The rainbow ribbon in the legend mirrors the coloured rings on stage, reinforcing the idea that each trio is an autonomous “node” on the network.

2.3 Colour & role mapping
Colour    Smartphone trio    Vocal register    Possible timbral goal
🔴 Red    A3    upper alto    bright, alarm‑like pulses
🟢 Green    S3    soprano    shimmering, rapid flutter
🟣 Purple    B1    bass    low sub‑harmonic rumbles
🟡 Gold    T1    tenor    rhythmic mid‑range motifs
🌸 Pink    B2    bass    “choral sub‑bass” drones
🟠 Orange    S1    soprano    piercing singles / strobe
💖 Magenta    S2    soprano    melodic fragments
🔵 Blue    A2    alto    call‑and‑response delays
🩵 Cyan    A1    alto    wide‑band noise sweeps

Observation: distributing every colour around the arc avoids clustering one timbre or light hue in a single sector, yielding a surround‑sound & surround‑light experience.

2.4 Technology flow
MacBook launches the score’s master patch.

A closed (offline) Wi‑Fi router creates a latency‑controlled network; no internet = fewer drop‑outs.

All 28 phones join; timestamps are periodically re‑synchronised (NTP/OSC).

The proxy Tenor/Bass receives redundant cue packets; if Wi‑Fi glitches, they “tap” the pattern so the ensemble never loses the beat.

Each phone drives both loudspeaker samples and its flashlight LED, turning the choir into a living light‑array that punctuates the darkened hall.

2.5 Score logistics
Two scores per singer type: a normal choral part and a condensed “phone cue” part.

Conductor’s KEY succinctly shows which group looks up when (the teal arrows) – crucial in low‑light conditions.

The graphic anticipates rehearsal needs: traditional readers sight‑sing first; phone singers rehearse with headphones; then merged run‑throughs leverage the proxy’s tap‑tempo for alignment.

2.6 Aesthetic implications
By mixing human vibrato with phone samplers the piece blurs organic vs. synthetic timbres – aligning with your own Simphoni ethos of “collaborative intelligence”.

The neon‑mint + magenta palette carries your brand language forward, signaling that this is as much a visual performance as an aural one.

Flashlights turn every performer into a pixel in a dynamic screen – a scalable concept should you wish to port this to larger forces or VR representation inside Simphoni‑Spatial.

2.7 Potential refinements
Consideration    Suggestion
Emergency fallback    Add a wired audio click to front‑row monitors so the conductor can re‑calibrate if Wi‑Fi fully drops.
Battery drain    Stagger flashlight intensity between trios, or instruct singers to start at ≥ 80 % charge.
Choreography    The grid lines could become LEDs or tape on stage to guide darkness‑navigation.
Immersion    For VR capture, mount 360° cameras at the conductor’s and audience mid‑aisle positions; the colour coding already aids later spatial audio mixing.

In short: the chart is a compact performance blueprint that balances score reading, networked electronics, and theatrical light design, clearly separating traditional and smartphone forces while showing how they merge in a 54‑voice, 28‑device electro‑acoustic tapestry.
