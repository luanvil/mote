-- URL pattern matching router

local lpeg = require("lpeg")

local router = {}

local routes = {}
local middleware_stack = {}

local P, C, Ct = lpeg.P, lpeg.C, lpeg.Ct

local function compile_pattern(path)
    local params = {}
    for param in path:gmatch(":([%w_]+)") do
        params[#params + 1] = param
    end

    local segments = {}
    local pos = 1
    while pos <= #path do
        local param_start, param_end, param_name = path:find(":([%w_]+)", pos)
        if param_start then
            if param_start > pos then
                segments[#segments + 1] = { type = "literal", value = path:sub(pos, param_start - 1) }
            end
            segments[#segments + 1] = { type = "param", name = param_name }
            pos = param_end + 1
        else
            segments[#segments + 1] = { type = "literal", value = path:sub(pos) }
            break
        end
    end

    local pattern = P(true)
    for _, seg in ipairs(segments) do
        if seg.type == "literal" then
            pattern = pattern * P(seg.value)
        else
            pattern = pattern * C((1 - P("/")) ^ 1)
        end
    end
    pattern = pattern * -1

    return Ct(pattern), params
end

function router.add(method, path, handler)
    local pattern, param_names = compile_pattern(path)
    routes[#routes + 1] = {
        method = method,
        pattern = pattern,
        param_names = param_names,
        handler = handler,
    }
end

function router.get(path, handler)
    router.add("GET", path, handler)
end

function router.post(path, handler)
    router.add("POST", path, handler)
end

function router.put(path, handler)
    router.add("PUT", path, handler)
end

function router.patch(path, handler)
    router.add("PATCH", path, handler)
end

function router.delete(path, handler)
    router.add("DELETE", path, handler)
end

function router.all(path, handler)
    router.add("*", path, handler)
end

function router.match(method, path)
    for _, route in ipairs(routes) do
        if route.method == method or route.method == "*" then
            local captures = route.pattern:match(path)
            if captures then
                local params = {}
                for i, name in ipairs(route.param_names) do
                    params[name] = captures[i]
                end
                return route.handler, params
            end
        end
    end
    return nil
end

function router.clear()
    routes = {}
    middleware_stack = {}
end

function router.use(fn)
    middleware_stack[#middleware_stack + 1] = fn
    return router
end

function router.compose(handler)
    return function(ctx)
        local index = 0
        local function dispatch()
            index = index + 1
            if index <= #middleware_stack then
                local mw = middleware_stack[index]
                mw(ctx, dispatch)
            else
                handler(ctx)
            end
        end
        dispatch()
    end
end

return router
