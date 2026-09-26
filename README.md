# animus-package-pixellab

PixelLab pixel-art generation API as an [Animus](https://github.com/railstracks/animus)
api package (manifest v1). Turns [PixelLab's](https://www.pixellab.ai/) generation
models into agent tools: text-to-image, style transfer, two animation models,
rotation, inpainting, and skeleton estimation.

Source of truth for the API surface: the OpenAPI spec at
`https://api.pixellab.ai/v1/openapi.json` (the docs site renders it).

## Commands

| Command | Endpoint | What it does |
|---|---|---|
| `generate pixflux` | POST `/v1/generate-image-pixflux` | Text → pixel art (16–400px/side) |
| `generate bitforge` | POST `/v1/generate-image-bitforge` | Style-transfer generation (≤200×200 area) |
| `animate skeleton` | POST `/v1/animate-with-skeleton` | 4-frame animation windows from 3 skeleton poses |
| `animate text` | POST `/v1/animate-with-text` | Text-guided animation (64×64 only) |
| `rotate` | POST `/v1/rotate` | Turn a character between views/directions |
| `inpaint` | POST `/v1/inpaint` | Mask-guided editing |
| `skeleton estimate` | POST `/v1/estimate-skeleton` | Image → 18 labeled keypoints |
| `balance get` | GET `/v1/balance` | USD balance |

Full parameter reference: [`docs/ENDPOINTS.md`](docs/ENDPOINTS.md).

## How images flow

The package filespace is the image bus — the **flat** package directory
(kernel rule: slug names only, no subdirectories):

- **Inputs** (`init_image`, `reference_image`, `mask_image`, arrays like
  `init_images` = comma-separated paths) are filespace paths, read and
  base64-encoded by the script. Usually these are outputs of earlier calls.
- **Outputs** are decoded and written as PNG files; the result carries a
  verified `files` array of paths plus `meta.usage` (what the call cost).
  Without a `filename` param, names are auto-generated and never collide:
  `pixflux-20260926-041500_s42.png` (UTC timestamp + seed). With `filename`,
  the sanitized name is used and **overwrites** — that's the iteration
  workflow (`hero.png` refined across calls). Animation frames get `_f1.._f4`
  suffixes.

Reads are capped at 1 MB per file by the kernel — irrelevant for pixel art at
supported sizes, but noted for completeness.

## Composition recipes

The commands compose into full asset pipelines:

- **Walk cycle from scratch:** `generate pixflux` (character, transparent
  background) → `skeleton estimate` → edit the 3 pose frames →
  `animate skeleton` (repeat with the next 3-frame window, chaining frames
  via `init_images`) → `inpaint` fixes → `rotate` for the other facings.
- **Style-matched enemy set:** one `generate pixflux` hero as the
  `style_image`, then `generate bitforge` per enemy.
- **Rigging assist:** `skeleton estimate` gives z-ordered keypoints; the same
  JSON feeds `animate skeleton` and bitforge's `skeleton_keypoints`.

## Cost model

Every generation response carries a `usage` block (USD or generations); the
package surfaces it in `meta.usage`. Check `balance get` before long runs.
Client-side validation (sizes, enums, required masks, keypoint shape) fails
before any HTTP call — mistakes are free.

## State

| key | type | secret | notes |
|---|---|---|---|
| `api_token` | string | ✓ | from <https://pixellab.ai/account> |
| `base_url` | string | | default `https://api.pixellab.ai`; trailing `/v1` tolerated |

Egress: `api.pixellab.ai` only (declared in the manifest, deny-by-default
elsewhere).

## Development

```
python3 build.py              # emits built/manifest.json (scripts inlined)
lua tests/test_shared.lua     # helper unit tests
lua tests/test_commands.lua   # integration tests (stubbed http/fs, real files)
python3 tests/test_manifest.py # manifest lint (kernel rules mirrored)
```

All three suites green before every publish. Lua 5.4.

## License

MIT
