local _luwa = ...
_G = _ENV

math.mininteger = -9223372036854775808
math.maxinteger = 9223372036854775807
math.pi = 0x1.921fb54442d18p1
math.huge = 1./0.
package.config = '/\n;\n?\n!\n-\n'
package.loaded = {
	_G = _ENV,
	coroutine = coroutine,
	debug = debug,
	io = io,
	math = math,
	os = os,
	package = package,
	string = string,
	table = table,
	utf8 = utf8,
}

-- capture globals so that behavior doesn't change if rebound
local _rawget, _type = rawget, type
local _error, _next, _select, _pcall = error, next, select, pcall
local debug_getmetatable, debug_setmetatable = debug.getmetatable, debug.setmetatable
local io_type = io.type
local tointeger, math_type = math.tointeger, math.type
local string_byte, string_char = string.byte, string.char
local table_unpack = table.unpack
local co_create, co_resume, co_running = coroutine.create, coroutine.resume, coroutine.running
local math_floor, math_ceil = math.floor, math.ceil

debug_setmetatable('', { __index = string })

local function _assert(v, ...)
	if v then
		return v, ...
	elseif _select('#', ...) == 0 then
		return _error('assertion failed!', 2)
	else
		return _error(..., 2)
	end
end
assert = _assert

local function _getmetatable(object)
	object = debug_getmetatable(object)
	return (_type(object) == 'table' and _rawget(object, '__metatable')) or object
end
getmetatable = _getmetatable

function setmetatable(table, metatable)
	_assert(_type(tablety) == 'table')
	_assert(metatable == nil or _type(metatable) == 'table')
	local mt = debug_getmetatable(table)
	if mt then
		_assert(not _rawget(mt, '__metatable'), 'cannot change a protected metatable')
	end
	return debug_setmetatable(table, metatable)
end

local function _tostring(v)
	local ty = _type(v)
	if ty == 'string' then
		return v
	elseif ty == 'number' then
		return v .. ''
	else
		local mt = _getmetatable(v)
		local __tostring = mt.__tostring
		if __tostring then
			local s = __tostring(v)
			local sty = _type(s)
			if sty == 'string' then
				return s
			elseif sty == 'number' then
				return s .. ''
			else
				_error("'__tostring' must return a string")
			end
		else
			return ty .. ': ' .. _luwa.hexid(v)
		end
	end
end
tostring = _tostring

local digits = {}
for i=0,9 do
	digits[48+i] = i
end
for i=10,35 do
	digits[55+i] = i
	digits[87+i] = i
end
function tonumber(num, base)
	if base == nil then
		return _luwa.tonumber(num)
	else
		base = assert(tointeger(base), "bad argument #2 to 'tonumber' (number expected, got string)")
		assert(type(num) == 'string', "bad argument #1 to 'tonumber' (string expected, got number)")
		assert(base > 1 and base < 37, "bad argument #2 to 'tonumber' (base out of range)")
		if num == '' then
			return nil
		end
		local ret = 0
		local e = 1
		for i=#num,1 do
			local ch = digits[string_byte(num, i)]
			if not ch or ch >= base then
				return nil
			end
			ret = ret + ch * e
			e = e * base
		end
		return ret
	end
end

math.atan2 = math.atan
function math.deg(x)
	return x * (180./0x1.921fb54442d18p1)
end
function math.max(x, ...)
	for i = 1,_select('#', ...) do
		local m = _select(i, ...)
		if m > x then
			x = m
		end
	end
	return x
end
function math.min(x, ...)
	for i = 1,_select('#', ...) do
		local m = _select(i, ...)
		if m < x then
			x = m
		end
	end
	return x
end
function math.modf(x)
	if x > 0 then
		local xi = math_floor(x)
		return xi, x - xi
	else
		local xi = math_ceil(x)
		return -xi, x + xi
	end
end
function math.pow(x, y)
	return x ^ y
end
function math.rad(x)
	return x * (0x1.921fb54442d18p1/180.)
end
local randomseed = 1 + math_floor(_luwa.random() * 0x7ffffffffffffff7)
function math.random()
	-- xorshift* from wikipedia
	randomseed = randomseed ~ (randomseed>>12)
	randomseed = randomseed ~ (randomseed<<25)
	randomseed = randomseed ~ (randomseed>>27)
	return randomseed * 0x2545f4914f6cdd1d
