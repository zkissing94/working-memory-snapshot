# Working Memory Icon System

## Concept

The selected mark is **WM Brain**. A symmetrical brain structure surrounds a central capsule with a bold `WM` knockout, making the product name immediately legible while retaining the memory metaphor from the supplied mockup.

This direction supersedes the earlier Thread Through Snapshot mark by explicit product-owner selection. The production artwork simplifies the mockup's fine brain-line detail into a small-size-safe system with two dominant foreground layers.

## Palette

- Indigo: `#243C8F`
- Violet: `#6558E8`
- Off-white: `#F7F8FF`
- Periwinkle: `#B8C7FF`

## Construction

- Canvas: 1024 × 1024, square and unmasked.
- Icon Composer layer order: `00-background.svg`, `01-brain-structure.svg`, `02-wm-capsule.svg`.
- Keep source artwork flat and opaque. The full-bleed background owns the exact brand gradient; Icon Composer owns masking and system material effects.
- Preserve the geometry and layer order in Default, Dark, and Mono appearances.
- Preserve the open, symmetrical brain silhouette and the negative-space `WM` letterforms.
- Do not add circuit nodes, timers, documents, chat bubbles, sparkles, secondary text, or baked shadows.

## Usage

- `WorkingMemorySnapshot/AppIcon.icon` is the application icon source for Xcode 26 and newer.
- `WorkingMemoryIcon.svg` is the deterministic flattened source for the 40-point in-app header tile.
- The existing “Working Memory / Snapshot” SF typography remains unchanged.

The prior similarity screen and this user-selected revision are directional design checks, not formal trademark clearance.
