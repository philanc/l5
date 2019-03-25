-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- L5 filesystem functions


local l5 = require "l5"
local util = require "l5.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local insert, concat = table.insert, table.concat
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

------------------------------------------------------------------------



------------------------------------------------------------------------
-- fs function

fs = {}

function fs.makepath(dirname, name)
	-- returns a path made with a dirname and a filename
	-- if dirname is "", name is returned
	if dirname == "" then return name end
	if dirname:match('/$') then return dirname .. name end
	return dirname .. '/' .. name
end

local typt = {
	[1]="f",	--fifo
	[2]="c",	--char device
	[4]="d",	--directory
	[6]="b",	--block device
	[8]="r", 	--regular
	[10]="l", 	--link
	[12]="s",	--socket
	--[14]="w",	--whiteout (bsd? and/or codafs? => ignore it)
}

local function typestr(ft)
	return typt[ft] or "u" --unknown
end

function fs.dirmap(dirpath, func, t)
	-- map func over the directory
	-- collect func results in table t
	-- return the table.
	-- func signature: func(t, fname, ftype, dirpath) 
	-- 
	local dp = (dirpath == "") and "." or dirpath
	-- (note: keep dp and dirpath distinct. it allows to have an 
	-- empty prefix instead of "./" for find functions)
	--
	local dh, eno = l5.opendir(dp)
	if not dh then return nil, errm(eno, "opendir") end
	while true do
		local fname, ftype = l5.readdir(dh)
		if not fname then
			eno = ftype
			if eno == 0 then break
			else 
				l5.closedir(dh)
				return nil, errm(eno, "readdir")
			end
		else
			func(t, fname, ftype, dirpath)
		end
	end
	l5.closedir(dh)
	return t
end

function fs.ls0(dirpath)
	local tbl = {}
	return fs.dirmap(dirpath, 
		function(t, fname, ftype) insert(t, fname) end,
		tbl)
end

function fs.ls1(dirpath)
	local tbl = {}
	return fs.dirmap(dirpath, function(t, fname, ftype) 
		insert(t, {fname, typestr(ftype)}) 
		end, 
		tbl)
end

function fs.ls3(dirpath)
	-- ls3(dp) => { {name, type, size, mtime}, ... }
	local ls3 = function(t, fname, ftype, dirpath)
		local fpath = fs.makepath(dirpath, fname)
		local mode, size, mtime = l5.lstat3(fpath)
		insert(t, {fname, typestr(ftype), mtime, size})	
	end
	return fs.dirmap(dirpath, ls3, {})
end

function fs.lsd(dirpath)
	-- return dirlist, filelist
	local lsd = function(t, fname, ftype, dirpath)
		insert(t[ftype==4 and 1 or 2], fname)
	end
	local t, em = fs.dirmap(dirpath, lsd, {{}, {}})
	if not t then return nil, em end
	return t[1], t[2]
end

function fs.findfiles(dirpath)
	-- find (recursively) files in dirpath. return a list of file paths
	local dl, fl = fs.lsd(dirpath)
	if not dl then return nil, fl end
	for i, f in ipairs(fl) do
		fl[i] = fs.makepath(dirpath, f)
	end
	for i, d in ipairs(dl) do
		if d == "." or d == ".." then goto continue end
		local ffl, em = fs.findfiles(fs.makepath(dirpath, d))
		if not ffl then return nil, em end
		for j, f in ipairs(ffl) do
			insert(fl, f)
		end
		::continue::
	end
	return fl
end

function fs.findall(dirpath)
	-- find (recursively) files and dirs in dirpath. 
	-- return a list of file and dir paths
	local dl, fl = fs.lsd(dirpath)
	if not dl then return nil, fl end
	for i, f in ipairs(fl) do --replace file names with file paths
		fl[i] = fs.makepath(dirpath, f)
	end
	for i, d in ipairs(dl) do
		if d == "." or d == ".." then goto continue end
		local dp = fs.makepath(dirpath, d)
		insert(fl, dp) -- append dir paths to file list
		local ffl, em = fs.findfiles(dp) -- recurse into dir
		if not ffl then return nil, em end
		for j, f in ipairs(ffl) do
			insert(fl, f)
		end
		::continue::
	end
	return fl
end

function fs.stat(fpath, tbl)
	-- return an "attributes" or "lstat" table for a file
	tbl = tbl or {}
	local fa, eno = l5.lstat(fpath, tbl)
	if not fa then return nil, errm(eno, "lstat") end
	return fa
end

-- access commonly used fields of an attributes table

function fs.mode(fa) return fa[3] end
function fs.fsize(fa) return fa[8] end
function fs.fmod(fa) return fa[12] end
function fs.uid(fa) return fa[5] end
function fs.gid(fa) return fa[6] end

function fs.ftype(fa) 
	-- return file type as a one char string (f=fifo, c=chardev,
	-- d=directory, b=blockdev, r=regular, l=link, s=socket)
	return typestr((fa[3] >> 12) & 0x1f) 
end

function fs.fperms(fa) 
	-- return the octal representation of permissions as a string
	-- eg. "0755", "4755", "0600", etc.
	return strf("%04o", fa[3] & 0x0fff) 
end

function fs.fexec(fa) 
	-- retrun true if file is a regular file and executable
	-- (0x49 == 0o0111)
	return ((fa[3] & 0x49) ~= 0) and ((fa[3] >> 12) == 8) 
end

function fs.stat3(fpath)
	-- get useful attributes without filling a table:
	-- return file type, size, mtime | nil, errmsg
	local mode, size, mtime = l5.lstat3(fpath)
	if not mode then return nil, errm(size, "stat3") end
	local ftype = typestr((mode >> 12) & 0x1f)
	return ftype, size, mtime
end
	

-- some useful mount options

fs.mount_options = {
	ro = 1,
	nosuid = 2,
	nodev = 4,
	noexec = 8,
	remount = 32,
	noatime = 1024,
	bind = 4096,
}




------------------------------------------------------------------------
return fs
