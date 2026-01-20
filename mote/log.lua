-- Structured logging

local log = {}

local levels = { debug = 1, info = 2, warn = 3, error = 4 }
local level_names = { [1] = "debug", [2] = "info", [3] = "warn", [4] = "error" }
local current_level = levels.info
local enabled = os.getenv("MOTE_LOG") ~= "0"

function log.set_level(level)
    if type(level) == "string" then
        current_level = levels[level:lower()] or levels.info
    else
        current_level = level
    end
end

function log.enable()
    enabled = true
end

function log.disable()
    enabled = false
end

local function format_value(v)
    if type(v) == "number" and v == math.floor(v) then return string.format("%d", v) end
    return tostring(v)
end

local function format_context(context)
    if not context then return "" end
    local parts = {}
    for k, v in pairs(context) do
        parts[#parts + 1] = k .. "=" .. format_value(v)
    end
    if #parts == 0 then return "" end
    return " (" .. table.concat(parts, ", ") .. ")"
end

local function write(level, category, message, context)
    if not enabled or level < current_level then return end

    local line = os.date("%Y-%m-%d %H:%M:%S")
        .. " ["
        .. level_names[level]
        .. "]"
        .. " ["
        .. category
        .. "] "
        .. message
        .. format_context(context)
        .. "\n"

    if level >= levels.warn then
        io.stderr:write(line)
        io.stderr:flush()
    else
        io.stdout:write(line)
        io.stdout:flush()
    end
end

function log.debug(category, message, context)
    write(levels.debug, category, message, context)
end

function log.info(category, message, context)
    write(levels.info, category, message, context)
end

function log.warn(category, message, context)
    write(levels.warn, category, message, context)
end

function log.error(category, message, context)
    write(levels.error, category, message, context)
end

-- auth-specific helpers (optional, for JWT logging)
function log.auth_success(user_id, method)
    write(levels.info, "auth", "authentication successful", {
        user_id = user_id,
        method = method or "jwt",
    })
end

function log.auth_failure(reason, context)
    write(levels.warn, "auth", "authentication failed: " .. reason, context)
end

function log.token_issued(user_id, jti)
    write(levels.info, "auth", "token issued", { user_id = user_id, jti = jti })
end

function log.token_rejected(reason, context)
    write(levels.warn, "auth", "token rejected: " .. reason, context)
end

return log
