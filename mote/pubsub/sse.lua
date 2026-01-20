-- Server-Sent Events handler

local cjson = require("cjson")
local client_mod = require("mote.pubsub.client")
local broker = require("mote.pubsub.broker")
local log = require("mote.log")

local sse = {}

sse.IDLE_TIMEOUT = 300

function sse.create_handler(wrapper, sse_client, send_fn)
    return coroutine.create(function()
        return sse.run_loop(wrapper, sse_client, send_fn)
    end)
end

function sse.run_loop(wrapper, sse_client, send_fn)
    local connect_data = cjson.encode({ clientId = sse_client.id })
    local connect_msg = client_mod.format_sse(sse_client.id, "CONNECT", connect_data)
    local ok, err = send_fn(wrapper, connect_msg)
    if not ok then
        log.error("sse", "failed to send connect message", { client_id = sse_client.id, error = err })
        broker.unregister(sse_client.id)
        return false, err
    end

    while not sse_client:is_discarded() do
        if sse_client:has_messages() then
            local msg = sse_client:pop_message()
            if msg then
                local sse_data = client_mod.format_sse(sse_client.id, msg.name, msg.data)
                local send_ok, send_err = send_fn(wrapper, sse_data)
                if not send_ok then
                    log.error("sse", "failed to send message", { client_id = sse_client.id, error = send_err })
                    broker.unregister(sse_client.id)
                    return false, send_err
                end
            end
        else
            coroutine.yield("sse")
        end
    end

    broker.unregister(sse_client.id)
    return true, nil
end

function sse.should_resume(c)
    return c.waiting == "sse" and c.sse_client and (c.sse_client:has_messages() or c.sse_client:is_discarded())
end

function sse.cleanup(sse_client)
    if sse_client then broker.unregister(sse_client.id) end
end

return sse
