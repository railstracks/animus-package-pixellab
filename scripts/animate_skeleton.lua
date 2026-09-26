-- animate skeleton: 3-frame-window animation from poses (POST /v1/animate-with-skeleton)
function run(ctx)
  local pkg = ctx.package
  if not shared.require_auth(pkg) then
    return {success = false, error = "api_token not configured (get one at https://pixellab.ai/account)"}
  end
  local a = ctx.args
  local w, err = shared.int_arg(a, "width")
  if err then return {success = false, error = err} end
  local h, err = shared.int_arg(a, "height")
  if err then return {success = false, error = err} end
  if w == nil or h == nil then
    return {success = false, error = "width and height are required (each from 16/32/64/128/256)"}
  end
  err = shared.check_size(w, h, shared.SIZES.animate_skeleton)
  if err then return {success = false, error = err} end

  err = shared.check_enum(a.view, shared.VIEWS, "view")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.direction, shared.DIRECTIONS, "direction")
  if err then return {success = false, error = err} end

  local gs, terr = shared.num_arg(a, "guidance_scale")
  if terr then return {success = false, error = terr} end
  local strength, terr = shared.int_arg(a, "init_image_strength")
  if terr then return {success = false, error = terr} end
  local seed, terr = shared.int_arg(a, "seed")
  if terr then return {success = false, error = terr} end

  local ref, ierr = shared.read_image(ctx, a.reference_image, "reference_image")
  if ref == nil then return {success = false, error = ierr} end

  local kp, kerr = shared.parse_keypoints(a.skeleton_keypoints, 3)
  if kp == nil then return {success = false, error = kerr} end

  local body = {
    image_size = { width = w, height = h },
    reference_image = ref,
    skeleton_keypoints = kp
  }
  if gs ~= nil then body.guidance_scale = gs end
  if a.view ~= nil and a.view ~= "" then body.view = a.view end
  if a.direction ~= nil and a.direction ~= "" then body.direction = a.direction end
  if shared.bool_arg(a, "isometric") then body.isometric = true end
  if shared.bool_arg(a, "oblique_projection") then body.oblique_projection = true end

  if a.init_images ~= nil and a.init_images ~= "" then
    local imgs, ierr2 = shared.read_images(ctx, a.init_images, "init_images", 3)
    if imgs == nil then return {success = false, error = ierr2 or "init_images: must be exactly 3 comma-separated paths"} end
    body.init_images = imgs
    if strength ~= nil then body.init_image_strength = strength end
  end
  if a.inpainting_images ~= nil and a.inpainting_images ~= "" then
    local imgs, ierr2 = shared.read_images(ctx, a.inpainting_images, "inpainting_images", 3)
    if imgs == nil then return {success = false, error = ierr2 or "inpainting_images: must be exactly 3 comma-separated paths"} end
    body.inpainting_images = imgs
  end
  if a.mask_images ~= nil and a.mask_images ~= "" then
    local imgs, ierr2 = shared.read_images(ctx, a.mask_images, "mask_images", 3)
    if imgs == nil then return {success = false, error = ierr2 or "mask_images: must be exactly 3 comma-separated paths"} end
    body.mask_images = imgs
  end
  if a.color_image ~= nil and a.color_image ~= "" then
    local img, cerr = shared.read_image(ctx, a.color_image, "color_image")
    if img == nil then return {success = false, error = cerr} end
    body.color_image = img
  end
  if seed ~= nil then body.seed = seed end

  local r = shared.post(ctx, pkg, "/animate-with-skeleton", body, shared.slow_timeout_s(pkg))
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  local base = shared.out_base(ctx, "animate", a.filename, seed)
  local files, werr = shared.write_images(ctx, r.json.images, base)
  if files == nil then return {success = false, error = werr} end
  return {
    success = true,
    files = files,
    meta = {
      usage = shared.usage_meta(r.json),
      model = "animate-skeleton",
      frames = #files,
      size = w .. "x" .. h,
      seed = seed or 0
    }
  }
end
