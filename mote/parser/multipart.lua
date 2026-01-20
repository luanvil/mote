-- RFC-2046 multipart/form-data parser

local lpeg = require("lpeg")
local core = require("mote.parser.core")
local mime = require("mote.parser.mime")

local C, Cf, Cg, Ct, P = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Ct, lpeg.P

local multipart = {}

-- patterns --

local CRLF = P("\r") ^ -1 * P("\n")

local param = Cg(C(mime.token) * P("=") * mime.param_value)
local params = Cf(Ct("") * (P(";") * core.WSP ^ 0 * param) ^ 0, rawset)
local disposition_grammar = P("form-data") * params

local header_name = C(mime.token)
local header_value = C((P(1) - CRLF) ^ 0)
local header = Cg(header_name * P(":") * core.WSP ^ 0 * header_value)
local header_grammar = Cf(Ct("") * (header * CRLF) ^ 0, rawset)

function multipart.get_boundary(content_type)
    if not content_type then return nil end
    if type(content_type) == "table" then return content_type.parameters and content_type.parameters.boundary end
    local parsed = mime.parse(content_type)
    return parsed and parsed.parameters and parsed.parameters.boundary
end

function multipart.is_multipart(content_type)
    if not content_type then return false end
    if type(content_type) == "table" then return content_type.type == "multipart/form-data" end
    local parsed = mime.parse(content_type)
    return parsed and parsed.type == "multipart/form-data"
end

local function parse_part(part_content)
    local sep = "\r\n\r\n"
    local header_end = part_content:find(sep, 1, true)
    local body_start = 4

    if not header_end then
        sep = "\n\n"
        header_end = part_content:find(sep, 1, true)
        body_start = 2
    end

    if not header_end then return nil, "malformed part: no header/body separator" end

    local header_section = part_content:sub(1, header_end - 1)
    local body = part_content:sub(header_end + body_start)

    local headers = lpeg.match(header_grammar, header_section .. "\n")
    if not headers then return nil, "failed to parse headers" end

    local disposition_header = nil
    for k, v in pairs(headers) do
        if k:lower() == "content-disposition" then
            disposition_header = v
            break
        end
    end

    if not disposition_header then return nil, "missing Content-Disposition header" end

    local disposition = lpeg.match(disposition_grammar, disposition_header)
    if not disposition then return nil, "failed to parse Content-Disposition" end

    local content_type = nil
    for k, v in pairs(headers) do
        if k:lower() == "content-type" then
            content_type = v
            break
        end
    end

    return {
        name = disposition.name,
        filename = disposition.filename,
        content_type = content_type or "text/plain",
        data = body,
    }
end

function multipart.parse(body, boundary)
    if not body or not boundary then return nil, "missing body or boundary" end

    local parts = {}
    local delimiter = "--" .. boundary

    local pos = body:find(delimiter, 1, true)
    if not pos then return nil, "no parts found" end

    while true do
        pos = pos + #delimiter

        local next_two = body:sub(pos, pos + 1)
        if next_two == "\r\n" then
            pos = pos + 2
        elseif body:sub(pos, pos) == "\n" then
            pos = pos + 1
        elseif next_two == "--" then
            break
        end

        local next_delim = body:find(delimiter, pos, true)
        if not next_delim then break end

        local part_content = body:sub(pos, next_delim - 1)
        part_content = part_content:gsub("\r?\n$", "")

        local part = parse_part(part_content)
        if part and part.name then
            local name = part.name
            if not parts[name] then
                parts[name] = part
            elseif parts[name].data then
                parts[name] = { parts[name], part }
            else
                parts[name][#parts[name] + 1] = part
            end
        end

        local after_delim = body:sub(next_delim + #delimiter, next_delim + #delimiter + 1)
        if after_delim == "--" then break end

        pos = next_delim
    end

    return parts
end

function multipart.is_file(part)
    return part and part.filename and part.filename ~= ""
end

return multipart
