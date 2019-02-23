
he = require "he"

--[[
ln = require "linenoise"

cooked = ln.getmode()

print('cooked', #cooked)
print(he.stohex(cooked, 16, ':'))
ln.setrawmode()

raw = ln.getmode()
r = ln.setmode(cooked)
print('retored.', r)

print('raw', #raw)
print(he.stohex(raw, 16, ':'))

-- ]]

l5 = require "l5"


function makerawmode(mode, opostflag)
	-- taken from linenoise
	-- see also musl src/termios/cfmakeraw.c
	local fmt = "I4I4I4I4c6I1I1c36" -- 60 bytes
	local iflag, oflag, cflag, lflag, dum1, ccVTIME, ccVMIN, dum2 =
		string.unpack(fmt, mode)
	-- no break, no CRtoNL, no parity check, no strip, no flow control
	-- .c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
	iflag = iflag & 0xfffffacd
	if not opostflag then oflag = oflag & 0xfffffffe end
	-- set 8 bit chars -- .c_cflag |= CS8
	cflag = cflag | 0x00000030
	-- echo off, canonical off, no extended funcs, no signal (^Z ^C)
	-- .c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG)
	lflag = lflag & 0xffff7ff4
	-- return every single byte, without timeout
	ccVTIME = 0
	ccVMIN = 1
	return fmt:pack(iflag, oflag, cflag, lflag, 
			dum1, ccVTIME, ccVMIN, dum2)
end

function getmode()
	-- return mode, or nil, errno
	return l5.ioctl(0, 0x5401, "", 60)
end

function setmode(mode)
	-- return true or nil, errno
	return l5.ioctl(0, 0x5404, mode)
end


-- get mode
mode, err = getmode()
print("mmmm???", err)
print(he.stohex(mode, 16, ':'))

print("test raw mode:  hit key, 'q' to quit.")
-- set raw mode
setmode(makerawmode(mode))

while true do 
	c = io.read(1)
	if c == 'q' then break end
	print(string.byte(c))
end

setmode(mode)
print('\rback to normal cooked mode.')


	

