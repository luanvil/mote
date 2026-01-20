/**
 * \file            hashings.c
 * \brief           Lua bindings for SHA256 and HMAC-SHA256
 */

/*
 * Uses public domain implementations from https://github.com/h5p9sl/hmac_sha256
 */

#include <lua.h>
#include <lauxlib.h>

#include "sha256.h"
#include "hmac_sha256.h"

/**
 * \brief           Calculate SHA256 hash of input string
 * \param[in]       L: Lua state
 * \return          1 (hash string on stack)
 */
static int
l_sha256(lua_State* L)
{
    size_t len;
    const char* data = luaL_checklstring(L, 1, &len);
    SHA256_HASH hash;

    Sha256Calculate(data, (uint32_t)len, &hash);

    lua_pushlstring(L, (const char*)hash.bytes, SHA256_HASH_SIZE);
    return 1;
}

/**
 * \brief           Calculate HMAC-SHA256 of input string with key
 * \param[in]       L: Lua state
 * \return          1 (hash string on stack)
 */
static int
l_hmac_sha256(lua_State* L)
{
    size_t key_len, data_len;
    const char* key = luaL_checklstring(L, 1, &key_len);
    const char* data = luaL_checklstring(L, 2, &data_len);
    uint8_t out[SHA256_HASH_SIZE];

    hmac_sha256(key, key_len, data, data_len, out, sizeof(out));

    lua_pushlstring(L, (const char*)out, SHA256_HASH_SIZE);
    return 1;
}

static const luaL_Reg hashings_funcs[] = {
    {"sha256", l_sha256},
    {"hmac_sha256", l_hmac_sha256},
    {NULL, NULL},
};

int
luaopen_mote_crypto_c(lua_State* L)
{
#if LUA_VERSION_NUM >= 502
    luaL_newlib(L, hashings_funcs);
#else
    luaL_register(L, "mote.crypto_c", hashings_funcs);
#endif /* LUA_VERSION_NUM >= 502 */
    return 1;
}
