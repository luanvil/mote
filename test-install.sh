#!/bin/bash
set -euo pipefail

echo "=== Mote Installation Test ==="
echo ""

# Platform info
echo "Platform: $(uname -s) $(uname -m)"
echo ""

# Cleanup function
cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        kill $SERVER_PID 2>/dev/null || true
    fi
    rm -f /tmp/mote_test_server.lua /tmp/mote_test_output.log
}
trap cleanup EXIT

# Detect Lua and set version for luarocks
if command -v luajit &> /dev/null; then
    LUA=luajit
    LUA_VERSION="5.1"
elif command -v lua5.4 &> /dev/null; then
    LUA=lua5.4
    LUA_VERSION="5.4"
elif command -v lua5.3 &> /dev/null; then
    LUA=lua5.3
    LUA_VERSION="5.3"
elif command -v lua &> /dev/null; then
    LUA=lua
    # Detect version from lua itself
    LUA_VERSION=$($LUA -v 2>&1 | grep -oE '5\.[0-9]' | head -1)
else
    echo "❌ Lua not found. Install Lua or LuaJIT first."
    exit 1
fi

echo "Lua: $($LUA -v 2>&1 | head -1)"
echo "Lua version for luarocks: $LUA_VERSION"
echo ""

# Install mote
echo "📦 Installing mote..."
if luarocks --lua-version "$LUA_VERSION" install mote 2>/dev/null; then
    echo "Installed globally"
elif luarocks --lua-version "$LUA_VERSION" --local install mote; then
    echo "Installed locally"
else
    echo "❌ Failed to install mote"
    exit 1
fi

# Set up paths
eval "$(luarocks --lua-version "$LUA_VERSION" path)"
echo ""

# Verify mote loads
echo "🔍 Verifying mote loads..."
if ! $LUA -e "require('mote')" 2>/tmp/mote_test_error.log; then
    echo "❌ Failed to load mote"
    cat /tmp/mote_test_error.log
    exit 1
fi
echo "✅ mote loads successfully"
echo ""

# Create test server
echo "📝 Creating test server..."
cat > /tmp/mote_test_server.lua << 'EOF'
local mote = require("mote")

-- Test 1: Basic routing with params
mote.get("/", function(ctx)
    ctx.response.body = { status = "ok", message = "Hello from mote!" }
end)

mote.get("/users/:id", function(ctx)
    ctx.response.body = { id = ctx.params.id }
end)

-- Test 2: POST with JSON body
mote.post("/echo", function(ctx)
    ctx.response.body = ctx.request.body
end)

-- Test 3: Query params
mote.get("/search", function(ctx)
    ctx.response.body = { query = ctx.query.q or "none" }
end)

-- Test 4: Custom status and headers
mote.get("/created", function(ctx)
    ctx.response.status = 201
    ctx:set("X-Custom-Header", "test-value")
    ctx.response.body = { created = true }
end)

-- Test 5: Middleware
mote.use(function(ctx, next)
    ctx.state.middleware_ran = true
    next()
end)

mote.get("/middleware", function(ctx)
    ctx.response.body = { middleware = ctx.state.middleware_ran }
end)

-- Test 6: Throw/error handling
mote.get("/protected", function(ctx)
    ctx:throw(401, "unauthorized")
end)

-- Test 7: Redirect
mote.get("/old", function(ctx)
    ctx:redirect("/")
end)

local app = mote.create({ port = 18080 })
io.stdout:write("SERVER_READY\n")
io.stdout:flush()
app:run()
EOF

# Start server in background
echo "🚀 Starting test server on port 18080..."
$LUA /tmp/mote_test_server.lua >/tmp/mote_test_output.log 2>&1 &
SERVER_PID=$!

# Wait for server to be ready (max 5 seconds)
for i in {1..50}; do
    if curl -s http://localhost:18080/ > /dev/null 2>&1; then
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "❌ Server crashed on startup"
        cat /tmp/mote_test_output.log
        exit 1
    fi
    sleep 0.1
done

