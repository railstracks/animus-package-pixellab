-- test_commands.lua — integration tests for every command script (plain lua5.4).
-- Stubs: ctx.http (captures requests, returns fixtures), ctx.fs (real files in a
-- temp dir), b64 (roundtrip marker scheme), json (compact serializer).
-- Run: lua tests/test_commands.lua

package.path = "scripts/?.lua;" .. package.path
shared = dofile("scripts/_shared.lua")   -- global: command scripts reference it

local TMP = "/tmp/pixellab-pkg-test"
os.execute("rm -rf " .. TMP .. " && mkdir -p " .. TMP)

-- ---- stubs ---------------------------------------------------------------
b64 = {
  encode = function(s) return "\001PNG" .. s end,
  decode = function(s)
    if s:sub(1, 4) ~= "\001PNG" then return nil end
    return s:sub(5)
  end
}

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local function esc(s)
  -- escape only quotes and backslashes; keep raw bytes (incl. the \001 b64
  -- marker) so assertions can match them literally
  return (s:gsub('["\\]', function(c) return "\\" .. c end))
end

local function ser(t)
  if type(t) == "table" then
    if is_array(t) then
      local parts = {}
      for _, v in ipairs(t) do parts[#parts + 1] = ser(v) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. tostring(k) .. '":' .. ser(t[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(t) == "string" then
    return '"' .. esc(t) .. '"'
  elseif type(t) == "boolean" then
    return tostring(t)
  else
    return string.format("%.17g", t)
  end
end

json = { encode = ser, decode_safe = function() return nil end }

local captured = {}
local fixture = nil
local http_calls = 0

local function mkctx(args, state)
  return {
    now = 1758900000000,
    package = {
      name = "pixellab",
      get_state = function(k)
        local s = state or { api_token = "T0K", base_url = "https://api.pixellab.ai/v1/" }
        return s[k]
      end
    },
    args = args,
    http = {
      post = function(url, opts)
        http_calls = http_calls + 1
        captured = { url = url, body = opts.body, headers = opts.headers }
        return fixture
      end,
      get = function(url, opts)
        http_calls = http_calls + 1
        captured = { url = url, headers = opts.headers }
        return fixture
      end
    },
    fs = {
      read = function(p)
        local f = io.open(TMP .. "/" .. p, "rb")
        if not f then return nil, "not found" end
        local d = f:read("*a")
        f:close()
        return d
      end,
      write = function(p, d)
        local f = io.open(TMP .. "/" .. p, "wb")
        if not f then return nil, "open failed" end
        f:write(d)
        f:close()
        return p
      end
    }
  }
end

local function load_cmd(name)
  local chunk = assert(loadfile("scripts/" .. name .. ".lua"))
  chunk()                      -- executes: defines the global run(ctx)
  return run                   -- capture it before the next script overwrites
end

local failures = 0
local function check(label, cond, extra)
  if not cond then
    print("FAIL  " .. label .. (extra and (" — " .. tostring(extra)) or ""))
    failures = failures + 1
  else
    print("ok    " .. label)
  end
end

local function file_exists(p)
  local f = io.open(TMP .. "/" .. p, "rb")
  if not f then return false end
  f:close()
  return true
end

local function file_content(p)
  local f = io.open(TMP .. "/" .. p, "rb")
  local d = f:read("*a")
  f:close()
  return d
end

-- seed a reference/init image into the filespace
local function seed_file(p, data)
  local f = io.open(TMP .. "/" .. p, "wb")
  f:write(data or "SRC")
  f:close()
end

-- ---- generate pixflux ----------------------------------------------------
local run = load_cmd("generate_pixflux")

fixture = { status = 200, json = { usage = { type = "usd", usd = 0.01 }, image = { type = "base64", base64 = b64.encode("PNG1") } } }
seed_file("init.png", "INITDATA")
local r = run(mkctx({ description = "cute dragon", width = 64, height = 64, init_image = "init.png", init_image_strength = 250, seed = 42, filename = "hero.png" }))
check("pixflux success", r.success == true, r.error)
check("pixflux file written", file_exists("hero.png"))
check("pixflux content roundtrip", file_content("hero.png") == "PNG1")
check("pixflux files array", r.files and r.files[1] and r.files[1].path == "hero.png")
check("pixflux usage surfaced", r.meta and r.meta.usage and r.meta.usage.usd == 0.01)
check("pixflux url", captured.url == "https://api.pixellab.ai/v1/generate-image-pixflux", captured.url)
check("pixflux bearer", captured.headers["Authorization"] == "Bearer T0K")
check("pixflux body has description", captured.body:find('"description":"cute dragon"', 1, true) ~= nil, captured.body)
check("pixflux body image_size", captured.body:find('"image_size":{"height":64,"width":64}', 1, true) ~= nil, captured.body)
check("pixflux body init image b64", captured.body:find('"base64":"\001PNGINITDATA"', 1, true) ~= nil, captured.body)
check("pixflux body strength", captured.body:find('"init_image_strength":250', 1, true) ~= nil)
check("pixflux body seed", captured.body:find('"seed":42', 1, true) ~= nil)

-- auto name: flat, no slash
r = run(mkctx({ description = "x", width = 32, height = 32 }))
check("pixflux auto name flat", r.files[1].path:find("/") == nil, r.files[1].path)
check("pixflux auto name prefix", r.files[1].path:match("^pixflux%-") ~= nil, r.files[1].path)
check("pixflux auto name has seed", r.files[1].path:match("_s0%.png$") ~= nil, r.files[1].path)

-- kernel os.date simulation (field-tested Sept 26): only the exact ISO format
-- is honored, anything else silently falls back to ISO, time arg ignored.
-- Generated names must stay slug-safe (no colons) under that behavior.
do
  local real_date = os.date
  os.date = function(fmt, t)
    if fmt ~= "%Y-%m-%dT%H:%M:%SZ" and fmt ~= "!%Y-%m-%dT%H:%M:%SZ" then
      fmt = "!%Y-%m-%dT%H:%M:%SZ"
    end
    return real_date(fmt)
  end
  local r2 = run(mkctx({ description = "x", width = 32, height = 32 }))
  os.date = real_date
  check("auto name slug-safe under kernel os.date",
        r2.files[1].path:find(":") == nil and r2.files[1].path:match("^[%w%.%-_]+$") ~= nil, r2.files[1].path)
end

-- validation fails before http
http_calls = 0
r = run(mkctx({ description = "x", width = 16, height = 16 }))  -- area too small
check("pixflux area guard", r.success == false and r.error:find("area too small") ~= nil, r.error)
r = run(mkctx({ description = "x", width = 64, height = 64, view = "diagonal" }))
check("pixflux enum guard", r.success == false and r.error:find("view must be one of") ~= nil, r.error)
r = run(mkctx({ width = 64, height = 64 }))
check("pixflux description required", r.success == false)
r = run(mkctx({ description = "x", width = 64, height = 64, init_image = "missing.png" }))
check("pixflux missing init file", r.success == false and r.error:find("init_image could not be read") ~= nil, r.error)
check("no http on validation fail", http_calls == 0)

-- error mapping
fixture = { status = 402, json = { detail = "no funds" } }
r = run(mkctx({ description = "x", width = 32, height = 32 }))
check("402 maps to balance hint", r.success == false and r.error:find("insufficient balance") ~= nil, r.error)
fixture = { status = 529, body = "overloaded" }
r = run(mkctx({ description = "x", width = 32, height = 32 }))
check("529 maps to overloaded", r.success == false and r.error:find("overloaded") ~= nil, r.error)

-- ---- generate bitforge ---------------------------------------------------
run = load_cmd("generate_bitforge")
fixture = { status = 200, json = { usage = { type = "usd", usd = 0.02 }, image = { type = "base64", base64 = b64.encode("PNG2") } } }
seed_file("style.png", "STYLEDATA")
r = run(mkctx({ description = "knight", width = 96, height = 96, style_image = "style.png", style_strength = 50, no_background = true }))
check("bitforge success", r.success == true, r.error)
check("bitforge style b64 in body", captured.body:find('"base64":"\001PNGSTYLEDATA"', 1, true) ~= nil)
check("bitforge style_strength", captured.body:find('"style_strength":50', 1, true) ~= nil)
check("bitforge no_background", captured.body:find('"no_background":true', 1, true) ~= nil)

r = run(mkctx({ description = "k", width = 150, height = 200, inpainting_image = "init.png" }))
check("bitforge mask required with inpaint", r.success == false and r.error:find("mask_image is required") ~= nil, r.error)
r = run(mkctx({ description = "k", width = 200, height = 200, style_strength = 150 }))
check("bitforge style_strength range", r.success == false and r.error:find("0%-100") ~= nil, r.error)

-- ---- animate skeleton ----------------------------------------------------
run = load_cmd("animate_skeleton")
local imgb64 = { type = "base64", base64 = b64.encode("ANIM") }
fixture = { status = 200, json = { usage = { type = "usd", usd = 0.04 }, images = { imgb64, imgb64, imgb64, imgb64 } } }
seed_file("char.png", "CHARDATA")
seed_file("i1.png", "F1"); seed_file("i2.png", "F2"); seed_file("i3.png", "F3")

-- keypoints fixture: valid JSON-ish via stubbed decode? parse_keypoints uses
-- json.decode_safe — override locally for this command's happy path.
local kp_json = {
  { { x = 1, y = 2, label = "NECK", z_index = 0 } },
  { { x = 3, y = 4, label = "NECK", z_index = 0 } },
  { { x = 5, y = 6, label = "NECK", z_index = 0 } }
}
local real_decode = json.decode_safe
json.decode_safe = function(s)
  if s == "KP3" then return kp_json end
  return real_decode(s)
end
r = run(mkctx({ width = 128, height = 64, reference_image = "char.png", skeleton_keypoints = "KP3", init_images = "i1.png,i2.png,i3.png", filename = "walk.png", seed = 7 }))
check("animate sk success", r.success == true, r.error)
check("animate sk 4 frames", r.files and #r.files == 4)
check("animate sk frame names", r.files[1].path == "walk_f1.png" and r.files[4].path == "walk_f4.png", r.files[1].path)
check("animate sk frames on disk", file_exists("walk_f4.png"))
check("animate sk kp in body (frames are arrays)", captured.body:find('"skeleton_keypoints":[[{"', 1, true) ~= nil, captured.body:sub(1,120))
check("animate sk 3 init images", captured.body:find('"init_images":[', 1, true) ~= nil and select(2, captured.body:gsub("\001PNGF%d", "")) == 3, captured.body)

r = run(mkctx({ width = 128, height = 64, reference_image = "char.png", skeleton_keypoints = "KP3", init_images = "i1.png,i2.png" }))
check("animate sk init count guard", r.success == false and r.error:find("exactly 3") ~= nil, r.error)
json.decode_safe = real_decode

json.decode_safe = function() return nil end
r = run(mkctx({ width = 128, height = 64, reference_image = "char.png", skeleton_keypoints = "BAD" }))
check("animate sk bad keypoints json", r.success == false and r.error:find("not valid JSON") ~= nil, r.error)
r = run(mkctx({ width = 100, height = 64, reference_image = "char.png", skeleton_keypoints = "KP3" }))
check("animate sk size set guard", r.success == false and r.error:find("16/32/64/128/256") ~= nil, r.error)

-- ---- animate text --------------------------------------------------------
run = load_cmd("animate_text")
fixture = { status = 200, json = { usage = { type = "usd", usd = 0.03 }, images = { imgb64, imgb64, imgb64, imgb64 } } }
r = run(mkctx({ description = "human mage", action = "walking", reference_image = "char.png" }))
check("animate tx success", r.success == true, r.error)
check("animate tx default 64", captured.body:find('"image_size":{"height":64,"width":64}', 1, true) ~= nil, captured.body)
r = run(mkctx({ description = "mage", action = "walk", reference_image = "char.png", width = 32, height = 64 }))
check("animate tx size guard", r.success == false and r.error:find("only supports 64x64") ~= nil, r.error)
r = run(mkctx({ description = "mage", reference_image = "char.png" }))
check("animate tx action required", r.success == false)

-- ---- rotate --------------------------------------------------------------
run = load_cmd("rotate")
fixture = { status = 200, json = { usage = { type = "usd", usd = 0.01 }, image = { type = "base64", base64 = b64.encode("ROT") } } }
r = run(mkctx({ from_image = "char.png", width = 64, height = 64, from_direction = "south", to_direction = "east", filename = "side.png" }))
check("rotate success", r.success == true, r.error)
check("rotate file", file_exists("side.png"))
check("rotate from/to in body", captured.body:find('"from_direction":"south"') ~= nil and captured.body:find('"to_direction":"east"') ~= nil)
r = run(mkctx({ from_image = "char.png", width = 64, height = 64, mask_image = "i1.png" }))
check("rotate mask requires init", r.success == false and r.error:find("mask_image requires init_image") ~= nil, r.error)
r = run(mkctx({ from_image = "char.png", width = 256, height = 128 }))
check("rotate size set guard", r.success == false)

-- ---- inpaint -------------------------------------------------------------
run = load_cmd("inpaint")
fixture = { status = 200, json = { usage = { type = "usd", usd = 0.01 }, image = { type = "base64", base64 = b64.encode("INP") } } }
seed_file("mask.png", "MASKDATA")
r = run(mkctx({ description = "add a hat", inpainting_image = "char.png", mask_image = "mask.png", width = 64, height = 64 }))
check("inpaint success", r.success == true, r.error)
check("inpaint mask b64", captured.body:find('"base64":"\001PNGMASKDATA"', 1, true) ~= nil)
http_calls = 0
r = run(mkctx({ description = "add a hat", inpainting_image = "char.png", width = 64, height = 64 }))
check("inpaint mask required", r.success == false and r.error:find("mask_image required") ~= nil, r.error)
check("inpaint no http on missing mask", http_calls == 0)

-- ---- skeleton estimate ---------------------------------------------------
run = load_cmd("skeleton_estimate")
fixture = { status = 200, json = { usage = { type = "generations", generations = 1 }, keypoints = { { x = 1, y = 2, label = "NOSE", z_index = 0 }, { x = 2, y = 3, label = "NECK", z_index = 0 } } } }
r = run(mkctx({ image = "char.png" }))
check("estimate success", r.success == true, r.error)
check("estimate keypoints in data", r.data and #r.data.keypoints == 2)
check("estimate no files", r.files == nil)
check("estimate usage generations", r.meta.usage.generations == 1)
r = run(mkctx({}))
check("estimate image required", r.success == false and r.error:find("image required") ~= nil, r.error)

-- ---- balance -------------------------------------------------------------
run = load_cmd("balance_get")
fixture = { status = 200, json = { type = "usd", usd = 12.5 } }
r = run(mkctx({}))
check("balance success", r.success == true, r.error)
check("balance value", r.data.balance_usd == 12.5)
check("balance url", captured.url == "https://api.pixellab.ai/v1/balance", captured.url)

-- no auth -> nothing leaves
http_calls = 0
r = run(mkctx({}, { api_token = "" }))
check("balance no-auth guard", r.success == false and http_calls == 0, http_calls)

print("")
if failures == 0 then
  print("test_commands: ALL OK")
else
  print("test_commands: " .. failures .. " FAILURES")
  os.exit(1)
end
