-- pixellab / shared helpers (inlined at build time — the sandbox has no require)
--
-- PixelLab API: https://api.pixellab.ai/v1 (FastAPI; OpenAPI at /v1/openapi.json)
-- Auth: single Bearer token (state.api_token, secret).
--
-- Image flow: inputs are filespace paths read via ctx.fs.read + b64.encode;
-- outputs are base64 PNGs decoded and written via ctx.fs.write, returned as a
-- verified `files` array (relative paths — the kernel adds byte counts).

local shared = {}

-- ---------------------------------------------------------------------------
-- State / auth
-- ---------------------------------------------------------------------------

function shared.require_auth(pkg)
  local t = pkg.get_state("api_token")
  if t == nil or t == "" or t == "***" then
    return false
  end
  return true
end

function shared.headers(pkg)
  return {
    ["Authorization"] = "Bearer " .. tostring(pkg.get_state("api_token")),
    ["Content-Type"] = "application/json"
  }
end

-- Normalize a configured base URL. Paths carry their own /v1 segment, so a
-- base ending in a version doubles it (".../v1/v1/..."). Strip one trailing
-- version segment and any trailing slashes; everything else passes through.
function shared.normalize_base(u)
  u = string.gsub(tostring(u), "/+$", "")
  u = string.gsub(u, "/v%d+$", "")
  return u
end

function shared.base_url(pkg)
  local base = pkg.get_state("base_url")
  if base ~= nil and base ~= "" and base ~= "***" then
    return shared.normalize_base(base)
  end
  return "https://api.pixellab.ai"
end

-- ---------------------------------------------------------------------------
-- Argument coercion (typed params arrive typed; string params may be nil)
-- ---------------------------------------------------------------------------

function shared.num_arg(a, k)
  local v = a[k]
  if v == nil or v == "" then return nil end
  local n = tonumber(v)
  if n == nil then return nil, k .. " must be a number, got: " .. tostring(v) end
  return n
end

function shared.int_arg(a, k, default)
  local n, err = shared.num_arg(a, k)
  if err ~= nil then return nil, err end
  if n == nil then return default end
  if math.floor(n) ~= n then return nil, k .. " must be an integer" end
  return math.floor(n)
end

function shared.bool_arg(a, k)
  local v = a[k]
  if v == nil or v == "" or v == false or v == "false" then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- Enums (verbatim from the OpenAPI spec — error messages list the set)
-- ---------------------------------------------------------------------------

shared.VIEWS = { "side", "low top-down", "high top-down" }
shared.DIRECTIONS = {
  "north", "north-east", "east", "south-east",
  "south", "south-west", "west", "north-west"
}
shared.OUTLINES = {
  "single color black outline", "single color outline",
  "selective outline", "lineless"
}
shared.SHADINGS = {
  "flat shading", "basic shading", "medium shading",
  "detailed shading", "highly detailed shading"
}
shared.DETAILS = { "low detail", "medium detail", "highly detailed" }

local function member(set, v)
  for _, s in ipairs(set) do if s == v then return true end end
  return false
end

-- Returns nil when ok; an error string otherwise.
function shared.check_enum(v, set, field)
  if v == nil or v == "" then return nil end
  if member(set, v) then return nil end
  return field .. " must be one of: " .. table.concat(set, ", ")
end

-- ---------------------------------------------------------------------------
-- Size validation
-- ---------------------------------------------------------------------------

