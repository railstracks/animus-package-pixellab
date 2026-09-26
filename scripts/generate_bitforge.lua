-- generate bitforge: style-transfer generation (POST /v1/generate-image-bitforge)
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
    return {success = false, error = "width and height are required (16-200 each, area at most 200x200)"}
  end
  err = shared.check_size(w, h, shared.SIZES.bitforge)
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
  local sgs, terr = shared.num_arg(a, "skeleton_guidance_scale")
  if terr then return {success = false, error = terr} end
  local cov, terr = shared.num_arg(a, "coverage_percentage")
  if terr then return {success = false, error = terr} end
  if cov ~= nil and (cov < 1 or cov > 100) then
    return {success = false, error = "coverage_percentage must be 1-100"}
  end
  local style_strength, terr = shared.int_arg(a, "style_strength")
  if terr then return {success = false, error = terr} end
  if style_strength ~= nil and (style_strength < 0 or style_strength > 100) then
    return {success = false, error = "style_strength must be 0-100"}
  end
  local strength, terr = shared.int_arg(a, "init_image_strength")
  if terr then return {success = false, error = terr} end
  local seed, terr = shared.int_arg(a, "seed")
  if terr then return {success = false, error = terr} end

  local kp
  if a.skeleton_keypoints ~= nil and a.skeleton_keypoints ~= "" then
    kp, err = shared.parse_keypoints(a.skeleton_keypoints, nil)
    if kp == nil then return {success = false, error = err} end
  end

  local body = {
    description = tostring(a.description),
    image_size = { width = w, height = h }
  }
  if a.negative_description ~= nil and a.negative_description ~= "" then
    body.negative_description = tostring(a.negative_description)
  end
  if tgs ~= nil then body.text_guidance_scale = tgs end
  if sgs ~= nil then body.skeleton_guidance_scale = sgs end
  if cov ~= nil then body.coverage_percentage = cov end
  if style_strength ~= nil then body.style_strength = style_strength end
  if a.outline ~= nil and a.outline ~= "" then body.outline = a.outline end
  if a.shading ~= nil and a.shading ~= "" then body.shading = a.shading end
  if a.detail ~= nil and a.detail ~= "" then body.detail = a.detail end
  if a.view ~= nil and a.view ~= "" then body.view = a.view end
  if a.direction ~= nil and a.direction ~= "" then body.direction = a.direction end
  if shared.bool_arg(a, "isometric") then body.isometric = true end
  if shared.bool_arg(a, "oblique_projection") then body.oblique_projection = true end
  if shared.bool_arg(a, "no_background") then body.no_background = true end

  local has_init = a.init_image ~= nil and a.init_image ~= ""
  if has_init then
    local img, ierr = shared.read_image(ctx, a.init_image, "init_image")
    if img == nil then return {success = false, error = ierr} end
    body.init_image = img
    if strength ~= nil then body.init_image_strength = strength end
  end
  if a.style_image ~= nil and a.style_image ~= "" then
    local img, ierr = shared.read_image(ctx, a.style_image, "style_image")
    if img == nil then return {success = false, error = ierr} end
    body.style_image = img
  end
  if a.inpainting_image ~= nil and a.inpainting_image ~= "" then
    local img, ierr = shared.read_image(ctx, a.inpainting_image, "inpainting_image")
    if img == nil then return {success = false, error = ierr} end
    if a.mask_image == nil or a.mask_image == "" then
      return {success = false, error = "mask_image is required together with inpainting_image"}
    end
    local mask, merr = shared.read_image(ctx, a.mask_image, "mask_image")
    if mask == nil then return {success = false, error = merr} end
    body.inpainting_image = img
    body.mask_image = mask
  end
  if a.mask_image ~= nil and a.mask_image ~= "" and body.inpainting_image == nil then
    return {success = false, error = "mask_image requires inpainting_image"}
  end
  if a.color_image ~= nil and a.color_image ~= "" then
    local img, ierr = shared.read_image(ctx, a.color_image, "color_image")
    if img == nil then return {success = false, error = ierr} end
    body.color_image = img
  end
  if kp ~= nil then body.skeleton_keypoints = kp end
  if seed ~= nil then body.seed = seed end

  local r = shared.post(ctx, pkg, "/generate-image-bitforge", body, shared.slow_timeout_s(pkg))
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  local base = shared.out_base(ctx, "bitforge", a.filename, seed)
  local files, werr = shared.write_images(ctx, r.json.image, base)
  if files == nil then return {success = false, error = werr} end
  return {
    success = true,
    files = files,
    meta = {
      usage = shared.usage_meta(r.json),
      model = "bitforge",
      size = w .. "x" .. h,
      seed = seed or 0
    }
  }
end
