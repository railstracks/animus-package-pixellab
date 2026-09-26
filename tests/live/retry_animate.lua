-- retry_animate.lua — re-run animate skeleton live after the z_index fix.
-- Reuses the dragon already in /tmp/pixellab-live. Run:
--   . .secrets/env && lua tests/live/retry_animate.lua <dragon.png>

package.path = "scripts/?.lua;tests/live/?.lua;" .. package.path
shared = dofile("scripts/_shared.lua")
local b64mod = require("b64")
b64 = { encode = b64mod.encode, decode = b64mod.decode }
local OUT = "/tmp/pixellab-live"
local TOKEN = assert(os.getenv("PIXELLAB_API_TOKEN"))
local DRAGON = assert(arg and arg[1], "usage: retry_animate.lua <dragon.png>")

local function is_array(t)
  local n = 0
  for k in pairs(t) do if type(k) ~= "number" then return false end n = n + 1 end
  return n == #t
end
local function esc(s) return (s:gsub('["\\]', function(c) return "\\" .. c end)) end
local function ser(t)
  if type(t) == "table" then
    if is_array(t) then
      local p = {} for _, v in ipairs(t) do p[#p + 1] = ser(v) end return "[" .. table.concat(p, ",") .. "]"
    end
    local ks = {} for k in pairs(t) do ks[#ks + 1] = k end table.sort(ks)
    local p = {} for _, k in ipairs(ks) do p[#p + 1] = '"' .. k .. '":' .. ser(t[k]) end return "{" .. table.concat(p, ",") .. "}"
  elseif type(t) == "string" then return '"' .. esc(t) .. '"'
  elseif type(t) == "boolean" then return tostring(t)
  else return string.format("%.17g", t) end
end

local function pydecode(s)
  local f = io.open(OUT .. "/_r.json", "wb"); f:write(s); f:close()
  local h = io.popen("python3 tests/live/json2lua.py < " .. OUT .. "/_r.json")
  local out = h:read("*a"); h:close()
  if not out or out == "" then return nil end
  local chunk = load("return " .. out)
  return chunk and chunk()
end

json = { encode = ser, decode_safe = pydecode }

local function http_call(method, url, headers, body)
  if body then
    local f = io.open(OUT .. "/_req.json", "wb"); f:write(body); f:close()
  end
  local hs = {}
  for k, v in pairs(headers or {}) do hs[#hs + 1] = string.format("-H '%s: %s'", k, v) end
  local cmd = string.format("curl -sS --max-time 180 -X %s '%s' %s %s -o %s/_b.bin -w '%%{http_code}'",
    method, url, table.concat(hs, " "), body and ("--data-binary @" .. OUT .. "/_req.json") or "", OUT)
  local h = io.popen(cmd, "r")
  local status = tonumber(h:read("*a")); h:close()
  local bt = ""
  local bf = io.open(OUT .. "/_b.bin", "rb")
  if bf then bt = bf:read("*a") bf:close() end
  return { status = status, body = bt, json = (#bt > 0 and pydecode(bt)) or nil }
end

local function mkctx(args)
  return {
    now = os.time() * 1000,
    package = { name = "pixellab", get_state = function(k) return k == "api_token" and TOKEN or nil end },
    args = args,
    http = {
      post = function(u, o) return http_call("POST", u, o.headers, o.body) end,
      get = function(u, o) return http_call("GET", u, o.headers, nil) end
    },
    fs = {
      read = function(p) local f = io.open(OUT .. "/" .. p, "rb") if not f then return nil end local d = f:read("*a") f:close() return d end,
      write = function(p, d) local f = io.open(OUT .. "/" .. p, "wb") f:write(d) f:close() return p end
    }
  }
end

local function load_cmd(name)
  local c = assert(loadfile("scripts/" .. name .. ".lua")); c(); return run
end

-- 1) estimate on the dragon
local r = load_cmd("skeleton_estimate")(mkctx({ image = DRAGON }))
assert(r.success, "estimate failed: " .. tostring(r.error))
local kps = r.data.keypoints
print("estimate ok: " .. #kps .. " keypoints, sample z_index = " .. tostring(kps[1].z_index))

-- 2) animate with 3 identical frames (z_index rounding now in parse_keypoints)
r = load_cmd("animate_skeleton")(mkctx({
  width = 64, height = 64, reference_image = DRAGON,
  skeleton_keypoints = json.encode({ kps, kps, kps }), seed = 7
}))
if r.success then
  local magic_ok = true
  for _, f in ipairs(r.files) do
    local fh = io.open(OUT .. "/" .. f.path, "rb")
    magic_ok = magic_ok and fh and fh:read(4) == "\137PNG"
    if fh then fh:close() end
  end
  print("animate skeleton ok: " .. #r.files .. " frames, all PNG: " .. tostring(magic_ok))
  print("files: " .. table.concat((function() local t = {} for _, f in ipairs(r.files) do t[#t + 1] = f.path end return t end)()), ", ")
  print("usage: " .. tostring(r.meta.usage and r.meta.usage.generations))
  os.exit(0)
else
  print("animate skeleton FAILED: " .. tostring(r.error))
  os.exit(1)
end