# Final check
if ! curl -s http://localhost:18080/ > /dev/null 2>&1; then
    echo "❌ Server not responding"
    cat /tmp/mote_test_output.log
    exit 1
fi
echo "✅ Server started"

# Run tests
echo ""
echo "🧪 Running tests..."
echo ""

PASSED=0
FAILED=0

test_endpoint() {
    local name="$1"
    local method="$2"
    local url="$3"
    local expected="$4"
    local data="${5:-}"

    if [ "$method" = "POST" ]; then
        response=$(curl -s -X POST -H "Content-Type: application/json" -d "$data" "$url")
    else
        response=$(curl -s "$url")
    fi

    if echo "$response" | grep -q "$expected"; then
        echo "✅ $name"
        PASSED=$((PASSED + 1))
    else
        echo "❌ $name"
        echo "   Expected: $expected"
        echo "   Got: $response"
        FAILED=$((FAILED + 1))
    fi
}

test_status() {
    local name="$1"
    local url="$2"
    local expected_status="$3"

    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")

    if [ "$status" = "$expected_status" ]; then
        echo "✅ $name"
        PASSED=$((PASSED + 1))
    else
        echo "❌ $name"
        echo "   Expected status: $expected_status"
        echo "   Got: $status"
        FAILED=$((FAILED + 1))
    fi
}

test_header() {
    local name="$1"
    local url="$2"
    local header="$3"
    local expected="$4"

    # Use -i (include headers) with GET instead of -I (HEAD) since mote doesn't handle HEAD
    value=$(curl -s -i "$url" | grep -i "^$header:" | cut -d' ' -f2 | tr -d '\r' || true)

    if [ "$value" = "$expected" ]; then
        echo "✅ $name"
        PASSED=$((PASSED + 1))
    else
        echo "❌ $name"
        echo "   Expected $header: $expected"
        echo "   Got: $value"
        FAILED=$((FAILED + 1))
    fi
}

# Test 1: Basic GET
test_endpoint "GET /" "GET" "http://localhost:18080/" "Hello from mote"

# Test 2: Route params
test_endpoint "GET /users/:id" "GET" "http://localhost:18080/users/42" '"id":"42"'

# Test 3: POST JSON echo
test_endpoint "POST /echo" "POST" "http://localhost:18080/echo" '"foo":"bar"' '{"foo":"bar"}'

# Test 4: Query params
test_endpoint "GET /search?q=lua" "GET" "http://localhost:18080/search?q=lua" '"query":"lua"'

# Test 5: Custom status code
test_status "Custom status 201" "http://localhost:18080/created" "201"

# Test 6: Custom header
test_header "Custom header" "http://localhost:18080/created" "X-Custom-Header" "test-value"

# Test 7: Middleware
test_endpoint "Middleware" "GET" "http://localhost:18080/middleware" '"middleware":true'

# Test 8: Throw 401
test_status "Throw 401" "http://localhost:18080/protected" "401"

# Test 9: Error body
test_endpoint "Error body" "GET" "http://localhost:18080/protected" '"error":"unauthorized"'

# Test 10: Redirect
test_status "Redirect 302" "http://localhost:18080/old" "302"

# Test 11: 404 for unknown route
test_status "404 Not Found" "http://localhost:18080/nonexistent" "404"

# Test 12: CORS headers
test_header "CORS header" "http://localhost:18080/" "Access-Control-Allow-Origin" "*"

# Test 13: HEAD returns 200 with Content-Length but no body
head_status=$(curl -s -o /dev/null -w "%{http_code}" -I http://localhost:18080/)
head_length=$(curl -s -I http://localhost:18080/ | grep -i "^Content-Length:" | cut -d' ' -f2 | tr -d '\r' || true)
if [ "$head_status" = "200" ] && [ -n "$head_length" ] && [ "$head_length" -gt 0 ]; then
    echo "✅ HEAD request (status=$head_status, Content-Length=$head_length)"
    PASSED=$((PASSED + 1))
else
    echo "❌ HEAD request"
    echo "   Status: $head_status (expected 200)"
    echo "   Content-Length: $head_length (expected > 0)"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "💥 Some tests failed"
    exit 1
fi
