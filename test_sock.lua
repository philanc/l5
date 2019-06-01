

-- tso.lua - test sockets

he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"

util = require "l5.util"
sock = require "l5.sock"

local spack, sunpack = string.pack, string.unpack
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px

------------------------------------------------------------------------

function test_1()
	-- send to a unix datagram socket
	local a, ab, fd, eno, em, em2, r, n, mb, msg, msg2
	soname = "./aaa"
	os.remove(soname)
--~ 	mb = l5.mbnew(1400)
	fd = assert(sock.dsocket(1))
	a = sock.make_unix_sockaddr(soname)
--~ 	print("sockaddr:", repr(a), #a)
	assert(l5.bind(fd, a))
	msg = "hello-1"
	assert(l5.sendto(fd, msg, 0, a))
	r, ab = l5.recvfrom(fd)
	assert(a == ab)
	msg2 = r
	assert(msg2 == msg)
--~ 	print("recvfrom", repr(ab), #ab, r, repr(msg2))
	l5.close(fd)
	os.remove(soname)
	print("test_1 ok.")
end


function test_1a() -- same as test_1() with dso object
	local a, ab, d, eno, em, r, n
	soname = "./aaa"
	os.remove(soname)
	d = assert(sock.newdso(1):bind(soname) )
	msg = "hello-1"
	a = d.sa
	assert(d:send(msg, a))
	r, ab = d:recv()
	assert(a == ab)
	assert(msg == r)
	r, ab = d:recv(0x40) -- MSG_DONTWAIT = 0x00000040
	assert(r==nil and ab==11) -- EAGAIN=11
	d:close()
	r, eno = d:send(msg, a)  --> nil, 9 EBADF 
	assert(r == nil and eno == 9)
	os.remove(soname)
	print("test_1a ok.")
end

function test_2()
	local a, ab, fd, eno, em, em2, r, n, mb, msg, msg2
	soname = "./aaa"
	os.remove(soname)
	fd = assert(sock.dsocket(1))
	a = sock.make_unix_sockaddr(soname)
--~ 	print("sockaddr:", repr(a), #a)
	assert(l5.bind(fd, a))
	msg = "hello-1"
	r, eno = l5.connect(fd, a)
	assert(r, errm(eno, "connect"))
	r, eno = l5.write(fd, msg)
	assert(r, errm(eno, "write"))
	r, eno = l5.read(fd)
	assert(r, errm(eno, "read"))
	assert(r == msg)
--~ 	msg2 = mb:get(0, r)
--~ 	assert(msg2 == msg)
--~ 	print("recvfrom", repr(ab), #ab, r, repr(msg2))
	l5.close(fd)
	os.remove(soname)
	print("test_2 ok.")
end

local IGNORE_SA = 0x01000000
local DONTWAIT = 0x40

function test_2a()  -- as test_2, with send/recv
	local a, ab, fd, eno, em, em2, r, n, mb, msg, msg2
	soname = "./aaa"
	os.remove(soname)
	fd = assert(sock.dsocket(1))
	a = sock.make_unix_sockaddr(soname)
	assert(l5.bind(fd, a))
	msg = "hello-1"
	assert(l5.connect(fd, a))
	r, eno = l5.send(fd, msg, 0)
	assert(r, errm(eno, "send1"))
	r, eno = l5.recv(fd)
	assert(r, errm(eno, "recv1"))
--~ 	print("read:", r)
	assert(r == msg)
	l5.close(fd)
	os.remove(soname)
	print("test_2a ok.")
end

function test_3()  
	-- try to send w/o any recv, until it fails
	local a, ab, d, eno, em, r, n, tot, i
	soname = "./aaa"
	os.remove(soname)
	d = assert(sock.newdso(1):bind(soname) )
	msg = ("m"):rep(1280)
	a = d.sa
	tot = 0
	for i = 1, 1000 do
		r, eno = d:send(msg, a, DONTWAIT)
		if not r then 
			pf("test_3 #msg: %d  iter: %d  tot: %d  errno: %d", 
				#msg, i, tot, eno)
			break
		end
		tot = tot + r
	end
	d:close()
	print("test_3 ok.")
end

function test_3a()  -- same as test_3() with a (local) af_inet socket
	-- try to send w/o any recv, until it fails
	local a, ab, d, eno, em, r, n, tot, i
	local soname, port = "127.0.0.1", 10000
--~ 	os.remove(soname)
	d = assert(sock.newdso(2))
	r, em = d:bind(soname, port) 
	if not r then 
		d:close()
		print(em, repr(d.sa))
		return nil, em
	end
	msg = ("m"):rep(1280)
	a = d.sa
	tot = 0
	for i = 1, 10000 do
		r, eno = d:send(msg, a, DONTWAIT)
		if (not r) or (r < #msg) then 
			pf("test_3a #msg: %d  iter: %d  tot: %d  errno: %d", 
				#msg, i, tot, eno)
			break
		end
		tot = tot + r
	end
	d:close()
	print("test_3a ok.")
end

function test_5()  -- test sso objects
	local a, ab, d, eno, em, r, n, tot, i, line, msg
	local soname, port = "127.0.0.1", 10000
	local line, msg, mlen, l2, m2, ss, chs, cs, pid
	line = "hello\n"
	--line = "\n"
	mlen = 5000	-- make msg larger than on read buffer
	msg = ("m"):rep(mlen)
	
	-- setup server
	local ss = sock.newsso()
	assert(ss:bind(soname, port) == ss)
	assert(ss:timeout(10000) == ss)
	pid = l5.fork()
	if pid == 0 then
		-- child / client here
		chs = sock.newsso()
--~ 		print('child chs', chs)
		l5.msleep(100) -- give time to the server to accept
		assert(chs:connect(soname, port) == chs)
		chs:write(line .. msg)
		chs:close()
--~ 		print("child exiting")
		os.exit(0)
	else
		-- parent / server here
		cs, em = ss:accept()
--~ 		print('parent accept cs', cs, em)
		l2, em = cs:read()
		assert(l2, em)
		m2, em = cs:read(mlen)
		assert(m2, em)
--~ 		print(l2, #m2)
		assert(l2 == he.strip(line))
		assert(m2 == msg)
		cs:close()
		ss:close()
		l5.waitpid(pid)
	end
	print("test_5 ok.")
end


------------------------------------------------------------------------
-- test poll

function test_6()
	print("test_6 waiting 1 sec")
	r = l5.poll({}, 1000)
	assert(r == 0)
	print("test_6 ok. (waited 1 sec)")
end

local POLLIN = 1
local POLLOUT = 4
local POLLERR = 8
local POLLHUP = 0x10
local POLLNVAL = 0x20

local function pfd(fd, events) 
	return (fd << 32) | (events << 16)
end

local function pfdrev(pfd)
	local fd, rev = pfd >> 32, pfd & 0xffff
	return fd, rev
end

function test_7()
	print("test_7 press return within 3 sec.")
	pl = { pfd(0, POLLIN),  }
--~ 	pf("before: 0x%016x", pl[1])
	r = l5.poll(pl, 3000) -- wait 3 sec max
	assert(r == 0 or r == 1) 
--~ 	pf("after:  0x%016x", pl[1])
	assert(pl[1]==0x10000 or pl[1]==0x10001)
	if pl[1]==0x10001 then io.read() end -- read the newline
	desc = pl[1]==0x10001 
		and "(return pressed)" 
		or "(return not pressed. waited 3 sec.)"
	print("test_7 ok. " .. desc)
end


function test_7a()
--~ 	print("press return")
	pl = { pfd(0, POLLIN), pfd(1, POLLOUT), }
--~ 	pl = { pfd(0, POLLIN), pfd(1, POLLOUT), pfd(3, POLLOUT) }
--~ 	pf("before: 0x%016x", pl[1])
	-- return immediately since stdout is available
	r = l5.poll(pl, 5000)
	assert(r==1 or r==2)  -- maybe more than one return pressed before
--~ 	pf("after:  0x%016x  0x%016x  ", pl[1], pl[2])
--~ 	pf("after:  0x%016x  0x%016x  0x%016x  ", pl[1], pl[2], pl[3])
	assert(pl[2] == 0x100040004) -- stdout is available for output
	print("test_7a ok.")
end






------------------------------------------------------------------------

test_1()
test_1a()
test_2()
test_2a()
test_3()
test_3a()
test_5()
test_6()
test_7()
test_7a()


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

