
-- test popen functions

local he = require "he"

local popen = require "l5.popen"


local popen2 = popen.popen2

local function test_popen2_1()
	-- test large input
	local s, em, exitcode = popen2("md5sum", ("abc"):rep(100000))
	assert(s == "738099772b5a9e6727a93949be623917  -\n")
	assert(em == nil)
	assert(exitcode == 0)
	-- test exitcode with cmd error (md5sum -z invalid option)
	s, em, exitcode = popen2("md5sum -z 2>&1", "abc")
	assert(he.startswith(s, "md5sum: invalid option") and exitcode==1)
end

local function test_popen2_2()
	-- test large input, large output
	local r1 = assert(popen2("ls -l /usr/lib64 | md5sum", ""))
	local r2 = assert(popen2("ls -l /usr/lib64", ""))
	local r3 = assert(popen2("md5sum", r2))
	assert(r1 == r3)
end

test_popen2_1()
test_popen2_2()
print("test popen2 ok.")

