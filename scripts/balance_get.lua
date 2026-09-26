-- balance get: current USD balance (GET /v1/balance)
function run(ctx)
  local pkg = ctx.package
  if not shared.require_auth(pkg) then
    return {success = false, error = "api_token not configured (get one at https://pixellab.ai/account)"}
  end
  local r = shared.get(ctx, pkg, "/balance")
  if not r.ok then
    return {success = false, error = r.error, http_status = r.http_status}
  end
  return {
    success = true,
    data = { balance_usd = r.json.usd },
    meta = { usage = shared.usage_meta(r.json) }
  }
end