end
function math.randomseed(x)
	randomseed = math_floor(x)
end
function math.sqrt(x)
	return x ^ .5
end
function math.ult(m, n)
	m = tointeger(m)
	_assert(m, "bad argument #1 to 'ult'")
	n = tointeger(n)
	_assert(n, "bad argument #2 to 'ult'")
	if m >= 0 then
		return n < 0 or m < n
	else
		return n < 0 and m < n
	end
end

function string:len()
	_assert(_type(self) == "string", "bad argument #1 to 'len' (string expected)")
	return #self
end
function smtfb(meth, x, y)
	local mt = getmetatable(y)
	if mt then
		local fn = mt[meth]
		if fn then
			return fn(x, y)
		end
	end
	return error("attempt to " .. meth .. " a '" .. _type(x) .. "' with a '" .. _type(y) .. "'")
end
function string.__add(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx + ny
	else
		return smtfb('__add', x, y)
	end
end
function string.__sub(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx - ny
	else
		return smtfb('__sub', x, y)
	end
end
function string.__mul(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx * ny
	else
		return smtfb('__mul', x, y)
	end
end
function string.__mod(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx % ny
	else
		return smtfb('__mod', x, y)
	end
end
function string.__pow(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx ^ ny
	else
		return smtfb('__pow', x, y)
	end
end
function string.__div(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx / ny
	else
		return smtfb('__div', x, y)
	end
end
function string.__idiv(x, y)
	local nx, ny = tonumber(x), tonumber(y)
	if nx ~= nil and ny ~= nil then
		return nx // ny
	else
		return smtfb('__idiv', x, y)
	end
end
function string:__unm()
	local nx = tonumber(self)
	if nx ~= nil then
		return -nx
	else
		return error("attempt to unm a 'string'")
	end
end

utf8.charpattern = "[\0-\x7F\xC2-\xF4][\x80-\xBF]*"

function table.pack(...)
	return { n = _select('#', ...), ... }
end
function table.insert(list, pos, value)
	if not value then
		list[#list+1] = pos
	else
		for i = #list,pos,-1 do
			list[i+1] = list[i]
		end
		list[pos] = value
	end
end
function table.remove(list, pos)
	local ret
	if pos then
		ret = list[pos]
		for i = pos,#list-1 do
			list[i] = list[i+1]
		end
	else
		ret = list[#list]
	end
	list[#list] = nil
	return ret
end
function table.move(a1, f, e, t, a2)
	if not a2 then
		a2 = a1
	end
	local len1 = e - f - 1
	if t < f then
		for i=0,len do
			a[t+i] = a[f+i]
		end
	elseif t > f then
		for i=len,0,-1 do
			a[t+i] = a[f+i]
		end
	end
end

-- TODO use a better sort; this fails on a big list of 0s
local function partitioncmp(list, comp, lo, hi)
	local pivot, i = list[hi], lo
	for j = lo, hi-1 do
		local t = list[j]
		if comp(t, pivot) then
			list[j] = list[i]
			list[i] = t
			i = i + 1
		end
	end
	list[hi] = list[i]
	list[i] = pivot
	return i
end
local function qsortcmp(list, comp, lo, hi)
	if lo < hi then
		local p = partitioncmp(list, comp, lo, hi)
		qsortcmp(list, comp, lo, p - 1)
		return qsortcmp(list, comp, p + 1, hi)
	end
end
local function partition(list, lo, hi)
	local pivot, i = list[hi], lo
	for j = lo, hi-1 do
		local t = list[j]
		if t < pivot then
			list[j] = list[i]
			list[i] = t
			i = i + 1
		end
	end
	list[hi] = list[i]
	list[i] = pivot
	return i
end
local function qsort(list, lo, hi)
	if lo < hi then
		local p = partition(list, lo, hi)
		qsort(list, lo, p - 1)
		return qsort(list, p + 1, hi)
	end
end
function table.sort(list, comp)
	if comp then
		return qsortcmp(list, comp, 1, #list)
	else
		return qsort(list, 1, #list)
	end
end

local iometa = {}
local function io_open(filename, mode)
	_assert(_type(filename) == 'string', 'Unexpected argument #1 to io.open')
	if mode == nil then
		mode = 'r'
	end
	filename, mode = _luwa.ioopen(filename, mode)
	if filename then
		return debug_setmetatable(filename, iometa)
	end
	return nil, mode
end
io.open = io_open
local io_in = _luwa.stdin()
local stdin = io_in
local io_out = _luwa.stdout()
local stdout = io_out
local function io_input(file)
	if file == nil then
		return io_in
	elseif _type(file) == 'string' then
		io_in = io_open(file)
		return io_in
	else
		_assert(io_type(file), "bad argument #1 to 'io.input'")
		io_out = file
		return file
	end
end
io.input = io_input
local function io_output(file)
	if file == nil then
		return io_out
	elseif _type(file) == 'string' then
		io_out = io_open(file, 'w')
		return io_in
	else
		_assert(io_type(file), "bad argument #1 to 'io.output'")
		io_out = file
		return file
	end
end
io.output = io_output
local function io_read(...)
	return _luwa.ioread(io_in, ...)
end
io.read = io_read
local function io_write(...)
	return _luwa.iowrite(io_out, ...)
end
io.write = io_write
local function io_flush(file)
	return _luwa.ioflush(io_out)
end
io.flush = io_flush
local function io_lines(file)
	if file == nil then
		file = io_in
	elseif _type(file) == 'string' then
		file = io_open(file)
	else
		_assert(io_type(file), "bad argument #1 to 'io.lines'")
	end
	return function()
		return _luwa.ioread(file)
	end
end
io.lines = io_lines
local function io_close(file)
	if file == nil then
		return _luwa.ioclose(io_out)
	else
		_assert(io_type(file), "bad argument #1 to 'io.close'")
		return _luwa.ioclose(file)
	end
end
io.close = io_close

iometa.__index = iometa
iometa.__name = 'FILE*'
iometa.__gc = _luwa.iogc
iometa.lines = io_lines
iometa.flush = io_flush
iometa.read = io_read
iometa.write = io_write
iometa.close = io_close
iometa.setvbuf = _luwa.iosetvbuf

function iometa:__tostring()
	_assert(io_type(self), "bad argument #1 to '__tostring'")
	return 'file (' .. _luwa.hexid(self) .. ')'
end
function iometa:seek(whence, offset)
	_assert(io_type(self), "bad argument #1 to 'seek'")
	if not _luwa.ioseekable(self) then
		return nil, 'Invalid seek'
	end
	if offset == nil then
		offset = 0
	end
	if whence == 'cur' then
		offset = offset + _luwa.iopos(self)
	elseif whence == 'end' then
		offset = offset + _luwa.iolen(self)
	elseif whence ~= 'set' then
		_error('Unexpected argument #1 to file:seek')
	end
	offset = tointeger(offset)
	if offset < 0 then
		return nil, 'Invalid argument'
	end
	_luwa.ioseek(self, offset)
	return offset
end

function os.difftime(t2, t1)
	return t2 - t1
end
function os.setlocal(locale)
	if not locale or locale == '' or locale == 'C' then
		return 'C'
	else
		return nil
	end
end

function coro_wrap_handler(t, ...)
	if t then
		return ...
	else
		return _error(...)
	end
end
function coroutine.wrap(f)
	local c = co_create(f)
	return function(...)
		return coro_wrap_handler(co_resume(c, ...))
	end
end
function coroutine.isyieldable()
	local a, b = co_running()
	return b
end

function print(...)
	for i = 1, _select('#', ...) do
		if i > 1 then
			_luwa.iowrite(stdout, '\t')
		end
		_luwa.iowrite(stdout, _tostring((_select(i, ...))))
	end
	_luwa.iowrite(stdout, '\n')
end

function pairs(t)
	local mt = _getmetatable(t)
	if not mt then
		local __pairs = mt.__pairs
		if __pairs then
			local a, b, c = __pairs(t)
			return a, b, c
		end
	end
	return _next, t, nil
end

local function inext(a, b)
	b = b + 1
	if b < 1 or b >= #a then
		return nil
	else
		return a[b], b
	end
end
function ipairs(t)
	local mt = _getmetatable(t)
	if mt then
		local __ipairs = _rawget(mt, '__ipairs')
		if __ipairs then
			local a, b, c = __ipairs(t)
			return a, b, c
		end
	end
	return inext, t, 0
end

local function xpcallguard(res, ...)
	if res then
		return ...
	else
		return 'error in error handling'
	end
end
local function xpcallcore(msgh, res, ...)
	if res then
		return true, ...
	else
		return false, xpcallguard(_pcall(msgh, ...))
	end
end
function xpcall(f, msgh, ...)
	return xpcallcore(msgh, _pcall(f, ...))
end

local fakereqtbl = {
	ast = _luwa.ast,
	bc = _luwa.bc,
	lex =  _luwa.lex,
	astgen = _luwa.astgen,
	bcgen = _luwa.bcgen,
}
local fakereqcache = {}
local fakereqenv
local function fakereq(s)
	local fs = fakereqcache[s]
	if not fs then
		fs = fakereqtbl[s](fakereqenv)
		fakereqcache[s] = fs
	end
	return fs
end
fakereqenv = {
	assert = _assert,
	error = _error,
	getmetatable = _getmetatable,
	pairs = _pairs,
	pcall = _pcall,
	require = fakereq,
	select = _select,
	setmetatable = setmetatable,
	type = type,
	coroutine = {
		wrap = coroutine.wrap,
		yield = coroutine.yield,
	},
	math = {
		type = math_type,
		max = math.max,
	},
	string = {
		byte = string.byte,
		match = string.match,
		pack = string.pack,
		unpack = string.unpack,
	},
	table = {
		sort = table.sort,
		unpack = table_unpack,
	},
}
local astgen = fakereq('astgen')
local bcgen = fakereq('bcgen')

local function _load(src, name, mode, env)
	-- TODO function names
	local lx, vals = _luwa.lexgen(src)
	if not lx then
		return nil, vals
	end
	local result, root = _pcall(astgen, lx, vals)
	if not result then
		return nil, root
	end
	-- TODO need to signal _ENV is free
	local result, bcg = _pcall(bcgen, root)
	if not result then
		return nil, bcg
	end
	local fn = _luwa.fn_new()
	_luwa.fn_set_localc(fn, #bcg.locals)
	_luwa.fn_set_paramc(fn, #bcg.params)
	_luwa.fn_set_isdotdotdot(fn, true)
	_luwa.fn_set_bc(fn, string_char(table_unpack(bcg.bc)))
	_luwa.fn_set_frees(fn, _luwa.vec_new(env or _ENV))
	_luwa.fn_set_consts(fn, _luwa.vec_new(table_unpack(bcg.consts)))
	return fn
end
loadstring = _load
load = _load
local function _loadfile(fname, mode, env)
	local file
	if not fname then
		file = io_in
	elseif _type(file) == 'string' then
		file = _assert(_luwa.ioopen(fname, 'r'))
	else
		return _error('bad argument #1 to loadfile')
	end
	local src = _luwa.ioread(file, 'a')
	_luwa.ioclose(file)
	return _load(src, fname or 'stdin', mode, env)
end

local loaded = {}
local preload = {}
local searchers = {
	function(name)
		local pre = preload[name]
		if pre then
			return pre
		end
	end,
	function(name)
		local fname, err = package.searchpath(name)
		if fname then
			return _loadfile(fname)
		else
			return nil, err
		end
	end
}
package.preload = preload
package.searchers = searchers
local function _require(modname)
	modname = _tostring(modname)
	_assert(_type(modname) == 'string', 'bad argument #1 to require')
	local lded = loaded[modname]
	if lded then
		return lded
	else
		for i=1,#searchers do
			local f, p = searchers[i](modname)
			if f then
				local ret = f(p)
				if ret == nil then
					ret = true
				end
				loaded[modname] = ret
				return ret
			end
		end
		return _error('module \'' .. modname .. '\' not found')
	end
end
require = _require

local registry = {}
function debug.getregistry()
	return registry
end

function debug.debug()
	local iowrite = _luwa.iowrite
	local ioread = _luwa.ioread
	while true do
		iowrite(stdout, 'lua_debug> ')
		local line = ioread(stdin)
		if line == 'cont' then return end
		local succ, f = _pcall(_load(line))
		if succ then
			local succ, msg = _pcall(f)
			if not succ then
				iowrite(stdout, _tostring(msg))
			end
		else
			iowrite(stdout, _tostring(f))
		end
	end
end
