# ShoutOut Mascot Assets

This folder contains the canonical generated mascot sources used to derive web and macOS sprite assets.

## Sets

- `idle-walk/`: no boom microphone. Use for normal idle movement, walking, and wall traversal.
- `recording-boom/`: boom microphone visible. Use only for recording/listening states. The website should render this as a still pose; recording should feel steady, not busy.

Each set includes:

- `source.png`: original generated sheet on chroma key.
- `source-alpha.png`: chroma-key removed source sheet.
- `frame-1.png` through `frame-4.png`: normalized 724px transparent square frames.
- `sheet.png`: normalized 4-frame transparent sheet.

`recording-boom/boom-mic-overlay.png` is the recording source of truth. The
sync script composites that overlay onto `idle-walk/frame-1.png` so the crab
body, face, headphones, claws, and legs remain pixel-identical when the app
switches into recording.

## Derived Assets

The website consumes:

- `apps/web/public/assets/mascot/idle-walk.png`
- `apps/web/public/assets/mascot/recording-boom.png` as a static first-frame recording pose.

The macOS app resources are derived from the same frames while preserving existing file names and canvas sizes:

- `apps/macos/Resources/CrabSprites/idle-1.png` through `idle-4.png`
- `apps/macos/Resources/CrabSprites/recording-1.png` through `recording-4.png`
- `apps/macos/Resources/CrabSpritesWall/idle-1.png` through `idle-4.png`
- `apps/macos/Resources/CrabSpritesWall/recording-2.png`

Wall sprites are rotated from the shared source frames, so the same mascot can move horizontally on the website and vertically in the product.
