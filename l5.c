// Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
// ---------------------------------------------------------------------
/*   

L5  - Low-Level Linux Lua Lib

This is for Lua 5.3+ only, built with default 64-bit integers

*/

#define L5_VERSION "L5-0.1"

#include <stdlib.h>	// setenv
#include <stdio.h>
#include <string.h>

#include <sys/types.h>	// getpid
#include <sys/stat.h>	// stat
#include <unistd.h>	// getpid getcwd getuid.. readlink read environ
			// symlink
#include <errno.h>	// errno
#include <dirent.h>	// opendir...
#include <fcntl.h>	// open
#include <sys/ioctl.h>	// ioctl
#include <poll.h>	// poll
#include <time.h>	// nanosleep
#include <sys/socket.h>	// socket..
#include <netdb.h>	// getaddrinfo
#include <signal.h>	// kill
#include <sys/wait.h>	// waitpid 
#include <sys/mount.h>	// mount umount


#include "lua.h"
#include "lauxlib.h"



#define LERR(msg) return luaL_error(L, msg)

#define RET_ERRNO return (lua_pushnil(L), lua_pushinteger(L, errno), 2)
#define RET_ERRINT(n) return (lua_pushnil(L), lua_pushinteger(L, n), 2)
#define RET_ERRMSG(msg) return (lua_pushnil(L), lua_pushstring(L, msg), 2)
#define RET_TRUE return (lua_pushboolean(L, 1), 1)
#define RET_INT(i) return (lua_pushinteger(L, (i)), 1)
#define RET_STRN(s, slen) return (lua_pushlstring (L, (s), (slen)), 1)
#define RET_STRZ(s) return (lua_pushstring (L, (s)), 1)

//~ typedef unsigned char u8;
//~ typedef unsigned long u32;
//~ typedef unsigned long long u64;


// API constants

// default backlog for listen()
#define BACKLOG 32

// buffer size for send1, recv1
#define BUFSIZE1 1280

// flag for send1, recv1. indicate that the param sockaddr is not used
#define IGNORE_SA 0x01000000

// default timeout: 10 seconds  (poll, ...)
#define DEFAULT_TIMEOUT 10000

//----------------------------------------------------------------------
// memory buffer object
// userdata, allocated memory.  api: 
// new(bytesize) => mb  --(bytesize must be multiple of 8)
// get(mb, byteindex, len) => string
// set(mb, byteindex, string)
// geti(mb, byteindex) => integer -- index must be aligned
// seti(mb, byteindex, integer)   -- index must be aligned
//
// Usage in C  - with a mb object on the stack at index idx:
//	
// 	char *mb = lua_touserdata(L, idx); // get a pointer to buffer
//	size_t size = lua_rawlen(L, idx);  // get buffer size

#define MBNAME "mb_memory_buffer"

static int ll_mbnew(lua_State *L) {
	// lua api: mbnew(size) => mb, ptr as integer
	// return a memory buffer with the given size and a pointer 
	// to the beginning of the block as a Lua integer
	// the memory block is zeroed.
	size_t size = luaL_checkinteger(L, 1);
	if ((size % 8) != 0) LERR("mbnew: size must be multiple of 8");
	char *mb = (char *) lua_newuserdata(L, size);
	memset(mb, 0, size); 
	luaL_getmetatable(L, MBNAME);
	lua_setmetatable(L, -2);
	lua_pushinteger(L, (int64_t)mb);
	return 2;
}

static int ll_mbget(lua_State *L) {
	// lua api:  mb:get(idx, len)
	// return the len bytes at offset idx as a string
	// byte offset start at 0
	// if len is too large given mb size and idx, the function errors.
	// if len is not provided it deafults to the mb size
	// if idx is not provided, it defaults to 0
	// so mg:get() returns all the content of the mb as a string
	char *mb = lua_touserdata(L, 1);
	int64_t size = lua_rawlen(L, 1);
	int64_t idx = luaL_optinteger(L, 2, 0);
	int64_t len = luaL_optinteger(L, 3, size);
	if ((idx+len) > size) LERR("out of range");
	RET_STRN(mb + idx, len);
}

