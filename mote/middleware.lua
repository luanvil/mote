-- HTTP middleware (CORS, body parsing, rate limiting)

local cjson = require("cjson")
local jwt = require("mote.jwt")
local log = require("mote.log")
local multipart = require("mote.parser.multipart")
local url = require("mote.url")

local encode, decode = cjson.encode, cjson.decode

local middleware = {}

-- cors --

local cors_base = {
    ["Access-Control-Allow-Origin"] = "*",
    ["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    ["Access-Control-Allow-Headers"] = "Content-Type, Authorization",
}

function middleware.cors_headers()
    local headers = {}
    for k, v in pairs(cors_base) do
        headers[k] = v
    end
    return headers
end

function middleware.configure_cors(config)
    if config.origin then cors_base["Access-Control-Allow-Origin"] = config.origin end
    if config.methods then cors_base["Access-Control-Allow-Methods"] = config.methods end
    if config.headers then cors_base["Access-Control-Allow-Headers"] = config.headers end
end

function middleware.is_preflight(method)
    return method == "OPTIONS"
end

-- auth --

-- Optional callbacks for user validation and issuer resolution
local user_validator = nil
local issuer_resolver = nil

function middleware.set_user_validator(fn)
    user_validator = fn
end

function middleware.set_issuer_resolver(fn)
    issuer_resolver = fn
end

function middleware.extract_auth(headers, secret, options)
    local auth_header = headers["authorization"]
    if not auth_header then return nil end

    local token = auth_header:match("^Bearer%s+(.+)$")
    if not token then return nil end

    options = options or {}
    if issuer_resolver then options.issuer = issuer_resolver() end

    local payload, err = jwt.decode(token, secret, options)
    if not payload then return nil, err end

    if user_validator and payload.sub then
        local user_ok, user_err = user_validator(payload.sub)
        if not user_ok then
            log.token_rejected(user_err or "user validation failed", { sub = payload.sub })
            return nil, user_err or "user validation failed"
        end
    end

    log.auth_success(payload.sub, "jwt")

    return payload
end

-- body --

function middleware.encode_json(data)
    return encode(data)
end

function middleware.parse_body(body_raw, headers)
    if not body_raw or body_raw == "" then return {} end

    local ct = headers and headers["content-type"]
    local content_type = ""
    if type(ct) == "table" and ct.type then
        content_type = ct.type
    elseif type(ct) == "string" then
        content_type = ct
    end

    if multipart.is_multipart(content_type) then
        local boundary = multipart.get_boundary(content_type)
        if not boundary then return nil, "missing boundary in multipart request" end
        local parts, err = multipart.parse(body_raw, boundary)
        if not parts then return nil, "failed to parse multipart: " .. (err or "unknown error") end
        return parts, nil, true
    end

    if content_type:find("application/x%-www%-form%-urlencoded", 1, false) then
        return url.parse_query(body_raw)
    end

    local ok, data = pcall(decode, body_raw)
    if not ok then return nil, "invalid JSON: " .. tostring(data) end

    return data
end

-- ratelimit --

local buckets = {}
local ratelimit_config = {}
local global_limit = nil

local DEFAULT_RATELIMIT = {
    ["*"] = { max = 100, window = 60 },
}

local function get_bucket_key(ip, path)
    return ip .. ":" .. path
end

local function get_config_for_path(path)
    if global_limit then return { max = global_limit, window = 60 } end
    if ratelimit_config[path] then return ratelimit_config[path] end
    return ratelimit_config["*"] or DEFAULT_RATELIMIT["*"]
end

local function get_or_create_bucket(key, cfg)
    local now = os.time()
    local bucket = buckets[key]

    if not bucket then
        bucket = {
            tokens = cfg.max,
            last_refill = now,
        }
        buckets[key] = bucket
    end

    local elapsed = now - bucket.last_refill
    if elapsed > 0 then
        local refill_rate = cfg.max / cfg.window
        local new_tokens = bucket.tokens + (elapsed * refill_rate)
        bucket.tokens = math.min(cfg.max, new_tokens)
        bucket.last_refill = now
    end

    return bucket
end

function middleware.ratelimit_configure(cfg)
    ratelimit_config = cfg or DEFAULT_RATELIMIT
end

function middleware.ratelimit_set_global(limit)
    global_limit = limit
end

function middleware.ratelimit_check(ip, path)
    if global_limit == 0 then return true end

    local cfg = get_config_for_path(path)
    local key = get_bucket_key(ip, path)
    local bucket = get_or_create_bucket(key, cfg)

    if bucket.tokens >= 1 then
        bucket.tokens = bucket.tokens - 1
        return true
    end

    return false
end

function middleware.ratelimit_reset()
    buckets = {}
end

function middleware.ratelimit_cleanup()
    local now = os.time()
    local stale_threshold = 300

    for key, bucket in pairs(buckets) do
        if now - bucket.last_refill > stale_threshold then buckets[key] = nil end
    end
end

return middleware
