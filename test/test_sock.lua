

-- tso.lua - test sockets

he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"

util = require "l5.util"
sock = require "l5.sock"

local spack, sunpack = string.pack, string.unpack
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px

local function sa2s(sa)
	-- return ipv4 address as a string and port as a number
	-- or nil, errmsg if family is not AF_INET (2) or length is not 16
	-- 
	if #sa ~= 16 then 
		return nil, "bad length"
	end
	local family, port, ip1, ip2, ip3, ip4 = 	
		sunpack("<H>HBBBB", sa)
	if family ~= 2 then 
		return nil, "not an IPv4 address"
	end
	local ipaddr = table.concat({ip1, ip2, ip3, ip4}, '.')
	return ipaddr, port	
end
------------------------------------------------------------------------

function test_stream() 
	local a, ab, d, eno, em, r, n, tot, i, line, msg
	local soname, port = "127.0.0.1", 10000
	local line, msg, mlen, l2, m2, ss, chs, cs, pid
	line = "hello\n"
	--line = "\n"
	mlen = 5000000	-- make msg larger than on read buffer
	msg = ("m"):rep(mlen)
	
	-- setup server
	local sa = sock.sockaddr(soname, port)
	local ss = sock.sbind(sa)
	assert(ss)
	assert(sock.timeout(ss, 10000) == ss)
	pid = l5.fork()
	if pid == 0 then
		-- child / client here
		l5.msleep(100) -- give time to the server to accept
		chs = assert(sock.sconnect(sa))
		assert(sock.write(chs, line .. msg))
		sock.close(chs)
--~ 		print("test_stream: child exiting")
		os.exit(0)
	else
		-- parent / server here
		cs, em = sock.accept(ss)
		assert(cs, em)
--~ 		print('server', sa2s(sock.getsockname(ss)))
--~ 		print('client', sa2s(sock.getpeername(ss)))
		local a, p
		a, p = sa2s(sock.getsockname(ss))
		assert(a == "127.0.0.1" and p == 10000)
		a, p = sa2s(sock.getpeername(ss))
		assert(a == "127.0.0.1" and p == 10000)
		l2, em = sock.read(cs)
		assert(l2, em)
		m2, em = sock.read(cs, mlen)
		assert(m2, em)
--~ 		print(l2, #m2)
		assert(l2 == he.strip(line))
--~ 		print('>>>' .. m2:sub(1,100))
		assert(m2 == msg)
		sock.close(cs)
		sock.close(ss)
		l5.waitpid(pid)
		print("test_stream ok.")
	end
end


function test_datagram() 
	local a, ab, d, eno, em, r, n, tot, i, line, msg
	local soname, port = "./test_dg.sock"
	local line, msg, mlen, l2, m2, ss, chs, cs, pid
	local NONBLOCKING = true
	local ping, pong = "ping", "pong"
	
	-- setup server
	local ssa = sock.sockaddr(soname, port)
	local ss = sock.dsocket(sock.AF_UNIX, NONBLOCKING)
	assert(sock.bind(ss, ssa))
	assert(sock.timeout(ss, 10000) == ss)
	
	-- setup client
	local cs = sock.dsocket(sock.AF_UNIX, NONBLOCKING)

	
	pid = l5.fork()
	if pid == 0 then
		-- child / client here
		for i = 1, 10 do
			print("client:", ping)
			l5.msleep(1000) -- 1 sec
			sock.sendto(cs, ping, ssa)
		end
		print("child exiting")
		os.exit(0)
	else
		-- parent / server here
		local cnt = 1
		while true do
			local r, csa = sock.recvfrom(ss)
			if not r and csa == sock.EAGAIN then
				print("server: waiting")
				l5.msleep(600)
			else 
				print("server", r, csa, cnt)
				cnt = cnt + 1
				if cnt >= 10 then break end
			end
		end
		print("server: closing all")	
		
		sock.close(cs)
		sock.close(ss)
		os.remove(soname)
		l5.waitpid(pid)
		print("test_datagram ok.")
	end
end

function test_datagram0() 
	local a, ab, d, eno, em, r, n, tot, i, line, msg
	local soname, port = "./test_dg.sock"
	local line, msg, mlen, l2, m2, ss, chs, cs, pid
	local NONBLOCKING = true
	local ping, pong = "ping", "pong"
	local ssa = sock.sockaddr(soname, port)
	-- test recv return on a non-blocking socket
	local ss = sock.dsocket(sock.AF_UNIX, NONBLOCKING)
	assert(sock.bind(ss, ssa))
	r, eno = sock.recv(ss)
	assert((not r) and (eno == sock.EAGAIN))
	sock.close(ss)
	os.remove(soname)
	--
	-- test recv timeout on a blocking socket
	local ss = sock.dsocket(sock.AF_UNIX)
	assert(sock.bind(ss, ssa))
	assert(sock.timeout(ss, 1000) == ss)
	print("...waiting 1sec timeout...")
	r, eno = sock.recv(ss)
	assert((not r) and (eno == sock.EAGAIN))
	sock.close(ss)
	os.remove(soname)
	--
	-- test send; recv, recvfrom on the same socket
	local ss = sock.dsocket(sock.AF_UNIX)
	assert(sock.bind(ss, ssa))
	assert(sock.timeout(ss, 1000) == ss)
	r, eno = sock.sendto(ss, ping, ssa)
	assert(r == #ping)
	local pingpong = ping .. pong
	r, eno = sock.sendto(ss, pingpong, ssa)
	assert(r == #pingpong)
	r, eno = sock.recv(ss)
	assert(r == ping)
	local osa
	r, osa = sock.recvfrom(ss)
	assert(r == pingpong)
	assert(osa == ssa)
	sock.close(ss)
	os.remove(soname)
	print("test_datagram0 ok.")
end


------------------------------------------------------------------------
------------------------------------------------------------------------

test_stream()

--~ test_datagram()
test_datagram0()

print("test_sock ok.")


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