static int ll_mbset(lua_State *L) {
	// lua api:  mb:set(idx, str)
	// copy string str in mb at byte offset idx (starting at 0) 
	// if  string is too long to fit, the function errors.
	char *mb = lua_touserdata(L, 1);
	int64_t size = lua_rawlen(L, 1);
	int64_t idx = luaL_checkinteger(L, 2);
	int64_t len;
	const char *str = luaL_checklstring(L, 3, &len);
	if ((idx+len) > size) LERR("out of range");	
	memcpy(mb + idx, str, len);
	RET_TRUE;
}

static int ll_mbzero(lua_State *L) {
	// lua api:  mb:zero()
	// fill the memory block with zeros
	char *mb = lua_touserdata(L, 1);
	int64_t size = lua_rawlen(L, 1);
	memset(mb, 0, size);
	RET_TRUE;
}
	
static int ll_mbseti(lua_State *L) {
	// lua api: mb:seti(idx, i)
	// writes integer i at byte offset idx (starting at 0)
	char *mb = lua_touserdata(L, 1);
	int64_t size = lua_rawlen(L, 1);
	int64_t idx = luaL_checkinteger(L, 2);
	int64_t i = luaL_checkinteger(L, 3);
	if ((idx < 0) || (idx >= size)) LERR("out of range");
	if ((idx & 7) != 0) LERR("unaligned access");
	*((int64_t *)(mb + idx)) = i;
	RET_TRUE;
}

static int ll_mbgeti(lua_State *L) {
	// lua api: mb:geti(idx)
	// mb is seen as an array of int64, starting at offset 0
	// mb:geti(idx) returns the element at offset idx
	char *mb = lua_touserdata(L, 1);
	int64_t size = lua_rawlen(L, 1);
	int64_t idx = luaL_checkinteger(L, 2);
	if ((idx < 0) || (idx >= size)) LERR("out of range");
	if ((idx & 7) != 0) LERR("unaligned access");
	RET_INT(*((int64_t *)(mb + idx)));
}

//------------------------------------------------------------
// l5 functions

static int ll_getpid(lua_State *L) { RET_INT(getpid()); }

static int ll_getppid(lua_State *L) { RET_INT(getppid()); }

static int ll_geteuid(lua_State *L) { RET_INT(geteuid()); }

static int ll_getegid(lua_State *L) { RET_INT(getegid()); }

static int ll_errno(lua_State *L) {
	// lua api: errno() => errno value; 
	//          errno(n): set errno to n (main use: errno(0))
	int r = luaL_optinteger(L, 1, -1);
	if (r != -1) errno = r; 
	RET_INT(errno);
}

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

static int ll_environ(lua_State *L) {
	// lua api: environ() => list of strings "key=value"
	extern char **environ;
	int i = 0;
	char *eline = environ[i];
	lua_newtable(L);
	while (eline != NULL) {
		lua_pushstring(L, eline);
		lua_rawseti(L, -2, ++i); // index is 1-based in lua!
		eline = environ[i];
	}
	return 1;
}

static int ll_msleep(lua_State *L) {
	// lua api: msleep(fd, ms)
	// suspend the execution for ms milliseconds
	// return true, or nil, errno
	int ms = luaL_checkinteger(L, 1);
	struct timespec req;
	req.tv_sec = ms / 1000;
	req.tv_nsec = (ms % 1000) * 1000000;
	int n = nanosleep(&req, NULL);
	if (n == -1) RET_ERRNO;
	RET_TRUE;
}

static int ll_fork(lua_State *L) {
	// fork the current process (fork(2))
	// lua api: fork() => pid | nil, errno
	// pid in the parent: pid of the child, in the child: 0
	int pid = fork();
	if (pid == -1) RET_ERRNO; 
	RET_INT(pid);
}

static int ll_waitpid(lua_State *L) {
	// wait for state changes in a child process (waitpid(2))
	// lua api: waitpid(pid, opt) => pid, status | nil, errno
	// pid, opt and status are integers
	// (for status consts and macros, see sys/wait.h)
	//	exitstatus: (status & 0xff00) >> 8
	//	termsig: status & 0x7f
	//	coredump: status & 0x80
	// pid default value is -1 (wait for any child - same as wait())
	// pid=0: wait for any child in same process group
	// pid=123: wait for child with pid 123
	// opt=1 (WNOHANG) => return immediately if no child has exited.
	int status = 0;
	int pid = luaL_optinteger(L, 1, -1);
	int opt = luaL_optinteger(L, 2, 0);
	pid = waitpid(pid, &status, opt);
	if (pid == -1) RET_ERRNO; 
	lua_pushinteger(L, pid);
	lua_pushinteger(L, status);
	return 2;
}

