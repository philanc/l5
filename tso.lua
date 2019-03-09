

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
	local a, ab, fd, eno, em, em2, r, n, mb, msg, msg2
	soname = "./aaa"
	os.remove(soname)
	mb = l5.mbnew(1400)
	fd = assert(sock.dsocket(1))
	a = sock.make_unix_sockaddr(soname)
--~ 	print("sockaddr:", repr(a), #a)
	assert(l5.bind(fd, a))
	msg = "hello-1"
	assert(l5.sendto(fd, msg, 0, a))
	r, ab = l5.recvfrom(fd, mb, 1400, 0)
	assert(a == ab)
	msg2 = mb:get(0, r)
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
--~ 	print(r, repr(ab))
	assert(a == ab)
	assert(msg == r)
	r, ab = d:recv(0x40) -- MSG_DONTWAIT = 0x00000040
	print(r, repr(ab))  --> nil, 11 EAGAIN
	d:close()
	print(d:send(msg, a))  --> nil, 9 EBADF 
	os.remove(soname)
	print("test_1a ok.")
end

function test_2()
	local a, ab, fd, eno, em, em2, r, n, mb, msg, msg2
	soname = "./aaa"
	os.remove(soname)
	mb = l5.mbnew(1400)
	fd = assert(sock.dsocket(1))
	a = sock.make_unix_sockaddr(soname)
--~ 	print("sockaddr:", repr(a), #a)
	assert(l5.bind(fd, a))
	msg = "hello-1"
	r, eno = l5.connect(fd, a)
	assert(r, errm(eno, "connect"))
	r, eno = l5.write(fd, msg)
	assert(r, errm(eno, "write"))
	r, eno = l5.read4k(fd)
	assert(r, errm(eno, "read"))
	print("read:", r)
--~ 	msg2 = mb:get(0, r)
--~ 	assert(msg2 == msg)
--~ 	print("recvfrom", repr(ab), #ab, r, repr(msg2))
	l5.close(fd)
	os.remove(soname)
	print("test_2 ok.")
end

local IGNORE_SA = 0x01000000

function test_2a()  -- as test_2, with send1/recv1
	local a, ab, fd, eno, em, em2, r, n, mb, msg, msg2
	soname = "./aaa"
	os.remove(soname)
	fd = assert(sock.dsocket(1))
	a = sock.make_unix_sockaddr(soname)
	assert(l5.bind(fd, a))
	msg = "hello-1"
	assert(l5.connect(fd, a))
	r, eno = l5.send1(fd, msg, IGNORE_SA)
	assert(r, errm(eno, "send1"))
	r, eno = l5.recv1(fd, IGNORE_SA)
	assert(r, errm(eno, "recv1"))
--~ 	print("read:", r)
	assert(r == msg)
	l5.close(fd)
	os.remove(soname)
	print("test_2a ok.")
end



------------------------------------------------------------------------

--~ test_1()
test_1a()
--~ test_2()
--~ test_2a()



------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

