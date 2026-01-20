-- Crypto utilities

local band, bor, bxor, lshift, rshift
if rawget(_G, "jit") then
    local b = require("bit")
    band, bor, bxor, lshift, rshift = b.band, b.bor, b.bxor, b.lshift, b.rshift
elseif _VERSION >= "Lua 5.3" then
    band = load("return function(a, b) return a & b end")()
    bor = load("return function(a, b) return a | b end")()
    bxor = load("return function(a, b) return a ~ b end")()
    lshift = load("return function(a, n) return a << n end")()
    rshift = load("return function(a, n) return a >> n end")()
else
    local ok, b = pcall(require, "bit32")
    if not ok then
        ok, b = pcall(require, "bit")
    end
    if ok then
        band, bor, bxor, lshift, rshift = b.band, b.bor, b.bxor, b.lshift, b.rshift
    else
        error("no bitwise library available")
    end
end
local byte, char, format, rep, sub = string.byte, string.char, string.format, string.rep, string.sub
local concat = table.concat

local crypto = {}

-- Try to load C extension for SHA256/HMAC, fall back to pure Lua
local hashings_ok, hashings = pcall(require, "mote.hashings_c")
if not hashings_ok then
    -- Try alternative name
    hashings_ok, hashings = pcall(require, "mote.crypto_c")
end

if hashings_ok and hashings.sha256 then
    function crypto.sha256(message)
        return hashings.sha256(message)
    end

    function crypto.hmac_sha256(key, message)
        return hashings.hmac_sha256(key, message)
    end
else
    -- Pure Lua SHA256 implementation would go here
    -- For now, require the C extension
    error("mote.hashings_c or mote.crypto_c required for SHA256/HMAC")
end

function crypto.to_hex(data)
    local out = {}
    for i = 1, #data do
        out[i] = format("%02x", byte(data, i))
    end
    return concat(out)
end

-- base64 --

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, 64 do
    B64_LOOKUP[sub(B64, i, i)] = i - 1
end

function crypto.base64_encode(data)
    local result = {}
    local mod = #data % 3
    if mod > 0 then data = data .. rep("\0", 3 - mod) end
    for i = 1, #data, 3 do
        local n = bor(bor(lshift(byte(data, i), 16), lshift(byte(data, i + 1), 8)), byte(data, i + 2))
        result[#result + 1] = sub(B64, rshift(n, 18) + 1, rshift(n, 18) + 1)
            .. sub(B64, band(rshift(n, 12), 63) + 1, band(rshift(n, 12), 63) + 1)
            .. sub(B64, band(rshift(n, 6), 63) + 1, band(rshift(n, 6), 63) + 1)
            .. sub(B64, band(n, 63) + 1, band(n, 63) + 1)
    end
    local encoded = concat(result)
    if mod > 0 then encoded = sub(encoded, 1, -(3 - mod) - 1) .. rep("=", 3 - mod) end
    return encoded
end

function crypto.base64_decode(data)
    data = data:gsub("%s", ""):gsub("=", "")
    local pad = (4 - #data % 4) % 4
    data = data .. rep("A", pad)
    local result = {}
    for i = 1, #data, 4 do
        local n = bor(
            bor(lshift(B64_LOOKUP[sub(data, i, i)], 18), lshift(B64_LOOKUP[sub(data, i + 1, i + 1)], 12)),
            bor(lshift(B64_LOOKUP[sub(data, i + 2, i + 2)], 6), B64_LOOKUP[sub(data, i + 3, i + 3)])
        )
        result[#result + 1] = char(band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF))
    end
    local decoded = concat(result)
    return pad > 0 and sub(decoded, 1, -pad - 1) or decoded
end

function crypto.base64url_encode(data)
    return crypto.base64_encode(data):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

function crypto.base64url_decode(data)
    local b64 = data:gsub("-", "+"):gsub("_", "/")
    local pad = (4 - #b64 % 4) % 4
    if pad > 0 and pad < 4 then b64 = b64 .. rep("=", pad) end
    return crypto.base64_decode(b64)
end

function crypto.constant_time_compare(a, b)
    if #a ~= #b then return false end
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(byte(a, i), byte(b, i)))
    end
    return result == 0
end

function crypto.random_bytes(n)
    local f = io.open("/dev/urandom", "rb")
    if not f then error("cannot open /dev/urandom") end
    local bytes = f:read(n)
    f:close()
    if not bytes or #bytes ~= n then error("failed to read from /dev/urandom") end
    return bytes
end

return crypto