static int ll_kill(lua_State *L) {
	// lua api:  kill(pid, signal)
	int r = kill(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2));
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_execve(lua_State *L) {
	// lua api: execve(pname, argv, envp) => nothing | nil, errno
	// argv and envp are lists of strings. For envp, each string
	// is of the form 'varname=varvalue'
	const char *pname = luaL_checkstring(L, 1);
	int argvlen = lua_rawlen(L, 2);
	int envplen = lua_rawlen(L, 3);
	const char **argv = lua_newuserdata(L, (argvlen + 1) * 8);
	int i;
	for (i = 0; i < argvlen; i++) {
		lua_pushinteger(L, i+1); //push table key
		lua_rawget(L, 2);	  //replace key with value
		argv[i] = lua_tostring(L, -1); // get the value
		lua_pop(L, 1); // pop the value
	}
	argv[argvlen] = NULL;
	const char **envp = lua_newuserdata(L, (envplen + 1) * 8);
	for (i = 0; i < envplen; i++) {
		lua_pushinteger(L, i+1);
		lua_rawget(L, 3);
		envp[i] = lua_tostring(L, -1);
		lua_pop(L, 1);
	}
	envp[envplen] = NULL;
	execve(pname, (char **)argv, (char **)envp);
	RET_ERRNO; // execve returns only on error
}

//----------------------------------------------------------------------
// basic I/O

static int ll_open(lua_State *L) {
	const char *pname = luaL_checkstring(L, 1);
	int flags = luaL_checkinteger(L, 2);
	mode_t mode = luaL_checkinteger(L, 3);
	int r = open(pname, flags, mode);
	if (r == -1) RET_ERRNO; 
	RET_INT(r);
}

