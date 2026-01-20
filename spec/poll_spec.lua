local socket = require("socket")
local poll = require("mote.poll")

describe("poll", function()
    describe("poll.poll", function()
        it("returns _MAXFDS constant", function()
            assert.are.equal(4096, poll._MAXFDS)
        end)

        it("returns timeout when no sockets are ready", function()
            local sock = socket.udp()
            sock:setsockname("127.0.0.1", 0)

            local ready, err = poll.poll({
                { sock = sock, read = true, write = false },
            }, 0.01)

            assert.is_nil(ready)
            assert.are.equal("timeout", err)
            sock:close()
        end)

        it("detects writable sockets", function()
            local sock = socket.udp()
            sock:setsockname("127.0.0.1", 0)

            local ready = poll.poll({
                { sock = sock, read = false, write = true },
            }, 0.1)

            assert.is_truthy(ready)
            assert.are.equal(1, #ready)
            assert.are.equal(sock, ready[1].sock)
            assert.is_true(ready[1].write)
            sock:close()
        end)

        it("detects readable TCP server socket", function()
            local server = socket.bind("127.0.0.1", 0)
            server:settimeout(0)
            local _, port = server:getsockname()

            local client = socket.tcp()
            client:settimeout(0)
            client:connect("127.0.0.1", port)

            local ready = poll.poll({
                { sock = server, read = true, write = false },
            }, 0.5)

            assert.is_truthy(ready)
            assert.are.equal(1, #ready)
            assert.are.equal(server, ready[1].sock)
            assert.is_true(ready[1].read)

            server:close()
            client:close()
        end)
    end)

    describe("poll.select", function()
        it("returns empty tables on timeout", function()
            local sock = socket.udp()
            sock:setsockname("127.0.0.1", 0)

            local readable, writable = poll.select({ sock }, {}, 0.01)

            assert.are.same({}, readable)
            assert.are.same({}, writable)
            sock:close()
        end)

        it("returns writable sockets", function()
            local sock1 = socket.udp()
            sock1:setsockname("127.0.0.1", 0)
            local sock2 = socket.udp()
            sock2:setsockname("127.0.0.1", 0)

            local readable, writable = poll.select({}, { sock1, sock2 }, 0.1)

            assert.are.same({}, readable)
            assert.are.equal(2, #writable)
            sock1:close()
            sock2:close()
        end)

        it("handles socket in both readers and writers", function()
            local sock = socket.udp()
            sock:setsockname("127.0.0.1", 0)

            local readable, writable = poll.select({ sock }, { sock }, 0.1)

            assert.are.same({}, readable)
            assert.are.equal(1, #writable)
            assert.are.equal(sock, writable[1])
            sock:close()
        end)

        it("handles empty inputs", function()
            local readable, writable = poll.select({}, {}, 0.01)
            assert.are.same({}, readable)
            assert.are.same({}, writable)
        end)

        it("handles nil inputs", function()
            local readable, writable = poll.select(nil, nil, 0.01)
            assert.are.same({}, readable)
            assert.are.same({}, writable)
        end)
    end)
end)
