# Modes

Fifteen bodies of water. Each is a different *substance*, not a different
palette — see [DECISIONS.md](DECISIONS.md#5-modes-are-behaviour-not-palettes).

Ordered restful first, so the picker opens on what most people want and the
violent ones are a deliberate scroll away.

## The catalogue

| Mode | Character | Defining feature |
|---|---|---|
| **Calm ocean** | Deep blue, orderly swell. The one to fall asleep to | — |
| **Rain shower** | Nothing but falling drops | `rainRate` — the only mode alive when you are still |
| **Tide pool** | Clear water over sand and pebbles | `bedDetail` |
| **Koi pond** | Still green water, something moving below | `shadows` |
| **Under ice** | Frozen, cracked, barely responsive | `causticTimeScale = 0` |
| **Aurora** | Black water with the sky in it | `skyGlow` |
| **Midnight glow** | Dark; lights up where you stir it | `glowResponse` |
| **Deep drift** | Snow falling through light shafts | `shafts` + drifting particles |
| **Zero gravity** | No up, no down; the swell wanders | `followsGravity = false` |
| **Tropical lagoon** | Bright turquoise, warm light | — |
| **Molten** | Not water: thick, slow, lit from below | — |
| **Mercury** | Silver, heavy, hard specular | — |
| **Storm swell** | Grey and heaving | moderate foam and chop |
| **Breaking surf** | Crests break, whitecaps tear across, spray flies | `foaminess` + `crestSharpness` + spray |
| **Storm at night** | Breaking surf, unlit, with lightning | `lightningInterval` |

## What the behaviour fields do, and the traps in them

**`crestSharpness`** raises a wave's half-cycle to a power, narrowing crests and
broadening troughs — the trochoidal shape water takes as it steepens toward
breaking. The derivative is carried through so the normal stays exact.

> Sharpening *every* band drives the whole fan into a regular diamond lattice
> that reads as lace, not sea. Only the two longest bands are sharpened and the
> value is capped well below 1.

**`turbulence`** warps the sampling domain before the waves are evaluated, in two
octaves at unrelated scales.

> One octave only translates the lattice; two dissolve it. This is the main
> defence against the periodicity of a sum of sines becoming visible.

**`foaminess`** keys off surface steepness, so whitecaps land exactly on breaking
crests and ripple fronts and spread on their own when the water is thrown about.

> The threshold is high on purpose. Foam that starts too early covers everything
> in white haze — that reads as fog, not as breaking waves.

**`causticTimeScale`** scales how fast the caustic web evolves. **Zero freezes
it**, turning the same cell network from moving light into a static fracture
pattern. That one number is the whole of Under ice.

**`bedDetail`** draws sand ripples and pebbles under the refraction.

> Pebbles are jittered inside their cells and randomly skipped. One pebble at the
> centre of every cell of a square grid does not read as a stony bottom, it reads
> as polka dots.

**`shadows`** puts silhouettes below the surface — never lit, never detailed. A
fish underwater reads as a moving absence of light; drawing scales at this size
only makes mush.

**`shafts`** are leaned rather than vertical. Shafts running straight down the
screen look like a UI gradient; leaning them looks like light entering at an
angle.

**`skyGlow`** reflects coloured curtains, weighted by the same grazing-angle term
as the sheen so they live *in* the surface and ripple with it rather than
floating over the top as a decal.

**`lightningInterval`** is an *average*, with real variance. A metronome is
maddening over minutes. The flash lands hardest on the foam, so a strike reveals
the shape of the water rather than washing the screen flat, and it decays hard —
a slow fade reads as someone turning a lamp up.

**`motionGain`** scales how hard the mode answers the wrist: 2.6 for Breaking
surf against 0.55 for Rain shower.

**`rainRate`** spawns ripples from nothing. Fractional drops carry over, so a
slow shower still produces evenly spaced drops rather than none.

**`followsGravity = false`** makes the swell ignore gravity and wander on two
incommensurate rates — one rate is a visible loop.

## Adding a mode

1. Add a `static let` to `OceanTheme` in
   `OceanCore/Sources/OceanCore/OceanTheme.swift`. **Declare only what makes it
   different** — every behaviour field defaults to off.
2. Add it to `OceanTheme.all`, in the right place for its restfulness.
3. If it needs a capability that does not exist, add a parameter and a
   uniform-branched block in `WaterShader`. Mind the uniform ceiling — see
   [ARCHITECTURE.md](ARCHITECTURE.md#the-spritekit-shader-contract) — and **pack
   into an existing `vec4` rather than adding a slot**.
4. Add a check to `oceancheck` asserting the mode has its defining feature. The
   suite tests the catalogue against its own premise, so a new mode that is
   secretly a recolour should fail.
5. Look at it on the simulator:
   ```bash
   xcrun simctl launch <udid> com.example.Slosh.watchkitapp -themeID <id>
   ```

## Unbuilt ideas

- **Rain on glass** — droplets running down a pane, merging as they go. The one
  idea here that the height-field approach cannot already express; it needs a
  genuinely different simulation.
- **Sunrise** — a single mode whose palette tracks real time of day.
- **Aquarium** — Koi pond's shadows over Tide pool's bed, at depth.
- **Storm surge** — Breaking surf that builds and subsides over minutes rather
  than answering the wrist directly.
