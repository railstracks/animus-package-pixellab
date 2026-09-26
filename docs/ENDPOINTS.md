# Endpoint reference

Param mapping from package commands to the PixelLab API (`/v1`, Bearer auth).
Types are the manifest/tool-schema types; the API's JSON types are what the
scripts emit. Sizes are validated client-side — see the constraints column.

## Shared enums

| enum | values |
|---|---|
| views (`view`, `from_view`, `to_view`) | `side`, `low top-down`, `high top-down` |
| directions (`direction`, `from_direction`, `to_direction`) | `north`, `north-east`, `east`, `south-east`, `south`, `south-west`, `west`, `north-west` |
| outline | `single color black outline`, `single color outline`, `selective outline`, `lineless` |
| shading | `flat shading`, `basic shading`, `medium shading`, `detailed shading`, `highly detailed shading` |
| detail | `low detail`, `medium detail`, `highly detailed` |

Shared conventions:

- **Image inputs** are filespace paths (`init_image`, `color_image`, …).
  Array params (`init_images`, `inpainting_images`, `mask_images`) are
  comma-separated paths; counts must match the endpoint's frame window.
- **`init_image_strength`**: integer, API default 300, how strongly the init
  image guides generation.
- **`color_image`**: forced palette — colors are sampled from the image.
- **`seed`**: integer for reproducible outputs (0/absent = random); echoed in
  output filenames.
- **`filename`**: optional output name (sanitized; overwrites existing).

## generate pixflux — POST /v1/generate-image-pixflux

| param | type | req | notes |
|---|---|---|---|
| `description` | string | ✓ | what to generate |
| `width` / `height` | integer | ✓ | 16–400 each; area 32×32–400×400 |
| `text_guidance_scale` | string(number) | | default 8 |
| `outline` / `shading` / `detail` | string enum | | weakly guiding |
| `view` / `direction` | string enum | | weakly guiding |
| `isometric` | boolean | | |
| `no_background` | boolean | | transparent background |
| `init_image` | path | | + `init_image_strength` |
| `color_image` | path | | forced palette |
| `seed` / `filename` | integer / string | | |

## generate bitforge — POST /v1/generate-image-bitforge

| param | type | req | notes |
|---|---|---|---|
| `description` | string | ✓ | |
| `width` / `height` | integer | ✓ | 16–200 each; area ≤ 200×200 |
| `negative_description` | string | | what to avoid |
| `text_guidance_scale` | string(number) | | default 8 |
| `style_image` | path | | the style reference |
| `style_strength` | integer | | 0–100, default 0 (50 = balanced) |
| `outline` / `shading` / `detail` / `view` / `direction` | enum | | |
| `isometric` / `oblique_projection` / `no_background` | boolean | | |
| `coverage_percentage` | string(number) | | 1–100, share of canvas covered |
| `init_image` | path | | + `init_image_strength` |
| `inpainting_image` + `mask_image` | path | | pair; white = regenerate |
| `color_image` | path | | |
| `skeleton_guidance_scale` | string(number) | | default 1 |
| `skeleton_keypoints` | string (JSON) | | frames of `{x,y,label,z_index?}`; non-16/32/64 sizes degrade quality (API warning) |
| `seed` / `filename` | | | |

## animate skeleton — POST /v1/animate-with-skeleton

| param | type | req | notes |
|---|---|---|---|
| `width` / `height` | integer | ✓ | each from 16/32/64/128/256 |
| `reference_image` | path | ✓ | character, transparent background |
| `skeleton_keypoints` | string (JSON) | ✓ | **exactly 3 frames** — the model is a 3-frame window; edit `skeleton estimate` output |
| `guidance_scale` | string(number) | | default 4 — reference/keypoint fidelity |
| `view` / `direction` | enum | | |
| `isometric` / `oblique_projection` | boolean | | |
| `init_images` | paths | | exactly 3 |
| `init_image_strength` | integer | | |
| `inpainting_images` / `mask_images` | paths | | exactly 3 each |
| `color_image` | path | | |
| `seed` / `filename` | | | frames get `_f1.._f4` |

Always generates 4 frames. Longer animations: re-run with the next 3-pose
window, feeding prior frames via `init_images`.

## animate text — POST /v1/animate-with-text

| param | type | req | notes |
|---|---|---|---|
| `description` | string | ✓ | the character |
| `action` | string | ✓ | what it does |
| `reference_image` | path | ✓ | |
| `width` / `height` | integer | | fixed 64×64 (only accepted value) |
| `negative_description` | string | | |
| `text_guidance_scale` | string(number) | | default 8 |
| `image_guidance_scale` | string(number) | | default 1.4 |
| `n_frames` | integer | | default 4; model always generates 4 |
| `start_frame_index` | integer | | default 0; window start for longer animations |
| `view` / `direction` | enum | | |
| `init_images` / `inpainting_images` / `mask_images` | paths | | exactly 4 each |
| `init_image_strength` | integer | | |
| `color_image` | path | | |
| `seed` / `filename` | | | output names carry `_a<start_frame_index>` |

## rotate — POST /v1/rotate

| param | type | req | notes |
|---|---|---|---|
| `from_image` | path | ✓ | source |
| `width` / `height` | integer | ✓ | each from 16/32/64/128 |
| `from_view` / `to_view` | enum | | defaults `side`/`side` |
| `from_direction` / `to_direction` | enum | | defaults `south`/`east` |
| `view_change` | string(number) | | degrees of camera tilt |
| `direction_change` | string(number) | | degrees of subject rotation |
| `image_guidance_scale` | string(number) | | default 3 |
| `isometric` / `oblique_projection` | boolean | | |
| `init_image` | path | | + `init_image_strength` |
| `mask_image` | path | | **requires** `init_image` |
| `color_image` | path | | |
| `seed` / `filename` | | | |

## inpaint — POST /v1/inpaint

| param | type | req | notes |
|---|---|---|---|
| `description` | string | ✓ | the change to make |
| `inpainting_image` | path | ✓ | image to edit |
| `mask_image` | path | ✓ | white = regenerate |
| `width` / `height` | integer | ✓ | 16–200 each; area ≤ 200×200 |
| `negative_description` | string | | |
| `text_guidance_scale` | string(number) | | default 3 |
| `outline` / `shading` / `detail` / `view` / `direction` | enum | | |
| `isometric` / `oblique_projection` / `no_background` | boolean | | |
| `init_image` | path | | + `init_image_strength` |
| `color_image` | path | | |
| `seed` / `filename` | | | |

## skeleton estimate — POST /v1/estimate-skeleton

| param | type | req | notes |
|---|---|---|---|
| `image` | path | ✓ | character on transparent background, 16–256/side |

Returns `data.keypoints` — an array of `{x, y, label, z_index}` (18 labels:
NOSE, NECK, shoulders/elbows/arms, hips/knees/legs, eyes, ears). No file
output. Feed the (edited) frames to `animate skeleton`.

## balance get — GET /v1/balance

No parameters. Returns `data.balance_usd`.

## Error mapping

Every command maps HTTP errors to actionable text: 401 → token hint,
402 → balance/top-up, 422 → API validation detail, 429 → retry later,
529 → service overloaded. Transport and non-200 responses include
`http_status` in the result.
