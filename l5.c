// Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
// ---------------------------------------------------------------------
/*   l5  - Low-Level Linux Lua Lib

*/

#define L5_VERSION "l5-0.0"

#include <stdlib.h>	// setenv
#include <stdio.h>
#include <string.h>

#include <sys/types.h>	// getpid
#include <sys/stat.h>	// stat
#include <unistd.h>	// getpid, getcwd
#include <errno.h>	// errno
#include <dirent.h>	// opendir...
#include <fcntl.h>	// open
#include <sys/ioctl.h>	// ioctl

#include "lua.h"
#include "lauxlib.h"


//=========================================================
// compatibility with Lua 5.2  --and lua 5.3, added 150621
// (from roberto's lpeg 0.10.1 dated 101203)
//
#if (LUA_VERSION_NUM >= 502)

#undef lua_equal
#define lua_equal(L,idx1,idx2)  lua_compare(L,(idx1),(idx2),LUA_OPEQ)

#undef lua_getfenv
#define lua_getfenv	lua_getuservalue
#undef lua_setfenv
#define lua_setfenv	lua_setuservalue

#undef lua_objlen
#define lua_objlen	lua_rawlen

#undef luaL_register
#define luaL_register(L,n,f) \
	{ if ((n) == NULL) luaL_setfuncs(L,f,0); else luaL_newlib(L,f); }

#endif
//=========================================================

#define LERR(msg) return luaL_error(L, msg)

#define RET_ERRNO return (lua_pushnil(L), lua_pushinteger(L, errno), 2)
#define RET_TRUE return (lua_pushboolean(L, 1), 1)
#define RET_INT(i) return (lua_pushinteger(L, (i)), 1)
#define RET_STRN(s, slen) return (lua_pushlstring (L, (s), (slen)), 1)
#define RET_STRZ(s) return (lua_pushstring (L, (s)), 1)

typedef unsigned char u8;
typedef unsigned long u32;
typedef unsigned long long u64;

//------------------------------------------------------------
// memory block object
// userdata, allocated memory - bytesize is stored in the first 8 bytes
// api: memory block either as a byte array or a int64 array:
// new(bytesize) => mb  --(bytesize must be multiple of 8)
// get(mb, byteindex, len) => string
// set(mb, byteindex, string)
// geti(mb, int64index) => integer
// seti(mb, int64index, integer)
//
// mb is declared in C as (char *)
#define MBPTR(mb) (mb+8)
#define MBSIZE(mb) (*((int64_t *) mb))

#define MBNAME "mb_memory_block"

static int ll_mbnew(lua_State *L) {
	size_t size = luaL_checkinteger(L, 1);
	if ((size % 8) != 0) LERR("mbnew: size must be multiple of 8");
	char *mb = (char *) lua_newuserdata(L, size + 8);
	MBSIZE(mb) = size;
	luaL_getmetatable(L, MBNAME);
	lua_setmetatable(L, -2);
	return 1;
}

static int ll_mbget(lua_State *L) {
}

static int ll_mbset(lua_State *L) {
}

static int ll_mbzero(lua_State *L) {
	char *mb = lua_touserdata(L, 1);
	int64_t size = MBSIZE(mb);
	memset(mb+8, 0, size);
	RET_TRUE;
}
	
static int ll_mbseti(lua_State *L) {
	char *mb = lua_touserdata(L, 1);
	int64_t idx = luaL_checkinteger(L, 2);
	int64_t val = luaL_checkinteger(L, 3);
	int64_t max = MBSIZE(mb) / 8;
	if ((idx < 1) || (idx > max)) LERR("out of range");
	*( ((int64_t *)mb) + idx) = val;
	RET_TRUE;
}

static int ll_mbgeti(lua_State *L) {
	char *mb = lua_touserdata(L, 1);
	int64_t idx = luaL_checkinteger(L, 2);
	int64_t max = MBSIZE(mb) / 8;
	if ((idx < 1) || (idx > max)) LERR("out of range");
	int64_t val = *( ((int64_t *)mb) + idx);
	RET_INT(val);
	
}

//------------------------------------------------------------
// l5 functions

static int ll_getpid(lua_State *L) { RET_INT(getpid()); }

static int ll_getppid(lua_State *L) { RET_INT(getppid()); }

static int ll_getcwd(lua_State *L) { 
	char buf[4096];
	char *p = getcwd(buf, 4096);
	if (p == NULL) RET_ERRNO; else RET_STRZ(p);
}

