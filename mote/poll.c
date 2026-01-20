/**
 * \file            poll.c
 * \brief           POSIX poll() binding - removes select() FD_SETSIZE limit
 *
 * Based on proof-of-concept by Robert Masen (@FreeMasen)
 * https://github.com/lunarmodules/luasocket/issues/446
 */

#include <lua.h>
#include <lauxlib.h>

#include <poll.h>
#include <errno.h>

#define MAX_POLL_FDS 4096

static int
getfd(lua_State *L)
{
    int fd = -1;
    lua_pushstring(L, "getfd");
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) {
        lua_pushvalue(L, -2);
        lua_call(L, 1, 1);
        if (lua_isnumber(L, -1)) {
            double numfd = lua_tonumber(L, -1);
            fd = (numfd >= 0.0) ? (int)numfd : -1;
        }
    }
    lua_pop(L, 1);
    return fd;
}

static int
collect_poll_args(lua_State *L, int tab, int fd_to_sock_tab, struct pollfd *fds)
{
    int i, n = 0;

    if (lua_isnil(L, tab)) {
        return 0;
    }
    luaL_checktype(L, tab, LUA_TTABLE);

    for (i = 1; ; i++) {
        int fd;
        short events;
        int info;

        lua_rawgeti(L, tab, i);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            break;
        }

        info = lua_gettop(L);

        lua_getfield(L, info, "sock");
        fd = getfd(L);

        if (fd != -1) {
            lua_pushinteger(L, fd);
            lua_pushvalue(L, -2);
            lua_rawset(L, fd_to_sock_tab);
        }
        lua_pop(L, 1);

        if (fd != -1 && n < MAX_POLL_FDS) {
            events = POLLERR | POLLHUP;

            lua_getfield(L, info, "read");
            if (lua_toboolean(L, -1)) {
                events |= POLLIN;
            }
            lua_pop(L, 1);

            lua_getfield(L, info, "write");
            if (lua_toboolean(L, -1)) {
                events |= POLLOUT;
            }
            lua_pop(L, 1);

            fds[n].fd = fd;
            fds[n].events = events;
            fds[n].revents = 0;
            n++;
        }

        lua_pop(L, 1);
    }
    return n;
}

/**
 * \brief           Poll sockets for I/O readiness
 * \param[in]       L: Lua state (arg1: socket table, arg2: timeout)
 * \return          1 (ready table) or 2 (nil, error)
 */
static int
l_poll(lua_State *L)
{
    struct pollfd fds[MAX_POLL_FDS];
    int fd_to_sock_tab, result_tab;
    int timeout_ms;
    int fd_count, result;
    int ready_count = 0;
    int i;
    double timeout;

    timeout = luaL_optnumber(L, 2, 0);
    timeout_ms = (int)(timeout * 1000);

    lua_settop(L, 2);

    lua_newtable(L);
    fd_to_sock_tab = lua_gettop(L);

    fd_count = collect_poll_args(L, 1, fd_to_sock_tab, fds);

    result = poll(fds, (nfds_t)fd_count, timeout_ms);

    if (result < 0) {
        const char *error_msg;
        switch (errno) {
        case EFAULT:
            error_msg = "invalid fd provided";
            break;
        case EINTR:
            error_msg = "interrupted";
            break;
        case EINVAL:
            error_msg = "too many sockets";
            break;
        case ENOMEM:
            error_msg = "no memory";
            break;
        default:
            error_msg = "unknown error";
            break;
        }
        lua_pushnil(L);
        lua_pushstring(L, error_msg);
        return 2;
    }

    if (result == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "timeout");
        return 2;
    }

    lua_newtable(L);
    result_tab = lua_gettop(L);

    for (i = 0; i < fd_count; i++) {
        int is_readable = (fds[i].revents & POLLIN) != 0;
        int is_writable = (fds[i].revents & POLLOUT) != 0;

        if (is_readable || is_writable) {
            lua_createtable(L, 0, 3);

            lua_pushinteger(L, fds[i].fd);
            lua_rawget(L, fd_to_sock_tab);
            lua_setfield(L, -2, "sock");

            lua_pushboolean(L, is_readable);
            lua_setfield(L, -2, "read");

            lua_pushboolean(L, is_writable);
            lua_setfield(L, -2, "write");

            lua_rawseti(L, result_tab, ++ready_count);
        }
    }

    return 1;
}

