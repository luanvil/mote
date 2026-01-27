-- mote HTTP server

local socket = require("socket")
local poll = require("mote.poll")
local router = require("mote.router")
local middleware = require("mote.middleware")
local log = require("mote.log")
local http_parser = require("mote.parser.http")
local ip_parser = require("mote.parser.ip")
local timer_wheel = require("mote.timer_wheel")
local sse_mod = require("mote.pubsub.sse")
local url_mod = require("mote.url")

local concat = table.concat
local insert = table.insert

local server = {}

-- IANA HTTP Status Codes (http://www.iana.org/assignments/http-status-codes)
local status_text = setmetatable({
    -- 1xx Informational
    [100] = "Continue",
    [101] = "Switching Protocols",
    [102] = "Processing",
    [103] = "Early Hints",
    -- 2xx Success
    [200] = "OK",
    [201] = "Created",
    [202] = "Accepted",
    [203] = "Non-Authoritative Information",
    [204] = "No Content",
    [205] = "Reset Content",
    [206] = "Partial Content",
    [207] = "Multi-Status",
    [208] = "Already Reported",
    [226] = "IM Used",
    -- 3xx Redirection
    [300] = "Multiple Choices",
    [301] = "Moved Permanently",
    [302] = "Found",
    [303] = "See Other",
    [304] = "Not Modified",
    [305] = "Use Proxy",
    [307] = "Temporary Redirect",
    [308] = "Permanent Redirect",
    -- 4xx Client Errors
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [402] = "Payment Required",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [406] = "Not Acceptable",
    [407] = "Proxy Authentication Required",
    [408] = "Request Timeout",
    [409] = "Conflict",
    [410] = "Gone",
    [411] = "Length Required",
    [412] = "Precondition Failed",
    [413] = "Content Too Large",
    [414] = "URI Too Long",
    [415] = "Unsupported Media Type",
    [416] = "Range Not Satisfiable",
    [417] = "Expectation Failed",
    [418] = "I'm a teapot",
    [421] = "Misdirected Request",
    [422] = "Unprocessable Content",
    [423] = "Locked",
    [424] = "Failed Dependency",
    [425] = "Too Early",
    [426] = "Upgrade Required",
    [428] = "Precondition Required",
    [429] = "Too Many Requests",
    [431] = "Request Header Fields Too Large",
    [451] = "Unavailable For Legal Reasons",
    -- 5xx Server Errors
    [500] = "Internal Server Error",
    [501] = "Not Implemented",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
    [504] = "Gateway Timeout",
    [505] = "HTTP Version Not Supported",
    [506] = "Variant Also Negotiates",
    [507] = "Insufficient Storage",
    [508] = "Loop Detected",
    [510] = "Not Extended",
    [511] = "Network Authentication Required",
}, {
    __index = function()
        return "Unknown"
    end,
})

local DEFAULT_KEEP_ALIVE_TIMEOUT = 5
local DEFAULT_KEEP_ALIVE_MAX = 1000
local DEFAULT_MAX_CONCURRENT = 10000
local MAX_LINE_LENGTH = 8192

-- socket --

local function create_client_wrapper(client)
    client:settimeout(0)
    client:setoption("tcp-nodelay", true)
    client:setoption("keepalive", true)
    local ip, _ = client:getpeername()
    return {
        socket = client,
        read_buffer = "",
        write_buffer = "",
        last_activity = socket.gettime(),
        request_count = 0,
        keep_alive = true,
        ip = ip or "unknown",
    }
end

local function receive_line(wrapper, max_length)
    max_length = max_length or MAX_LINE_LENGTH
    while true do
        if #wrapper.read_buffer > max_length then return nil, "line too long" end
        local nl = wrapper.read_buffer:find("\r?\n")
        if nl then
            local line = wrapper.read_buffer:sub(1, nl - 1):gsub("\r$", "")
            wrapper.read_buffer = wrapper.read_buffer:sub(nl + 1):gsub("^\n", "")
            return line
        end

        local chunk, err, partial = wrapper.socket:receive(4096)
        if chunk then
            wrapper.read_buffer = wrapper.read_buffer .. chunk
            wrapper.last_activity = socket.gettime()
        elseif partial and #partial > 0 then
            wrapper.read_buffer = wrapper.read_buffer .. partial
            wrapper.last_activity = socket.gettime()
        elseif err == "timeout" or err == "wantread" then
            coroutine.yield("read")
        elseif err == "closed" then
            return nil, "closed"
        else
            return nil, err or "unknown error"
        end
    end
end

local function receive_bytes(wrapper, count)
    while #wrapper.read_buffer < count do
        local chunk, err, partial = wrapper.socket:receive(4096)
        if chunk then
            wrapper.read_buffer = wrapper.read_buffer .. chunk
            wrapper.last_activity = socket.gettime()
        elseif partial and #partial > 0 then
            wrapper.read_buffer = wrapper.read_buffer .. partial
            wrapper.last_activity = socket.gettime()
        elseif err == "timeout" or err == "wantread" then
            coroutine.yield("read")
        elseif err == "closed" then
            return nil, "closed"
        else
            return nil, err or "unknown error"
        end
    end

    local data = wrapper.read_buffer:sub(1, count)
    wrapper.read_buffer = wrapper.read_buffer:sub(count + 1)
    return data
end

local function send_all(wrapper, data)
    wrapper.write_buffer = wrapper.write_buffer .. data
    while #wrapper.write_buffer > 0 do
        local sent, err, last_sent = wrapper.socket:send(wrapper.write_buffer)
        if sent then
            wrapper.write_buffer = wrapper.write_buffer:sub(sent + 1)
            wrapper.last_activity = socket.gettime()
        elseif last_sent and last_sent > 0 then
            wrapper.write_buffer = wrapper.write_buffer:sub(last_sent + 1)
            wrapper.last_activity = socket.gettime()
        elseif err == "timeout" or err == "wantwrite" then
            coroutine.yield("write")
        elseif err == "closed" then
            return nil, "closed"
        else
            return nil, err or "unknown error"
        end
    end
    return true
end

-- http --

local function parse_request_line(line)
    return http_parser.parse_request_line(line)
end

local function parse_headers(wrapper)
    local header_lines = {}
    while true do
        local line, err = receive_line(wrapper)
        if err then return nil, err end
        if not line or line == "" then break end
        header_lines[#header_lines + 1] = line
    end
    return http_parser.parse_headers(table.concat(header_lines, "\n"))
end

local function read_chunk(wrapper)
    local line, err = receive_line(wrapper, MAX_LINE_LENGTH)
    if not line then return nil, err end

    local size_hex = line:match("^(%x+)")
    if not size_hex or #size_hex > 8 then return nil, "invalid chunk size" end

    local size = tonumber(size_hex, 16)
    if size == 0 then return false end

    local data, data_err = receive_bytes(wrapper, size + 2)
    if not data then return nil, data_err end

    if data:sub(-2) ~= "\r\n" then return nil, "chunk missing CRLF" end

    return data:sub(1, -3)
end

local function read_chunked_body(wrapper)
    local chunks = {}
    while true do
        local chunk, err = read_chunk(wrapper)
        if chunk == nil then return nil, err end
        if chunk == false then break end
        chunks[#chunks + 1] = chunk
    end
    local _ = parse_headers(wrapper)
    return concat(chunks)
end

local function read_body(wrapper, headers)
    local te = headers["transfer-encoding"]
    if te and te:lower():match("chunked") then return read_chunked_body(wrapper) end
    local content_length = headers["content-length"]
    if not content_length or content_length == 0 then return nil end
    return receive_bytes(wrapper, content_length)
end

local function send_response(wrapper, status, headers, body, keep_alive)
    local response = "HTTP/1.1 " .. status .. " " .. (status_text[status] or "OK") .. "\r\n"

    headers = headers or {}
    if body then headers["Content-Length"] = #body end

    if keep_alive then
        headers["Connection"] = "keep-alive"
        headers["Keep-Alive"] = "timeout=" .. DEFAULT_KEEP_ALIVE_TIMEOUT .. ", max=" .. DEFAULT_KEEP_ALIVE_MAX
    else
        headers["Connection"] = "close"
    end

    local header_lines = {}
    for name, value in pairs(headers) do
        header_lines[#header_lines + 1] = name .. ": " .. value
    end

    response = response .. concat(header_lines, "\r\n") .. "\r\n\r\n"
    if body then response = response .. body end

    return send_all(wrapper, response)
end

local function send_sse_headers(wrapper, status, headers)
    headers["Connection"] = "keep-alive"
    local response = "HTTP/1.1 " .. status .. " " .. (status_text[status] or "OK") .. "\r\n"
    local header_lines = {}
    for name, value in pairs(headers) do
        header_lines[#header_lines + 1] = name .. ": " .. value
    end
    response = response .. concat(header_lines, "\r\n") .. "\r\n\r\n"
    return send_all(wrapper, response)
end

-- cookies --

local function parse_cookies(str)
    if not str or str == "" then return {} end
    local cookies = {}
    for pair in str:gmatch("[^;]+") do
        local key, value = pair:match("^%s*([^=]+)=(.*)%s*$")
        if key then cookies[key:match("^%s*(.-)%s*$")] = value:match("^%s*(.-)%s*$") end
    end
    return cookies
end

-- request --

local ctx_methods = {}

function ctx_methods:throw(status, message)
    self.response.status = status or 500
    self.response.body = { error = message or status_text[status] or "Error" }
    error({ _mote_throw = true })
end

function ctx_methods:assert(value, status, message)
    if not value then self:throw(status or 500, message) end
    return value
end

function ctx_methods:get(field)
    return self.request.headers[field:lower()]
end

function ctx_methods:set(name, value)
    self.response.headers[name] = value
    return self
end

function ctx_methods:append(name, value)
    local existing = self.response.headers[name]
    if existing then
        if type(existing) == "table" then
            insert(existing, value)
        else
            self.response.headers[name] = { existing, value }
        end
    else
        self.response.headers[name] = value
    end
    return self
end

function ctx_methods:remove(name)
    self.response.headers[name] = nil
    return self
end

function ctx_methods:redirect(url, status)
    self.response.status = status or 302
    self.response.headers["Location"] = url
    self.response.body = ""
    return self
end

function ctx_methods:cookie(name, value, options)
    options = options or {}
    local parts = { name .. "=" .. (value or "") }

    if options.maxAge then insert(parts, "Max-Age=" .. options.maxAge) end
    if options.expires then insert(parts, "Expires=" .. options.expires) end
    if options.path then insert(parts, "Path=" .. options.path) end
    if options.domain then insert(parts, "Domain=" .. options.domain) end
    if options.secure then insert(parts, "Secure") end
    if options.httpOnly then insert(parts, "HttpOnly") end
    if options.sameSite then insert(parts, "SameSite=" .. options.sameSite) end

    local cookie_str = concat(parts, "; ")

    local existing = self.response.headers["Set-Cookie"]
    if existing then
        if type(existing) == "table" then
            insert(existing, cookie_str)
        else
            self.response.headers["Set-Cookie"] = { existing, cookie_str }
        end
    else
        self.response.headers["Set-Cookie"] = cookie_str
    end
    return self
end

local function create_context(method, path, headers, request_body, config)
    local ctx = {
        request = {
            method = method,
            path = path,
            headers = headers,
            body = request_body,
        },
        response = {
            headers = {},
            status = nil,
            body = nil,
            type = nil,
        },
        state = {},
        config = config,
        user = nil,
        params = {},
        _cookies = nil,
        _query = nil,
    }
    return setmetatable(ctx, {
        __index = function(self, key)
            if key == "cookies" then
                if not self._cookies then self._cookies = parse_cookies(headers["cookie"]) end
                return self._cookies
            elseif key == "query" then
                if not self._query then self._query = url_mod.parse_query(self.query_string) end
                return self._query
            elseif key == "url" then
                return self.request.path .. (self.query_string and ("?" .. self.query_string) or "")
            elseif key == "ip" then
                return self.wrapper and self.wrapper.ip or "unknown"
            elseif ctx_methods[key] then
                return ctx_methods[key]
            end
        end,
    })
end

local function finalize_response(ctx)
    local body = ctx.response.body
    local status = ctx.response.status
    local resp_headers = middleware.cors_headers()

    for k, v in pairs(ctx.response.headers) do
        resp_headers[k] = v
    end

    if body == nil then
        if not status then status = 204 end
    elseif type(body) == "table" then
        if not resp_headers["Content-Type"] then resp_headers["Content-Type"] = "application/json" end
        body = middleware.encode_json(body)
        if not status then status = 200 end
    else
        if not resp_headers["Content-Type"] then resp_headers["Content-Type"] = "text/plain; charset=utf-8" end
        body = tostring(body)
        if not status then status = 200 end
    end

    if ctx.response.type then resp_headers["Content-Type"] = ctx.response.type end

    return status or 404, resp_headers, body
end

local function should_keep_alive(http_version, headers, wrapper, config)
    if wrapper.request_count >= (config.keep_alive_max or DEFAULT_KEEP_ALIVE_MAX) then return false end

    local connection = headers["connection"]
    if connection then
        connection = connection:lower()
        if connection == "close" then return false end
        if connection == "keep-alive" then return true end
    end

    return tonumber(http_version) >= 1.1
end

local function handle_request(wrapper, config)
    wrapper.request_count = wrapper.request_count + 1
    local start_time = socket.gettime()

    local line, err = receive_line(wrapper)
    if err then return false, false, err end

    -- RFC 7230 Section 3.5: ignore at least one empty line before request-line
    if line == "" then
        line, err = receive_line(wrapper)
        if err then return false, false, err end
    end

    local req = parse_request_line(line)
    if not req then
        local status = (err == "line too long") and 414 or 400
        send_response(wrapper, status, {}, status_text[status], false)
        return false, false, "bad request"
    end

    local headers, headers_err = parse_headers(wrapper)
    if headers_err then return false, false, headers_err end

    local keep_alive = should_keep_alive(req.version, headers, wrapper, config)

    local body_raw, body_err = read_body(wrapper, headers)
    if body_err then return false, false, body_err end

    local path = req.location.path or "/"
    local query = req.location.query

    if middleware.is_preflight(req.method) then
        local cors = middleware.cors_headers()
        cors["Content-Length"] = "0"
        send_response(wrapper, 204, cors, nil, keep_alive)
        log.info("http", req.method .. " " .. path .. " 204")
        return true, keep_alive, nil
    end

    if config.ratelimit ~= false and not middleware.ratelimit_check(wrapper.ip, path) then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        cors["Retry-After"] = "60"
        send_response(wrapper, 429, cors, middleware.encode_json({ error = "too many requests" }), keep_alive)
        log.info("http", req.method .. " " .. path .. " 429")
        return true, keep_alive, nil
    end

    local body, parse_err, is_multipart = middleware.parse_body(body_raw, headers)
    if parse_err then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 400, cors, middleware.encode_json({ error = parse_err }), keep_alive)
        return true, keep_alive, nil
    end

    local ctx = create_context(req.method, path, headers, body, config)
    ctx.query_string = query
    ctx.full_path = path .. (query and ("?" .. query) or "")
    ctx.is_multipart = is_multipart
    ctx.wrapper = wrapper
    ctx.start_time = start_time

    local auth_payload, auth_err = middleware.extract_auth(headers, config.secret)
    if auth_payload then
        ctx.user = auth_payload
    elseif auth_err then
        ctx.auth_error = auth_err
    end

    local handler, params = router.match(req.method, path)
    if not handler and req.method == "HEAD" then
        handler, params = router.match("GET", path)
    end
    if not handler then
        local cors = middleware.cors_headers()
        cors["Content-Type"] = "application/json"
        send_response(wrapper, 404, cors, middleware.encode_json({ error = "not found" }), keep_alive)
        log.info("http", req.method .. " " .. path .. " 404")
        return true, keep_alive, nil
    end

    ctx.params = params or {}

    local composed = router.compose(handler)
    local ok, handler_err = pcall(composed, ctx)
    if not ok then
        local is_throw = type(handler_err) == "table" and handler_err._mote_throw
        if not is_throw then
            io.stderr:write("handler error on " .. req.method .. " " .. path .. ": " .. tostring(handler_err) .. "\n")
            local err_cors = middleware.cors_headers()
            err_cors["Content-Type"] = "application/json"
            send_response(wrapper, 500, err_cors, middleware.encode_json({ error = "internal server error" }), false)
            return true, false, nil
        end
    end

    local resp_status, resp_headers, resp_body = finalize_response(ctx)

    if ctx._sse_mode and ctx._sse_client then
        send_sse_headers(wrapper, resp_status, resp_headers)
        log.info("http", req.method .. " " .. path .. " " .. resp_status .. " (SSE)")
        return true, false, nil, ctx._sse_client
    end

    if req.method == "HEAD" then
        if resp_body then resp_headers["Content-Length"] = #resp_body end
        resp_body = nil
    end

    send_response(wrapper, resp_status, resp_headers, resp_body, keep_alive)
    log.info("http", req.method .. " " .. path .. " " .. resp_status)
    return true, keep_alive, nil
end

local function handle_client(wrapper, config)
    while true do
        local ok, keep_alive, err, sse_client = handle_request(wrapper, config)

        if not ok then return false, err end
        if sse_client then return true, nil, sse_client end
        if not keep_alive then return true, nil end

        wrapper.keep_alive = true
    end
end

-- server --

function server.create(config)
    config = config or {}
    config.host = config.host or "0.0.0.0"
    config.port = config.port or 8080
    config.secret = config.secret or os.getenv("MOTE_SECRET") or "change-me-in-production"
    config.timeout = config.timeout or 30
    config.keep_alive_timeout = config.keep_alive_timeout or DEFAULT_KEEP_ALIVE_TIMEOUT
    config.keep_alive_max = config.keep_alive_max or DEFAULT_KEEP_ALIVE_MAX
    config.max_concurrent = config.max_concurrent or DEFAULT_MAX_CONCURRENT
    if config.reuseaddr == nil then config.reuseaddr = true end
    if config.reuseport == nil then config.reuseport = true end

    local srv, err
    if ip_parser.is_ipv6(config.host) then
        srv, err = socket.tcp6()
    else
        srv, err = socket.tcp4()
    end
    if not srv then return nil, "failed to create socket: " .. (err or "unknown error") end

    if config.reuseaddr then srv:setoption("reuseaddr", true) end
    if config.reuseport then srv:setoption("reuseport", true) end

    local bind_ok, bind_err = srv:bind(config.host, config.port)
    if not bind_ok then
        srv:close()
        return nil, "failed to bind: " .. (bind_err or "unknown error")
    end

    local listen_ok, listen_err = srv:listen(128)
    if not listen_ok then
        srv:close()
        return nil, "failed to listen: " .. (listen_err or "unknown error")
    end

    srv:settimeout(0)

    local clients = setmetatable({}, { __mode = "k" })
    local client_list = {}
    local coro_names = setmetatable({}, { __mode = "k" })
    local timers = timer_wheel.new()

    local function coro_name(c)
        return coro_names[c.coro] or tostring(c.coro)
    end

    local instance = {
        _socket = srv,
        _config = config,
        _running = false,
        _clients = client_list,
        _timers = timers,
        _on_tick = nil,
    }

    local function close_client(c)
        timers:cancel(c.timeout_handle)
        c.wrapper.socket:close()
        if c.sse_client then sse_mod.cleanup(c.sse_client) end
        clients[c.wrapper.socket] = nil
    end

    local function add_client(c)
        local timeout
        if c.sse_client then
            timeout = sse_mod.IDLE_TIMEOUT
        elseif c.wrapper.request_count > 0 then
            timeout = config.keep_alive_timeout
        else
            timeout = config.timeout
        end

        c.timeout_handle = timers:add(timeout, function()
            close_client(c)
        end)

        clients[c.wrapper.socket] = c
        insert(client_list, c)
    end

    local function refresh_timeout(c)
        local timeout
        if c.sse_client then
            timeout = sse_mod.IDLE_TIMEOUT
        elseif c.wrapper.request_count > 0 then
            timeout = config.keep_alive_timeout
        else
            timeout = config.timeout
        end

        c.timeout_handle = timers:reset(c.timeout_handle, timeout)
    end

    local function handle_new_connection(client_sock)
        if #client_list >= config.max_concurrent then
            client_sock:close()
            log.warn("http", "max concurrent connections reached, rejecting client")
            return
        end

        local wrapper = create_client_wrapper(client_sock)
        local coro = coroutine.create(function()
            return handle_client(wrapper, config)
        end)
        coro_names[coro] = "http:" .. wrapper.ip

        local ok, result, _, sse_client = coroutine.resume(coro)
        if not ok then
            io.stderr:write("[" .. coro_names[coro] .. "] error: " .. tostring(result) .. "\n")
            client_sock:close()
            return
        end

        if coroutine.status(coro) ~= "dead" then
            add_client({ wrapper = wrapper, coro = coro, waiting = result })
            return
        end

        if sse_client then
            local sse_coro = sse_mod.create_handler(wrapper, sse_client, send_all)
            coro_names[sse_coro] = "sse:" .. wrapper.ip

            local sse_ok, sse_result = coroutine.resume(sse_coro)
            if not sse_ok then
                io.stderr:write("[" .. coro_names[sse_coro] .. "] error: " .. tostring(sse_result) .. "\n")
                sse_mod.cleanup(sse_client)
                client_sock:close()
                return
            end
            if coroutine.status(sse_coro) ~= "dead" then
                add_client({
                    wrapper = wrapper,
                    coro = sse_coro,
                    waiting = sse_result,
                    sse_client = sse_client,
                })
                return
            end
        end

        client_sock:close()
    end

    local function resume_and_check(c)
        local ok, result = coroutine.resume(c.coro)
        if not ok then
            io.stderr:write("[" .. coro_name(c) .. "] error: " .. tostring(result) .. "\n")
            close_client(c)
            return false
        elseif coroutine.status(c.coro) ~= "dead" then
            c.waiting = result
            refresh_timeout(c)
            return true
        else
            close_client(c)
            return false
        end
    end

    local function process_readable(readable)
        for _, sock in ipairs(readable) do
            if sock == instance._socket then
                local client_sock = instance._socket:accept()
                if client_sock then handle_new_connection(client_sock) end
            else
                local c = clients[sock]
                if c and c.waiting == "read" then resume_and_check(c) end
            end
        end
    end

    local function process_writable(writable)
        for _, sock in ipairs(writable) do
            local c = clients[sock]
            if c and c.waiting == "write" then resume_and_check(c) end
        end
    end

    local function process_sse_clients()
        for i = 1, #client_list do
            local c = client_list[i]
            if c and sse_mod.should_resume(c) then
                if resume_and_check(c) then refresh_timeout(c) end
            end
        end
    end

    local function compact_client_list()
        local new_list = {}
        for i = 1, #client_list do
            local c = client_list[i]
            if c and clients[c.wrapper.socket] then insert(new_list, c) end
        end
        client_list = new_list
        instance._clients = client_list
    end

    function instance:on_tick(callback)
        self._on_tick = callback
    end

    function instance:step(timeout)
        timeout = timeout or 0.1

        local read_sockets = { self._socket }
        local write_sockets = {}

        for i = 1, #client_list do
            local c = client_list[i]
            if c and clients[c.wrapper.socket] then
                if c.waiting == "read" then
                    insert(read_sockets, c.wrapper.socket)
                elseif c.waiting == "write" then
                    insert(write_sockets, c.wrapper.socket)
                end
            end
        end

        local readable, writable = poll.select(read_sockets, write_sockets, timeout)

        if readable == nil and writable == "interrupted" then return false end

        if readable then process_readable(readable) end
        if writable then process_writable(writable) end

        process_sse_clients()

        timers:tick()

        if self._on_tick then pcall(self._on_tick) end

        compact_client_list()

        return true
    end

    function instance:run()
        self._running = true

        while self._running do
            self:step(0.1)
        end
    end

    function instance:stop(drain_timeout)
        self._running = false
        self._socket:close()

        if drain_timeout and drain_timeout > 0 then
            local deadline = socket.gettime() + drain_timeout
            while #client_list > 0 and socket.gettime() < deadline do
                self:step(0.1)
                compact_client_list()
            end
        end

        for i = 1, #client_list do
            local c = client_list[i]
            if c then
                timers:cancel(c.timeout_handle)
                pcall(function()
                    c.wrapper.socket:close()
                end)
                if c.sse_client then sse_mod.cleanup(c.sse_client) end
            end
        end
    end

    function instance.active_connections(_)
        return #client_list
    end

    function instance:get_config()
        return self._config
    end

    return instance
end

function server.sse(ctx, client)
    ctx._sse_mode = true
    ctx._sse_client = client
    ctx.response.status = 200
    ctx.response.headers["Content-Type"] = "text/event-stream"
    ctx.response.headers["Cache-Control"] = "no-store"
    ctx.response.headers["X-Accel-Buffering"] = "no"
end

server._should_keep_alive = should_keep_alive
server._DEFAULT_KEEP_ALIVE_MAX = DEFAULT_KEEP_ALIVE_MAX
server._ctx_methods = ctx_methods
server.status_text = status_text

return server
