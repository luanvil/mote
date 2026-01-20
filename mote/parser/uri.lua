-- RFC 3986 URI Parser

local lpeg = require("lpeg")

local P, S = lpeg.P, lpeg.S
local C, Cc, Cg, Cs, Ct = lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Cs, lpeg.Ct

local core = require("mote.parser.core")
local ip = require("mote.parser.ip")

local ALPHA = core.ALPHA
local DIGIT = core.DIGIT
local HEXDIG = core.HEXDIG

local IPv4address = ip.IPv4address
local IPv6address = ip.IPv6address

local uri = {}

-- helpers --

local function read_hex(hex_num)
    return tonumber(hex_num, 16)
end

-- delimiters --

uri.sub_delims = S("!$&'()*+,;=")
local unreserved = ALPHA + DIGIT + S("-._~")

uri.pct_encoded = P("%")
    * (HEXDIG * HEXDIG / read_hex)
    / function(n)
        local c = string.char(n)
        if unreserved:match(c) then
            return c
        else
            return string.format("%%%02X", n)
        end
    end

-- scheme --

uri.scheme = ALPHA * (ALPHA + DIGIT + S("+-.")) ^ 0 / string.lower

-- userinfo --

uri.userinfo = Cs((unreserved + uri.pct_encoded + uri.sub_delims + P(":")) ^ 0)

-- host --

local IPvFuture_mt = {
    __name = "IPvFuture",
}

function IPvFuture_mt:__tostring()
    return string.format("v%x.%s", self.version, self.string)
end

local function new_IPvFuture(version, str)
    return setmetatable({ version = version, string = str }, IPvFuture_mt)
end

local IPvFuture = S("vV")
    * (HEXDIG ^ 1 / read_hex)
    * P(".")
    * C((unreserved + uri.sub_delims + P(":")) ^ 1)
    / new_IPvFuture

local ZoneID = Cs((unreserved + uri.pct_encoded) ^ 1)
local IPv6addrz = IPv6address
    * (P("%25") * ZoneID) ^ -1
    / function(IPv6, zoneid)
        IPv6:setzoneid(zoneid)
        return IPv6
    end

uri.IP_literal = P("[") * (IPv6addrz + IPvFuture) * P("]")
local IP_host = (uri.IP_literal + IPv4address) / tostring

local reg_name = Cs((unreserved / string.lower + uri.pct_encoded / function(s)
    return s:sub(1, 1) == "%" and s or string.lower(s)
end + uri.sub_delims) ^ 1) + Cc(nil)

uri.host = IP_host + reg_name

-- port --

uri.port = DIGIT ^ 0 / tonumber

-- path --

local pchar = unreserved + uri.pct_encoded + uri.sub_delims + S(":@")
local segment = pchar ^ 0
uri.segment = Cs(segment)
local segment_nz = pchar ^ 1
local segment_nz_nc = (pchar - P(":")) ^ 1

local path_empty = Cc(nil)
local path_abempty = Cs((P("/") * segment) ^ 1) + path_empty
local path_rootless = Cs(segment_nz * (P("/") * segment) ^ 0)
local path_noscheme = Cs(segment_nz_nc * (P("/") * segment) ^ 0)
local path_absolute = Cs(P("/") * (segment_nz * (P("/") * segment) ^ 0) ^ -1)

-- query and fragment --

uri.query = Cs((pchar + S("/?")) ^ 0)
uri.fragment = uri.query

-- authority --

uri.authority = (Cg(uri.userinfo, "userinfo") * P("@")) ^ -1
    * Cg(uri.host, "host")
    * (P(":") * Cg(uri.port, "port")) ^ -1

-- hier_part --

local hier_part = P("//") * uri.authority * Cg(path_abempty, "path")
    + Cg(path_absolute + path_rootless + path_empty, "path")

-- absolute_uri --

uri.absolute_uri = Ct((Cg(uri.scheme, "scheme") * P(":")) * hier_part * (P("?") * Cg(uri.query, "query")) ^ -1)

-- uri --

uri.uri = Ct(
    (Cg(uri.scheme, "scheme") * P(":"))
        * hier_part
        * (P("?") * Cg(uri.query, "query")) ^ -1
        * (P("#") * Cg(uri.fragment, "fragment")) ^ -1
)

-- relative_part --

uri.relative_part = P("//") * uri.authority * Cg(path_abempty, "path")
    + Cg(path_absolute + path_noscheme + path_empty, "path")

local relative_ref =
    Ct(uri.relative_part * (P("?") * Cg(uri.query, "query")) ^ -1 * (P("#") * Cg(uri.fragment, "fragment")) ^ -1)

uri.uri_reference = uri.uri + relative_ref

uri.path = path_abempty + path_absolute + path_noscheme + path_rootless + path_empty

-- sane variants --

local sane_host_char = unreserved / string.lower
local hostsegment = (sane_host_char - P(".")) ^ 1
local dns_entry = Cs((hostsegment * P(".")) ^ 1 * ALPHA ^ 2)

uri.sane_host = IP_host + dns_entry
uri.sane_authority = (Cg(uri.userinfo, "userinfo") * P("@")) ^ -1
    * Cg(uri.sane_host, "host")
    * (P(":") * Cg(uri.port, "port")) ^ -1

local sane_hier_part = (P("//")) ^ -1 * uri.sane_authority * Cg(path_absolute + path_empty, "path")

uri.sane_uri = Ct(
    (Cg(uri.scheme, "scheme") * P(":")) ^ -1
        * sane_hier_part
        * (P("?") * Cg(uri.query, "query")) ^ -1
        * (P("#") * Cg(uri.fragment, "fragment")) ^ -1
)

return uri
