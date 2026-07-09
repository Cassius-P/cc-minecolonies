----------------------------------------------------------------------------
-- common/sha1.lua -- pure-Lua SHA-1 (no bit32 / bit dependency, so it runs the
-- same on CC:Tweaked and under luajit tests). Used to compute git blob hashes
-- for the incremental updater: git_blob_sha = sha1("blob <len>\0" .. content).
--
-- 32-bit words are handled with plain arithmetic; the bitwise ops use precomputed
-- 4-bit (nibble) tables, so each 32-bit op is 8 table lookups rather than a
-- 32-iteration bit loop.
----------------------------------------------------------------------------

local M = {}

local xor4, and4, or4 = {}, {}, {}
for a = 0, 15 do
  xor4[a], and4[a], or4[a] = {}, {}, {}
  for b = 0, 15 do
    local x, an, o, p = 0, 0, 0, 1
    for k = 0, 3 do
      local abit = math.floor(a / p) % 2
      local bbit = math.floor(b / p) % 2
      if abit ~= bbit then x = x + p end
      if abit == 1 and bbit == 1 then an = an + p end
      if abit == 1 or bbit == 1 then o = o + p end
      p = p * 2
    end
    xor4[a][b], and4[a][b], or4[a][b] = x, an, o
  end
end

local function op32(t, a, b)
  local r, shift = 0, 1
  for _ = 1, 8 do
    r = r + t[a % 16][b % 16] * shift
    a = math.floor(a / 16); b = math.floor(b / 16); shift = shift * 16
  end
  return r
end

local function bxor(a, b) return op32(xor4, a, b) end
local function band(a, b) return op32(and4, a, b) end
local function bor(a, b) return op32(or4, a, b) end
local function bnot(a) return 4294967295 - a end

-- rotate-left within 32 bits.
local function rol(x, n)
  local hi = x * (2 ^ n)
  hi = hi % 4294967296
  local lo = math.floor(x / (2 ^ (32 - n)))
  return hi + lo
end

-- SHA-1 of a byte string -> 40-char lowercase hex.
function M.hex(msg)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local len = #msg
  local bitlen = len * 8

  -- Pad: 0x80, then zeros to 56 mod 64, then 64-bit big-endian bit length.
  msg = msg .. "\128"
  while (#msg % 64) ~= 56 do msg = msg .. "\0" end
  local hi = math.floor(bitlen / 4294967296)
  local lo = bitlen % 4294967296
  local function be32(v)
    return string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256,
      math.floor(v / 256) % 256, v % 256)
  end
  msg = msg .. be32(hi) .. be32(lo)

  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local o = chunk + i * 4
      local b1, b2, b3, b4 = msg:byte(o, o + 3)
      w[i] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
    end
    for i = 16, 79 do
      w[i] = rol(bxor(bxor(w[i - 3], w[i - 8]), bxor(w[i - 14], w[i - 16])), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f = bor(band(b, c), band(bnot(b), d)); k = 0x5A827999
      elseif i < 40 then
        f = bxor(bxor(b, c), d); k = 0x6ED9EBA1
      elseif i < 60 then
        f = bor(bor(band(b, c), band(b, d)), band(c, d)); k = 0x8F1BBCDC
      else
        f = bxor(bxor(b, c), d); k = 0xCA62C1D6
      end
      local tmp = (rol(a, 5) + f + e + k + w[i]) % 4294967296
      e = d; d = c; c = rol(b, 30); b = a; a = tmp
    end

    h0 = (h0 + a) % 4294967296
    h1 = (h1 + b) % 4294967296
    h2 = (h2 + c) % 4294967296
    h3 = (h3 + d) % 4294967296
    h4 = (h4 + e) % 4294967296
  end

  return ("%08x%08x%08x%08x%08x"):format(h0, h1, h2, h3, h4)
end

return M
