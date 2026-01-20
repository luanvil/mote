-- RFC 5234 ABNF Core Rules

local lpeg = require("lpeg")

local P, R, S = lpeg.P, lpeg.R, lpeg.S

local core = {}

core.ALPHA = R("AZ", "az")
core.BIT = S("01")
core.CHAR = R("\1\127")
core.CR = P("\r")
core.CRLF = P("\r\n")
core.CTL = R("\0\31") + P("\127")
core.DIGIT = R("09")
core.DQUOTE = P('"')
core.HEXDIG = core.DIGIT + S("ABCDEFabcdef")
core.HTAB = P("\t")
core.LF = P("\n")
core.OCTET = P(1)
core.SP = P(" ")
core.VCHAR = R("\33\126")
core.WSP = S(" \t")

core.LWSP = (core.WSP + core.CRLF * core.WSP) ^ 0

return core
