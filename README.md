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

errno() => errno value

chdir(pathname)
setenv(varname, value)
unsetenv(varname)
environ() => list of string "key=value"

msleep(millisecs)
fork() => pid
waitpid(pid, flags) => pid, status
kill(pid, sig)
execve(pname, argv, envp)

open() => fd
read(fd, buf [, offset, count]) => n
read4k(fd) => str  --read 4 kbytes
write(fd, str [, idx, count]) => n
close(fd)
dup2(oldfd [, newfd]) => newfd

opendir(pathname) => dfd
readdir(dfd) => pathname, filetype
closedir(dfd)
readlink(pathname) => target pathname
lstat3(pathname) => mode, size, mtime
lstat(pathname, tbl) => tbl  --a list of stat fields
symlink(target, linkpath)
mkdir(pathname)
rmdir(pathname)

mount(src, dest, fstype, flags, data)
umount(dest)

ioctl(fd, cmd, arg_in, outlen) => out
ioctl_int(fd, cmd, intarg)

poll(pollset, nfds, timeout) => n
pollin(fd, timeout) => n -- monitor only one input fd

socket(domain, type, protocol) => fd
setsockopt(fd, level, optname, optvalue)
bind(fd, addr)
listen(fd, backlog)
accept(fd) => clientfd
connect(fd, addr)
getsockname(fd) => sockaddr
getpeername(fd) => sockaddr
getaddrinfo(host, port) => {sockaddr, ...}
getnameinfo(sockaddr) => host, port

-- In case of error, most functions return nil, errno.

-- memory buffer interface: read/write a string or an integer
mbnew(size) => mb
mb:get(offset, len) => str
mb:set(offset, str)
mb:geti(offset) => int
mb:seti(offset, int)


```



### License

MIT.