/**
 * \brief           Collect sockets from array into pollfd array
 * \param[in]       L: Lua state
 * \param[in]       tab: Stack index of socket array
 * \param[in]       fd_to_sock_tab: Stack index of fd->socket mapping table
 * \param[in]       fds: pollfd array to fill
 * \param[in]       start: Starting index in fds array
 * \param[in]       events: POLLIN or POLLOUT
 * \return          New count in fds array
 */
static int
collect_select_sockets(lua_State *L, int tab, int fd_to_sock_tab,
                       struct pollfd *fds, int start, short events)
{
    int i, j, n = start;

    if (lua_isnil(L, tab)) {
        return n;
    }

    for (i = 1; ; i++) {
        int fd, found;

        lua_rawgeti(L, tab, i);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            break;
        }

        fd = getfd(L);
        if (fd == -1 || n >= MAX_POLL_FDS) {
            lua_pop(L, 1);
            continue;
        }

        lua_pushinteger(L, fd);
        lua_pushvalue(L, -2);
        lua_rawset(L, fd_to_sock_tab);

        found = 0;
        for (j = 0; j < n; j++) {
            if (fds[j].fd == fd) {
                fds[j].events |= events;
                found = 1;
                break;
            }
        }

        if (!found) {
            fds[n].fd = fd;
            fds[n].events = events | POLLERR | POLLHUP;
            fds[n].revents = 0;
            n++;
        }

        lua_pop(L, 1);
    }

    return n;
}

/**
 * \brief           select-compatible poll wrapper
 * \param[in]       L: Lua state (arg1: readers, arg2: writers, arg3: timeout)
 * \return          2 (readable, writable arrays)
 *
 * Input: select({sock1, sock2}, {sock3}, timeout)
 * Output: {readable_socks}, {writable_socks}
 */
static int
l_select(lua_State *L)
{
    struct pollfd fds[MAX_POLL_FDS];
    int fd_to_sock_tab;
    int timeout_ms;
    int fd_count, result;
    int readable_count = 0, writable_count = 0;
    int readable_tab, writable_tab;
    int i;
    double timeout;

    timeout = luaL_optnumber(L, 3, 0);
    timeout_ms = (int)(timeout * 1000);

    lua_settop(L, 3);

    lua_newtable(L);
    fd_to_sock_tab = lua_gettop(L);

    fd_count = 0;
    fd_count = collect_select_sockets(L, 1, fd_to_sock_tab, fds, fd_count, POLLIN);
    fd_count = collect_select_sockets(L, 2, fd_to_sock_tab, fds, fd_count, POLLOUT);

    lua_newtable(L);
    readable_tab = lua_gettop(L);

    lua_newtable(L);
    writable_tab = lua_gettop(L);

    if (fd_count == 0) {
        return 2;
    }

    result = poll(fds, (nfds_t)fd_count, timeout_ms);

    if (result < 0) {
        if (errno == EINTR) {
            lua_pushnil(L);
            lua_pushstring(L, "interrupted");
            return 2;
        }
        return 2;
    }

    if (result == 0) {
        return 2;
    }

    for (i = 0; i < fd_count; i++) {
        if (fds[i].revents & POLLIN) {
            lua_pushinteger(L, fds[i].fd);
            lua_rawget(L, fd_to_sock_tab);
            lua_rawseti(L, readable_tab, ++readable_count);
        }
        if (fds[i].revents & POLLOUT) {
            lua_pushinteger(L, fds[i].fd);
            lua_rawget(L, fd_to_sock_tab);
            lua_rawseti(L, writable_tab, ++writable_count);
        }
    }

    return 2;
}

static const luaL_Reg poll_funcs[] = {
    {"poll", l_poll},
    {"select", l_select},
    {NULL, NULL},
};

int
luaopen_mote_poll_c(lua_State *L)
{
#if LUA_VERSION_NUM >= 502
    luaL_newlib(L, poll_funcs);
#else
    luaL_register(L, "mote.poll_c", poll_funcs);
#endif
    lua_pushinteger(L, MAX_POLL_FDS);
    lua_setfield(L, -2, "_MAXFDS");
    return 1;
}
