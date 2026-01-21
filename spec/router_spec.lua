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

    describe("middleware", function()
        it("runs middleware before handler", function()
            local order = {}
            router.use(function(_ctx, next)
                table.insert(order, "mw1-before")
                next()
                table.insert(order, "mw1-after")
            end)
            router.get("/test", function()
                table.insert(order, "handler")
            end)

            local handler = router.match("GET", "/test")
            local composed = router.compose(handler)
            composed({})

            assert.are.same({ "mw1-before", "handler", "mw1-after" }, order)
        end)

        it("runs multiple middleware in onion order", function()
            local order = {}
            router.use(function(_ctx, next)
                table.insert(order, "mw1-before")
                next()
                table.insert(order, "mw1-after")
            end)
            router.use(function(_ctx, next)
                table.insert(order, "mw2-before")
                next()
                table.insert(order, "mw2-after")
            end)
            router.get("/test", function()
                table.insert(order, "handler")
            end)

            local handler = router.match("GET", "/test")
            local composed = router.compose(handler)
            composed({})

            assert.are.same({
                "mw1-before",
                "mw2-before",
                "handler",
                "mw2-after",
                "mw1-after",
            }, order)
        end)

        it("can short-circuit by not calling next", function()
            local order = {}
            router.use(function(ctx, _next)
                table.insert(order, "mw1")
                ctx.response.status = 401
                ctx.response.body = { error = "unauthorized" }
            end)
            router.get("/test", function()
                table.insert(order, "handler")
            end)

            local handler = router.match("GET", "/test")
            local composed = router.compose(handler)
            local ctx = { response = { status = nil, body = nil } }
            composed(ctx)

            assert.are.same({ "mw1" }, order)
            assert.are.equal(401, ctx.response.status)
        end)

        it("passes ctx through middleware chain", function()
            router.use(function(ctx, next)
                ctx.mw1 = true
                next()
            end)
            router.use(function(ctx, next)
                ctx.mw2 = true
                next()
            end)
            router.get("/test", function(ctx)
                ctx.handler = true
            end)

            local handler = router.match("GET", "/test")
            local composed = router.compose(handler)
            local ctx = {}
            composed(ctx)

            assert.is_true(ctx.mw1)
            assert.is_true(ctx.mw2)
            assert.is_true(ctx.handler)
        end)

        it("allows upstream code to access response", function()
            local response_body
            router.use(function(ctx, next)
                next()
                response_body = ctx.response.body
            end)
            router.get("/test", function(ctx)
                ctx.response.body = { message = "hello" }
            end)

            local handler = router.match("GET", "/test")
            local composed = router.compose(handler)
            local ctx = { response = { body = nil } }
            composed(ctx)

            assert.are.same({ message = "hello" }, response_body)
        end)
    end)
end)