static int ll_close(lua_State *L) {
	int fd = luaL_checkinteger(L, 1);
	int r = close(fd);
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_read(lua_State *L) {
	// lua api: read(fd, buf, count [, offset])
	// attempt to read up to count bytes into buffer buf
	// read bytes are stored in buffer at offset (defaults to 0)
	// the buffer is a memory buffer object (mb) - see mbnew() above.
	// return number of read bytes or nil, errno
	int fd = luaL_checkinteger(L, 1);
	char *mb = lua_touserdata(L, 2);
	int64_t size = lua_rawlen(L, 2);
	int64_t count = luaL_checkinteger(L, 3);
	int64_t offset = luaL_optinteger(L, 4, 0);
	if (offset + count > size) LERR("out of range");
	int n = read(fd, mb + offset, count);
	if (n == -1) RET_ERRNO;
	RET_INT(n);
}

static int ll_read4k(lua_State *L) { 
	// lua api:  read4k(fd) => readbytes
	// attempt to read 4,096 bytes (ie. 4kb)
	// return read bytes as a string or nil, errno
	//
	//--- KEEP IT??  --- can be implemented with a unique mb buffer:
	// mb=mbnew(4096); n=read(fd, mb, 4096); return mb:get(1, n)
	//
	char buf[4096];
	int fd = luaL_checkinteger(L, 1);
	int n = read(fd, buf, 4096);
	if (n == -1) RET_ERRNO;
	RET_STRN(buf, n);
}

static int ll_write(lua_State *L) {
	// lua api: write(fd, str [, idx, count])
	// attempt to write count bytes in string str starting at 
	// index 'idx'. count defaults to (#str-idx+1), idx defaults to 1, 
	// ie. write(fd, str) attempts to write all bytes in str.
	// return number of bytes actually written, or nil, errno
	int fd = luaL_checkinteger(L, 1);
	int64_t len, idx, count;
	const char *str = luaL_checklstring(L, 2, &len);	
	idx = luaL_optinteger(L, 3, 1);
	count = len + idx - 1;
	count = luaL_optinteger(L, 4, count);
	if ((idx < 1) || (idx + count - 1 > len)) LERR("out of range");
	int n = write(fd, str + idx - 1, count);
	if (n == -1) RET_ERRNO;
	RET_INT(n);
}

static int ll_dup2(lua_State *L) {
	// lua api: dup2(oldfd [, newfd]) => newfd | nil, errno
	// if newfd is not provided, return dup(oldfd)
	int oldfd = luaL_checkinteger(L, 1);
	int newfd = luaL_optinteger(L, 2, -1);
	if (newfd == -1) newfd = dup(oldfd);
	else newfd = dup2(oldfd, newfd);
	if (newfd == -1) RET_ERRNO;
	RET_INT(newfd);
}

//----------------------------------------------------------------------
// directories, filesystem 




static int ll_opendir(lua_State *L) {
	// lua api: opendir(pathname) => dirhandle (lightuserdata)
	DIR *dp = opendir(luaL_checkstring(L, 1));
	if (dp == NULL) RET_ERRNO;
	lua_pushlightuserdata(L, dp);
	return 1; 
}

static int ll_readdir(lua_State *L) {
	// lua api: readdir(dh) => filename, filetype | nil, errno
	// at end of dir, return nil, 0
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
	// lua api: closedir(dh)
	DIR *dp = lua_touserdata(L, 1);
	int r = closedir(dp);
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_readlink(lua_State *L) { 
	char buf[4096];
	const char *pname = luaL_checkstring(L, 1);
	int n = readlink(pname, buf, 4096);
	if (n == -1) RET_ERRNO; 
	RET_STRN(buf, n);
}

static int ll_lstat3(lua_State *L) {
	// lua api: lstat3(path [,statflag:int])
	// if statflag=1: do stat(). default: do lstat
	// return mode, size, mtime(sec)
	struct stat buf;
	int r;
	const char *pname = luaL_checkstring(L, 1);
	lua_Integer statflag = luaL_optinteger(L, 2, 0);
	if (statflag != 0) r = stat(pname, &buf);
	else r = lstat(pname, &buf);
	if (r == -1) RET_ERRNO; 
	lua_pushinteger(L, buf.st_mode);
	lua_pushinteger(L, buf.st_size);
	lua_pushinteger(L, buf.st_mtim.tv_sec);
	return 3;
}

static int ll_lstat(lua_State *L) {
	// lua api: lstatraw(path, tbl, [,statflag:int])
	// tbl is a table that is to be filled with stat values
	// indices in tbl: dev=1 ino=2 mode=3 nlink=4 uid=5 gid=6
	// rdev=7 size=8 blksize=9 blocks=10 atime=11 mtime=12 ctime=13
	// if statflag=1: do stat(). default: do lstat
	// return tbl
	struct stat buf;
	int r;
	const char *pname = luaL_checkstring(L, 1);
	// ensure second arg is a table (LUA_TTABLE=5, see lua.h)
	luaL_checktype(L, 2, 5);
	lua_Integer statflag = luaL_optinteger(L, 3, 0);
	if (statflag != 0) r = stat(pname, &buf);
	else r = lstat(pname, &buf);
	if (r == -1) RET_ERRNO; 
	lua_pushvalue(L, 2); // ensure tbl is top of stack - set values:
	lua_pushinteger(L, buf.st_dev); lua_rawseti(L, -2, 1);
	lua_pushinteger(L, buf.st_ino); lua_rawseti(L, -2, 2);
	lua_pushinteger(L, buf.st_mode); lua_rawseti(L, -2, 3);
	lua_pushinteger(L, buf.st_nlink); lua_rawseti(L, -2, 4);
	lua_pushinteger(L, buf.st_uid); lua_rawseti(L, -2, 5);
	lua_pushinteger(L, buf.st_gid); lua_rawseti(L, -2, 6);
	lua_pushinteger(L, buf.st_rdev); lua_rawseti(L, -2, 7);
	lua_pushinteger(L, buf.st_size); lua_rawseti(L, -2, 8);
	lua_pushinteger(L, buf.st_blksize); lua_rawseti(L, -2, 9);
	lua_pushinteger(L, buf.st_blocks); lua_rawseti(L, -2, 10);
	lua_pushinteger(L, buf.st_atim.tv_sec); lua_rawseti(L, -2, 11);
	lua_pushinteger(L, buf.st_mtim.tv_sec); lua_rawseti(L, -2, 12);
	lua_pushinteger(L, buf.st_ctim.tv_sec); lua_rawseti(L, -2, 13);
	return 1;
}

static int ll_symlink(lua_State *L) {
	// lua api:  symlink(target, linkpath) => true | nil, errno
	//
	const char *target = luaL_checkstring(L, 1);
	const char *linkpath = luaL_checkstring(L, 2);
	int n = symlink(target, linkpath);
	if (n == -1) RET_ERRNO; else RET_TRUE;	
}

static int ll_mkdir(lua_State *L) {
	const char *pname = luaL_checkstring(L, 1);
	int mode = luaL_optinteger(L, 2, 0);
	int n = mkdir(pname, mode);
	if (n == -1) RET_ERRNO; else RET_TRUE;	
}

static int ll_rmdir(lua_State *L) { 
	const char *pname = luaL_checkstring(L, 1);
	int n = rmdir(pname);
	if (n == -1) RET_ERRNO; else RET_TRUE;
}


static int ll_mount(lua_State *L) {
	// lua api: mount(src, dest, fstype, flags, data)
	// src, dest, fstype and data are strings, flags is int.
	// return true or nil, errno
	const char *src = luaL_checkstring(L, 1);
	const char *dest = luaL_checkstring(L, 2);
	const char *fstype = luaL_checkstring(L, 3);
	int flags = luaL_checkinteger(L, 4);
	const char *data = luaL_checkstring(L, 5);
	int r = mount(src, dest, fstype, flags, data);
	if (r == -1) RET_ERRNO; else RET_TRUE;
}

static int ll_umount(lua_State *L) {
	// lua api: umount(dest) => true | nil, errno
	// dest is a string
	const char *dest = luaL_checkstring(L, 1);
	int r = umount(dest);
	if (r == -1) RET_ERRNO; else RET_TRUE;
}


// how to ensure it's enough? --- rewrite with a mb?
#define IOCTLBUFLEN 1024

static int ll_ioctl(lua_State *L) {
	// lua api:  ioctl(fd, cmd, arg, argoutlen) => r | argout | nil, errno
	int fd = luaL_checkinteger(L, 1);
	int cmd = luaL_checkinteger(L, 2);
	size_t arglen = 0;
	const char *arg = luaL_checklstring(L, 3, &arglen);
	size_t argoutlen = (size_t) luaL_optinteger(L, 4, 0);
	char buf[IOCTLBUFLEN]; // how to ensure it's enough?
	if (arglen > IOCTLBUFLEN) LERR("ioctl: arg too large");
	if (argoutlen > IOCTLBUFLEN) LERR("ioctl: argoutlen too large");
	if (arglen > 0) memcpy(buf, arg, arglen);
	int r = ioctl(fd, cmd, buf);
	if (r == -1) RET_ERRNO; 
	if (argoutlen > 0) { RET_STRN(buf, argoutlen); }
	RET_TRUE;
}

static int ll_ioctl_int(lua_State *L) {
	// lua api:  ioctl(fd, cmd, intarg) => r | nil, errno
	int fd = luaL_checkinteger(L, 1);
	int cmd = luaL_checkinteger(L, 2);
	long arg = luaL_checkinteger(L, 3);
	int r = ioctl(fd, cmd, arg);
	if (r == -1) RET_ERRNO; else RET_INT(r);
}

static int ll_poll(lua_State *L) {
	// lua api: poll(pollsetmb, nfds, timeout) => n | nil, errno
	// pollsetmb: an array of struct pollfd stored in a memory block (mb)
	// ndfs: number of  pollfd in the pollset
	// timeout:  timeout in millisecs
	//
	void *mb = (void *)lua_touserdata(L, 1);
	int64_t size = lua_rawlen(L, 1);
	int nfds = luaL_checkinteger(L, 2);
	if (nfds * 8 <= size) LERR("out of range");
	int timeout = luaL_optinteger(L, 3, DEFAULT_TIMEOUT); 
	struct pollfd *pfd = (struct pollfd *)mb;
	int n = poll(pfd, nfds, timeout);
	if (n < 0) RET_ERRNO;
	RET_INT(n);
}

static int ll_pollin(lua_State *L) {
	// a simplified poll variant to monitor only one input fd
	// with an easy interface
	// lua api: pollin(fd, timeout)
	// fd: fd to monitor (input only)
	// timeout:  timeout in millisecs
	// return 1 | 0 on timeout | nil, errno on error
	int fd = luaL_checkinteger(L, 1);
	int timeout = luaL_optinteger(L, 2, DEFAULT_TIMEOUT); 
	struct pollfd pfd;
	pfd.fd = fd;
	pfd.events = POLLIN;
	pfd.revents = 0;
	int n = poll(&pfd, (nfds_t) 1, timeout);
	if (n < 0) RET_ERRNO;
	RET_INT(n);
}

//----------------------------------------------------------------------
// socket functions

static int ll_socket(lua_State *L) {
	// lua api: socket(domain, type, protocol) => fd
	int domain = luaL_checkinteger(L, 1);
	int sotype = luaL_checkinteger(L, 2);
	int protocol = luaL_checkinteger(L, 3);
	int fd = socket(domain, sotype, protocol);
	if (fd < 0) RET_ERRNO;
	RET_INT(fd);	
}

static int ll_setsockopt(lua_State *L) {
	// lua api: setsockopt_int(fd, level, optname, intvalue)
	int fd = luaL_checkinteger(L, 1);
	int level = luaL_checkinteger(L, 2);
	int optname = luaL_checkinteger(L, 3);
	int optvalue = luaL_checkinteger(L, 4);
	int r = setsockopt(fd, level, optname, &optvalue, sizeof(optvalue));
	if (r < 0) RET_ERRNO; else RET_TRUE;
}

// will add a ll_setsockopt_str() to set option with 
// a non-integer value, if needed.

static int ll_bind(lua_State *L) {
	// lua api: bind(fd, addr)
	int fd = luaL_checkinteger(L, 1);
	size_t len;
	const char *addr = luaL_checklstring(L, 2, &len);
	int r = bind(fd, (const struct sockaddr *)addr, len);
	if (r < 0) RET_ERRNO; else RET_TRUE;
}

static int ll_listen(lua_State *L) {
	// lua api: listen(fd, backlog)
	int fd = luaL_checkinteger(L, 1);
	int backlog = luaL_optinteger(L, 2, BACKLOG);
	int r = listen(fd, backlog);
	if (r < 0) RET_ERRNO; else RET_TRUE;
}

static int ll_accept(lua_State *L) {
	// lua_api: accept(fd) => cfd
	int fd = luaL_checkinteger(L, 1);
	struct sockaddr addr;
	socklen_t len = sizeof(addr); //enough for ip4&6 addr
	int cfd = accept(fd, &addr, &len);
	if (cfd < 0) RET_ERRNO;
	RET_INT(cfd);
}

static int ll_connect(lua_State *L) {
	// lua_api: connect(fd, addr)
	int fd = luaL_checkinteger(L, 1);
	size_t len;
	const char *addr = luaL_checklstring(L, 2, &len);
	int r = connect(fd, (const struct sockaddr *)addr, len);
	if (r < 0) RET_ERRNO; else RET_TRUE;
}

static int ll_recvfrom(lua_State *L) {
	// lua api: recvfrom(fd, buf, count, flags) => n, sockaddr
	// receive up to count bytes into buffer buf
	// the buffer is a memory buffer object (mb) - see mbnew() above.
	// return number of read bytes or nil, errno
	int fd = luaL_checkinteger(L, 1);
	char *mb = lua_touserdata(L, 2);
	int64_t size = lua_rawlen(L, 2);
	int64_t count = luaL_checkinteger(L, 3);
	if (count > size) LERR("out of range");
	int flags = luaL_checkinteger(L, 4);
	char addrbuf[256];
	socklen_t addrbuflen = 256;
	int n = recvfrom(fd, mb, count, flags, 
		(struct sockaddr *) addrbuf, &addrbuflen);
	if (n == -1) RET_ERRNO;
	lua_pushinteger(L, n);
	lua_pushlstring(L, addrbuf, addrbuflen);
	return 2;
}

static int ll_sendto(lua_State *L) {
	// lua api: sendto(fd, str, sockaddr)
	// attempt to send string str at address sockaddr
	// return number of bytes actually sent, or nil, errno
	int fd = luaL_checkinteger(L, 1);
	int64_t len, count, salen;
	const char *str = luaL_checklstring(L, 2, &len);	
	int flags = luaL_checkinteger(L, 3);
	struct sockaddr *sa = (struct sockaddr *)luaL_checklstring(
		L, 4, &salen);	
	int n = sendto(fd, str, len, flags, sa, salen);
	if (n == -1) RET_ERRNO;
	RET_INT(n);
}

// recv1, send1:  convenience functions for small datagrams (0 to ~1k)
// the max size is BUFSIZE1=1280 (it is intended to be enough for 1024-byte
// payload plus room for enveloppe, encryption, seq number, etc.)

static int ll_recv1(lua_State *L) {
	// lua api: recv1(fd, flags) => str, sockaddr
	// receive up to a fixed number of bytes (BUFSIZE1=1280)
	// flags is an OR of all the MSG_* flags defined in sys/socket.h
	// an additional flag is IGNORE_SA=0x01000000. if it is set,
	// recv() is used and sockaddr is not returned
	// return number of read bytes or nil, errno
	int fd = luaL_checkinteger(L, 1);
	char buf[BUFSIZE1];
	int flags = luaL_checkinteger(L, 2);
	char addrbuf[136];
	socklen_t addrbuflen = 136;
	int n;
	int ignoresa = (flags & IGNORE_SA);
	if (ignoresa) {
		n = recv(fd, buf, BUFSIZE1, flags);
	} else {
		n = recvfrom(fd, buf, BUFSIZE1, flags, 
			(struct sockaddr *) addrbuf, &addrbuflen);
	}
	if (n == -1) RET_ERRNO;
	lua_pushinteger(L, n);
	if (ignoresa) {
		lua_pushlstring(L, addrbuf, addrbuflen);
		return 2;
	} else {
		return 1; 
	}
}

static int ll_send1(lua_State *L) {
	// lua api: sendto(fd, str, flags [, sockaddr])
	// attempt to send string str at address sockaddr
	// flags is an OR of all the MSG_* flags defined in sys/socket.h
	// an additional flag is IGNORE_SA=0x01000000. if it is set,
	// assume the socket is connected. sockaddr is not used.
	// return number of bytes actually sent, or nil, errno
	int fd = luaL_checkinteger(L, 1);
	int64_t len, count, salen;
	const char *str = luaL_checklstring(L, 2, &len);	
	if (len > BUFSIZE1) LERR("out of range");
	int flags = luaL_checkinteger(L, 3);
	int n;
	struct sockaddr *sa;
	if (flags & IGNORE_SA) {
		n = send(fd, str, len, flags);
	} else {
		sa = (struct sockaddr *)luaL_checklstring(L, 4, &salen);
		n = sendto(fd, str, len, flags, sa, salen);
	}
	if (n == -1) RET_ERRNO;
	RET_INT(n);
}


static int ll_getsockname(lua_State *L) {
	// get the address a socket is bound to
	// lua api: getsockname(fd) => sockaddr | nil, errno
	// return raw socket address (struct sockaddr) as a string 
	int fd = luaL_checkinteger(L, 1);
	struct sockaddr addr;
	socklen_t len = sizeof(addr); //enough for ip4&6 addr
	int n = getsockname(fd, &addr, &len);
	if (n == -1) RET_ERRNO;
	RET_STRN((char *)&addr, len);
}
	
static int ll_getpeername(lua_State *L) {
	// get the address of the peer connected to socket fd
	// lua api: getpeername(fd) => sockaddr | nil, errno
	// return raw socket address (struct sockaddr) as a string 
	int fd = luaL_checkinteger(L, 1);
	struct sockaddr addr;
	socklen_t len = sizeof(addr); //enough for ip4&6 addr
	int n = getsockname(fd, &addr, &len);
	if (n == -1) RET_ERRNO;
	RET_STRN((char *)&addr, len);
}


static int ll_getaddrinfo(lua_State *L) {
	// interface to DNS:
	// get a list of addresses corresponding to a hostname and port
	// lua api:  
	// getaddrinfo(hostname, port [, flags]) => { sockaddr, ... }
	// hostname and port are strings, flags is int
	// if error, return nil, errcode (EAI_* values defined in netdb.h)
	const char *host = luaL_checkstring(L, 1);
	const char *service = luaL_checkstring(L, 2);
	int flags = luaL_optinteger(L, 2, 0);
	struct addrinfo hints;
	struct addrinfo *result, *rp;	
	memset(&hints, 0, sizeof(struct addrinfo));
	hints.ai_flags = flags;
	hints.ai_family = AF_UNSPEC;	 /* Allow IPv4 or IPv6 */
	//~ hints.ai_socktype = SOCK_STREAM;
	int n = getaddrinfo(host, service, &hints, &result);
	if (n) RET_ERRINT(n);
	// build the table of the returned addresses
	lua_newtable(L);
	n = 1;
	for (rp = result; rp != NULL; rp = rp->ai_next) {
		lua_pushinteger (L, n);
		lua_pushlstring(L, 
			(const char *)rp->ai_addr, 
			rp->ai_addrlen);
		lua_settable(L, -3);
		n += 1;
	}	
	// free the address list
	freeaddrinfo(result);
	// return the table
	return 1;
}

int ll_getnameinfo(lua_State *L) {
	// converts a raw socket address (sockaddr) into a host and port
	// lua api:  getnameinfo(sockaddr [, numflag]) => hostname, port
	// return hostname and port as strings.
	// if numflag is true, the numeric form of hostname is returned
	// (default to false)
	// if error, return nil, errcode (EAI_* values defined in netdb.h)
	//   
	char host[512];
	char serv[16];
	size_t addrlen;
	const char *addr = luaL_checklstring(L, 1, &addrlen);
	int numflag = lua_toboolean(L, 2);
	int flags = (numflag ? NI_NUMERICHOST : 0) | NI_NUMERICSERV;
	int n = getnameinfo((const struct sockaddr *)addr, addrlen, 
			host, sizeof(host), serv, sizeof(serv), flags);
	if (n) RET_ERRINT(n);
	lua_pushstring(L, host);
	lua_pushstring(L, serv);
	return 2;	
}

		
	
	
	











//----------------------------------------------------------------------
// lua library declaration
//

// l5 function table
static const struct luaL_Reg l5lib[] = {
	//
	{"mbnew", ll_mbnew},
	//
	{"getpid", ll_getpid},
	{"getppid", ll_getppid},
	{"geteuid", ll_geteuid},
	{"getegid", ll_getegid},
	{"errno", ll_errno},
	{"chdir", ll_chdir},
	{"getcwd", ll_getcwd},
	{"setenv", ll_setenv},
	{"unsetenv", ll_unsetenv},
	{"environ", ll_environ},
	//
	{"msleep", ll_msleep},
	{"fork", ll_fork},
	{"waitpid", ll_waitpid},
	{"kill", ll_kill},
	{"execve", ll_execve},
	//
	{"open", ll_open},
	{"close", ll_close},
	{"read", ll_read},
	{"read4k", ll_read4k},
	{"write", ll_write},
	{"dup2", ll_dup2},
	//
	{"opendir", ll_opendir},
	{"readdir", ll_readdir},
	{"closedir", ll_closedir},
	{"readlink", ll_readlink},
	{"lstat3", ll_lstat3},
	{"lstat", ll_lstat},
	{"symlink", ll_symlink},
	{"mkdir", ll_mkdir},
	{"rmdir", ll_rmdir},
	{"mount", ll_mount},
	{"umount", ll_umount},
	//
	{"ioctl", ll_ioctl},
	{"ioctl_int", ll_ioctl_int},
	{"poll", ll_poll},
	{"pollin", ll_pollin},
	//
	{"socket", ll_socket},
	{"setsockopt", ll_setsockopt},
	{"bind", ll_bind},
	{"listen", ll_listen},
	{"accept", ll_accept},
	{"connect", ll_connect},
	{"recvfrom", ll_recvfrom},
	{"sendto", ll_sendto},
	{"recv1", ll_recv1},
	{"send1", ll_send1},
	{"getsockname", ll_getsockname},
	{"getpeername", ll_getpeername},
	{"getaddrinfo", ll_getaddrinfo},
	{"getnameinfo", ll_getnameinfo},
	//
	{NULL, NULL},
};

// l5 memory block (mb) methods
static const struct luaL_Reg l5mbfuncs[] = {
	{"get", ll_mbget},
	{"set", ll_mbset},
	{"geti", ll_mbgeti},
	{"seti", ll_mbseti},
	{"zero", ll_mbzero},
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
	//~ luaL_register (L, "l5", l5lib);
	luaL_newlib (L, l5lib);
	lua_pushliteral (L, "VERSION");
	lua_pushliteral (L, L5_VERSION); 
	lua_settable (L, -3);
	return 1;
}

