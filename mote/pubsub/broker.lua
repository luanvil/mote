-- Message broker for pub/sub

local client_mod = require("mote.pubsub.client")

local broker = {
    clients = {},
    client_count = 0,
}

-- Optional callback for permission checking
-- Signature: function(client, topic, record) -> boolean
local permission_checker = nil

function broker.set_permission_checker(fn)
    permission_checker = fn
end

function broker.register(cl)
    broker.clients[cl.id] = cl
    broker.client_count = broker.client_count + 1
    return cl
end

function broker.unregister(client_id)
    local cl = broker.clients[client_id]
    if cl then
        cl:discard()
        broker.clients[client_id] = nil
        broker.client_count = broker.client_count - 1
    end
end

function broker.get_client(client_id)
    return broker.clients[client_id]
end

function broker.total_clients()
    return broker.client_count
end

function broker.all_clients()
    local result = {}
    for _, cl in pairs(broker.clients) do
        result[#result + 1] = cl
    end
    return result
end

local function check_permission(cl, topic, record)
    if not permission_checker then return true end
    return permission_checker(cl, topic, record)
end

function broker.broadcast(topic_name, action, record, _metadata)
    if broker.client_count == 0 then return end

    local record_id = record and record.id
    local message_data = {
        action = action,
        record = record,
    }

    for _, cl in pairs(broker.clients) do
        if not cl:is_discarded() then
            local topic = cl:matches_topic(topic_name, record_id)
            if topic then
                local can_view = check_permission(cl, topic, record)
                if can_view then
                    cl:queue_message({
                        name = topic,
                        data = message_data,
                    })
                end
            end
        end
    end
end

function broker.send_to_client(client_id, event_name, data)
    local cl = broker.clients[client_id]
    if cl and not cl:is_discarded() then
        cl:queue_message({
            name = event_name,
            data = data,
        })
        return true
    end
    return false
end

function broker.create_client()
    local cl = client_mod.new()
    broker.register(cl)
    return cl
end

function broker.cleanup()
    for id, cl in pairs(broker.clients) do
        if cl:is_discarded() then
            broker.clients[id] = nil
            broker.client_count = broker.client_count - 1
        end
    end
end

function broker.reset()
    for _, cl in pairs(broker.clients) do
        cl:discard()
    end
    broker.clients = {}
    broker.client_count = 0
end

return broker
