-- skeleton estimate: image -> 18 labeled keypoints (POST /v1/estimate-skeleton)
function run(ctx)
  local pkg = ctx.package
  if not shared.require_auth(pkg) then
    return {success = false, error = "api_token not configured (get one at https://pixellab.ai/account)"}
  end
  local a = ctx.args
  local img, err = shared.read_image(ctx, a.image, "image")
  if img == nil then return {success = false, error = err} end

  local body = { image = img }

  local r = shared.post(ctx, pkg, "/estimate-skeleton", body, shared.slow_timeout_s(pkg))
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  local n = 0
  if type(r.json.keypoints) == "table" then n = #r.json.keypoints end
  return {
    success = true,
    data = { keypoints = r.json.keypoints },
    meta = {
      usage = shared.usage_meta(r.json),
      model = "estimate-skeleton",
      keypoints = n,
      note = "edit these frames and feed them to 'animate skeleton' (exactly 3 frames per call)"
    }
  }
end
