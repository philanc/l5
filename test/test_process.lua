
-- test popen functions

-- NOTE: for some tests, child writes to uncaptured stderr. to prevent 
--	 the test from displaying stderr text, run as:
--
--	 lua test/test_process.lua 2>/dev/null
--

local he = require "he"

local process = require "l5.process"

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

local function test_popen2_3()
	-- test cd
	print(popen2("pwd", "", {}, "/bin"))
end




local function test_run1() -- stdout only
	local rout, rerr, exitcode = process.run1("/bin/who", {"who"})
--~ 	print("test_run1", rout, rerr, exitcode)
	assert(rerr == "")
	assert(exitcode == 0)
	rout, rerr, exitcode = process.run1("/bin/who", {"who", "-z"})
--~ 	print("test_run1", rout, rerr, exitcode)
	assert(rout == "")
	assert(rerr == "")
	assert(exitcode == 1)
end

local function test_run2() -- stdin + stdout
	local rout, rerr, exitcode = process.run2(
		"/bin/md5sum", {"md5sum"}, "abc"
		)
--~ 	print("test_run2", rout, rerr, exitcode)
	assert(rout == "900150983cd24fb0d6963f7d28e17f72  -\n")
	assert(rerr == "")
	assert(exitcode == 0)
	
	rout, rerr, exitcode = process.run2( -- bad md5sum option
		"/bin/md5sum", {"md5sum", "-z"}, "abc"
		)
	assert(rout == "")
	assert(rerr == "")
	assert(exitcode == 1)
end --test_run2

local function test_run3() -- stdin + stdout + stderr
	local rout, rerr, exitcode = process.run3(
		"/bin/md5sum", {"md5sum"}, "abc"
		)
--~ 	print("test_run3", rout, rerr, exitcode)
	assert(rout == "900150983cd24fb0d6963f7d28e17f72  -\n")
	assert(rerr == "")
	assert(exitcode == 0)
	
	rout, rerr, exitcode = process.run3( -- bad md5sum option
		"/bin/md5sum", {"md5sum", "-z"}, "abc"
		)
--~ 	print("test_run3", rout, rerr, exitcode)
	assert(rout == "")
	assert(he.startswith(rerr, "md5sum: invalid option -- 'z'"))
	assert(exitcode == 1)
end --test_run3

local function test_shell1_2()
	-- test large input, large output
	local r1 = assert(process.shell1("ls -l /usr/bin | md5sum", ""))
	local r2 = assert(process.shell1("ls -l /usr/bin", ""))
	local r3 = assert(process.shell2("md5sum", r2))
--~ 	print(r3)
	assert(r1 == r3)
end

local function test_shell3()
	-- test get output + err
	local rout, rerr, ex = assert(process.shell3("who ; who -z", ""))
--~ 	print("test_shell3", rout, rerr, ex)
	assert(rout and rerr and #rout > 5 and #rerr >5)
end

local function test_shell_opt1()
	local rout, rerr, ex = process.shell1("pwd", {cd="/bin"})
--~ 	print("test_shell_opt1", rout, rerr, ex)
	assert(rout == "/bin\n")
	assert(rerr == "")
	assert(ex == 0)
end

--~ test_run1()
--~ test_run2()
--~ test_run3()
--~ test_shell1_2()
--~ test_shell3()
test_shell_opt1()
print("test process ok.")

