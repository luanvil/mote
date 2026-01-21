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

    describe("ctx:cookie", function()
        local function make_ctx()
            local ctx = {
                request = { headers = {} },
                response = { headers = {} },
            }
            local ctx_methods = require("mote.server")._ctx_methods
            return setmetatable(ctx, { __index = ctx_methods })
        end

        it("sets a simple cookie", function()
            local ctx = make_ctx()
            ctx:cookie("session", "abc123")
            assert.are.equal("session=abc123", ctx.response.headers["Set-Cookie"])
        end)

        it("sets cookie with all options", function()
            local ctx = make_ctx()
            ctx:cookie("token", "xyz", {
                path = "/",
                domain = "example.com",
                maxAge = 3600,
                secure = true,
                httpOnly = true,
                sameSite = "Strict",
            })

            local cookie = ctx.response.headers["Set-Cookie"]
            assert.matches("token=xyz", cookie)
            assert.matches("Path=/", cookie)
            assert.matches("Domain=example.com", cookie)
            assert.matches("Max%-Age=3600", cookie)
            assert.matches("Secure", cookie)
            assert.matches("HttpOnly", cookie)
            assert.matches("SameSite=Strict", cookie)
        end)

        it("handles multiple cookies", function()
            local ctx = make_ctx()
            ctx:cookie("a", "1")
            ctx:cookie("b", "2")
            ctx:cookie("c", "3")

            local cookies = ctx.response.headers["Set-Cookie"]
            assert.are.equal("table", type(cookies))
            assert.are.equal(3, #cookies)
            assert.are.equal("a=1", cookies[1])
            assert.are.equal("b=2", cookies[2])
            assert.are.equal("c=3", cookies[3])
        end)

        it("clears cookie with empty value", function()
            local ctx = make_ctx()
            ctx:cookie("session", "", { maxAge = 0 })
            assert.matches("session=", ctx.response.headers["Set-Cookie"])
            assert.matches("Max%-Age=0", ctx.response.headers["Set-Cookie"])
        end)
    end)

    describe("ctx:get", function()
        local function make_ctx()
            local ctx = {
                request = { headers = { ["content-type"] = "application/json", ["x-custom"] = "value" } },
                response = { headers = {} },
            }
            local ctx_methods = require("mote.server")._ctx_methods
            return setmetatable(ctx, { __index = ctx_methods })
        end

        it("gets header case-insensitively", function()
            local ctx = make_ctx()
            assert.are.equal("application/json", ctx:get("Content-Type"))
            assert.are.equal("application/json", ctx:get("content-type"))
            assert.are.equal("application/json", ctx:get("CONTENT-TYPE"))
        end)

        it("returns nil for missing header", function()
            local ctx = make_ctx()
            assert.is_nil(ctx:get("X-Missing"))
        end)
    end)

    describe("ctx:append", function()
        local function make_ctx()
            local ctx = {
                request = { headers = {} },
                response = { headers = {} },
            }
            local ctx_methods = require("mote.server")._ctx_methods
            return setmetatable(ctx, { __index = ctx_methods })
        end

        it("sets header if not exists", function()
            local ctx = make_ctx()
            ctx:append("Link", "<http://example.com>")
            assert.are.equal("<http://example.com>", ctx.response.headers["Link"])
        end)

        it("appends to existing header", function()
            local ctx = make_ctx()
            ctx:append("Link", "<http://a.com>")
            ctx:append("Link", "<http://b.com>")
            ctx:append("Link", "<http://c.com>")

            local links = ctx.response.headers["Link"]
            assert.are.equal("table", type(links))
            assert.are.equal(3, #links)
        end)
    end)

    describe("ctx:throw", function()
        local function make_ctx()
            local ctx = {
                request = { headers = {} },
                response = { headers = {}, status = nil, body = nil },
            }
            local ctx_methods = require("mote.server")._ctx_methods
            return setmetatable(ctx, { __index = ctx_methods })
        end

        it("sets status and body then throws", function()
            local ctx = make_ctx()
            local ok = pcall(function()
                ctx:throw(401, "unauthorized")
            end)
            assert.is_false(ok)
            assert.are.equal(401, ctx.response.status)
            assert.are.same({ error = "unauthorized" }, ctx.response.body)
        end)

        it("uses default message from status code", function()
            local ctx = make_ctx()
            pcall(function()
                ctx:throw(404)
            end)
            assert.are.equal(404, ctx.response.status)
            assert.are.same({ error = "Not Found" }, ctx.response.body)
        end)
    end)

    describe("ctx:assert", function()
        local function make_ctx()
            local ctx = {
                request = { headers = {} },
                response = { headers = {}, status = nil, body = nil },
            }
            local ctx_methods = require("mote.server")._ctx_methods
            return setmetatable(ctx, { __index = ctx_methods })
        end

        it("returns value when truthy", function()
            local ctx = make_ctx()
            local result = ctx:assert("hello", 400, "missing")
            assert.are.equal("hello", result)
        end)

        it("returns value for truthy table", function()
            local ctx = make_ctx()
            local t = { id = 1 }
            local result = ctx:assert(t, 404, "not found")
            assert.are.same(t, result)
        end)

        it("throws when value is nil", function()
            local ctx = make_ctx()
            local ok = pcall(function()
                ctx:assert(nil, 404, "not found")
            end)
            assert.is_false(ok)
            assert.are.equal(404, ctx.response.status)
            assert.are.same({ error = "not found" }, ctx.response.body)
        end)

        it("throws when value is false", function()
            local ctx = make_ctx()
            local ok = pcall(function()
                ctx:assert(false, 401, "unauthorized")
            end)
            assert.is_false(ok)
            assert.are.equal(401, ctx.response.status)
        end)
    end)

    describe("ctx:remove", function()
        local function make_ctx()
            local ctx = {
                request = { headers = {} },
                response = { headers = { ["X-Custom"] = "value", ["Content-Type"] = "text/plain" } },
            }
            local ctx_methods = require("mote.server")._ctx_methods
            return setmetatable(ctx, { __index = ctx_methods })
        end

        it("removes existing header", function()
            local ctx = make_ctx()
            ctx:remove("X-Custom")
            assert.is_nil(ctx.response.headers["X-Custom"])
            assert.are.equal("text/plain", ctx.response.headers["Content-Type"])
        end)

        it("is chainable", function()
            local ctx = make_ctx()
            local result = ctx:remove("X-Custom")
            assert.are.equal(ctx, result)
        end)

        it("does nothing for non-existent header", function()
            local ctx = make_ctx()
            ctx:remove("X-Missing")
            assert.are.equal("value", ctx.response.headers["X-Custom"])
        end)
    end)

    describe("ctx.url", function()
        it("returns path with query string", function()
            local ctx = {
                request = { path = "/users" },
                query_string = "page=1&limit=10",
            }
            setmetatable(ctx, {
                __index = function(self, key)
                    if key == "url" then
                        return self.request.path .. (self.query_string and ("?" .. self.query_string) or "")
                    end
                end,
            })
            assert.are.equal("/users?page=1&limit=10", ctx.url)
        end)

        it("returns path only when no query string", function()
            local ctx = {
                request = { path = "/users" },
                query_string = nil,
            }
            setmetatable(ctx, {
                __index = function(self, key)
                    if key == "url" then
                        return self.request.path .. (self.query_string and ("?" .. self.query_string) or "")
                    end
                end,
            })
            assert.are.equal("/users", ctx.url)
        end)
    end)

    describe("ctx.ip", function()
        it("returns wrapper ip", function()
            local ctx = {
                wrapper = { ip = "192.168.1.1" },
            }
            setmetatable(ctx, {
                __index = function(self, key)
                    if key == "ip" then return self.wrapper and self.wrapper.ip or "unknown" end
                end,
            })
            assert.are.equal("192.168.1.1", ctx.ip)
        end)

        it("returns unknown when no wrapper", function()
            local ctx = {}
            setmetatable(ctx, {
                __index = function(self, key)
                    if key == "ip" then return self.wrapper and self.wrapper.ip or "unknown" end
                end,
            })
            assert.are.equal("unknown", ctx.ip)
        end)
    end)

    describe("ctx.state", function()
        it("allows passing data through middleware", function()
            local router = require("mote.router")
            router.clear()

            local final_state
            router.use(function(ctx, next)
                ctx.state.user = { id = 42 }
                ctx.state.requestId = "abc123"
                next()
            end)
            router.get("/test", function(ctx)
                final_state = ctx.state
            end)

            local handler = router.match("GET", "/test")
            local composed = router.compose(handler)
            composed({ state = {} })

            assert.are.same({ id = 42 }, final_state.user)
            assert.are.equal("abc123", final_state.requestId)
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
