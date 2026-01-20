-- SSE client model for pub/sub

local crypto = require("mote.crypto")
local cjson = require("cjson")

local client = {}
client.__index = client

function client.new()
    local self = setmetatable({}, client)
    self.id = crypto.to_hex(crypto.random_bytes(20))
    self.subscriptions = {}
    self.auth = nil
    self.discarded = false
    self.messages = {}
    self.context = {}
    return self
end

function client:subscribe(topics)
    if type(topics) ~= "table" then topics = { topics } end
    for _, topic in ipairs(topics) do
        if topic and topic ~= "" then self.subscriptions[topic] = true end
    end
end

function client:unsubscribe(topics)
    if not topics or #topics == 0 then
        self.subscriptions = {}
        return
    end
    if type(topics) ~= "table" then topics = { topics } end
    for _, topic in ipairs(topics) do
        self.subscriptions[topic] = nil
    end
end

function client:has_subscription(topic)
    return self.subscriptions[topic] == true
end

function client:get_subscriptions()
    local result = {}
    for topic in pairs(self.subscriptions) do
        result[#result + 1] = topic
    end
    return result
end

function client:matches_topic(collection, record_id)
    local wildcard = collection .. "/*"
    if self.subscriptions[wildcard] then return wildcard end

    if record_id then
        local specific = collection .. "/" .. record_id
        if self.subscriptions[specific] then return specific end
    end

    if self.subscriptions[collection] then return collection end

    return nil
end

function client:queue_message(message)
    if self.discarded then return false end
    self.messages[#self.messages + 1] = message
    return true
end

function client:pop_message()
    if #self.messages == 0 then return nil end
    return table.remove(self.messages, 1)
end

function client:has_messages()
    return #self.messages > 0
end

function client:discard()
    self.discarded = true
    self.subscriptions = {}
    self.messages = {}
end

function client:is_discarded()
    return self.discarded
end

function client:set_auth(user)
    self.auth = user
end

function client:get_auth()
    return self.auth
end

function client:set(key, value)
    self.context[key] = value
end

function client:get(key)
    return self.context[key]
end

function client:unset(key)
    self.context[key] = nil
end

function client.format_sse(event_id, event_name, data)
    local data_str
    if type(data) == "string" then
        data_str = data
    else
        local ok, encoded = pcall(cjson.encode, data)
        data_str = ok and encoded or "{}"
    end
    return string.format("id:%s\nevent:%s\ndata:%s\n\n", event_id, event_name, data_str)
end

return client