static int ll_chdir(lua_State *L) {
	int r = chdir(luaL_checkstring(L, 1));
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_setenv(lua_State *L) {
	int r = setenv(luaL_checkstring(L, 1), luaL_checkstring(L, 2), 1);
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_unsetenv(lua_State *L) {
	int r = unsetenv(luaL_checkstring(L, 1));
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_opendir(lua_State *L) {
	DIR *dp = opendir(luaL_checkstring(L, 1));
	if (dp == NULL) RET_ERRNO;
	lua_pushlightuserdata(L, dp);
	return 1; 
}

static int ll_readdir(lua_State *L) {
	DIR *dp = lua_touserdata(L, 1);
	errno = 0;
	struct dirent *p = readdir(dp);
	if (p == NULL) RET_ERRNO;
	char *name = p->d_name;
	unsigned short type = p->d_type;
	lua_pushstring (L, name);
	lua_pushinteger(L, type);
	return 2;
}

static int ll_closedir(lua_State *L) {
	DIR *dp = lua_touserdata(L, 1);
	int r = closedir(dp);
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_lstat5(lua_State *L) {
	// lua api: lstat5(path [,statflag:int])
	// if statflag=1: do stat(). default: do lstat
	// return mode, size, mtime(sec), ctime(sec), gid|uid
	struct stat buf;
	int r;
	const char *pname = luaL_checkstring(L, 1);
	lua_Integer statflag = luaL_optinteger(L, 2, 0);
	if (statflag != 0) r = stat(pname, &buf);
	else r = stat(pname, &buf);
	if (r == -1) RET_ERRNO; 
	lua_pushinteger(L, buf.st_mode);
	lua_pushinteger(L, buf.st_size);
	lua_pushinteger(L, buf.st_mtim.tv_sec);
	lua_pushinteger(L, buf.st_ctim.tv_sec);
	uint64_t m = ((uint64_t)buf.st_gid << 32) | (uint64_t)buf.st_uid;
	lua_pushinteger(L, m);
	return 5;
}

static int ll_lstatraw(lua_State *L) {
	// lua api: lstatraw(path [,statflag:int])
	// if statflag=1: do stat(). default: do lstat
	// return the raw struct stat as a string
	struct stat buf;
	int r;
	const char *pname = luaL_checkstring(L, 1);
	lua_Integer statflag = luaL_optinteger(L, 2, 0);
	if (statflag != 0) r = stat(pname, &buf);
	else r = lstat(pname, &buf);
	if (r == -1) RET_ERRNO; 
	RET_STRN((char *)&buf, sizeof(buf));
}

static int ll_open(lua_State *L) {
	const char *pname = luaL_checkstring(L, 1);
	int flags = luaL_checkinteger(L, 2);
	mode_t mode = luaL_checkinteger(L, 3);
	int r = open(pname, flags, mode);
	if (r == -1) RET_ERRNO; 
	RET_INT(r);
}

#define IOCTLBUFLEN 1024

static int ll_ioctl(lua_State *L) {
	// lua api:  ioctl(fd, cmd, pin, poutlen) => r [, pout] | nil, errno
	int fd = luaL_checkinteger(L, 1);
	int cmd = luaL_checkinteger(L, 2);
	size_t pinlen = 0;
	const char *pin = luaL_checklstring(L, 3, &pinlen);
	size_t poutlen = (size_t) luaL_optinteger(L, 4, 0);
	char buf[IOCTLBUFLEN]; // how to ensure it's enough?
	if (pinlen > IOCTLBUFLEN) LERR("ioctl: pin too large");
	if (poutlen > IOCTLBUFLEN) LERR("ioctl: pout too large");
	if (pinlen > 0) memcpy(buf, pin, pinlen);
	int r = ioctl(fd, cmd, buf);
	if (r == -1) RET_ERRNO; 
	if (poutlen > 0) { RET_STRN(buf, poutlen); }
	RET_TRUE;
}


/*

static int ll_pollset_new(lua_State *L) {
	// lua api: pollset_new(fdn) => u | nil, errno
	int fdn = luaL_checkinteger(L, 1);
	int usize = (fdn +1) * sizeof(struct pollfd);
	struct pollfd *pfd = lua_newuserdata(L, usize);
	if (pfd == NULL) { errno = ENOMEM; RET_ERRNO; }
	// 1st pollfd is used only to store total number of elements
	// for get/set bound checks
	pfd->fd = fdn; 
	return 1;
}

static int ll_pollset_get(lua_State *L) {
	// lua api: pollset_get(pfd, i) => fd, events, revents | nil, errno
	struct pollfd *pfd = lua_touserdata(L, 1);
	int fdn = pfd->fd; // get total number of elements
	
*/


		
	
	
	











//------------------------------------------------------------
// lua library declaration
//
static const struct luaL_Reg l5lib[] = {
	// l5 function table
	{"getpid", ll_getpid},
	{"getppid", ll_getppid},
	{"chdir", ll_chdir},
	{"getcwd", ll_getcwd},
	{"setenv", ll_setenv},
	{"unsetenv", ll_unsetenv},
	//
	{"opendir", ll_opendir},
	{"readdir", ll_readdir},
	{"closedir", ll_closedir},
	{"lstat5", ll_lstat5},
	{"lstatraw", ll_lstatraw},
	//
	{"open", ll_open},
	{"ioctl", ll_ioctl},
	//
	{"mbnew", ll_mbnew},

		
	{NULL, NULL},
};

static const struct luaL_Reg l5mbfuncs[] = {
	// l5 memory block (mb) methods
	{"mbget", ll_mbget},
	{"mbset", ll_mbset},
	{"mbgeti", ll_mbgeti},
	{"mbseti", ll_mbseti},
	{"mbzero", ll_mbzero},
	{NULL, NULL},
};

int luaopen_l5 (lua_State *L) {
	
	// register MB metatable
	luaL_newmetatable(L, MBNAME);
	luaL_setfuncs(L, l5mbfuncs, 0);
	lua_pushliteral(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);	
	lua_pop(L, 1);  // pop the metatable left on the stack

	// register main library functions
	luaL_register (L, "l5", l5lib);
	lua_pushliteral (L, "VERSION");
	lua_pushliteral (L, L5_VERSION); 
	lua_settable (L, -3);
	return 1;
}

