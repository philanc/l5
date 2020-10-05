-- Copyright (c) 2020  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- L5 popen functions (popen2, popen3)


he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"

util = require "l5.util"
tty = require "l5.tty"
fs = require "l5.fs"

local spack, sunpack = string.pack, string.unpack
local strf = string.format
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px



local POLLIN, POLLOUT = 1, 4
local POLLNVAL, POLLUP, POLLERR = 32, 16, 8

local O_CLOEXEC = 0x00080000
local O_NONBLOCK = 0x800  -- for non-blocking pipes

local F_GETFD, F_SETFD = 1, 2  -- (used to set O_CLOEXEC)
local F_GETFL, F_SETFL = 3, 4  -- (used to set O_NONBLOCK)

local EPIPE = 32
local EINVAL = 22


------------------------------------------------------------------------

local function spawn_child(exepath, argl, envl, ef)
	-- if ef is true, a pipe is also provided for child stderr
	-- return child pid, cin, cout [, cerr]  or nil, errmsg
	envl = envl or l5.environ()
	argl = argl or {}
	-- create pipes:  
	-- cin is child stdin, cout is child stdout, cerr is child stderr
	-- pipes are non-blocking
	local cin0, cin1, cout0, cout1, cerr0, cerr1
	local flags, r, eno, pid
	cin0, cin1 = l5.pipe2()
	assert(cin0, cin1)
	
	cout0, cout1 = l5.pipe2()
	assert(cout0, cout1)
	if ef then 
		cerr0, cerr1 = l5.pipe2()
		assert(cerr0, cerr1)
	end

	-- set cin1 non-blocking
	flags = assert(l5.fcntl(cin1, F_GETFL))
	assert(l5.fcntl(cin1, F_SETFL, O_NONBLOCK))
	
--~ 	-- set cout0 non-blocking
--~ 	flags = assert(l5.fcntl(cout0, F_GETFL))
--~ 	assert(l5.fcntl(cout0, F_SETFL, O_NONBLOCK))
	
	pid, eno = l5.fork()
	if not pid then 
		local clo = l5.close
		clo(cin0); clo(cin1); clo(cout0); clo(cout1)
		if ef then clo(cerr0); clo(cerr1) end
		return nil, errm(eno, "fork") 
	end	
	if pid == 0 then -- child
		l5.close(cin1)  -- close unused ends
		l5.close(cout0)
		-- set cin0, cout1 to child stdin, stdout
		assert(l5.dup2(cin0, 0)); l5.close(cin0)
		assert(l5.dup2(cout1, 1)); l5.close(cout1)
		if ef then -- same for stderr
			l5.close(cerr0)
			assert(l5.dup2(cerr1, 2)); l5.close(cerr1)
		end
		r, err = l5.execve(exepath, argl, envl)
		-- get here only if execve failed.
		os.exit(99) -- child exits with an error code
	end
	-- parent
	l5.close(cin0)  -- close unused ends
	l5.close(cout1)
	if ef then l5.close(cerr1) end
	-- parent writes to child stdin (cin1), 
	-- and reads from child stdout (cout0) [and stderr (cerr0)]
	return pid, cin1, cout0, cerr0
end --spawn_child

local function piperead_new(fd)
	local prt = { -- a "piperead" task
		done = false,
		fd = fd,
		rt = {}, -- table to collect read fragments
		poll = (fd << 32) | (POLLIN << 16), -- poll_list entry
	}
	return prt
end

local function piperead(prt, rev)
	-- a read step in a poll loop
	-- prt: the piperead state
	-- rev: a poll revents for the prt file descriptor
	-- return the updated prt or nil, errmsg in case of unrecoverable
	-- error
	local em
	if prt.done or rev == 0 then 
		-- nothing to do
	elseif rev & POLLIN ~= 0 then -- can read
		r, eno = l5.read(prt.fd)
		if not r then
			em = errm(eno, "piperead")
			return nil, em --abort
		elseif #r == 0 then --eof?
			goto done
			prt.done=true
		else
			table.insert(prt.rt, r)
		end
	elseif rev & (POLLNVAL | POLLUP) ~= 0 then 
		-- pipe closed by other party
		goto done
	elseif rev & POLLERR ~= 0 then
		-- cannot read. should abort.
		em = "cannot read from pipe (POLLERR)"
		return nil, em
	else
		-- unknown condition - abort
		em = strf("unknown poll revents: 0x%x", rev)
		return nil, em
	end--if
	do return prt end --cannot leave return alone here!!!
	
	::done::
	prt.done = true
	prt.poll = -1 << 32
	return prt
end --piperead

local function pipewrite_new(fd, str)
	local pwt = { -- a "pipewrite" task
		done = false,
		fd = fd, 
		s = str,
		si = 1, 	--index in s
		bs = 4096,  	--blocksize
		poll = (fd << 32) | (POLLOUT << 16), -- poll_list entry
	}
	return pwt
