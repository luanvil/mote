-- RFC 7230 HTTP/1.1 Request Parser

local lpeg = require("lpeg")

local core = require("mote.parser.core")
local mime = require("mote.parser.mime")
local uri = require("mote.parser.uri")

local C, Cc, Cf, Cg, Cs, Ct = lpeg.C, lpeg.Cc, lpeg.Cf, lpeg.Cg, lpeg.Cs, lpeg.Ct
local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V

-- helpers --

local function safe_tonumber(str)
    return tonumber(str)
end

local function no_rich_capture(patt)
    return C(patt) / function(a)
        return a
    end
end

-- whitespace (RFC 7230 Section 3.2.3) --

local OWS = (core.SP + core.HTAB) ^ 0
local RWS = (core.SP + core.HTAB) ^ 1
local BWS = OWS

-- comma separation --

local sep = OWS * P(",") * OWS
local optional_sep = (P(",") + core.SP + core.HTAB) ^ 0

local function comma_sep(element, min, max)
    local extra = sep * optional_sep * element
    local patt = element
    if min then
        for _ = 2, min do
            patt = patt * extra
        end
    else
        min = 0
        patt = patt ^ -1
    end
    if max then
        local more = max - min - 1
        patt = patt * extra ^ -more
    else
        patt = patt * extra ^ 0
    end
    return patt
end

local function comma_sep_trim(...)
    return optional_sep * comma_sep(...) * optional_sep
end

-- tokens (RFC 7230 Section 3.2.6) --

local tchar = S("!#$%&'*+-.^_`|~") + core.DIGIT + core.ALPHA
local token = C(tchar ^ 1)
local obs_text = R("\128\255")
local qdtext = core.HTAB + core.SP + P("\33") + R("\35\91", "\93\126") + obs_text
local quoted_pair = Cs(P("\\") * C(core.HTAB + core.SP + core.VCHAR + obs_text) / "%1")
local quoted_string = core.DQUOTE * Cs((qdtext + quoted_pair) ^ 0) * core.DQUOTE

local ctext = core.HTAB + core.SP + R("\33\39", "\42\91", "\93\126") + obs_text
local comment = P({ P("(") * (ctext + quoted_pair + V(1)) ^ 0 * P(")") })

-- headers (RFC 7230 Section 3.2) --

local field_name = token / string.lower
local field_vchar = core.VCHAR + obs_text
local field_content = field_vchar * ((core.SP + core.HTAB) ^ 1 * field_vchar) ^ -1
local obs_fold = (core.SP + core.HTAB) ^ 0 * core.CRLF * (core.SP + core.HTAB) ^ 1 / " "
local field_value = Cs((field_content + obs_fold) ^ 0)
local header_field = field_name * P(":") * OWS * field_value * OWS

-- content-length --

local Content_Length = core.DIGIT ^ 1

-- content-encoding (RFC 7231 Section 3.1.2.2) --

local content_coding = token / string.lower
local Content_Encoding = comma_sep_trim(content_coding, 1)

-- transfer encoding --

local transfer_parameter = (token - S("qQ") * BWS * P("=")) * BWS * P("=") * BWS * (token + quoted_string)
local transfer_extension = Cf(Ct(token / string.lower) * (OWS * P(";") * OWS * Cg(transfer_parameter)) ^ 0, rawset)
local transfer_coding = transfer_extension
local Transfer_Encoding = comma_sep_trim(transfer_coding, 1)

-- chunk extension --

local chunk_ext_name = token
local chunk_ext_val = token + quoted_string
local chunk_ext = (P(";") * chunk_ext_name * (P("=") * chunk_ext_val) ^ -1) ^ 0

-- rank --

local rank = (P("0") * ((P(".") * core.DIGIT ^ -3) / safe_tonumber + Cc(0)) + P("1") * (P(".") * (P("0")) ^ -3) ^ -1)
    * Cc(1)
local t_ranking = OWS * P(";") * OWS * S("qQ") * P("=") * rank
local t_codings = (transfer_coding * t_ranking ^ -1) / function(t, q)
    if q then t["q"] = q end
    return t
end
local TE = comma_sep_trim(t_codings)

-- trailer --

local Trailer = comma_sep_trim(field_name, 1)

-- request target (RFC 7230 Section 5.3) --

