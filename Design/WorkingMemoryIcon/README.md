# Working Memory Icon System

## Concept

The selected mark is **WM Brain**. A symmetrical brain structure surrounds a central capsule with a bold custom `WM` monogram, making the product name immediately legible while retaining the memory metaphor from the supplied mockup.

This direction supersedes the earlier Thread Through Snapshot mark by explicit product-owner selection. One simplified construction is the complete production identity at every current size; there is no separate detailed or marketing master.

## Palette

- Deep indigo: `#1B2472`
- Blue: `#3A49E0`
- Violet: `#6A4DFF`
- Off-white: `#F5F7FF`
- Periwinkle: `#BBD1FF`

## Construction

- Canvas: 1024 × 1024, square and unmasked.
- Foreground optical bounds: `x: 128–896`, `y: 176–816`; visual mass centered at `(512, 504)`.
- Icon Composer layer order, back to front: `00-background.svg`, `01-brain-structure.svg`, `02-capsule.svg`, `03-wm-monogram.svg`.
- The full-bleed background is square and unmasked. It owns the exact indigo-to-violet brand gradient; macOS owns corner masking and native depth.
- The brain is drawn as one hemisphere mirrored across `x = 512`, with one outer contour and one lower interior fold per side. Upper interior folds are intentionally omitted to keep the space above the monogram quiet.
- Outer brain strokes are 72 px; lower interior folds are 60 px. All joins and terminals are round.
- Capsule bounds are `x: 210–814`, `y: 370–654`, with a 142 px radius.
- The `WM` is custom outlined vector artwork, not live text, with a 28 px optical gap between letters.
- Preserve source colors and all four layers in Default, Dark, and Mono appearances. Liquid Glass is disabled on foreground layers.
- Use only restrained native group depth: neutral shadow at 35% and translucency at 28%.
- Do not add circuit nodes, timers, documents, chat bubbles, sparkles, secondary text, or baked shadows.

## Usage

- `WorkingMemorySnapshot/AppIcon.icon` is the application icon source for Xcode 26 and newer.
- `WorkingMemoryIcon.svg` is the deterministic, identical four-layer flattening for the 40-point in-app header tile.
- The existing “Working Memory / Snapshot” SF typography remains unchanged.

The prior similarity screen and this user-selected revision are directional design checks, not formal trademark clearance.
