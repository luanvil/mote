local router = require("mote.router")

describe("router", function()
    before_each(function()
        router.clear()
    end)

    it("matches simple routes", function()
        local called = false
        router.get("/health", function()
            called = true
        end)

        local handler = router.match("GET", "/health")
        assert.is_truthy(handler)
        handler()
        assert.is_true(called)
    end)

    it("matches routes with params", function()
        router.get("/users/:id", function() end)
        router.get("/collections/:name/records/:id", function() end)

        local handler, params = router.match("GET", "/users/123")
        assert.is_truthy(handler)
        assert.are.equal("123", params.id)

        local handler2, params2 = router.match("GET", "/collections/posts/records/42")
        assert.is_truthy(handler2)
        assert.are.equal("posts", params2.name)
        assert.are.equal("42", params2.id)
    end)

    it("matches different methods", function()
        router.get("/resource", function()
            return "get"
        end)
        router.post("/resource", function()
            return "post"
        end)

        assert.is_truthy(router.match("GET", "/resource"))
        assert.is_truthy(router.match("POST", "/resource"))
        assert.is_nil(router.match("DELETE", "/resource"))
    end)

    it("returns nil for unmatched routes", function()
        router.get("/exists", function() end)
        assert.is_nil(router.match("GET", "/not-exists"))
    end)
end)
