-- generate pixflux: text-to-image (POST /v1/generate-image-pixflux)
function run(ctx)
  local pkg = ctx.package
  if not shared.require_auth(pkg) then
    return {success = false, error = "api_token not configured (get one at https://pixellab.ai/account)"}
  end
  local a = ctx.args
  if a.description == nil or a.description == "" then
    return {success = false, error = "description required"}
  end
  local w, err = shared.int_arg(a, "width")
  if err then return {success = false, error = err} end
  local h, err = shared.int_arg(a, "height")
  if err then return {success = false, error = err} end
  if w == nil or h == nil then
    return {success = false, error = "width and height are required (16-400 each, area 32x32 to 400x400)"}
  end
  err = shared.check_size(w, h, shared.SIZES.pixflux)
  if err then return {success = false, error = err} end

  err = shared.check_enum(a.outline, shared.OUTLINES, "outline")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.shading, shared.SHADINGS, "shading")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.detail, shared.DETAILS, "detail")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.view, shared.VIEWS, "view")
  if err then return {success = false, error = err} end
  err = shared.check_enum(a.direction, shared.DIRECTIONS, "direction")
  if err then return {success = false, error = err} end

  local tgs, terr = shared.num_arg(a, "text_guidance_scale")
  if terr then return {success = false, error = terr} end
  local strength, terr = shared.int_arg(a, "init_image_strength")
  if terr then return {success = false, error = terr} end
  local seed, terr = shared.int_arg(a, "seed")
  if terr then return {success = false, error = terr} end

  local body = {
    description = tostring(a.description),
    image_size = { width = w, height = h }
  }
  if tgs ~= nil then body.text_guidance_scale = tgs end
  if a.outline ~= nil and a.outline ~= "" then body.outline = a.outline end
  if a.shading ~= nil and a.shading ~= "" then body.shading = a.shading end
  if a.detail ~= nil and a.detail ~= "" then body.detail = a.detail end
  if a.view ~= nil and a.view ~= "" then body.view = a.view end
  if a.direction ~= nil and a.direction ~= "" then body.direction = a.direction end
  if shared.bool_arg(a, "isometric") then body.isometric = true end
  if shared.bool_arg(a, "no_background") then body.no_background = true end

  if a.init_image ~= nil and a.init_image ~= "" then
    local img, ierr = shared.read_image(ctx, a.init_image, "init_image")
    if img == nil then return {success = false, error = ierr} end
    body.init_image = img
    if strength ~= nil then body.init_image_strength = strength end
  end
  if a.color_image ~= nil and a.color_image ~= "" then
    local img, ierr = shared.read_image(ctx, a.color_image, "color_image")
    if img == nil then return {success = false, error = ierr} end
    body.color_image = img
  end
  if seed ~= nil then body.seed = seed end

  local r = shared.post(ctx, pkg, "/generate-image-pixflux", body, shared.slow_timeout_s(pkg))
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  local base = shared.out_base(ctx, "pixflux", a.filename, seed)
  local files, werr = shared.write_images(ctx, r.json.image, base)
  if files == nil then return {success = false, error = werr} end
  return {
    success = true,
    files = files,
    meta = {
      usage = shared.usage_meta(r.json),
      model = "pixflux",
      size = w .. "x" .. h,
      seed = seed or 0
    }
  }
end
