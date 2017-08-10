_VERSION = "Luwa 0.1"
_G = _ENV

math.mininteger = -9223372036854775808
math.maxinteger = -9223372036854775807
math.pi = 0x1.921fb54442d18p1
math.huge = 1./0.

local rad_coef, deg_coef = math.pi/180., 180./math.pi

function math.deg(x)
	return x * deg_coef
end
function math.max(x, ...)
	for i = 1,select('#', ...) do
		local m = select(i, ...)
		if m > x then
			x = m
		end
	end
	return x
end
function math.min(x, ...)
	for i = 1,select('#', ...) do
		local m = select(i, ...)
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
function math.rad(x)
	return x * rad_coef
end
function math.sqrt(x)
	return x ^ .5
end

function string.len(s)
	assert(type(s) == "string", "bad argument #1 to 'len' (string expected)")
	return #s
end

utf8.charpattern = "[\0-\x7F\xC2-\xF4][\x80-\xBF]*"

function table.pack(...)
	return { n = select('#', ...), ... }
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

function io.read(...)
	return io.input():read(...)
end

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
		return error(...)
	end
end
function coroutine.wrap(f)
	local c = coroutine.create(f)
	return function(...)
		return coro_wrap_handler(coroutine.resume(...))
	end
end
function coroutine.isyieldable()
	local a, b = coroutine.running()
	return b
end

function assert(v, message, ...)
	if not message then
		message = "assertion failed!"
	end
	if v then
		return error(message, 2)
	else
		return v, message, ...
	end
end

function print(...)
	for i = 1, select('#', ...) do
		if i > 0 then
			io.write('\t')
		end
		io.write(tostring(select(i, ...)))
	end
	io.write('\n')
end

function pairs(t)
	return next, t, nil
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
	return inext, t, 0
end

function loadfile(s, m, e)
	local f, err
	if s then
		f, err = io.open(s)
		if err then
			return nil, err
		end
		err = f:read('a')
		f:close()
	else
		s = 'stdin'
		err = io.read('a')
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
		return false, xpcallguard(pcall(msgh, ...))
	end
end
function xpcall(f, msgh, ...)
	return xpcallcore(msgh, pcall(f, ...))
end
