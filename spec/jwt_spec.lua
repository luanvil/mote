local jwt = require("mote.jwt")

describe("jwt", function()
    local secret = "test-secret-key"

    it("encodes and decodes token", function()
        local payload = { sub = 123, name = "alice" }
        local token = jwt.encode(payload, secret)
        assert.is_string(token)
        assert.is_truthy(token:match("^[%w%-_]+%.[%w%-_]+%.[%w%-_]+$"))

        local decoded = jwt.decode(token, secret)
        assert.are.equal(123, decoded.sub)
        assert.are.equal("alice", decoded.name)
    end)

    it("rejects invalid tokens", function()
        local payload = { sub = 123 }
        local token = jwt.encode(payload, secret)

        local decoded, err = jwt.decode(token, "wrong-secret")
        assert.is_nil(decoded)
        assert.are.equal("invalid signature", err)

        local decoded2, err2 = jwt.decode("not.valid", secret)
        assert.is_nil(decoded2)
        assert.are.equal("invalid token format", err2)
    end)

    it("rejects expired token", function()
        local payload = { sub = 123, exp = os.time() - 100 }
        local token = jwt.encode(payload, secret)

        local decoded, err = jwt.decode(token, secret)
        assert.is_nil(decoded)
        assert.are.equal("token expired", err)
    end)

    it("creates token with standard claims", function()
        local token = jwt.create_token(42, secret, { expires_in = 3600 })
        local decoded = jwt.decode(token, secret)
        assert.are.equal(42, decoded.sub)
        assert.is_truthy(decoded.exp)
        assert.is_truthy(decoded.iat)
        assert.is_truthy(decoded.jti)
        assert.is_true(decoded.exp > os.time())

        local token2 = jwt.create_token(1, secret)
        local decoded2 = jwt.decode(token2, secret)
        assert.are_not.equal(decoded.jti, decoded2.jti)
    end)

    it("handles audience and issuer", function()
        local token = jwt.create_token(1, secret, { audience = "api.example.com", issuer = "mote" })
        local decoded = jwt.decode(token, secret)
        assert.are.equal("api.example.com", decoded.aud)
        assert.are.equal("mote", decoded.iss)

        local decoded2 = jwt.decode(token, secret, { audience = "api.example.com" })
        assert.are.equal(1, decoded2.sub)

        local decoded3, err = jwt.decode(token, secret, { audience = "other.example.com" })
        assert.is_nil(decoded3)
        assert.are.equal("invalid audience", err)
    end)
end)
