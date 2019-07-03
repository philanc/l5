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

-- file types and attributes


local typetbl = {
	[1] = "f",	--fifo
	[2] = "c",	--char device
	[4] = "d",	--directory
	[6] = "b",	--block device
	[8] = "r", 	--regular
	[10]= "l", 	--link
	[12]= "s",	--socket
	--[14]= "w",	--whiteout (only bsd? and/or codafs? => ignore it)
}

function fs.typestr(ft)
	-- convert the numeric file type into a one-letter string
	return typetbl[ft] or "u" --unknown
end

fs.attribute_ids = {
	dev = 1,
	ino = 2,
	mode = 3,
	nlink = 4,
	uid = 5,
	gid = 6,
	rdev = 7,
	size = 8,
	blksize= 9,
	blocks = 10,
	atime = 11,
	mtime = 12,
	ctime = 13,
}

function fs.mtype(mode)
	-- return the file type of a file given its 'mode' attribute
	return (mode >> 12) & 0x1f
end

function fs.mperm(mode) 
	-- get the access permissions of a file given its 'mode' attribute
	return mode & 0x0fff
end

function fs.mpermo(mode) 
	-- get the access permissions of a file given its 'mode' attribute
	-- return the octal representation of permissions as a four-digit
	-- string, eg. "0755", "4755", "0600", etc.
	return strf("%04o", mode & 0x0fff) 
end

function fs.mexec(mode) -- !!! will probably remove this function 
	-- return true if file is a regular file and executable
	-- (0x49 == 0o0111)
	-- note: true if executable "by someone" --maybe not by the caller!!
	return ((mode & 0x49) ~= 0) and ((mode >> 12) == 8) 
end

function fs.lstat(fpath, tbl, statflag)
	-- tbl is filled with lstat() results for file fpath
	-- tbl is optional. it defaults to a new empty table
	-- return tbl
	-- if statflag is true, stat() is used instead of lstat()
	statflag = statflag and 1 or nil
	tbl = tbl or {}
	return l5.lstat(fpath, tbl, statflag) 
end

function fs.attr(fpath, attr_name, statflag)
	-- return a single lstat() attribute for file fpath
	-- fpath can be replaced by the table returned by lstat()
	-- for the file. attr_name is the name of the attribute.
	-- if statflag is true, stat() is used instead of lstat()
	local attr_id = fs.attribute_ids[attr_name] 
		or error("unknown attribute name")
	if type(fpath) == "table" then return fpath[attr_id] end
	statflag = statflag and 1 or nil
	return l5.lstat(fpath, attr_id, statflag)
end	

function fs.stat3(fpath)
	-- get useful attributes without filling a table:
	-- return file type, size, mtime | nil, errmsg
	local mode, size, mtime = l5.lstat3(fpath)
	if not mode then return nil, errm(size, "stat3") end
	local ftype = (mode >> 12) & 0x1f
	return ftype, size, mtime
end

function fs.fsize(fpath)
	return fs.attr(fpath, 'size')
end

function fs.mtime(fpath)
	return fs.attr(fpath, 'mtime')
end

------------------------------------------------------------------------
-- directories

function fs.dirmap(dirpath, func, t)
	-- map func over the directory  ("." and ".." are ignored)
	-- func signature: func(fname, ftype, t, dirpath)
	-- t is a table passed to func. It defaults to {}
	-- func should return true if the iteration is to continue.
	-- if func returns nil, err then iteration stops, and dirmap 
	-- returns nil, err.
	-- dirmap() returns t after directory iteration
	-- in case of opendir or readdir error, dirmap returns nil, errno
	-- 
	t = t or {}
	local dp = (dirpath == "") and "." or dirpath
	-- (note: keep dp and dirpath distinct. it allows to have an 
	-- empty prefix instead of "./" for find functions)
	--
	local dh, eno = l5.opendir(dp)
	if not dh then return nil, eno end
	local r
	while true do
		local fname, ftype = l5.readdir(dh)
		if not fname then
			eno = ftype
			if eno == 0 then break
			else 
				l5.closedir(dh)
				return nil, errm(eno, "readdir")
			end
		elseif fname == "." or fname == ".." then
			-- continue
		else
			r, eno = func(fname, ftype, t, dirpath)
			if not r then
				l5.closedir(dh)
				return nil, errm(eno, "readdir")
			end
		end
	end
	l5.closedir(dh)
	return t
end

function fs.ls0(dirpath)
	local tbl = {}
	return fs.dirmap(dirpath, 
		function(fname, ftype, t) insert(t, fname) end,
		tbl)
end

function fs.ls1(dirpath)
	-- ls1(dp) => { {name, type}, ... }
	local tbl = {}
	return fs.dirmap(dirpath, function(fname, ftype, t) 
		insert(t, {fname, typestr(ftype)}) 
		end, 
		tbl)
end

function fs.ls3(dirpath)
	-- ls3(dp) => { {name, type, size, mtime}, ... }
	local ls3 = function(fname, ftype, t, dirpath)
		local fpath = fs.makepath(dirpath, fname)
		local mode, size, mtime = l5.lstat3(fpath)
		insert(t, {fname, ftype, size, mtime})	
		return true
	end
	return fs.dirmap(dirpath, ls3, {})
end

function fs.lsdfo(dirpath)
	-- return directory list, regular filelist, other files list
	local lsdfo = function(fname, ftype, t, dirpath)
		insert(t[ (ftype == 4 and 1)
			  or (ftype == 8 and 2)
			  or 3], fname)
		return true
	end
	local t, em = fs.dirmap(dirpath, lsdfo, {{}, {}, {}})
	if not t then return nil, em end
	return t[1], t[2], t[3]
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

------------------------------------------------------------------------
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
