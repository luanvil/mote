local server = require("mote.server")
local url = require("mote.url")

describe("server", function()
    describe("ctx.query", function()
        it("parses query string lazily", function()
            local ctx = setmetatable({
                query_string = "page=1&limit=10",
                _query = nil,
            }, {
                __index = function(self, key)
                    if key == "query" then
                        if not self._query then self._query = url.parse_query(self.query_string) end
                        return self._query
                    end
                end,
            })

            assert.is_nil(rawget(ctx, "_query"))
            assert.are.equal("1", ctx.query.page)
            assert.are.equal("10", ctx.query.limit)
            assert.is_not_nil(rawget(ctx, "_query"))
        end)

        it("returns empty table for nil query string", function()
            local ctx = setmetatable({
                query_string = nil,
                _query = nil,
            }, {
                __index = function(self, key)
                    if key == "query" then
                        if not self._query then self._query = url.parse_query(self.query_string) end
                        return self._query
                    end
                end,
            })

            assert.are.same({}, ctx.query)
        end)

        it("decodes URL-encoded values", function()
            local ctx = setmetatable({
                query_string = "name=hello%20world&tag=%2Blua",
                _query = nil,
            }, {
                __index = function(self, key)
                    if key == "query" then
                        if not self._query then self._query = url.parse_query(self.query_string) end
                        return self._query
                    end
                end,
            })

            assert.are.equal("hello world", ctx.query.name)
            assert.are.equal("+lua", ctx.query.tag)
        end)
    end)

    describe("cookie", function()
        it("sets a simple cookie", function()
            local ctx = { _response_headers = {} }
            server.cookie(ctx, "session", "abc123")
            assert.are.equal("session=abc123", ctx._response_headers["Set-Cookie"])
        end)

        it("sets cookie with all options", function()
            local ctx = { _response_headers = {} }
            server.cookie(ctx, "token", "xyz", {
                path = "/",
                domain = "example.com",
                maxAge = 3600,
                secure = true,
                httpOnly = true,
                sameSite = "Strict",
            })

            local cookie = ctx._response_headers["Set-Cookie"]
            assert.matches("token=xyz", cookie)
            assert.matches("Path=/", cookie)
            assert.matches("Domain=example.com", cookie)
            assert.matches("Max%-Age=3600", cookie)
            assert.matches("Secure", cookie)
            assert.matches("HttpOnly", cookie)
            assert.matches("SameSite=Strict", cookie)
        end)

        it("handles multiple cookies", function()
            local ctx = { _response_headers = {} }
            server.cookie(ctx, "a", "1")
            server.cookie(ctx, "b", "2")
            server.cookie(ctx, "c", "3")

            local cookies = ctx._response_headers["Set-Cookie"]
            assert.are.equal("table", type(cookies))
            assert.are.equal(3, #cookies)
            assert.are.equal("a=1", cookies[1])
            assert.are.equal("b=2", cookies[2])
            assert.are.equal("c=3", cookies[3])
        end)

        it("clears cookie with empty value", function()
            local ctx = { _response_headers = {} }
            server.cookie(ctx, "session", "", { maxAge = 0 })
            assert.matches("session=", ctx._response_headers["Set-Cookie"])
            assert.matches("Max%-Age=0", ctx._response_headers["Set-Cookie"])
        end)
    end)

    describe("keep-alive", function()
        local function make_wrapper(request_count)
            return { request_count = request_count or 0 }
        end

        local function make_config(keep_alive_max)
            return { keep_alive_max = keep_alive_max }
        end

        it("enables keep-alive for HTTP/1.1", function()
            local result = server._should_keep_alive("1.1", {}, make_wrapper(), make_config())
            assert.is_true(result)
        end)

        it("disables keep-alive for HTTP/1.0", function()
            local result = server._should_keep_alive("1.0", {}, make_wrapper(), make_config())
            assert.is_false(result)
        end)

        it("enables keep-alive for HTTP/2.0", function()
            local result = server._should_keep_alive("2.0", {}, make_wrapper(), make_config())
            assert.is_true(result)
        end)

        it("respects Connection: close header", function()
            local headers = { connection = "close" }
            local result = server._should_keep_alive("1.1", headers, make_wrapper(), make_config())
            assert.is_false(result)
        end)

        it("respects Connection: keep-alive header for HTTP/1.0", function()
            local headers = { connection = "keep-alive" }
            local result = server._should_keep_alive("1.0", headers, make_wrapper(), make_config())
            assert.is_true(result)
        end)

        it("handles case-insensitive Connection header", function()
            local headers = { connection = "Keep-Alive" }
            local result = server._should_keep_alive("1.0", headers, make_wrapper(), make_config())
            assert.is_true(result)

            headers = { connection = "CLOSE" }
            result = server._should_keep_alive("1.1", headers, make_wrapper(), make_config())
            assert.is_false(result)
        end)

        it("disables keep-alive when max requests reached", function()
            local wrapper = make_wrapper(100)
            local config = make_config(100)
            local result = server._should_keep_alive("1.1", {}, wrapper, config)
            assert.is_false(result)
        end)

        it("allows keep-alive when under max requests", function()
            local wrapper = make_wrapper(99)
            local config = make_config(100)
            local result = server._should_keep_alive("1.1", {}, wrapper, config)
            assert.is_true(result)
        end)

        it("uses default max when config not provided", function()
            local wrapper = make_wrapper(server._DEFAULT_KEEP_ALIVE_MAX)
            local result = server._should_keep_alive("1.1", {}, wrapper, {})
            assert.is_false(result)
        end)
    end)
end)
