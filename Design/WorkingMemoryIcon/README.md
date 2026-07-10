# Working Memory Icon System

## Concept

The selected mark is **Thread Through Snapshot**. A single thread passes behind a snapshot boundary and returns in front, representing context captured at the end of one work session and resumed in the next.

The generated Folded-W direction was rejected during the similarity screen because white ribbon-W marks on blue gradients are already used by multiple live products. The selected mark avoids relying on a generic initial while staying tied to the product loop.

## Palette

- Indigo: `#243C8F`
- Violet: `#6558E8`
- Off-white: `#F7F8FF`
- Periwinkle: `#B8C7FF`

## Construction

- Canvas: 1024 × 1024, square and unmasked.
- Icon Composer layer order: `00-background.svg`, `01-rear-thread.svg`, `02-snapshot-frame.svg`, `03-resume-thread.svg`.
- Keep source artwork flat and opaque. The full-bleed background owns the exact brand gradient; Icon Composer owns masking and system material effects.
- Preserve the geometry and layer order in Default, Dark, and Mono appearances.
- Do not add brains, circuit nodes, timers, documents, chat bubbles, sparkles, text, or baked shadows.

## Usage

- `WorkingMemorySnapshot/AppIcon.icon` is the application icon source for Xcode 26 and newer.
- `WorkingMemoryIcon.svg` is the deterministic flattened source for the 40-point in-app header tile.
- The existing “Working Memory / Snapshot” SF typography remains unchanged.

The similarity screen is a directional check, not formal trademark clearance.
