

-- loop device test - this usually requires root privilege


local l5 = require "l5"
local util = require "l5.util"
local errno = require "l5.errno"
local loop = require "l5.loop"

-- some usual functions
local spack, sunpack, strf = string.pack, string.unpack, string.format
local errm, rpad, pf = util.errm, util.rpad, util.pf
local px, repr, fget, fput = util.px, util.repr, util.fget, util.fput

-- setup test data
local loopfile = os.tmpname()
local devname = "/dev/loop6" -- assume that this one is not used

-- create a 20MB empty loop file
fput(loopfile, string.rep('\0', 20 * 1024 * 1024))


local fname, eno, em, r

-- try to get the filename for an unused loop device
fname, eno, em = loop.filename(devname)
if eno == errno.EACCES then
	print(errno.msg(eno), "(must probably run with root privilege)")
	os.exit(1)
end
assert(eno == errno.ENXIO, "loop should not exist at this point.")

-- setup the loop device
r, eno, em = loop.setup(devname, loopfile)
assert(r, errm(eno, em))

-- get the loop filename
fname, eno, em = loop.filename(devname)
assert(fname == loopfile)
	
os.execute("losetup")
assert(os.execute("mkfs.ext2 " .. devname))

-- remove the loop
r, eno, em = loop.remove(devname)
assert(r, "cannot remove loop device")

-- remove the loop file
assert(os.remove(loopfile), "cannot remove loop file")
print("test_loop: ok")

