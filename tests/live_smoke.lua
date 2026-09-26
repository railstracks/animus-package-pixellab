-- live_smoke.lua — real-API smoke test for the pixellab package.
-- Run:  . .secrets/env && lua tests/live_smoke.lua
-- Costs a few cents; every command exercised once against api.pixellab.ai.

package.path = "scripts/?.lua;tests/live/?.lua;" .. package.path
shared = dofile("scripts/_shared.lua")
local b64mod = require("b64")
b64 = { encode = b64mod.encode, decode = b64mod.decode }

-- sanity: known vectors
assert(b64.encode("hello") == "aGVsbG8=", "b64 encode broken")
assert(b64.decode("aGVsbG8=") == "hello", "b64 decode broken")
assert(b64.decode(b64.encode("\1\2\3\255PNG\0")) == "\1\2\3\255PNG\0", "b64 roundtrip broken")

local OUT = "/tmp/pixellab-live"
os.execute("mkdir -p " .. OUT)

local TOKEN = assert(os.getenv("PIXELLAB_API_TOKEN"), "PIXELLAB_API_TOKEN not set")

-- json encode: compact serializer
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local function esc(s)
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

-- json decode: via python (exact bytes preserved)
local function pydecode(s)
  local f = io.open("/tmp/pixellab-live/_resp.json", "wb")
  f:write(s)
  f:close()
  local h = io.popen("python3 tests/live/json2lua.py < /tmp/pixellab-live/_resp.json 2>/tmp/pixellab-live/_err")
  local out = h:read("*a")
  h:close()
  if not out or out == "" then return nil end
  local chunk = load("return " .. out)
  if not chunk then return nil end
  return chunk()
end

json = { encode = ser, decode_safe = pydecode }

local http_log = {}

