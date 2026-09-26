-- animate text: text-guided 64x64 animation (POST /v1/animate-with-text)
function run(ctx)
  local pkg = ctx.package
  if not shared.require_auth(pkg) then
    return {success = false, error = "api_token not configured (get one at https://pixellab.ai/account)"}
  end
  local a = ctx.args
  if a.description == nil or a.description == "" then
    return {success = false, error = "description required (the character)"}
  end
  if a.action == nil or a.action == "" then
    return {success = false, error = "action required (what the character does)"}
  end

  -- Size is fixed at 64x64; width/height accepted only when they say 64.
  local w = 64
  local h = 64
  if (a.width ~= nil and a.width ~= "") or (a.height ~= nil and a.height ~= "") then
    local wt, werr = shared.int_arg(a, "width")
    if werr then return {success = false, error = werr} end
    local ht, herr = shared.int_arg(a, "height")
    if herr then return {success = false, error = herr} end
    w = wt or 64
    h = ht or 64
    local serr = shared.check_size(w, h, shared.SIZES.animate_text)
    if serr then return {success = false, error = serr .. " (this model only supports 64x64)"} end
  end

  local err = shared.check_enum(a.view, shared.VIEWS, "view")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.direction, shared.DIRECTIONS, "direction")
  if err then return {success = false, error = err} end

  local tgs, terr = shared.num_arg(a, "text_guidance_scale")
  if terr then return {success = false, error = terr} end
  local igs, terr = shared.num_arg(a, "image_guidance_scale")
  if terr then return {success = false, error = terr} end
  local n_frames, terr = shared.int_arg(a, "n_frames", 4)
  if terr then return {success = false, error = terr} end
  local start_f, terr = shared.int_arg(a, "start_frame_index", 0)
  if terr then return {success = false, error = terr} end
  if n_frames ~= nil and n_frames < 4 then
    return {success = false, error = "n_frames >= 4 (the model always generates 4 frames; use start_frame_index for longer animations)"}
  end
  local strength, terr = shared.int_arg(a, "init_image_strength")
  if terr then return {success = false, error = terr} end
  local seed, terr = shared.int_arg(a, "seed")
  if terr then return {success = false, error = terr} end

  local ref, ierr = shared.read_image(ctx, a.reference_image, "reference_image")
  if ref == nil then return {success = false, error = ierr} end

  local body = {
    description = tostring(a.description),
    action = tostring(a.action),
    image_size = { width = 64, height = 64 },
    reference_image = ref
  }
  if a.negative_description ~= nil and a.negative_description ~= "" then
    body.negative_description = tostring(a.negative_description)
  end
  if tgs ~= nil then body.text_guidance_scale = tgs end
  if igs ~= nil then body.image_guidance_scale = igs end
  if n_frames ~= nil then body.n_frames = n_frames end
  if start_f ~= nil then body.start_frame_index = start_f end
  if a.view ~= nil and a.view ~= "" then body.view = a.view end
  if a.direction ~= nil and a.direction ~= "" then body.direction = a.direction end

  if a.init_images ~= nil and a.init_images ~= "" then
    local imgs, ierr2 = shared.read_images(ctx, a.init_images, "init_images", 4)
    if imgs == nil then return {success = false, error = ierr2 or "init_images: must be exactly 4 comma-separated paths"} end
    body.init_images = imgs
    if strength ~= nil then body.init_image_strength = strength end
  end
  if a.inpainting_images ~= nil and a.inpainting_images ~= "" then
    local imgs, ierr2 = shared.read_images(ctx, a.inpainting_images, "inpainting_images", 4)
    if imgs == nil then return {success = false, error = ierr2 or "inpainting_images: must be exactly 4 comma-separated paths"} end
    body.inpainting_images = imgs
  end
  if a.mask_images ~= nil and a.mask_images ~= "" then
    local imgs, ierr2 = shared.read_images(ctx, a.mask_images, "mask_images", 4)
    if imgs == nil then return {success = false, error = ierr2 or "mask_images: must be exactly 4 comma-separated paths"} end
    body.mask_images = imgs
  end
  if a.color_image ~= nil and a.color_image ~= "" then
    local img, cerr = shared.read_image(ctx, a.color_image, "color_image")
    if img == nil then return {success = false, error = cerr} end
    body.color_image = img
  end
  if seed ~= nil then body.seed = seed end

  local r = shared.post(ctx, pkg, "/animate-with-text", body, shared.slow_timeout_s(pkg))
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  local base = shared.out_base(ctx, "animate", a.filename, seed, "_a" .. tostring(start_f or 0))
  local files, werr = shared.write_images(ctx, r.json.images, base)
  if files == nil then return {success = false, error = werr} end
  return {
    success = true,
    files = files,
    meta = {
      usage = shared.usage_meta(r.json),
      model = "animate-text",
      frames = #files,
      start_frame_index = start_f or 0,
      size = "64x64",
      seed = seed or 0
    }
  }
end
