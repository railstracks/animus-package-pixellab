-- b64.lua — real base64 for the live harness (sandbox has it built in; plain
-- lua5.4 does not). Roundtrip-verified against known vectors.

local M = {}
local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local rev = {}
for i = 1, #CHARS do rev[CHARS:byte(i)] = i - 1 end

function M.encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local b1, b2, b3 = data:byte(i, i + 2)
    local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
    local c1 = CHARS:sub(((n >> 18) & 63) + 1, ((n >> 18) & 63) + 1)
    local c2 = CHARS:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
    local c3 = CHARS:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1)
    local c4 = CHARS:sub((n & 63) + 1, (n & 63) + 1)
    if b2 == nil then c3 = "=" end
    if b3 == nil then c4 = "=" end
    out[#out + 1] = c1 .. c2 .. c3 .. c4
  end
  return table.concat(out)
end

function M.decode(s)
  s = s:gsub("[^%w%+%/]", "")
  local out = {}
  local i = 1
  while i <= #s do
    local c1, c2, c3, c4 = s:byte(i, i + 3)
    if not (c1 and c2) then break end
    local n = rev[c1] * 262144 + rev[c2] * 4096 + ((c3 and rev[c3]) or 0) * 64 + ((c4 and rev[c4]) or 0)
    local b1 = (n >> 16) & 0xFF
    local b2 = (n >> 8) & 0xFF
    local b3 = n & 0xFF
    out[#out + 1] = string.char(b1)
    if c3 and rev[c3] then out[#out + 1] = string.char(b2) end
    if c4 and rev[c4] then out[#out + 1] = string.char(b3) end
    i = i + 4
  end
  return table.concat(out)
end

return M
