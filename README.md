# mote

Lua HTTP server with routing and middleware.

## Features

- Express-style routing with parameter extraction
- Coroutine-based async I/O (no external event loop)
- Keep-alive connections
- Middleware (CORS, body parsing, rate limiting)
- JWT authentication (HS256)
- Server-Sent Events (SSE) for realtime
- RFC-compliant parsers (HTTP, URI, MIME, multipart, email)
- Timer wheel for efficient timeout management

## Installation

```bash
luarocks install mote
```

## Quick Start

```lua
local mote = require("mote")

mote.get("/", function(ctx)
    mote.json(ctx, 200, { message = "Hello, World!" })
end)

mote.get("/users/:id", function(ctx)
    mote.json(ctx, 200, { id = ctx.params.id })
end)

mote.post("/echo", function(ctx)
    mote.json(ctx, 200, ctx.body)
end)

local app = mote.create({ port = 8080 })
print("Listening on http://localhost:8080")
app:run()
```

## API

### Routing

```lua
mote.get(path, handler)
mote.post(path, handler)
mote.put(path, handler)
mote.patch(path, handler)
mote.delete(path, handler)
mote.all(path, handler)      -- matches any method
```

Routes support parameters:

```lua
mote.get("/users/:id/posts/:post_id", function(ctx)
    print(ctx.params.id, ctx.params.post_id)
end)
```

### Response Helpers

```lua
mote.json(ctx, status, data)           -- JSON response
mote.error(ctx, status, message)       -- JSON error
mote.html(ctx, status, content)        -- HTML response
mote.text(ctx, status, content)        -- Plain text response
mote.file(ctx, status, data, filename, mime_type)      -- Inline file
mote.download(ctx, status, data, filename, mime_type)  -- Download file
mote.redirect(ctx, url, status)        -- Redirect (default 302)
```

### Context Object

The `ctx` object passed to handlers contains:

```lua
ctx.method       -- HTTP method
ctx.path         -- URL path
ctx.full_path    -- Path with query string
ctx.query_string -- Query string (raw)
ctx.headers      -- Request headers (lowercase keys)
ctx.body         -- Parsed body (JSON or multipart)
ctx.params       -- Route parameters
ctx.cookies      -- Parsed cookies (lazy)
ctx.user         -- JWT payload (if authenticated)
ctx.config       -- Server config
ctx.is_multipart -- true if multipart request
```

### Middleware

Before filters run before every request:

```lua
mote.before(function(ctx)
    if not ctx.user then
        mote.error(ctx, 401, "unauthorized")
        return true  -- abort
    end
end)
```

### Rate Limiting

```lua
mote.ratelimit_configure({
    ["/api/login"] = { max = 10, window = 60 },
    ["*"] = { max = 100, window = 60 },
})
```

### CORS

```lua
mote.configure_cors({
    origin = "https://example.com",
    methods = "GET, POST",
    headers = "Content-Type, Authorization",
})
```

### Server-Sent Events

```lua
local broker = mote.pubsub.broker

mote.get("/events", function(ctx)
    local client = broker.create_client()
    client:subscribe("messages")
    mote.sse(ctx, client)
end)

-- Broadcast to subscribers
broker.broadcast("messages", "new", { text = "Hello!" })
```

### Server Lifecycle

```lua
local app = mote.create({
    host = "0.0.0.0",
    port = 8080,
    secret = "your-jwt-secret",
    timeout = 30,
    keep_alive_timeout = 5,
    keep_alive_max = 1000,
    max_concurrent = 10000,
    ratelimit = true,  -- set false to disable
})

-- Optional tick callback (runs every event loop iteration)
app:on_tick(function()
    -- custom logic
end)

app:run()       -- blocking
app:stop()      -- graceful shutdown
```

### Submodules

For advanced usage:

```lua
local parser = require("mote.parser")
local jwt = require("mote.jwt")
local crypto = require("mote.crypto")
local log = require("mote.log")
local url = require("mote.url")
```

## Dependencies

- Lua >= 5.1
- LPeg >= 1.0
- LuaSocket >= 3.0
- lua-cjson >= 2.1
- C extension for SHA256/HMAC (mote.hashings_c or mote.crypto_c)

## License

MIT