-- spec: {min, max, list?, min_area?, max_area?}
-- Returns nil when ok; an error string otherwise.
function shared.check_size(w, h, spec)
  if spec.list ~= nil then
    if not member(spec.list, w) or not member(spec.list, h) then
      local l = {}
      for _, v in ipairs(spec.list) do l[#l + 1] = tostring(v) end
      return "width/height must each be one of: " .. table.concat(l, "/")
    end
    return nil
  end
  if w < spec.min or w > spec.max or h < spec.min or h > spec.max then
    return "width and height must be " .. spec.min .. "-" .. spec.max .. " each"
  end
  local area = w * h
  if spec.min_area ~= nil and area < spec.min_area then
    return "area too small: " .. w .. "x" .. h .. " = " .. area ..
           " px² (minimum " .. spec.min_area .. " = 32x32)"
  end
  if spec.max_area ~= nil and area > spec.max_area then
    return "area too large: " .. w .. "x" .. h .. " = " .. area ..
           " px² (maximum " .. spec.max_area .. " = 200x200)"
  end
  return nil
end

shared.SIZES = {
  pixflux = { min = 16, max = 400, min_area = 1024, max_area = 160000 },
  bitforge = { min = 16, max = 200, max_area = 40000 },
  inpaint = { min = 16, max = 200, max_area = 40000 },
  animate_text = { list = { 64 } },
  animate_skeleton = { list = { 16, 32, 64, 128, 256 } },
  rotate = { list = { 16, 32, 64, 128 } },
  estimate = { min = 16, max = 256 },
}

-- ---------------------------------------------------------------------------
-- Image IO (filespace paths in/out; binary-safe via b64)
-- ---------------------------------------------------------------------------

-- Read one image file into the API's Base64Image table.
-- Returns image table, or nil + error.
function shared.read_image(ctx, path, field)
  if path == nil or path == "" then
    return nil, field .. " required (filespace path)"
  end
  local data, err = ctx.fs.read(tostring(path))
  if data == nil then
    return nil, field .. " could not be read (" .. tostring(path) .. "): " ..
           tostring(err or "not found")
  end
  return { type = "base64", base64 = b64.encode(data) }
end

-- Read a comma-separated list of image paths into an array of Base64Image.
-- Optional expected_n enforces an exact count (e.g. 3-frame windows).
function shared.read_images(ctx, csv, field, expected_n)
  if csv == nil or csv == "" then return nil end
  local paths = {}
  for p in string.gmatch(tostring(csv), "[^,]+") do
    local trimmed = p:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then paths[#paths + 1] = trimmed end
  end
  if #paths == 0 then return nil end
  if expected_n ~= nil and #paths ~= expected_n then
    return nil, field .. " must list exactly " .. expected_n ..
           " paths (comma-separated), got " .. #paths
  end
  local out = {}
  for i, p in ipairs(paths) do
    local img, err = shared.read_image(ctx, p, field .. "[" .. i .. "]")
    if img == nil then return nil, err end
    out[#out + 1] = img
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Skeleton keypoints (JSON passthrough with shape validation)
-- ---------------------------------------------------------------------------

-- skeleton_keypoints: array of frames (animate skeleton: EXACTLY 3 — the
-- model is a 3-frame window; bitforge: any count); each frame is an array of
-- points {x, y, label, z_index?} (labels per 'skeleton estimate' output).
function shared.parse_keypoints(s, expected_n)
  if s == nil or s == "" then
    return nil, "skeleton_keypoints required (JSON array of frames, as returned by 'skeleton estimate')"
  end
  local ok, kp = pcall(json.decode_safe, tostring(s))
  if not ok or kp == nil then
    return nil, "skeleton_keypoints is not valid JSON"
  end
  if type(kp) ~= "table" then
    return nil, "skeleton_keypoints must be an array of frames, got " .. type(kp)
  end
  if expected_n ~= nil and #kp ~= expected_n then
    return nil, "skeleton_keypoints must be an array of EXACTLY " .. expected_n ..
                " frames (the model is a 3-frame window), got " .. #kp
  end
  for i, frame in ipairs(kp) do
    if type(frame) ~= "table" then
      return nil, "skeleton_keypoints frame " .. i .. " is not an array of points"
    end
    for j, pt in ipairs(frame) do
      if type(pt) ~= "table" or pt.x == nil or pt.y == nil or pt.label == nil then
        return nil, "skeleton_keypoints frame " .. i .. " point " .. j ..
                    " needs x, y and label"
      end
      -- PixelLab quirk (live test, Sept 26): their own estimate-skeleton returns
      -- fractional z_index (-3.5, -0.5) while animate-with-skeleton validates it
      -- as a strict integer. Rounding preserves z-order semantics, so coerce.
      if pt.z_index ~= nil and pt.z_index ~= math.floor(pt.z_index) then
        pt.z_index = math.floor(pt.z_index + 0.5)
      end
    end
  end
  return kp
end

-- ---------------------------------------------------------------------------
-- Output files (FLAT filespace: the kernel accepts slugs only — alnum,
-- '.', '_', '-' — no slashes, no subdirectories)
-- ---------------------------------------------------------------------------

-- Sanitize an agent-provided filename: strip any directory components and
-- characters outside [A-Za-z0-9._-]; force the .png extension.
function shared.sanitize_filename(name)
  name = tostring(name or "")
  name = name:gsub("\\", "/")
  name = name:match("[^/]*$") or ""        -- last path component only
  name = name:gsub("[^%w%.%-_]", "_")     -- safe charset (matches kernel slug rule)
  name = name:gsub("^%.+", "")            -- no leading dots
  if name:match("^%.*png$") then name = "" end  -- extension-only input has no stem
  if name == "" then name = "out.png" end
  if not name:match("%.png$") then name = name .. ".png" end
  return name
end

-- Resolve the output base path for a command run (flat name).
-- filename given  -> <sanitized filename> (explicit overwrite is fine)
-- filename absent -> <prefix>-<utcstamp>_s<seed><suffix>.png (never collides)
function shared.out_base(ctx, prefix, filename, seed, suffix)
  if filename ~= nil and filename ~= "" then
    return shared.sanitize_filename(filename)
  end
  -- Kernel os.date is hostile territory (field-tested Sept 26): only two
  -- exact formats allowed, others silently rewritten, the time arg ignored,
  -- and the '!' UTC prefix passes through strftime as a LITERAL '!'. Stock
  -- lua5.4 differs in all of these. So: format, then slug-normalize the
  -- result — whatever os.date returns, the filename stays legal.
  local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ctx.now / 1000)):gsub("[^%w%.%-]", "")
  return prefix .. "-" .. stamp .. "_s" .. tostring(seed or 0) .. (suffix or "") .. ".png"
end

-- Write response images (single Base64Image or array) with flat base names.
-- Returns files array {{path=...}, ...} or nil + error.
function shared.write_images(ctx, imgs, base)
  if imgs == nil then return nil, "no image in response" end
  if imgs.base64 ~= nil then imgs = { imgs } end
  local files = {}
  for i, img in ipairs(imgs) do
    if img == nil or img.base64 == nil then
      return nil, "response image " .. i .. " has no base64 payload"
    end
    local data = b64.decode(img.base64)
    if data == nil then
      return nil, "response image " .. i .. " is not valid base64"
    end
    local path
    if #imgs == 1 then
      path = base
    else
      path = base:gsub("%.png$", string.format("_f%d.png", i))
    end
    local ok, err = ctx.fs.write(path, data)
    if ok == nil or ok == false then
      return nil, "could not write " .. path .. ": " .. tostring(err)
    end
    files[#files + 1] = { path = path }
  end
  return files
end

-- ---------------------------------------------------------------------------
-- HTTP + error mapping
-- ---------------------------------------------------------------------------

-- POST <base>/v1<path> with a JSON body. Returns {ok=true, json=...} or
-- {ok=false, error=...} with status-mapped, action-friendly messages.
-- Per-call timeout (kernel #118/#119 path: opts.timeout_s, clamped 1-300s server-side).
-- Generation/animation routinely runs 20-90s+ on 200x200 assets; the kernel default
-- is 30s when unset. Read the operator-tunable state field, fall back to 240.
function shared.slow_timeout_s(pkg)
  local v = tonumber(pkg.get_state("timeout_s"))
  if v == nil or v < 1 then return 240 end
  if v > 300 then return 300 end  -- kernel clamp ceiling
  return math.floor(v)
end

function shared.post(ctx, pkg, path, body, timeout_s)
  local opts = {
    headers = shared.headers(pkg),
    body = json.encode(body)
  }
  if timeout_s then opts.timeout_s = timeout_s end
  local r = ctx.http.post(shared.base_url(pkg) .. "/v1" .. path, opts)
  return shared.interpret(r)
end

function shared.get(ctx, pkg, path, timeout_s)
  local opts = {
    headers = shared.headers(pkg)
  }
  if timeout_s then opts.timeout_s = timeout_s end
  local r = ctx.http.get(shared.base_url(pkg) .. "/v1" .. path, opts)
  return shared.interpret(r)
end

function shared.interpret(r)
  if r == nil then return { ok = false, error = "no response from transport" } end
  if r.error ~= nil and r.error ~= "" then
    return { ok = false, error = "transport error: " .. tostring(r.error), http_status = r.status }
  end
  if r.status == 200 then
    return { ok = true, json = r.json, body = r.body }
  end
  -- Error mapping (spec: 401/402/422/429/529)
  local why
  if r.status == 401 then
    why = "authentication failed — check api_token (https://pixellab.ai/account)"
  elseif r.status == 402 then
    why = "insufficient balance — check with 'balance get' and top up at pixellab.ai"
  elseif r.status == 422 then
    why = "request rejected by the API (validation) — see detail"
  elseif r.status == 429 then
    why = "rate limited — wait and retry"
  elseif r.status == 529 then
    why = "PixelLab service overloaded — retry shortly"
  else
    why = "HTTP " .. tostring(r.status)
  end
  local detail = ""
  if r.json ~= nil and type(r.json) == "table" then
    local d = r.json.detail
    if d ~= nil then detail = " — " .. json.encode(d):sub(1, 300) end
  elseif r.body ~= nil and r.body ~= "" then
    detail = " — " .. tostring(r.body):sub(1, 300)
  end
  return { ok = false, error = why .. detail, http_status = r.status, json = r.json }
end

-- Usage block every response carries — surface cost in meta.
function shared.usage_meta(j)
  if j == nil or j.usage == nil then return nil end
  local u = { type = j.usage.type }
  if j.usage.usd ~= nil then u.usd = j.usage.usd end
  if j.usage.generations ~= nil then u.generations = j.usage.generations end
  return u
end

return shared
