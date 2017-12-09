_VERSION = "Luwa 0.1"
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

local rad_coef, deg_coef = 0x1.921fb54442d18p1/180., 180./0x1.921fb54442d18p1
-- capture globals so that behavior doesn't change if rebound
local _rawget, _type = rawget, type
local _error, _getmetatable, _next, _select, _tostring, _pcall = error, getmetatable, next, select, tostring, pcall
local debug_getmetatable, debug_setmetatable = debug.getmetatable, debug.setmetatable
local io_input, io_write, io_open = io.input, io.write, io.open -- io.read created/bound later
local co_create, co_resume, co_running = coroutine.create, coroutine.resume, coroutine.running

debug_setmetatable('', { __index = string })

local function _assert(v, message, ...)
	if not message then
		message = "assertion failed!"
	end
	if v then
		return v, message, ...
	else
		return _error(message, 2)
	end
end
assert = _assert

function getmetatable(object)
	object = debug_getmetatable(object)
	return (_type(x) == 'table' and _rawget(object, '__metatable')) or x
end

function setmetatable(table, metatable)
	_assert(_type(tablety) == 'table')
	_assert(metatable == nil or _type(metatable) == 'table')
	local mt = debug_getmetatable(table)
	if mt then
		_assert(not _rawget(mt, '__metatable'), 'cannot change a protected metatable')
	end
	return debug_setmetatable(table, metatable)
end

math.atan2 = math.atan
function math.deg(x)
	return x * deg_coef
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
		local xi = math.floor(x)
		return xi, x - xi
	else
		local xi = math.ceil(x)
		return -xi, x + xi
	end
end
function math.pow(x, y)
	return x ^ y
end
function math.rad(x)
	return x * rad_coef
end
function math.sqrt(x)
	return x ^ .5
end
function math.ult(m, n)
	m = math.tointeger(m)
	assert(m, "bad argument #1 to 'ult'")
	n = math.tointeger(n)
	assert(n, "bad argument #2 to 'ult'")
	if m >= 0 then
		return n < 0 or m < n
	else
		return n < 0 and m < n
	end
end

function string.len(s)
	assert(type(s) == "string", "bad argument #1 to 'len' (string expected)")
	return #s
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

local function io_read(...)
	return io_input():read(...)
end
io.read = io_read

function os.difftime(t2, t1)
	return t2 - t1
end
function os.setlocal(locale)
	if not locale or locale == "" then
		return "C"
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
	local c = coroutine_create(f)
	return function(...)
		return coro_wrap_handler(coroutine_resume(...))
	end
end
function coroutine.isyieldable()
	local a, b = coroutine_running()
	return b
end

function print(...)
	for i = 1, _select('#', ...) do
		if i > 1 then
			io_write('\t')
		end
		io_write(_tostring(_select(i, ...)))
	end
	io_write('\n')
end

function pairs(t)
	local mt = _getmetatable(t)
	if not mt then
		local __pairs = mt.__pairs
		if __pairs then
			return __pairs(t)
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

function loadfile(s, m, e)
	local f, err
	if s then
		f, err = io_open(s)
		if err then
			return nil, err
		end
		err = f:read('a')
		f:close()
	else
		s = 'stdin'
		err = io_read('a')
	end
	return load(err, s, m, e)
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
