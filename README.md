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

**Express-style Routing**

Parameter extraction, method handlers, before filters.

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
mote.all(path, handler)
```

Routes support parameters:

```lua
mote.get("/users/:id/posts/:post_id", function(ctx)
    print(ctx.params.id, ctx.params.post_id)
end)
```

### Response Helpers

```lua
mote.json(ctx, status, data)
mote.error(ctx, status, message)
mote.html(ctx, status, content)
mote.text(ctx, status, content)
mote.file(ctx, status, data, filename, mime_type)
mote.download(ctx, status, data, filename, mime_type)
mote.redirect(ctx, url, status)
```

<details>
<summary><strong>Context Object</strong></summary>

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

</details>

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
app:stop()
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

## Development

```bash
luarocks make         # Build
busted                # Tests
luacheck .            # Lint
stylua .              # Format
```

## Credits

- [lpeg_patterns](https://github.com/daurnimator/lpeg_patterns) by daurnimator (MIT)
- [hmac_sha256](https://github.com/h5p9sl/hmac_sha256) by h5p9sl (Unlicense)
- [luasocket-poll-api-test](https://github.com/FreeMasen/luasocket-poll-api-test) by FreeMasen (MIT)

## License

[MIT](LICENSE)

> [!NOTE]
> This library was written with assistance from LLMs (Claude). Human review and guidance provided throughout.