local function curl(method, url, headers, body)
  local cmd = string.format(
    "curl -sS --max-time 180 -X %s '%s' %s %s -o /tmp/pixellab-live/_body.bin -w '%%{http_code}'",
    method, url,
    headers and table.concat(
      (function()
        local h = {}
        for k, v in pairs(headers) do h[#h + 1] = string.format("-H '%s: %s'", k, v) end
        return h
      end)(), " ") or "",
    body and "--data-binary @/tmp/pixellab-live/_req.json" or "")
  if body then
    local f = io.open("/tmp/pixellab-live/_req.json", "wb")
    f:write(body)
    f:close()
  end
  local h = io.popen(cmd .. " 2>/tmp/pixellab-live/_curlerr", "r")
  local status = tonumber(h:read("*a"))
  h:close()
  local bodytxt = ""
  local bf = io.open("/tmp/pixellab-live/_body.bin", "rb")
  if bf then bodytxt = bf:read("*a") bf:close() end
  http_log[#http_log + 1] = { url = url, status = status, bytes = #bodytxt }
  return { status = status, body = bodytxt, json = (#bodytxt > 0 and pydecode(bodytxt)) or nil }
end

local calls = 0
local function mkctx(args)
  return {
    now = os.time() * 1000,
    package = {
      name = "pixellab",
      get_state = function(k)
        if k == "api_token" then return TOKEN end
        if k == "base_url" then return nil end
        return nil
      end
    },
    args = args,
    http = {
      post = function(url, opts)
        calls = calls + 1
        return curl("POST", url, opts.headers, opts.body)
      end,
      get = function(url, opts)
        calls = calls + 1
        return curl("GET", url, opts.headers, nil)
      end
    },
    fs = {
      read = function(p)
        local f = io.open(OUT .. "/" .. p, "rb")
        if not f then return nil, "not found" end
        local d = f:read("*a")
        f:close()
        return d
      end,
      write = function(p, d)
        local f = io.open(OUT .. "/" .. p, "wb")
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
  chunk()
  return run
end

local failures = 0
local function check(label, cond, extra)
  if cond then
    print("ok    " .. label)
  else
    print("FAIL  " .. label .. " — " .. tostring(extra))
    failures = failures + 1
  end
end

local function is_png(path)
  local f = io.open(OUT .. "/" .. path, "rb")
  if not f then return false end
  local magic = f:read(4)
  f:close()
  return magic == "\137PNG"
end

print("=== live smoke vs api.pixellab.ai — " .. os.date("!%Y-%m-%d %H:%M:%S UTC"))

-- 1. balance
local r = load_cmd("balance_get")(mkctx({}))
check("1 balance get", r.success == true, r.error)
print(string.format("      balance: $%.2f", r.data and r.data.balance_usd or -1))
local bal0 = r.data and r.data.balance_usd

-- 2. generate pixflux (the anchor asset)
r = load_cmd("generate_pixflux")(mkctx({
  description = "a small cute orange dragon, side view, 64x64 pixel art game sprite, single character, simple shading",
  width = 64, height = 64, no_background = true, seed = 42, outline = "single color black outline", shading = "basic shading"
}))
check("2 pixflux generate", r.success == true, r.error)
if r.success then
  check("2 png magic", is_png(r.files[1].path))
  print("      file: " .. r.files[1].path .. "  cost: $" .. tostring(r.meta.usage.usd))
  local kf = io.open(OUT .. "/_dragon.txt", "w")
  kf:write(r.files[1].path)
  kf:close()
end

-- 3. skeleton estimate on the dragon
r = load_cmd("skeleton_estimate")(mkctx({ image = io.open(OUT .. "/_dragon.txt"):read("*l") }))
check("3 skeleton estimate", r.success == true, r.error)
local kps
if r.success then
  kps = r.data.keypoints
  print("      keypoints: " .. #kps .. " (first: " .. kps[1].label .. " @" .. kps[1].x .. "," .. kps[1].y .. ")")
  check("3 plausible count", #kps >= 10 and #kps <= 18, #kps)
end

-- 4. animate skeleton — 3 identical frames from the real estimate
if kps then
  r = load_cmd("animate_skeleton")(mkctx({
    width = 64, height = 64, reference_image = io.open(OUT .. "/_dragon.txt"):read("*l"),
    skeleton_keypoints = json.encode({ kps, kps, kps }), seed = 7
  }))
  check("4 animate skeleton", r.success == true, r.error)
  if r.success then
    check("4 four frames", #r.files == 4)
    check("4 png magic f1/f4", is_png(r.files[1].path) and is_png(r.files[4].path))
    print("      frames: " .. r.files[1].path .. " … " .. r.files[4].path .. "  cost: $" .. tostring(r.meta.usage.usd))
  end
end

-- 5. animate text
r = load_cmd("animate_text")(mkctx({
  description = "a small cute orange dragon", action = "walking",
  reference_image = io.open(OUT .. "/_dragon.txt"):read("*l"), seed = 11
}))
check("5 animate text", r.success == true, r.error)
if r.success then
  check("5 four frames", #r.files == 4)
  check("5 png magic", is_png(r.files[1].path))
  print("      frames: " .. r.files[1].path .. " …  cost: $" .. tostring(r.meta.usage.usd))
end

-- 6. rotate the dragon south->east
r = load_cmd("rotate")(mkctx({
  from_image = io.open(OUT .. "/_dragon.txt"):read("*l"),
  width = 64, height = 64, from_direction = "south", to_direction = "east", seed = 3
}))
check("6 rotate", r.success == true, r.error)
if r.success then
  check("6 png magic", is_png(r.files[1].path))
  print("      file: " .. r.files[1].path .. "  cost: $" .. tostring(r.meta.usage.usd))
end

-- 7. inpaint: add a hat via generated mask (white rect at the head area)
os.execute("python3 tests/live/mkmask.py /tmp/pixellab-live/mask.png 64 64 20 2 44 22")
r = load_cmd("inpaint")(mkctx({
  description = "a small wizard hat on the dragon's head",
  inpainting_image = io.open(OUT .. "/_dragon.txt"):read("*l"),
  mask_image = "mask.png", width = 64, height = 64, seed = 5
}))
check("7 inpaint", r.success == true, r.error)
if r.success then
  check("7 png magic", is_png(r.files[1].path))
  print("      file: " .. r.files[1].path .. "  cost: $" .. tostring(r.meta.usage.usd))
end

-- 8. generate bitforge with the dragon as style reference
r = load_cmd("generate_bitforge")(mkctx({
  description = "a goblin warrior with a wooden club",
  width = 64, height = 64, style_image = io.open(OUT .. "/_dragon.txt"):read("*l"),
  style_strength = 60, no_background = true, seed = 9
}))
check("8 bitforge", r.success == true, r.error)
if r.success then
  check("8 png magic", is_png(r.files[1].path))
  print("      file: " .. r.files[1].path .. "  cost: $" .. tostring(r.meta.usage.usd))
end

-- 9. balance again + usage delta
r = load_cmd("balance_get")(mkctx({}))
if r.success then
  print(string.format("      balance after: $%.2f (delta: $%.2f over %d http calls)",
    r.data.balance_usd, bal0 - r.data.balance_usd, calls))
end

print("")
if failures == 0 then print("live smoke: ALL OK") else print("live smoke: " .. failures .. " FAILURES") os.exit(1) end
