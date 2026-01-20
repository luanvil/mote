local server = require("mote.server")

describe("server", function()
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
