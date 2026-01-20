-- mote - Lua HTTP server with routing and middleware
--
-- https://github.com/luanvil/mote

local server = require("mote.server")
local router = require("mote.router")
local middleware = require("mote.middleware")

local mote = {}

-- re-export server functions
mote.create = server.create
mote.json = server.json
mote.error = server.error
mote.html = server.html
mote.text = server.text
mote.file = server.file
mote.download = server.download
mote.sse = server.sse
mote.redirect = server.redirect
mote.status_text = server.status_text

-- re-export router functions
mote.get = router.get
mote.post = router.post
mote.put = router.put
mote.patch = router.patch
mote.delete = router.delete
mote.all = router.all
mote.add = router.add
mote.match = router.match
mote.before = router.before
mote.clear = router.clear

-- middleware configuration
mote.configure_cors = middleware.configure_cors
mote.ratelimit_configure = middleware.ratelimit_configure
mote.ratelimit_set_global = middleware.ratelimit_set_global
mote.set_user_validator = middleware.set_user_validator
mote.set_issuer_resolver = middleware.set_issuer_resolver

-- submodules (for advanced usage)
mote.server = server
mote.router = router
mote.middleware = middleware
mote.log = require("mote.log")
mote.crypto = require("mote.crypto")
mote.jwt = require("mote.jwt")
mote.url = require("mote.url")
mote.parser = require("mote.parser")
mote.pubsub = require("mote.pubsub")
mote.timer_wheel = require("mote.timer_wheel")
mote.poll = require("mote.poll")

return mote
