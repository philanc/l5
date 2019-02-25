# L5

L5, a **Low-Level Linux Library for Lua** is a minimal binding to low-level OS function for Linux, mostly basic Linux system calls, eg. open(2), ioctl(2), poll(2), etc. This is intended to be just one level above the Linux syscall interface.

The library targets **Lua 5.3+** with the default 64-bit integers. 

### Caveat

- This is work in progress. No guarantee that it works or do anything remotely useful.

- This is *really low-level*. It is *not* intended to be used as-is in applications. It is intended to be a minimal C core to implement Lua libraries offering a more reasonable API (eg. at the same level as Lua File System, or LuaSocket core for example).

- No doc at the moment.


### What's the point?

- this is fun,

- this is a great learning experience,

- this is a step to build a minimal, Lua-based userspace for Linux in IoT space. Ummm..., paraphrasing MLK, this is taking the first step even when I don't see the whole staircase :-)

### Available functions

```
getpid() =>  process id
getppid() => parent process id
geteuid() => effective process uid
getegid() => effective process gid
getcwd() =>  current dir pathname

chdir(pathname)
setenv(varname, value)
unsetenv(varname)

opendir(pathname) => dfd
readdir(dfd) => pathname, filetype
closedir(dfd)
readlink(pathname) => target pathname
lstat5(pathname) => mode, size, mtime, uid, gid
lstatraw(pathname) => raw struct stat as a string

open() => fd
read(fd, buf, count) => n
read4k(fd) => string
write(fd, str) => n
close(fd)

ioctl(fd, cmd, arg_in) => arg_out

poll(pollset, nfds, timeout) => n
pollin(fd, timeout) => n -- monitor only one input fd

socket()
bind()
listen()
accept()
connect()
getsockname(fd) => sockaddr
getpeername(fd) => sockaddr

-- In case of error, most functions return nil, errno.

```



### License

MIT.



