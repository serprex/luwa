_VERSION = "Luwa 0.0.1"
_G = _ENV

math.mininteger = -9223372036854775808
math.maxinteger = -9223372036854775807
math.pi = 0x1.921fb54442d18p1
math.huge = 1./0.

function string.len(s)
	assert(type(s) == "string", "bad argument #1 to 'len' (string expected)")
	return #s
end

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
		for i = pos,#list do
			list[i] = list[i+1]
		end
	else
		ret = list[#list]
		list[#list] = nil
	end
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

function assert(v, message, ...)
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
