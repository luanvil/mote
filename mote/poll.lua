-- Poll/select abstraction

local poll = {}

local ok, poll_c = pcall(require, "mote.poll_c")
if ok then
    poll._MAXFDS = poll_c._MAXFDS
    poll.poll = poll_c.poll
    poll.select = poll_c.select
else
    local socket = require("socket")
    poll._MAXFDS = 1024
    poll.select = socket.select
end

return poll
