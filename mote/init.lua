local server = require("mote.server")
local router = require("mote.router")
local middleware = require("mote.middleware")

local mote = {}

mote.create = server.create
mote.sse = server.sse
mote.status_text = server.status_text

mote.get = router.get
mote.post = router.post
mote.put = router.put
mote.patch = router.patch
mote.delete = router.delete
mote.all = router.all
mote.add = router.add
mote.match = router.match
mote.use = router.use
mote.clear = router.clear

mote.configure_cors = middleware.configure_cors
mote.ratelimit_configure = middleware.ratelimit_configure
mote.ratelimit_set_global = middleware.ratelimit_set_global
mote.set_user_validator = middleware.set_user_validator
mote.set_issuer_resolver = middleware.set_issuer_resolver

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
