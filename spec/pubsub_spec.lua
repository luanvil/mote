local client_mod = require("mote.pubsub.client")
local broker = require("mote.pubsub.broker")
local sse = require("mote.pubsub.sse")

describe("pubsub", function()
    describe("client", function()
        it("creates client with unique id", function()
            local c1 = client_mod.new()
            local c2 = client_mod.new()

            assert.is_truthy(c1.id)
            assert.is_truthy(c2.id)
            assert.are_not.equal(c1.id, c2.id)
            assert.are.equal(40, #c1.id)
        end)

        it("subscribes to topics", function()
            local c = client_mod.new()

            c:subscribe("posts/*")
            assert.is_true(c:has_subscription("posts/*"))
            assert.is_false(c:has_subscription("users/*"))

            c:subscribe({ "users/*", "comments/*" })
            assert.is_true(c:has_subscription("users/*"))
            assert.is_true(c:has_subscription("comments/*"))
        end)

        it("unsubscribes from topics", function()
            local c = client_mod.new()
            c:subscribe({ "posts/*", "users/*", "comments/*" })

            c:unsubscribe("posts/*")
            assert.is_false(c:has_subscription("posts/*"))
            assert.is_true(c:has_subscription("users/*"))

            c:unsubscribe()
            assert.is_false(c:has_subscription("users/*"))
            assert.is_false(c:has_subscription("comments/*"))
        end)

        it("gets subscriptions list", function()
            local c = client_mod.new()
            c:subscribe({ "posts/*", "users/*" })

            local subs = c:get_subscriptions()
            assert.are.equal(2, #subs)
        end)

        it("matches wildcard topic", function()
            local c = client_mod.new()
            c:subscribe("posts/*")

            assert.are.equal("posts/*", c:matches_topic("posts", "123"))
            assert.are.equal("posts/*", c:matches_topic("posts", nil))
            assert.is_nil(c:matches_topic("users", "123"))
        end)

        it("matches specific record topic", function()
            local c = client_mod.new()
            c:subscribe("posts/123")

            assert.are.equal("posts/123", c:matches_topic("posts", "123"))
            assert.is_nil(c:matches_topic("posts", "456"))
            assert.is_nil(c:matches_topic("posts", nil))
        end)

        it("matches legacy topic format", function()
            local c = client_mod.new()
            c:subscribe("posts")

            assert.are.equal("posts", c:matches_topic("posts", "123"))
            assert.are.equal("posts", c:matches_topic("posts", nil))
        end)

        it("prioritizes wildcard over legacy", function()
            local c = client_mod.new()
            c:subscribe({ "posts", "posts/*" })

            assert.are.equal("posts/*", c:matches_topic("posts", "123"))
        end)

        it("queues and pops messages", function()
            local c = client_mod.new()

            assert.is_false(c:has_messages())

            c:queue_message({ name = "posts/*", data = { action = "create" } })
            c:queue_message({ name = "posts/*", data = { action = "update" } })

            assert.is_true(c:has_messages())

            local msg1 = c:pop_message()
            assert.are.equal("create", msg1.data.action)

            local msg2 = c:pop_message()
            assert.are.equal("update", msg2.data.action)

            assert.is_false(c:has_messages())
            assert.is_nil(c:pop_message())
        end)

        it("rejects messages when discarded", function()
            local c = client_mod.new()
            c:queue_message({ name = "test", data = {} })

            c:discard()

            assert.is_true(c:is_discarded())
            assert.is_false(c:queue_message({ name = "test", data = {} }))
            assert.is_false(c:has_messages())
        end)

        it("manages auth state", function()
            local c = client_mod.new()

            assert.is_nil(c:get_auth())

            c:set_auth({ sub = 123, email = "test@example.com" })
            assert.are.equal(123, c:get_auth().sub)
        end)

        it("manages context storage", function()
            local c = client_mod.new()

            assert.is_nil(c:get("key"))

            c:set("key", "value")
            assert.are.equal("value", c:get("key"))

            c:set("key", { nested = true })
            assert.is_true(c:get("key").nested)

            c:unset("key")
            assert.is_nil(c:get("key"))
        end)

        it("formats SSE message", function()
            local msg = client_mod.format_sse("client123", "posts/*", { action = "create" })

            assert.is_truthy(msg:match("^id:client123\n"))
            assert.is_truthy(msg:match("event:posts/%*\n"))
            assert.is_truthy(msg:match('data:{"action":"create"}\n\n$'))
        end)

        it("formats SSE message with string data", function()
            local msg = client_mod.format_sse("client123", "CONNECT", '{"clientId":"abc"}')

            assert.is_truthy(msg:match("event:CONNECT\n"))
            assert.is_truthy(msg:match('data:{"clientId":"abc"}\n\n$'))
        end)
    end)

    describe("broker", function()
        before_each(function()
            for id in pairs(broker.clients) do
                broker.unregister(id)
            end
        end)

        it("creates and registers client", function()
            local c = broker.create_client()

            assert.is_truthy(c)
            assert.is_truthy(c.id)
            assert.are.equal(c, broker.get_client(c.id))
            assert.are.equal(1, broker.total_clients())
        end)

        it("registers and unregisters client", function()
            local c = client_mod.new()
            broker.register(c)

            assert.are.equal(c, broker.get_client(c.id))

            broker.unregister(c.id)
            assert.is_nil(broker.get_client(c.id))
            assert.is_true(c:is_discarded())
        end)

        it("returns nil for unknown client", function()
            assert.is_nil(broker.get_client("nonexistent"))
        end)

        it("lists all clients", function()
            broker.create_client()
            broker.create_client()
            broker.create_client()

            local all = broker.all_clients()
            assert.are.equal(3, #all)
            assert.are.equal(3, broker.total_clients())
        end)

        it("broadcasts to matching subscribers", function()
            local c1 = broker.create_client()
            local c2 = broker.create_client()
            local c3 = broker.create_client()

            c1:subscribe("posts/*")
            c2:subscribe("posts/*")
            c3:subscribe("users/*")

            broker.broadcast("posts", "create", { id = 1, title = "Hello" })

            assert.is_true(c1:has_messages())
            assert.is_true(c2:has_messages())
            assert.is_false(c3:has_messages())

            local msg = c1:pop_message()
            assert.are.equal("posts/*", msg.name)
            assert.are.equal("create", msg.data.action)
            assert.are.equal(1, msg.data.record.id)
        end)

        it("broadcasts to specific record subscribers", function()
            local c1 = broker.create_client()
            local c2 = broker.create_client()

            c1:subscribe("posts/1")
            c2:subscribe("posts/2")

            broker.broadcast("posts", "update", { id = 1, title = "Updated" })

            assert.is_true(c1:has_messages())
            assert.is_false(c2:has_messages())
        end)

        it("skips discarded clients", function()
            local c1 = broker.create_client()
            local c2 = broker.create_client()

            c1:subscribe("posts/*")
            c2:subscribe("posts/*")
            c2:discard()

            broker.broadcast("posts", "create", { id = 1 })

            assert.is_true(c1:has_messages())
            assert.is_false(c2:has_messages())
        end)

        it("cleans up discarded clients", function()
            local c1 = broker.create_client()
            local c2 = broker.create_client()

            c1:discard()

            assert.are.equal(2, broker.total_clients())
            broker.cleanup()
            assert.are.equal(1, broker.total_clients())
            assert.is_nil(broker.get_client(c1.id))
            assert.is_truthy(broker.get_client(c2.id))
        end)
    end)

    describe("sse", function()
        it("has IDLE_TIMEOUT constant", function()
            assert.are.equal(300, sse.IDLE_TIMEOUT)
        end)

        it("should_resume returns true when client has messages", function()
            local c = client_mod.new()
            c:queue_message({ name = "test", data = {} })

            local conn = { waiting = "sse", sse_client = c }
            assert.is_true(sse.should_resume(conn))
        end)

        it("should_resume returns true when client is discarded", function()
            local c = client_mod.new()
            c:discard()

            local conn = { waiting = "sse", sse_client = c }
            assert.is_true(sse.should_resume(conn))
        end)

        it("should_resume returns false when no messages and not discarded", function()
            local c = client_mod.new()

            local conn = { waiting = "sse", sse_client = c }
            assert.is_false(sse.should_resume(conn))
        end)

        it("should_resume returns false for non-sse connections", function()
            local c = client_mod.new()
            c:queue_message({ name = "test", data = {} })

            local conn = { waiting = "read", sse_client = c }
            assert.is_false(sse.should_resume(conn))
        end)

        it("cleanup unregisters client from broker", function()
            local c = broker.create_client()
            local id = c.id

            assert.is_truthy(broker.get_client(id))
            sse.cleanup(c)
            assert.is_nil(broker.get_client(id))
        end)

        it("cleanup handles nil client", function()
            assert.has_no.errors(function()
                sse.cleanup(nil)
            end)
        end)
    end)
end)
