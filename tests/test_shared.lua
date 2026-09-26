-- test_shared.lua — unit tests for _shared helpers (plain lua5.4, no sandbox)
-- Run: lua tests/test_shared.lua

local shared = dofile("scripts/_shared.lua")

-- Sandbox-global stubs (kernel provides these; shape per SANDBOX.md)
local function b64_encode(s)
  local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  return (s:gsub(".", function(c)
    local n = c:byte()
    local b1, rem = math.floor(n / 16), n % 16
    local enc = B:sub(b1 + 1, b1 + 1) .. B:sub(rem + 1, rem + 1)
    return enc
  end))
end

local failures = 0
local function check(label, got, want)
  if got ~= want then
    print("FAIL  " .. label .. ": got " .. tostring(got) .. ", want " .. tostring(want))
    failures = failures + 1
  else
    print("ok    " .. label)
  end
end

-- normalize_base (alpaca-proven pattern)
check("doubled /v1 stripped", shared.normalize_base("https://api.pixellab.ai/v1"), "https://api.pixellab.ai")
check("trailing slash stripped", shared.normalize_base("https://api.pixellab.ai/"), "https://api.pixellab.ai")
check("clean base untouched", shared.normalize_base("https://api.pixellab.ai"), "https://api.pixellab.ai")
check("custom host untouched", shared.normalize_base("http://localhost:3000"), "http://localhost:3000")

-- base_url defaulting
local pkg_default = { get_state = function(k) return nil end }
check("base_url default", shared.base_url(pkg_default), "https://api.pixellab.ai")
local pkg_override = { get_state = function(k) return k == "base_url" and "https://api.pixellab.ai/v1/" or "tok" end }
check("base_url override + normalize", shared.base_url(pkg_override), "https://api.pixellab.ai")

-- require_auth
check("auth missing", shared.require_auth({ get_state = function() return nil end }), false)
check("auth empty", shared.require_auth({ get_state = function() return "" end }), false)
check("auth masked", shared.require_auth({ get_state = function() return "***" end }), false)
check("auth present", shared.require_auth({ get_state = function() return "tok" end }), true)

-- headers
local h = shared.headers({ get_state = function(k) return k == "api_token" and "T0K" or nil end })
check("bearer header", h["Authorization"], "Bearer T0K")
check("content-type", h["Content-Type"], "application/json")

-- enums
check("enum ok", shared.check_enum("side", shared.VIEWS, "view"), nil)
check("enum empty ok", shared.check_enum("", shared.VIEWS, "view"), nil)
check("enum nil ok", shared.check_enum(nil, shared.VIEWS, "view"), nil)
check("enum bad", shared.check_enum("diagonal", shared.VIEWS, "view") ~= nil, true)

-- sizes: pixflux
check("pixflux 64x64 ok", shared.check_size(64, 64, shared.SIZES.pixflux), nil)
check("pixflux 400x400 ok", shared.check_size(400, 400, shared.SIZES.pixflux), nil)
check("pixflux 401 wide", shared.check_size(401, 64, shared.SIZES.pixflux) ~= nil, true)
check("pixflux area too small", shared.check_size(16, 16, shared.SIZES.pixflux) ~= nil, true)
check("pixflux area min 32x32", shared.check_size(32, 32, shared.SIZES.pixflux), nil)
check("pixflux area too large", shared.check_size(400, 401, shared.SIZES.pixflux) ~= nil, true)
-- bitforge / inpaint
check("bitforge 200x200 ok", shared.check_size(200, 200, shared.SIZES.bitforge), nil)
check("bitforge area too large", shared.check_size(200, 201, shared.SIZES.bitforge) ~= nil, true)
check("bitforge wide-thin within area ok", shared.check_size(100, 200, shared.SIZES.bitforge), nil)
-- animate text: only 64
check("animate text 64 ok", shared.check_size(64, 64, shared.SIZES.animate_text), nil)
check("animate text 32 bad", shared.check_size(32, 64, shared.SIZES.animate_text) ~= nil, true)
-- animate skeleton set
check("skeleton 128x64 ok", shared.check_size(128, 64, shared.SIZES.animate_skeleton), nil)
check("skeleton 100 bad", shared.check_size(100, 64, shared.SIZES.animate_skeleton) ~= nil, true)
-- rotate set
check("rotate 128 ok", shared.check_size(128, 128, shared.SIZES.rotate), nil)
check("rotate 256 bad", shared.check_size(256, 128, shared.SIZES.rotate) ~= nil, true)

-- sanitize_filename
check("sanitize keeps clean name", shared.sanitize_filename("hero.png"), "hero.png")
check("sanitize strips dirs", shared.sanitize_filename("../../etc/evil.png"), "evil.png")
check("sanitize windows path", shared.sanitize_filename("C:\\temp\\hero 2.png"), "hero_2.png")
check("sanitize forces png", shared.sanitize_filename("hero"), "hero.png")
check("sanitize empty fallback", shared.sanitize_filename(""), "out.png")
check("sanitize dots only", shared.sanitize_filename(".png"), "out.png")

-- arg coercion
check("int_arg number", shared.int_arg({ width = 64 }, "width"), 64)
check("int_arg string", shared.int_arg({ width = "64" }, "width"), 64)
check("int_arg default", shared.int_arg({}, "width", 300), 300)
check("int_arg float rejected", select(2, shared.int_arg({ width = 4.5 }, "width")) ~= nil, true)
check("int_arg bad string", select(2, shared.int_arg({ width = "big" }, "width")) ~= nil, true)
check("num_arg float ok", shared.num_arg({ g = "1.4" }, "g"), 1.4)
check("bool_arg true", shared.bool_arg({ x = true }, "x"), true)
check("bool_arg string true", shared.bool_arg({ x = "true" }, "x"), true)
check("bool_arg absent", shared.bool_arg({}, "x"), false)
check("bool_arg string false", shared.bool_arg({ x = "false" }, "x"), false)

-- parse_keypoints (with a json stub injected below the dofile? json is a
-- global lookup at call time — inject now)
json = {
  encode = function(t) return "{}" end,
  decode_safe = function(s)
    if s == "BAD{" then return nil, "parse error" end
    local frames = {}
    local i = 0
    for chunk in s:gmatch("[^|]+") do
      i = i + 1
      frames[i] = {}
      local j = 0
      for pt in chunk:gmatch("[;]+") do
        j = j + 1
        frames[i][j] = { x = 1, y = 2, label = "NOSE" }
      end
    end
    return frames
  end
}

local kp3 = "a;b|a;b|a;b"
check("keypoints 3 frames ok", select(1, shared.parse_keypoints(kp3, 3)) ~= nil, true)
check("keypoints wrong count", select(1, shared.parse_keypoints(kp3, 4)) == nil, true)
check("keypoints any count ok", select(1, shared.parse_keypoints(kp3, nil)) ~= nil, true)
check("keypoints bad json", select(1, shared.parse_keypoints("BAD{", 3)) == nil, true)
check("keypoints empty", select(1, shared.parse_keypoints("", 3)) == nil, true)

-- a frame with a bad point (label missing) must fail
json.decode_safe = function(s)
  return { { { x = 1, y = 2, label = "NOSE" } }, { { x = 1, y = 2 } }, { { x = 1, y = 2, label = "NOSE" } } }
end
check("keypoints bad point rejected", select(1, shared.parse_keypoints("x", 3)) == nil, true)

print("")
if failures == 0 then
  print("test_shared: ALL OK")
else
  print("test_shared: " .. failures .. " FAILURES")
  os.exit(1)
end