local absolute_path = (P("/") * uri.segment) ^ 1
local partial_uri = Ct(uri.relative_part * (P("?") * uri.query) ^ -1)
local origin_form = Cs(absolute_path * (P("?") * uri.query) ^ -1)
local absolute_form = no_rich_capture(uri.absolute_uri)
local authority_form = no_rich_capture(uri.authority)
local asterisk_form = C("*")
local request_target = asterisk_form + origin_form + absolute_form + authority_form

-- request line (RFC 7230 Section 3.1.1) --

local HTTP_name = P("HTTP")
local HTTP_version = HTTP_name * P("/") * (core.DIGIT * P(".") * core.DIGIT / safe_tonumber)
local method = token
local request_line_pattern = method * core.SP * request_target * core.SP * HTTP_version * core.CRLF

-- host header --

local Host = uri.host * (P(":") * uri.port) ^ -1

-- upgrade --

local protocol_name = token
local protocol_version = token
local protocol = protocol_name * (P("/") * protocol_version) ^ -1 / "%0"
local Upgrade = comma_sep_trim(protocol)

-- via --

local received_protocol = (protocol_name * P("/") + Cc("HTTP")) * protocol_version / "%1/%2"
local pseudonym = token
local received_by = uri.host * ((P(":") * uri.port) + -lpeg.B(",")) / "%0" + pseudonym
local Via = comma_sep_trim(
    Ct(Cg(received_protocol, "protocol") * RWS * Cg(received_by, "by") * (RWS * Cg(comment, "comment")) ^ -1),
    1
)

-- connection --

local connection_option = token / string.lower
local Connection = comma_sep_trim(connection_option)

-- request parsing (lenient CRLF for compatibility) --

local pchar = R("az", "AZ", "09") + S("-._~!$&'()*+,;=:@") + P("%") * R("09", "AF", "af") * R("09", "AF", "af")
local path = Cs((P("/") * pchar ^ 0) ^ 1) + Cc("/")
-- lenient query parsing: allow common unencoded chars for better compatibility
local query = Cs((pchar + S("/?<>[]{}|\\^`")) ^ 0)

local location = Ct(Cg(path, "path") * (P("?") * Cg(query, "query")) ^ -1)

local version = P("HTTP/") * C(R("09") * P(".") * R("09"))

local request_line =
    Ct(Cg(C(token), "method") * core.SP * Cg(location, "location") * core.SP * Cg(version, "version") * core.CRLF)

local header = Cg(field_name * P(":") * OWS * C((P(1) - core.CRLF) ^ 0)) * core.CRLF

local headers_grammar = Cf(Ct("") * header ^ 0, function(t, k, v)
    if k then
        t[k] = v
        if k == "content-type" then
            local parsed = mime.parse(v)
            if parsed then t["content-type"] = parsed end
        elseif k == "content-length" then
            t["content-length"] = tonumber(v) or v
        end
    end
    return t
end)

-- module --

local http = {}

function http.parse_request_line(line)
    if not line then return nil end
    local input = line
    if not input:match("\n$") then input = input .. "\n" end
    return lpeg.match(request_line, input)
end

function http.parse_headers(header_block)
    if not header_block then return {} end
    local input = header_block
    if not input:match("\n$") then input = input .. "\n" end
    return lpeg.match(headers_grammar, input) or {}
end

function http.parse_path(full_path)
    if not full_path then return nil end
    local result = lpeg.match(location, full_path)
    if result then return result.path or full_path, result.query end
    return full_path, nil
end

-- exports for advanced usage --

http.patterns = {
    comma_sep = comma_sep,
    comma_sep_trim = comma_sep_trim,
    OWS = OWS,
    RWS = RWS,
    BWS = BWS,
    chunk_ext = chunk_ext,
    comment = comment,
    field_name = field_name,
    field_value = field_value,
    header_field = header_field,
    method = method,
    obs_text = obs_text,
    partial_uri = partial_uri,
    pseudonym = pseudonym,
    qdtext = qdtext,
    quoted_string = quoted_string,
    rank = rank,
    request_line = request_line_pattern,
    request_target = request_target,
    t_ranking = t_ranking,
    tchar = tchar,
    token = token,
    Connection = Connection,
    Content_Encoding = Content_Encoding,
    Content_Length = Content_Length,
    Host = Host,
    TE = TE,
    Trailer = Trailer,
    Transfer_Encoding = Transfer_Encoding,
    Upgrade = Upgrade,
    Via = Via,
}

return http
