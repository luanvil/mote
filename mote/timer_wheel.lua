-- Timer wheel for O(1) timeout management

local socket = require("socket")

local floor = math.floor
local ceil = math.ceil
local insert = table.insert

local M = {}

local WHEEL_SIZE = 128
local TICK_MS = 500
local MAX_TIMEOUT_SECONDS = (WHEEL_SIZE * TICK_MS) / 1000

function M.new()
    local wheel = {}
    for i = 0, WHEEL_SIZE - 1 do
        wheel[i] = {}
    end

    local instance = {
        _wheel = wheel,
        _current = 0,
        _last_tick = socket.gettime(),
    }

    function instance:add(timeout_seconds, callback)
        if timeout_seconds > MAX_TIMEOUT_SECONDS then timeout_seconds = MAX_TIMEOUT_SECONDS end

        local ticks = ceil((timeout_seconds * 1000) / TICK_MS)
        if ticks < 1 then ticks = 1 end

        local slot = (self._current + ticks) % WHEEL_SIZE
        local rounds = floor(ticks / WHEEL_SIZE)

        local handle = {
            callback = callback,
            rounds = rounds,
            cancelled = false,
        }

        insert(self._wheel[slot], handle)
        return handle
    end

    function instance.cancel(_, handle)
        if handle then handle.cancelled = true end
    end

    function instance:reset(handle, timeout_seconds)
        if handle then handle.cancelled = true end
        return self:add(timeout_seconds, handle and handle.callback)
    end

    function instance:tick()
        local now = socket.gettime()
        local elapsed_ms = (now - self._last_tick) * 1000
        local ticks_to_process = floor(elapsed_ms / TICK_MS)

        if ticks_to_process < 1 then return end

        self._last_tick = now

        for _ = 1, ticks_to_process do
            self._current = (self._current + 1) % WHEEL_SIZE
            local slot = self._wheel[self._current]
            local remaining = {}

            for i = 1, #slot do
                local timer = slot[i]
                if timer.cancelled then
                    goto continue
                elseif timer.rounds > 0 then
                    timer.rounds = timer.rounds - 1
                    insert(remaining, timer)
                else
                    local ok, err = pcall(timer.callback)
                    if not ok then io.stderr:write("timer callback error: " .. tostring(err) .. "\n") end
                end
                ::continue::
            end

            self._wheel[self._current] = remaining
        end
    end

    function instance:pending_count()
        local count = 0
        for i = 0, WHEEL_SIZE - 1 do
            for j = 1, #self._wheel[i] do
                if not self._wheel[i][j].cancelled then count = count + 1 end
            end
        end
        return count
    end

    return instance
end

M.WHEEL_SIZE = WHEEL_SIZE
M.TICK_MS = TICK_MS
M.MAX_TIMEOUT_SECONDS = MAX_TIMEOUT_SECONDS

return M