end

local function pipewrite(pwt, rev)
	-- a write step in a poll loop
	-- pwt: the pipewrite task
	-- rev: a poll revents for the pwt file descriptor
	-- return the updated task or nil, errmsg in case of 
	-- unrecoverable error
	local em, cnt
	if pwt.done or rev == 0 then 
		-- nothing to do
	elseif rev & (POLLNVAL | POLLUP | POLLERR) ~= 0 then
		-- cannot write. should abort
		em = strf("cannot write to pipe. revents=0x%x", rev)
		return nil, em		
	elseif rev & POLLOUT ~= 0 then -- can write
		cnt =  #pwt.s - pwt.si + 1
		if cnt > pwt.bs then cnt = pwt.bs end
		r, eno = l5.write(pwt.fd, pwt.s, pwt.si, cnt)
		if not r then	
			em = errm(eno, "write to cin")
			return nil, em
		else
			assert(r >= 0)
			pwt.si = pwt.si + r
			if pwt.si >= #pwt.s then goto done end
		end
	else
		-- unknown poll condition - abort
		em = strf("unknown poll revents: 0%x", rev)
		return nil, em	
	end

	do return pwt end --cannot leave return alone here!!!
	
	::done::
	pwt.done = true
	pwt.poll = -1 << 32
	-- close pipe end, so that reading child can detect eof
	l5.close(pwt.fd) 
	pwt.closed = true --dont close it again later
	return pwt
end --pipewrite
------------------------------------------------------------------------
-- popen2


local function popen2raw(exepath, input_str, argl, envl)
	envl = envl or l5.environ()
	argl = argl or {}
	local r, eno, em, err, pid
	-- create pipes:  cin is child stdin, cout is child stdout
	-- pipes are non-blocking
	local pid, cin, cout = spawn_child(exepath, argl, envl)
	if not pid then return nil, cin end --here cin is the errmsg
	
--~ print("CHILD PID", pid)
	-- here parent writes to child stdin on cin and reads from
	-- child stdout, [stderr] on cout, cerr
	
	local inpwt = pipewrite_new(cin, input_str)
	local outprt = piperead_new(cout)
	
	local poll_list = {inpwt.poll, outprt.poll}
	local rev, cnt, wpid, status, exitcode
	
	while true do
		-- poll cin, cout
		r, eno = l5.poll(poll_list, 200) -- timeout=200ms
--~ print("POLL r, eno, indone, outdone", r, eno, inpwt.done, outprt.done)
		if not r then
			em = errm(eno, "poll")
			goto abort
		elseif r == 0 then
			goto continue
		end
		
		--write to cin
		rev = poll_list[1] & 0xffff
		r, em = pipewrite(inpwt, rev)
		if not r then goto abort end
		
		--read from cout
		rev = poll_list[2] & 0xffff
		r, em = piperead(outprt, rev)
		if not r then goto abort end
		
		-- are we done?
		if inpwt.done and outprt.done then break end
		
		-- update the poll_list
		poll_list[1] = inpwt.poll
		poll_list[2] = outprt.poll
		
		::continue::
	end--while
	
	wpid, status = l5.waitpid(pid)
	exitcode = (status & 0xff00) >> 8
--~ pf("WAITOID\t\t%s   status: 0x%x  exit: %d", wpid, status, exitcode)
	
	r = table.concat(outprt.rt)
	em = nil
	goto closeall
	
	::abort::
		r = false

	::closeall::
		if not inpwt.closed then l5.close(cin) end
		l5.close(cout)
--~ print("CLOSE cin", l5.close(cin))
--~ print("CLOSE cout", l5.close(cout))
	
	return r, em, exitcode
	
end--popen2raw

local function popen2(cmd, in_str, envl)
	envl = envl or l5.environ()
	local argl = {"bash", "-c", cmd}
	return popen2raw("/bin/bash", in_str, argl, envl)
end

------------------------------------------------------------------------
local popen = {
	popen2 = popen2,
}

return popen

--[[ NOTES

read() may fail due to nonblocking stdin
see eg. 
https://lists.gnu.org/archive/html/bug-bash/2017-01/msg00039.html

=> should set non-blocking only the parent-end of pipe cin
=> must add fcntl to l5.c ...

from url above -- set fd nonblocking:
	#include <fcntl.h>
	...
	int flags = fcntl (0, F_GETFL);
	if (fcntl(0, F_SETFL, flags | O_NONBLOCK)) { ...

-- set fd blocking
	int flags = fcntl (0, F_GETFL);
	if (fcntl(0, F_SETFL, flags & ~O_NONBLOCK))
	  sys_error (_("Failed to make stdin blocking"));



]]
	
	