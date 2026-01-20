-- JWT (JSON Web Tokens) with HS256

local cjson = require("cjson")
local crypto = require("mote.crypto")
local log = require("mote.log")

local jwt = {}

local function sign(message, secret)
    return crypto.hmac_sha256(secret, message)
end

function jwt.encode(payload, secret)
    local header = { alg = "HS256", typ = "JWT" }
    local header_b64 = crypto.base64url_encode(cjson.encode(header))
    local payload_b64 = crypto.base64url_encode(cjson.encode(payload))
    local message = header_b64 .. "." .. payload_b64
    local signature = sign(message, secret)
    local signature_b64 = crypto.base64url_encode(signature)
    return message .. "." .. signature_b64
end

function jwt.decode(token, secret, options)
    options = options or {}

    if not token then
        log.token_rejected("no token provided")
        return nil, "no token provided"
    end

    local parts = {}
    for part in token:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end

    if #parts ~= 3 then
        log.token_rejected("invalid token format")
        return nil, "invalid token format"
    end

    local header_b64, payload_b64, signature_b64 = parts[1], parts[2], parts[3]
    local message = header_b64 .. "." .. payload_b64

    local expected_sig = crypto.base64url_encode(sign(message, secret))
    if not crypto.constant_time_compare(signature_b64, expected_sig) then
        log.token_rejected("invalid signature")
        return nil, "invalid signature"
    end

    local ok, header = pcall(cjson.decode, crypto.base64url_decode(header_b64))
    if not ok then
        log.token_rejected("invalid header")
        return nil, "invalid header"
    end

    if header.alg ~= "HS256" then
        log.token_rejected("unsupported algorithm", { alg = header.alg })
        return nil, "unsupported algorithm"
    end

    local ok2, payload = pcall(cjson.decode, crypto.base64url_decode(payload_b64))
    if not ok2 then
        log.token_rejected("invalid payload")
        return nil, "invalid payload"
    end

    if payload.exp and os.time() > payload.exp then
        log.token_rejected("token expired", { sub = payload.sub, jti = payload.jti })
        return nil, "token expired"
    end

    if options.audience and payload.aud ~= options.audience then
        log.token_rejected("invalid audience", { expected = options.audience, got = payload.aud })
        return nil, "invalid audience"
    end

    if options.issuer and payload.iss ~= options.issuer then
        log.token_rejected("invalid issuer", { expected = options.issuer, got = payload.iss })
        return nil, "invalid issuer"
    end

    return payload
end

function jwt.create_token(user_id, secret, options)
    options = options or {}
    local expires_in = options.expires_in or 86400
    local jti = crypto.to_hex(crypto.random_bytes(16))

    local payload = {
        sub = user_id,
        iat = os.time(),
        exp = os.time() + expires_in,
        jti = jti,
    }

    if options.audience then payload.aud = options.audience end

    if options.issuer then payload.iss = options.issuer end

    local token = jwt.encode(payload, secret)

    log.token_issued(user_id, jti)

    return token, jti
end

return jwt
