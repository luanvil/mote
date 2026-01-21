<div align="center">

<img src="assets/mote.svg" alt="mote logo" width="128"/>

# mote

Lightweight Lua HTTP server with routing and middleware.

[![CI](https://github.com/luanvil/mote/actions/workflows/ci.yml/badge.svg)](https://github.com/luanvil/mote/actions/workflows/ci.yml)
[![LuaRocks](https://img.shields.io/luarocks/v/luanvil/mote)](https://luarocks.org/modules/luanvil/mote)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

## Features

<table>
<tr>
<td width="50%">

**Routing**

Parameter extraction, method handlers.

</td>
<td width="50%">

**Middleware**

CORS, body parsing, rate limiting, JWT support.

</td>
</tr>
<tr>
<td width="50%">

**Realtime**

Server-Sent Events with pub/sub broker.

</td>
<td width="50%">

**Async I/O**

Coroutine-based with keep-alive. No external event loop.

</td>
</tr>
</table>

## Installation

```bash
luarocks install mote
```

> [!TIP]
> Works with Lua 5.1–5.4. LuaJIT recommended for performance.

## Quick Start

```lua
local mote = require("mote")

mote.get("/", function(ctx)
    ctx.response.body = { message = "Hello, World!" }
end)

mote.get("/users/:id", function(ctx)
    ctx.response.body = { id = ctx.params.id }
end)

mote.post("/echo", function(ctx)
    ctx.response.body = ctx.request.body
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
mote.all(path, handler)
```

Routes support parameters:

```lua
mote.get("/users/:id/posts/:post_id", function(ctx)
    print(ctx.params.id, ctx.params.post_id)
end)
```

### Response

Set response via `ctx.response`:

```lua
ctx.response.body = { id = 1 }   -- auto JSON, auto 200
ctx.response.body = "hello"      -- text/plain
ctx.response.status = 201        -- override status
ctx.response.type = "text/html"  -- override content-type

ctx:set("X-Custom", "val")       -- set response header
ctx:append("Link", "<...>")      -- append to header
ctx:remove("X-Custom")           -- remove response header
ctx:redirect("/login")           -- 302 redirect
ctx:cookie("session", "abc123", { httpOnly = true })
ctx:throw(401, "unauthorized")   -- set status/body and stop
ctx:assert(user, 401, "login required")  -- assert or throw
```

<details>
<summary><strong>Static Files</strong></summary>

```lua
local mime_types = {
    css = "text/css",
    js = "application/javascript",
    png = "image/png",
    svg = "image/svg+xml",
}

mote.get("/static/:file", function(ctx)
    local filename = ctx.params.file
    if filename:match("%.%.") then ctx:throw(400, "invalid path") end

    local f = io.open("./public/" .. filename, "rb")
    if not f then ctx:throw(404, "not found") end

    local data = f:read("*a")
    f:close()

    local ext = filename:match("%.(%w+)$")
    ctx.response.type = mime_types[ext] or "application/octet-stream"
    ctx:set("Content-Disposition", "inline; filename=" .. filename)
    ctx.response.body = data
end)
```

> [!TIP]
> For production, serve static files via Nginx or a CDN for better performance and caching.

</details>

<details>
<summary><strong>Cookies</strong></summary>

Set cookies with `ctx:cookie()`:

```lua
ctx:cookie("session", "abc123", {
    path = "/",
    httpOnly = true,
    secure = true,
    sameSite = "Strict",
    maxAge = 86400,
})
```

Read cookies from `ctx.cookies`:

```lua
local session = ctx.cookies.session
```

</details>

<details>
<summary><strong>Context Object</strong></summary>

The `ctx` object passed to handlers:

```lua
-- Request
ctx.request.method   -- HTTP method
ctx.request.path     -- URL path
ctx.request.headers  -- Request headers (lowercase keys)
ctx.request.body     -- Parsed body (JSON or multipart)
ctx.params           -- Route parameters
ctx.query            -- Parsed query params (lazy)
ctx.cookies          -- Parsed cookies (lazy)
ctx.url              -- Full URL (path + query string)
ctx.ip               -- Client IP address
ctx.user             -- JWT payload (if authenticated)
ctx:get("Header")    -- Get request header (case-insensitive)

-- Response
ctx.response.body    -- Response body (table=JSON, string=text)
ctx.response.status  -- HTTP status (auto 200 with body, 204 without)
ctx.response.type    -- Content-Type override

-- Shared state
ctx.state            -- Pass data between middleware
ctx.config           -- Server config
```

</details>

### Middleware

Onion-style middleware with `next()`:

```lua
mote.use(function(ctx, next)
    local start = os.clock()
    next()  -- call downstream
    local ms = (os.clock() - start) * 1000
    ctx:set("X-Response-Time", string.format("%.3fms", ms))
end)

mote.use(function(ctx, next)
    if not ctx.user then
        ctx:throw(401, "unauthorized")
    end
    next()
end)
```

<details>
<summary><strong>Rate Limiting</strong></summary>

```lua
mote.ratelimit_configure({
    ["/api/login"] = { max = 10, window = 60 },
    ["*"] = { max = 100, window = 60 },
})
```

</details>

<details>
<summary><strong>CORS</strong></summary>

```lua
mote.configure_cors({
    origin = "https://example.com",
    methods = "GET, POST",
    headers = "Content-Type, Authorization",
})
```

</details>

### Server-Sent Events

```lua
local broker = mote.pubsub.broker

mote.get("/events", function(ctx)
    local client = broker.create_client()
    client:subscribe("messages")
    mote.sse(ctx, client)
end)

broker.broadcast("messages", "new", { text = "Hello!" })
```

<details>
<summary><strong>Server Options</strong></summary>

```lua
local app = mote.create({
    host = "0.0.0.0",
    port = 8080,
    secret = "your-jwt-secret",
    timeout = 30,
    keep_alive_timeout = 5,
    keep_alive_max = 1000,
    max_concurrent = 10000,
    ratelimit = true,
})

app:on_tick(function()
    -- runs every event loop iteration
end)

app:run()
app:stop()          -- immediate shutdown
app:stop(5)         -- graceful: drain connections for 5 seconds
```

</details>

<details>
<summary><strong>Submodules</strong></summary>

```lua
local parser = require("mote.parser")
local jwt = require("mote.jwt")
local crypto = require("mote.crypto")
local log = require("mote.log")
local url = require("mote.url")
```

</details>

<details>
<summary><strong>Advanced</strong></summary>

```lua
-- Manual event loop control (for embedding)
while true do
    app:step(0.1)  -- process events, 100ms timeout
end

-- Monitoring
local count = app.active_connections()

-- Direct client messaging
broker.send_to_client(client_id, "notification", { text = "Hello!" })

-- SSE permission checker (called on each broadcast)
broker.set_permission_checker(function(client, topic, record)
    return client:get_auth() ~= nil  -- only authenticated clients
end)

-- Dynamic subscriptions
client:subscribe("posts")
client:unsubscribe("posts")
```

</details>

## Deployment

Mote serves HTTP only. For production, use a reverse proxy for TLS termination:

```
Internet → Caddy/Nginx (HTTPS) → Mote (HTTP)
```

Cloud platforms like Fly.io, Railway, and Render handle TLS at the edge automatically.

## Development

```bash
luarocks make         # Build
busted                # Tests
luacheck .            # Lint
stylua .              # Format
```

## Examples

- [ena-api](https://github.com/ena-lang/ena-api) — Compile API for the Ena programming language

## Credits

- [lpeg_patterns](https://github.com/daurnimator/lpeg_patterns) by daurnimator (MIT)
- [hmac_sha256](https://github.com/h5p9sl/hmac_sha256) by h5p9sl (Unlicense)
- [luasocket-poll-api-test](https://github.com/FreeMasen/luasocket-poll-api-test) by FreeMasen (MIT)

## License

[MIT](LICENSE)

> [!NOTE]
> This library was written with assistance from LLMs. Human review and guidance provided where needed.
