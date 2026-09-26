-- rotate: turn a character between views/directions (POST /v1/rotate)
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
    return {success = false, error = "width and height are required (each from 16/32/64/128)"}
  end
  err = shared.check_size(w, h, shared.SIZES.rotate)
  if err then return {success = false, error = err} end

  err = shared.check_enum(a.from_view, shared.VIEWS, "from_view")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.to_view, shared.VIEWS, "to_view")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.from_direction, shared.DIRECTIONS, "from_direction")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.to_direction, shared.DIRECTIONS, "to_direction")
  if err then return {success = false, error = err} end

  local vc, terr = shared.num_arg(a, "view_change")
  if terr then return {success = false, error = terr} end
  local dc, terr = shared.num_arg(a, "direction_change")
  if terr then return {success = false, error = terr} end
  local igs, terr = shared.num_arg(a, "image_guidance_scale")
  if terr then return {success = false, error = terr} end
  local strength, terr = shared.int_arg(a, "init_image_strength")
  if terr then return {success = false, error = terr} end
  local seed, terr = shared.int_arg(a, "seed")
  if terr then return {success = false, error = terr} end

  local from, ierr = shared.read_image(ctx, a.from_image, "from_image")
  if from == nil then return {success = false, error = ierr} end

  local has_init = a.init_image ~= nil and a.init_image ~= ""
  if a.mask_image ~= nil and a.mask_image ~= "" and not has_init then
    return {success = false, error = "mask_image requires init_image (per the API)"}
  end

  local body = {
    image_size = { width = w, height = h },
    from_image = from
  }
  if a.from_view ~= nil and a.from_view ~= "" then body.from_view = a.from_view end
  if a.to_view ~= nil and a.to_view ~= "" then body.to_view = a.to_view end
  if a.from_direction ~= nil and a.from_direction ~= "" then body.from_direction = a.from_direction end
  if a.to_direction ~= nil and a.to_direction ~= "" then body.to_direction = a.to_direction end
  if vc ~= nil then body.view_change = vc end
  if dc ~= nil then body.direction_change = dc end
  if igs ~= nil then body.image_guidance_scale = igs end
  if shared.bool_arg(a, "isometric") then body.isometric = true end
  if shared.bool_arg(a, "oblique_projection") then body.oblique_projection = true end
  if has_init then
    local img, ierr2 = shared.read_image(ctx, a.init_image, "init_image")
    if img == nil then return {success = false, error = ierr2} end
    body.init_image = img
    if strength ~= nil then body.init_image_strength = strength end
  end
  if a.mask_image ~= nil and a.mask_image ~= "" then
    local img, merr = shared.read_image(ctx, a.mask_image, "mask_image")
    if img == nil then return {success = false, error = merr} end
    body.mask_image = img
  end
  if a.color_image ~= nil and a.color_image ~= "" then
    local img, cerr = shared.read_image(ctx, a.color_image, "color_image")
    if img == nil then return {success = false, error = cerr} end
    body.color_image = img
  end
  if seed ~= nil then body.seed = seed end

  local r = shared.post(ctx, pkg, "/rotate", body, shared.slow_timeout_s(pkg))
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  local base = shared.out_base(ctx, "rotate", a.filename, seed)
  local files, werr = shared.write_images(ctx, r.json.image, base)
  if files == nil then return {success = false, error = werr} end
  return {
    success = true,
    files = files,
    meta = {
      usage = shared.usage_meta(r.json),
      model = "rotate",
      from = (a.from_view or "side") .. "/" .. (a.from_direction or "south"),
      to = (a.to_view or "side") .. "/" .. (a.to_direction or "east"),
      size = w .. "x" .. h,
      seed = seed or 0
    }
  }
end
