-- RFC 2045 MIME Parser

local lpeg = require("lpeg")

local core = require("mote.parser.core")

local C, Cf, Cg, Cs, Ct = lpeg.C, lpeg.Cf, lpeg.Cg, lpeg.Cs, lpeg.Ct
local P, R, S = lpeg.P, lpeg.R, lpeg.S

-- patterns --

local CRLF = core.CRLF
local CTL = core.CTL
local DQUOTE = core.DQUOTE
local WSP = core.WSP

local tspecials = S([=["(),/:;<=>?@[\]]=])
local qtext = P(1) - S('"\\') - CRLF
local quoted_pair = P("\\") * C(P(1))

local mime = {
    token = (P(1) - tspecials - CTL - WSP) ^ 1,
    quoted_string = DQUOTE * Cs((qtext + quoted_pair) ^ 0) * DQUOTE,
}

mime.param_value = mime.quoted_string + C(mime.token)

-- grammar --

local ichar = R("AZ") / string.lower + (R("!~") - tspecials)
local itoken = Cs(ichar ^ 1)
local value = P('"') * C(R(" !", "#~") ^ 0) * P('"') + C((R(" ~") - tspecials) ^ 1)

local parameters = Cf(Ct("") * (P(";") * WSP ^ 0 * Cg(itoken * P("=") * value)) ^ 0, function(acc, name, val)
    acc[name] = val
    return acc
end)

local type_subtype = Cs(ichar ^ 1 * P("/") * ichar ^ 1)

mime.grammar = Ct(Cg(type_subtype, "type") * Cg(parameters, "parameters"))

function mime.parse(content_type)
    if not content_type then return nil end
    return lpeg.match(mime.grammar, content_type)
end

return mime
