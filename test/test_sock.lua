

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


function test_5() 
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
		print("child exiting")
		os.exit(0)
	else
		-- parent / server here
		cs, em = sock.accept(ss)
		print('parent accept cs', cs, em)
		print('server', sa2s(sock.getsockname(ss)))
		print('client', sa2s(sock.getpeername(ss)))
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
	end
end


------------------------------------------------------------------------
------------------------------------------------------------------------

test_5()

print("test_sock ok.")


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

