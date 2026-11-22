local push, pop = table.insert, table.remove
i32, i64, f32, f64, anyfunc, functy, void = 0x7f, 0x7e, 0x7d, 0x7c, 0x70, 0x60, 0x40
local i32, i64, f32, f64, functy, void = 0x7f, 0x7e, 0x7d, 0x7c, 0x60, 0x40
-- packed field types, only allowed as struct/array fields
local i8, i16 = 0x78, 0x77
local imptypes = { [0] = 'fid', [1] = 'tid', [2] = 'mid', [3] = 'gid' }
local modmeth = {}
local modmt = { __index = modmeth }

-- Abstract heap types. The byte is both the heap type & the short form of its nullable ref
local heap = {
	exn = 0x69,
	array = 0x6a,
	struct = 0x6b,
	i31 = 0x6c,
	eq = 0x6d,
	any = 0x6e,
	extern = 0x6f,
	func = 0x70,
	none = 0x71,
	noextern = 0x72,
	nofunc = 0x73,
	noexn = 0x74,
}
local heapname = {}
for k, v in pairs(heap) do
	heapname[v] = k
end

-- Value types: numbers for i32/i64/f32/f64, tables for refs.
-- Refs are interned, so the same ref type is always the same table & can be compared with ==
local refmt = {}
local refcache = setmetatable({}, { __mode = 'k' })
local function mkref(h, null)
	assert(heapname[h] or (type(h) == 'table' and h.isdef), 'Bad heap type')
	local c = refcache[h]
	if not c then
		c = {}
		refcache[h] = c
	end
	local k = null and 'n' or 'r'
	local r = c[k]
	if not r then
		r = setmetatable({ isref = true, heap = h, null = not not null }, refmt)
		c[k] = r
	end
	return r
end
local function ref(h)
	return mkref(h, false)
end
local function refnull(h)
	return mkref(h, true)
end

-- Bottom type, what pop gives on an unreachable stack. It matches any type
local bot = setmetatable({ isbot = true }, { __tostring = function() return 'bot' end })

local numname = { [i32] = 'i32', [i64] = 'i64', [f32] = 'f32', [f64] = 'f64', [i8] = 'i8', [i16] = 'i16' }
local function tyname(t)
	if type(t) == 'number' then
		return numname[t] or ('0x' .. ('%x'):format(t))
	elseif type(t) == 'table' and t.isref then
		local h = t.heap
		local hn = heapname[h] or (h.name and ('$' .. h.name)) or tostring(h)
		return '(ref ' .. (t.null and 'null ' or '') .. hn .. ')'
	else
		return tostring(t)
	end
end
refmt.__tostring = tyname

local function isvaltype(t)
	return t == i32 or t == i64 or t == f32 or t == f64 or (type(t) == 'table' and t.isref)
end
local function assert_isvty(ty)
	return assert(isvaltype(ty), tyname(ty))
end

-- Which abstract hierarchy a heap type belongs to
local function heaptop(h)
	if type(h) == 'table' then
		return h.kind == 'func' and heap.func or heap.any
	elseif h == heap.func or h == heap.nofunc then
		return heap.func
	elseif h == heap.extern or h == heap.noextern then
		return heap.extern
	elseif h == heap.exn or h == heap.noexn then
		return heap.exn
	else
		return heap.any
	end
end
local heapbot = { [heap.any] = heap.none, [heap.func] = heap.nofunc, [heap.extern] = heap.noextern, [heap.exn] = heap.noexn }

local function heapsub(a, b)
	if a == b then
		return true
	end
	local top = heaptop(a)
	if top ~= heaptop(b) then
		return false
	end
	if a == heapbot[top] then
		return true
	end
	if b == top then
		return true
	end
	if type(a) == 'table' then
		if type(b) == 'table' then
			local s = a.super
			while s do
				if s == b then
					return true
				end
				s = s.super
			end
			return false
		end
		-- b is abstract: eq, struct or array
		if b == heap.eq then
			return a.kind == 'struct' or a.kind == 'array'
		end
		return (a.kind == 'struct' and b == heap.struct) or (a.kind == 'array' and b == heap.array)
	end
	-- a is abstract, not bottom & not top
	if a == heap.i31 or a == heap.struct or a == heap.array then
		return b == heap.eq
	end
	return false
end

-- Is value type a a subtype of b
local function issub(a, b)
	if a == b or a == bot then
		return true
	end
	if type(a) ~= 'table' or type(b) ~= 'table' or not a.isref or not b.isref then
		return false
	end
	if a.null and not b.null then
		return false
	end
	return heapsub(a.heap, b.heap)
end

-- Packed field types read back as i32
local function unpacked(t)
	if t == i8 or t == i16 then
		return i32
	end
	return t
end

-- Defined types: struct, array, func. Make one with M.struct/M.array/M.functype.
-- Fields can be filled in later with :define, so types can refer to each other.
-- Types that refer to each other in a loop must be put in one group with M.rec
local defmeth = {}
local defmt = { __index = defmeth, __tostring = function(d) return '$' .. (d.name or d.kind) end }

local function normfield(e)
	local fe
	if type(e) == 'table' and not e.isref then
		fe = { type = e.type or e[1], mut = not not e.mut, name = e.name }
	else
		fe = { type = e, mut = false }
	end
	assert(isvaltype(fe.type) or fe.type == i8 or fe.type == i16, 'Bad field type ' .. tyname(fe.type))
	return fe
end

local function mkdef(kind, opts)
	opts = opts or {}
	local d = setmetatable({
		isdef = true,
		kind = kind,
		name = opts.name,
		super = opts.super,
		final = opts.final ~= false,
	}, defmt)
	if d.super then
		assert(d.super.kind == kind, 'Super type must be the same kind')
		assert(not d.super.final, 'Super type is final, give it final = false')
	end
	return d
end

-- fields: list of types, or { type, mut = true, name = 'x' }
function defmeth:define(fields)
	assert(self.kind ~= 'func' and not self.fields, 'Type already defined')
	if self.kind == 'array' then
		self.elem = normfield(fields)
		self.fields = { self.elem }
	else
		self.fields = {}
		self.fieldidx = {}
		for i = 1, #fields do
			local fe = normfield(fields[i])
			self.fields[i] = fe
			if fe.name then
				assert(not self.fieldidx[fe.name], fe.name)
				self.fieldidx[fe.name] = i - 1
			end
		end
	end
	return self
end

-- Field index by number (0 based) or name
function defmeth:field(x)
	assert(self.kind == 'struct', 'Not a struct')
	if type(x) == 'string' then
		x = assert(self.fieldidx[x], 'No field ' .. x)
	end
	return x, assert(self.fields[x + 1], 'No field ' .. tostring(x))
end

local function struct(fields, opts)
	local d = mkdef('struct', opts)
	if fields then
		d:define(fields)
	end
	return d
end
local function array(elem, opts)
	local d = mkdef('array', opts)
	if elem then
		d:define(elem)
	end
	return d
end

-- Results can be void, a type, or a list of types
local function resultsof(r)
	if r == nil or r == void then
		return {}
	elseif type(r) == 'table' and not r.isref and not r.isdef then
		return { table.unpack(r) }
	else
		return { r }
	end
end

local function tykey(t)
	if type(t) == 'number' then
		return tostring(t)
	end
	return tostring(t) .. '@' .. ('%p'):format(t)
end

-- Function types are interned by signature, unless opts are given
local functycache = {}
local function functype(params, results, opts)
	results = resultsof(results)
	if opts then
		local d = mkdef('func', opts)
		d.params, d.results = { table.unpack(params) }, results
		return d
	end
	local ks = {}
	for i = 1, #params do
		ks[#ks+1] = tykey(params[i])
	end
	ks[#ks+1] = '->'
	for i = 1, #results do
		ks[#ks+1] = tykey(results[i])
	end
	local k = table.concat(ks, ',')
	local d = functycache[k]
	if not d then
		d = mkdef('func')
		d.params, d.results = { table.unpack(params) }, results
		functycache[k] = d
	end
	return d
end

-- Old style signature list: params..., result (void for none). Empty list is () -> ()
local function sigtype(list)
	local n = #list
	if n == 0 then
		return functype({}, {})
	end
	return functype({ table.unpack(list, 1, n - 1) }, list[n])
end

-- Put types that refer to each other in one rec group
local function rec(...)
	local group = { ... }
	group.explicit = true
	for i = 1, #group do
		assert(not group[i].rec, 'Type already in a rec group')
		group[i].rec = group
	end
	return ...
end

local function mut(t)
	return { type = t, mut = true }
end

local function deps(d)
	local r = {}
	local function add(t)
		if type(t) == 'table' then
			if t.isref then
				t = t.heap
			end
			if type(t) == 'table' and t.isdef then
				r[#r+1] = t
			end
		end
	end
	add(d.super)
	if d.kind == 'func' then
		for i = 1, #d.params do
			add(d.params[i])
		end
		for i = 1, #d.results do
			add(d.results[i])
		end
	else
		assert(d.fields, 'Type used before :define')
		for i = 1, #d.fields do
			add(d.fields[i].type)
		end
	end
	return r
end

local function mod()
	return setmetatable({
		_type = {},
		_import = {},
		_func = {},
		_table = {},
		_memory = {},
		_global = {},
		_export = {},
		_start = nil,
		_code = {},
		_data = {},
		_declfunc = {},
		fcache = {},
		ids = {},
		dataids = {},
		typeids = {},
		typebusy = {},
		ntypes = 0,
		usesdataidx = false,
		fid = 0,
		tid = 0,
		mid = 0,
		gid = 0,
	}, modmt)
end
local function pushid(a, v)
	if a[v] then
		return a[v]
	else
		local id = #a
		a[v] = id
		a[id+1] = v
		return id
	end
end

local function encode_varint(dst, val)
	local negmask = 0
	if val < 0 then
		negmask = -1 << 57
	end
	while true do
		local b = val & 0x7f
		val = val >> 7 | negmask
		if (val == 0 and (b & 0x40) == 0) or (val == -1 and ((b & 0x40) == 0x40)) then
			dst[#dst+1] = b
			return
		else
			dst[#dst+1] = b | 0x80
		end
	end
end
local function encode_varuint(dst, val)
	assert(val >= 0)
	while true do
		local b = val & 0x7f
		val = val >> 7
		if val == 0 then
			dst[#dst+1] = b
			return
		else
			dst[#dst+1] = b | 0x80
		end
	end
end
local function encode_f32(dst, val)
	local repr = ('<f'):pack(val)
	for i = 1, 4 do
		dst[#dst+1] = repr:byte(i)
	end
end
local function encode_f64(dst, val)
	local repr = ('<d'):pack(val)
	for i = 1, 8 do
		dst[#dst+1] = repr:byte(i)
	end
end
local function encode_string(dst, str)
	encode_varuint(dst, #str)
	for i = 1, #str do
		dst[#dst+1] = str:byte(i)
	end
end
local function encode_limits(bc, sz, mxsz)
	if mxsz then
		bc[#bc+1] = 1
		encode_varuint(bc, sz)
		encode_varuint(bc, mxsz)
	else
		bc[#bc+1] = 0
		encode_varuint(bc, sz)
	end
end

local function remove_from(tbl, n)
	for i = n, #tbl do
		tbl[i] = nil
	end
end

-- Type

-- Index of a defined type. Registers it (& what it uses) the first time
function modmeth:typeidx(d)
	local idx = self.typeids[d]
	if idx then
		return idx
	end
	local group = d.rec or { d }
	assert(not self.typebusy[group], 'Types refer to each other, put them in one M.rec group')
	self.typebusy[group] = true
	local ingroup = {}
	for i = 1, #group do
		ingroup[group[i]] = true
	end
	for i = 1, #group do
		local ds = deps(group[i])
		for j = 1, #ds do
			if not ingroup[ds[j]] then
				self:typeidx(ds[j])
			end
		end
	end
	for i = 1, #group do
		self.typeids[group[i]] = self.ntypes
		self.ntypes = self.ntypes + 1
	end
	push(self._type, group)
	self.typebusy[group] = nil
	return self.typeids[d]
end

-- Old api: type index for a signature list (params..., result)
function modmeth:type(types)
	return self:typeidx(sigtype(types))
end

function modmeth:encodeheap(dst, h)
	if type(h) == 'number' then
		dst[#dst+1] = h
	else
		encode_varint(dst, self:typeidx(h))
	end
end
function modmeth:encodevt(dst, t)
	if type(t) == 'number' then
		dst[#dst+1] = t
	else
		assert(t.isref, tyname(t))
		if t.null and type(t.heap) == 'number' then
			dst[#dst+1] = t.heap
		else
			dst[#dst+1] = t.null and 0x63 or 0x64
			self:encodeheap(dst, t.heap)
		end
	end
end
function modmeth:encodevts(dst, ts)
	encode_varuint(dst, #ts)
	for i = 1, #ts do
		self:encodevt(dst, ts[i])
	end
end
function modmeth:encodefield(dst, fe)
	self:encodevt(dst, fe.type)
	dst[#dst+1] = fe.mut and 1 or 0
end
function modmeth:encodedef(dst, d)
	if not d.final or d.super then
		dst[#dst+1] = d.final and 0x4f or 0x50
		if d.super then
			dst[#dst+1] = 1
			encode_varuint(dst, self:typeidx(d.super))
		else
			dst[#dst+1] = 0
		end
	end
	if d.kind == 'func' then
		dst[#dst+1] = 0x60
		self:encodevts(dst, d.params)
		self:encodevts(dst, d.results)
	elseif d.kind == 'struct' then
		dst[#dst+1] = 0x5f
		encode_varuint(dst, #d.fields)
		for i = 1, #d.fields do
			self:encodefield(dst, d.fields[i])
		end
	else
		dst[#dst+1] = 0x5e
		self:encodefield(dst, d.elem)
	end
end

-- Block type: 0x40 for none, one value type, or a type index for anything else
function modmeth:encodeblockty(dst, params, results)
	if #params == 0 and #results == 0 then
		dst[#dst+1] = 0x40
	elseif #params == 0 and #results == 1 then
		self:encodevt(dst, results[1])
	else
		encode_varint(dst, self:typeidx(functype(params, results)))
	end
end

-- Import
function modmeth:import(imp)
	if not self.ids[imp] then
		local impty = imptypes[imp.ty]
		local id = self[impty]
		self.ids[imp] = id
		self[impty] = id + 1
		push(self._import, imp)
	end
	return self.ids[imp]
end
local function importfunc(m, f, ...)
	assert(utf8.len(m) and utf8.len(f), "Non utf8 function import")
	return { m = m, f = f, ty = 0, ... }
end
local function importtable(m, f, elety, sz, mxsz)
	assert(utf8.len(m) and utf8.len(f), "Non utf8 table import")
	return { m = m, f = f, ty = 1, elety = elety, sz = sz, mxsz = mxsz }
end
local function importmemory(m, f, sz, mxsz)
	assert(utf8.len(m) and utf8.len(f), "Non utf8 memory import")
	return { m = m, f = f, ty = 2, sz = sz, mxsz = mxsz }
end
local function nztrue(x)
	if not x or x == 0 then
		return 0
	else
		return 1
	end
end
local function importglobal(m, f, ty, mut)
	assert(utf8.len(m) and utf8.len(f), "Non utf8 global import")
	return { m = m, f = f, ty = 3, type = ty, mut = nztrue(mut) }
end

-- Function
local funcmeta = {}
local funcmt = { __index = funcmeta }

-- params & results of something callable: a func, an imported func, or a func type
local function callsig(f)
	if f.isfunc then
		return f.params, f.results
	elseif f.isdef then
		assert(f.kind == 'func')
		return f.params, f.results
	else
		local d = sigtype(f)
		return d.params, d.results
	end
end

function funcmeta:prstack()
	local s = {}
	for i = 1, #self.stack do
		s[i] = tyname(self.stack[i])
	end
	return print(table.concat(s, ", "))
end

function funcmeta:emit(val)
	self.bcode[#self.bcode+1] = val
end
function funcmeta:emitint(val)
	return encode_varint(self.bcode, val)
end
function funcmeta:emituint(val)
	return encode_varuint(self.bcode, val)
end
function funcmeta:emitheap(h)
	return self.mod:encodeheap(self.bcode, h)
end
function funcmeta:emitvt(t)
	return self.mod:encodevt(self.bcode, t)
end
function funcmeta:emittype(d)
	return self:emituint(self.mod:typeidx(d))
end

function funcmeta:push(ty)
	assert(isvaltype(ty) or ty == bot, tyname(ty))
	self.stack[#self.stack+1] = ty
end
-- Type n below the top, 0 is the top
function funcmeta:peekn(n)
	local sc = self.scopes[self.scope]
	local i = #self.stack - n
	if i <= sc.min then
		assert(sc.poly, 'Stack underflow')
		return bot
	end
	return self.stack[i]
end
function funcmeta:peek()
	return self:peekn(0)
end
function funcmeta:pop()
	local r = self:peek()
	if #self.stack > self.scopes[self.scope].min then
		self.stack[#self.stack] = nil
	end
	return r
end
-- Pop a value that must be a subtype of ty
function funcmeta:popt(ty)
	local r = self:pop()
	if not issub(r, ty) then
		self:prstack()
		error('Expected ' .. tyname(ty) .. ', got ' .. tyname(r))
	end
	return r
end
-- Pop a ref, returns its type
function funcmeta:popref()
	local r = self:pop()
	assert(r == bot or (type(r) == 'table' and r.isref), 'Expected a ref, got ' .. tyname(r))
	return r
end
-- Check the top of the stack matches tys, without popping
function funcmeta:checktop(tys)
	local n = #tys
	for i = 1, n do
		local t = self:peekn(n - i)
		if not issub(t, tys[i]) then
			self:prstack()
			error('Expected ' .. tyname(tys[i]) .. ', got ' .. tyname(t))
		end
	end
end
-- Pop tys off the stack, last first
function funcmeta:popts(tys)
	for i = #tys, 1, -1 do
		self:popt(tys[i])
	end
end
function funcmeta:pushts(tys)
	for i = 1, #tys do
		self:push(tys[i])
	end
end
-- After br/ret/unreachable the stack can be anything: drop what's on it down to
-- the scope's base, popping past that gives bot
function funcmeta:unreach()
	local sc = self.scopes[self.scope]
	sc.poly = true
	remove_from(self.stack, sc.min + 1)
end

-- kind is 'func', 'block', 'loop' or 'if'. params must be on the stack already
function funcmeta:pushscope(kind, params, results)
	self:checktop(params)
	local min = #self.stack - #params
	for i = 1, #params do
		self.stack[min + i] = params[i]
	end
	self.scope = self.scope + 1
	self.scopes[self.scope] = {
		kind = kind,
		params = params,
		results = results,
		min = min,
		poly = false,
	}
end
function funcmeta:popscope()
	local sc = self.scopes[self.scope]
	self:checktop(sc.results)
	if not sc.poly then
		assert(#self.stack == sc.min + #sc.results, #sc.results == 0 and 'Unexpected stack leftovers' or 'Wrong number of results on stack')
	end
	remove_from(self.stack, sc.min + 1)
	self.scopes[self.scope] = nil
	self.scope = self.scope - 1
	self:pushts(sc.results)
end

-- Types a branch to this scope carries: loops take params, others results
function funcmeta:labeltypes(scp)
	local sc = self.scopes[scp]
	if sc.kind == 'loop' then
		return sc.params
	end
	return sc.results
end

function funcmeta:labelidx(scp)
	if scp == self then
		scp = 1
	end
	assert(scp > 0 and scp <= self.scope, 'Bad scope')
	return scp
end
function funcmeta:emitscope(scp)
	scp = self:labelidx(scp)
	self:checktop(self:labeltypes(scp))
	return encode_varuint(self.bcode, self.scope - scp)
end

function funcmeta:params(...)
	assert(#self.localty == 0)
	self.localty = {...}
	self.pcount = #self.localty
	local ret = {}
	for i = 1, self.pcount do
		ret[i] = i
	end
	return table.unpack(ret)
end
function funcmeta:locals(lty, n)
	assert_isvty(lty)
	if not n then
		n = 1
	end
	local ret = {}
	for i=1,n do
		self.localty[#self.localty+1] = lty
		ret[i] = #self.localty
	end
	self.localbcn = self.localbcn + 1
	encode_varuint(self.localbc, n)
	self.mod:encodevt(self.localbc, lty)
	return table.unpack(ret)
end

local function mkconstop(name, ty, op, encoder)
	funcmeta[name] = function(self, x)
		assert(x)
		self:emit(op)
		encoder(self.bcode, x)
		self:push(ty)
	end
end
mkconstop('i32', i32, 0x41, encode_varint)
mkconstop('i64', i64, 0x42, encode_varint)
mkconstop('f32', f32, 0x43, encode_f32)
mkconstop('f64', f64, 0x44, encode_f64)

function funcmeta:unreachable()
	self:emit(0x00)
	self:unreach()
end
function funcmeta:nop()
	self:emit(0x01)
end

-- Block type args: nothing, a value type, a list of result types,
-- or a func type (its params are taken from the stack)
local function blocksig(ty)
	if ty == nil or ty == void then
		return {}, {}
	elseif type(ty) == 'table' and ty.isdef then
		assert(ty.kind == 'func', 'Block type must be a func type')
		return ty.params, ty.results
	else
		return {}, resultsof(ty)
	end
end
local function blockargs(ty, ...)
	if type(ty) == 'function' then
		return nil, ty, ...
	end
	return ty, ...
end

function funcmeta:emitblockty(params, results)
	return self.mod:encodeblockty(self.bcode, params, results)
end

function funcmeta:block(...)
	local ty, block = blockargs(...)
	local params, results = blocksig(ty)
	self:emit(0x02)
	self:emitblockty(params, results)
	self:pushscope('block', params, results)
	block(self.scope)
	self:popscope()
	self:emit(0x0b)
end
function funcmeta:loop(...)
	local ty, block = blockargs(...)
	local params, results = blocksig(ty)
	self:emit(0x03)
	self:emitblockty(params, results)
	self:pushscope('loop', params, results)
	block(self.scope)
	self:popscope()
	self:emit(0x0b)
end
function funcmeta:load(x)
	self:emit(0x20)
	self:emituint(x-1)
	self:push(self.localty[x])
end
function funcmeta:store(x)
	self:emit(0x21)
	self:emituint(x-1)
	self:popt(self.localty[x])
end
function funcmeta:tee(x)
	self:emit(0x22)
	self:emituint(x-1)
	self:popt(self.localty[x])
	self:push(self.localty[x])
end
function funcmeta:loadg(x)
	self:emit(0x23)
	self:emituint(self.mod:global(x))
	self:push(x.type)
end
function funcmeta:storeg(x)
	assert(x.mut == 1 or x.mut == true)
	self:emit(0x24)
	self:emituint(self.mod:global(x))
	self:popt(x.type)
end
function funcmeta:drop()
	self:emit(0x1a)
	self:pop()
end
-- ty is needed when selecting refs, it's inferred when the operands are refs
function funcmeta:select(ty)
	self:popt(i32)
	local a = self:pop()
	local b = self:pop()
	if not ty then
		ty = a == bot and b or a
	end
	if type(ty) == 'table' and ty.isref then
		assert(issub(a, ty) and issub(b, ty), 'select operand type mismatch')
		self:emit(0x1c)
		self:emit(1)
		self:emitvt(ty)
	else
		assert(a == b or a == bot or b == bot, 'select operand type mismatch')
		self:emit(0x1b)
	end
	self:push(ty)
end
function funcmeta:iff(...)
	local ty, brif, brelse = blockargs(...)
	local params, results = blocksig(ty)
	self:popt(i32)
	self:emit(0x04)
	self:emitblockty(params, results)
	assert(brelse or #params == #results, 'if without else must not change the stack')
	self:pushscope('if', params, results)
	brif(self.scope)
	self:popscope()

	if brelse then
		for i = 1, #results do
			self:pop()
		end
		self:pushts(params)
		self:emit(0x05)
		self:pushscope('if', params, results)
		brelse(self.scope)
		self:popscope()
	end
	self:emit(0x0b)
end

function funcmeta:br(scope)
	self:emit(0x0c)
	self:emitscope(scope)
	self:unreach()
end
function funcmeta:brif(scope)
	self:popt(i32)
	self:emit(0x0d)
	local scp = self:labelidx(scope)
	self:emitscope(scp)
	-- values left behind are typed as the label's types
	local tys = self:labeltypes(scp)
	for i = 1, #tys do
		self:pop()
	end
	self:pushts(tys)
end
function funcmeta:brtable(...)
	self:popt(i32)
	self:emit(0x0e)
	local scopes = {...}
	assert(#scopes > 0)
	while #scopes > 1 and scopes[#scopes] == scopes[#scopes-1] do
		scopes[#scopes] = nil
	end
	self:emituint(#scopes-1)
	local arity
	for i = 1, #scopes do
		local scp = self:labelidx(assert(scopes[i], i))
		local n = #self:labeltypes(scp)
		assert(not arity or arity == n, 'br_table targets differ in arity')
		arity = n
		self:emitscope(scp)
	end
	self:unreach()
end
function funcmeta:ret()
	self:checktop(self.fn.results)
	self:emit(0x0f)
	self:unreach()
end
function funcmeta:currentmemory()
	self:emit(0x3f)
	self:emit(0)
	self:push(i32)
end
function funcmeta:growmemory()
	assert(self:peek() == i32)
	self:emit(0x40)
	self:emit(0)
end
-- memory.copy: dst, src, len
function funcmeta:memcopy()
	self:popt(i32)
	self:popt(i32)
	self:popt(i32)
	self:emit(0xfc)
	self:emituint(10)
	self:emit(0)
	self:emit(0)
end
-- memory.fill: dst, byte, len
function funcmeta:memfill()
	self:popt(i32)
	self:popt(i32)
	self:popt(i32)
	self:emit(0xfc)
	self:emituint(11)
	self:emit(0)
end

function funcmeta:switch(expr, ...)
	local scames = {}
	local scopes = {}
	local maxsc = 0
	local function setscope(x, scp)
		assert(not scames[x])
		scames[x] = scp
		if type(x) == 'number' and x >= 0 then
			x = x+1
			scopes[x] = scp
			if x > maxsc then
				maxsc = x
			end
		end
	end
	local function jmp()
		expr(scames)
		local scdef = scames[-1]
		if scdef then
			for i=1,maxsc do
				if not scopes[i] then
					scopes[i] = scdef
				end
			end
			-- br_table's last target is the default, for values past the last case
			scopes[maxsc+1] = scdef
		else
			-- no default: the last case also takes values past it
			assert(maxsc > 0 and #scopes == maxsc)
		end
		return self:brtable(table.unpack(scopes))
	end
	for idx=1,select('#', ...) do
		local x = assert(select(idx, ...), idx)
		local xt, oldj = type(x), jmp
		if xt == 'function' then
			function jmp(scp)
				self:block(oldj)
				return x(scames)
			end
		elseif xt == 'table' then
			function jmp(scp)
				local lastx = assert(x[#x])
				for i=1,#x-1 do
					setscope(x[i], lastx)
				end
				return oldj(scp)
			end
		else
			function jmp(scp)
				setscope(x, scp)
				return oldj(scp)
			end
		end
	end
	return self:block(jmp)
end

local function mkopcore(self, name, tymap, a, tyret)
	if tymap[a] then
		self:emit(tymap[a])
		if tyret then
			self:push(tyret)
		else
			self:push(a)
		end
	else
		return error(name .. ' not implemented for ' .. tyname(a))
	end
end
local function mkunop(name, tymap, tyret)
	funcmeta[name] = function(self)
		local a = self:pop()
		assert(a ~= bot, name .. ' on unreachable stack needs a known type')
		return mkopcore(self, name, tymap, a, tyret)
	end
end
local function mkbinop(name, tymap, tyret)
	funcmeta[name] = function(self)
		local a = self:pop()
		local b = self:pop()
		if a == bot then
			a = b
		elseif b == bot then
			b = a
		end
		if a ~= b then
			print(tyname(b), tyname(a))
			return error('Type mismatch')
		end
		assert(a ~= bot, name .. ' on unreachable stack needs a known type')
		return mkopcore(self, name, tymap, a, tyret)
	end
end
mkunop('eqz', { [i32] = 0x45, [i64] = 0x50 }, i32)
mkbinop('eq', { [i32] = 0x46, [i64] = 0x51, [f32] = 0x5b, [f64] = 0x61 }, i32)
mkbinop('ne', { [i32] = 0x47, [i64] = 0x52, [f32] = 0x5c, [f64] = 0x62 }, i32)
mkbinop('lts', { [i32] = 0x48, [i64] = 0x53 }, i32)
mkbinop('ltu', { [i32] = 0x49, [i64] = 0x54 }, i32)
mkbinop('gts', { [i32] = 0x4a, [i64] = 0x55 }, i32)
mkbinop('gtu', { [i32] = 0x4b, [i64] = 0x56 }, i32)
mkbinop('les', { [i32] = 0x4c, [i64] = 0x57 }, i32)
mkbinop('leu', { [i32] = 0x4d, [i64] = 0x58 }, i32)
mkbinop('ges', { [i32] = 0x4e, [i64] = 0x59 }, i32)
mkbinop('geu', { [i32] = 0x4f, [i64] = 0x5a }, i32)
mkbinop('lt', { [f32] = 0x5d, [f64] = 0x63 }, i32)
mkbinop('gt', { [f32] = 0x5e, [f64] = 0x64 }, i32)
mkbinop('le', { [f32] = 0x5f, [f64] = 0x65 }, i32)
mkbinop('ge', { [f32] = 0x60, [f64] = 0x66 }, i32)
mkunop('clz', { [i32] = 0x67, [i64] = 0x79 })
mkunop('ctz', { [i32] = 0x68, [i64] = 0x7a })
mkunop('popcnt', { [i32] = 0x69, [i64] = 0x7b })
mkbinop('add', { [i32] = 0x6a, [i64] = 0x7c, [f32] = 0x92, [f64] = 0xa0 })
mkbinop('sub', { [i32] = 0x6b, [i64] = 0x7d, [f32] = 0x93, [f64] = 0xa1 })
mkbinop('mul', { [i32] = 0x6c, [i64] = 0x7e, [f32] = 0x94, [f64] = 0xa2 })
mkbinop('divs', { [i32] = 0x6d, [i64] = 0x7f })
mkbinop('divu', { [i32] = 0x6e, [i64] = 0x80 })
mkbinop('rems', { [i32] = 0x6f, [i64] = 0x81 })
mkbinop('remu', { [i32] = 0x70, [i64] = 0x82 })
mkbinop('band', { [i32] = 0x71, [i64] = 0x83 })
mkbinop('bor', { [i32] = 0x72, [i64] = 0x84 })
mkbinop('xor', { [i32] = 0x73, [i64] = 0x85 })
mkbinop('shl', { [i32] = 0x74, [i64] = 0x86 })
mkbinop('shrs', { [i32] = 0x75, [i64] = 0x87 })
mkbinop('shru', { [i32] = 0x76, [i64] = 0x88 })
mkbinop('rotl', { [i32] = 0x77, [i64] = 0x89 })
mkbinop('rotr', { [i32] = 0x78, [i64] = 0x8a })
mkunop('abs', { [f32] = 0x8b, [f64] = 0x99 })
mkunop('neg', { [f32] = 0x8c, [f64] = 0x9a })
mkunop('ceil', { [f32] = 0x8d, [f64] = 0x9b })
mkunop('floor', { [f32] = 0x8e, [f64] = 0x9c })
mkunop('trunc', { [f32] = 0x8f, [f64] = 0x9d })
mkunop('nearest', { [f32] = 0x90, [f64] = 0x9e })
mkunop('sqrt', { [f32] = 0x91, [f64] = 0x9f })
mkbinop('div', { [f32] = 0x95, [f64] = 0xa3 })
mkbinop('min', { [f32] = 0x96, [f64] = 0xa4 })
mkbinop('max', { [f32] = 0x97, [f64] = 0xa5 })
mkbinop('copysign', { [f32] = 0x98, [f64] = 0xa6 })
mkunop('i32wrap', { [i64] = 0xa7 }, i32)
mkunop('i32truncs', { [f32] = 0xa8, [f64] = 0xaa }, i32)
mkunop('i32truncu', { [f32] = 0xa9, [f64] = 0xab }, i32)
mkunop('i64extends', { [i32] = 0xac }, i64)
mkunop('i64extendu', { [i32] = 0xad }, i64)
mkunop('i64truncs', { [f32] = 0xae, [f64] = 0xb0 }, i64)
mkunop('i64truncu', { [f32] = 0xaf, [f64] = 0xb1 }, i64)
mkunop('f32converts', { [i32] = 0xb2, [i64] = 0xb4 }, f32)
mkunop('f32convertu', { [i32] = 0xb3, [i64] = 0xb5 }, f32)
mkunop('f32demote', { [f64] = 0xb6 }, f32)
mkunop('f64converts', { [i32] = 0xb7, [i64] = 0xb9 }, f64)
mkunop('f64convertu', { [i32] = 0xb8, [i64] = 0xba }, f64)
mkunop('f64promote', { [f32] = 0xbb }, f64)
mkunop('i32reinterpret', { [f32] = 0xbc }, i32)
mkunop('i64reinterpret', { [f64] = 0xbd }, i64)
mkunop('f32reinterpret', { [i32] = 0xbe }, f32)
mkunop('f64reinterpret', { [i64] = 0xbf }, f64)

local function mkstoreop(name, opcode, ty)
	funcmeta[name] = function(self, off, flags)
		if not off then
			off = 0
		end
		if not flags then
			flags = 0
		end
		self:popt(ty)
		self:popt(i32)
		self:emit(opcode)
		self:emituint(flags)
		self:emituint(off)
	end
end
local function mkloadop(name, opcode, ty)
	funcmeta[name] = function(self, off, flags)
		if not off then
			off = 0
		end
		if not flags then
			flags = 0
		end
		self:popt(i32)
		self:emit(opcode)
		self:emituint(flags)
		self:emituint(off)
		self:push(ty)
	end
end
mkloadop('i32load', 0x28, i32)
mkloadop('i64load', 0x29, i64)
mkloadop('f32load', 0x2a, f32)
mkloadop('f64load', 0x2b, f64)
mkloadop('i32load8s', 0x2c, i32)
mkloadop('i32load8u', 0x2d, i32)
mkloadop('i32load16s', 0x2e, i32)
mkloadop('i32load16u', 0x2f, i32)
mkloadop('i64load8s', 0x30, i64)
mkloadop('i64load8u', 0x31, i64)
mkloadop('i64load16s', 0x32, i64)
mkloadop('i64load16u', 0x33, i64)
mkloadop('i64load32s', 0x34, i64)
mkloadop('i64load32u', 0x35, i64)
mkstoreop('i32store', 0x36, i32)
mkstoreop('i64store', 0x37, i64)
mkstoreop('f32store', 0x38, f32)
mkstoreop('f64store', 0x39, f64)
mkstoreop('i32store8', 0x3a, i32)
mkstoreop('i32store16', 0x3b, i32)
mkstoreop('i64store8', 0x3c, i64)
mkstoreop('i64store16', 0x3d, i64)
mkstoreop('i64store32', 0x3e, i64)

function funcmeta:funcidx(f)
	if f.isfunc then
		return self.mod:func(f)
	else
		return self.mod:import(f)
	end
end

function funcmeta:call(f)
	local params, results = callsig(f)
	self:emit(0x10)
	self:emituint(self:funcidx(f))
	self:popts(params)
	self:pushts(results)
end
-- Tail call. Callee's results must fit this function's results
function funcmeta:retcall(f)
	local params, results = callsig(f)
	self:emit(0x12)
	self:emituint(self:funcidx(f))
	self:popts(params)
	self:pushts(results)
	self:checktop(self.fn.results)
	self:unreach()
end
-- call_ref: params..., (ref null fty)
function funcmeta:callref(fty)
	assert(fty.isdef and fty.kind == 'func')
	self:popt(refnull(fty))
	self:emit(0x14)
	self:emittype(fty)
	self:popts(fty.params)
	self:pushts(fty.results)
end
function funcmeta:retcallref(fty)
	assert(fty.isdef and fty.kind == 'func')
	self:popt(refnull(fty))
	self:emit(0x15)
	self:emittype(fty)
	self:popts(fty.params)
	self:pushts(fty.results)
	self:checktop(self.fn.results)
	self:unreach()
end

-- References

function funcmeta:refnull(h)
	self:emit(0xd0)
	self:emitheap(h)
	self:push(refnull(h))
end
function funcmeta:refisnull()
	self:popref()
	self:emit(0xd1)
	self:push(i32)
end
-- ref.func: pushes (ref $fty) of a func. The func gets declared in the elem section
function funcmeta:reffunc(f)
	local idx = self:funcidx(f)
	self.mod:declfunc(idx)
	self:emit(0xd2)
	self:emituint(idx)
	local params, results = callsig(f)
	self:push(ref(functype(params, results)))
end
function funcmeta:refeq()
	self:popt(refnull(heap.eq))
	self:popt(refnull(heap.eq))
	self:emit(0xd3)
	self:push(i32)
end
function funcmeta:refasnonnull()
	local r = self:popref()
	self:emit(0xd4)
	self:push(r == bot and bot or ref(r.heap))
end
-- br_on_null: branch if null, otherwise leave the ref as non null
function funcmeta:bronnull(scope)
	local r = self:popref()
	self:emit(0xd5)
	self:emitscope(scope)
	self:push(r == bot and bot or ref(r.heap))
end
-- br_on_non_null: branch with the non null ref, otherwise continue without it
function funcmeta:bronnonnull(scope)
	local r = self:popref()
	self:push(r == bot and bot or ref(r.heap))
	self:emit(0xd6)
	self:emitscope(scope)
	self:pop()
end

local function gcop(self, n)
	self:emit(0xfb)
	self:emituint(n)
end

-- ref.test & ref.cast to rt. Nullable rt lets null pass
function funcmeta:reftest(rt)
	self:popref()
	gcop(self, rt.null and 21 or 20)
	self:emitheap(rt.heap)
	self:push(i32)
end
function funcmeta:refcast(rt)
	self:popref()
	gcop(self, rt.null and 23 or 22)
	self:emitheap(rt.heap)
	self:push(rt)
end
-- What is left of rt1 when rt2 fails to match
local function refdiff(rt1, rt2)
	if rt2.null then
		return ref(rt1.heap)
	end
	return rt1
end
local function castflags(rt1, rt2)
	return (rt1.null and 1 or 0) | (rt2.null and 2 or 0)
end
-- br_on_cast: ref of type rt1 on the stack. Branch with it as rt2 if it is one
function funcmeta:broncast(scope, rt1, rt2)
	assert(issub(rt2, rt1), 'br_on_cast target must be a subtype of the source')
	self:popt(rt1)
	gcop(self, 24)
	self:emit(castflags(rt1, rt2))
	self:push(rt2)
	self:emitscope(scope)
	self:pop()
	self:emitheap(rt1.heap)
	self:emitheap(rt2.heap)
	self:push(refdiff(rt1, rt2))
end
-- br_on_cast_fail: branch if it's not an rt2, otherwise continue with it as rt2
function funcmeta:broncastfail(scope, rt1, rt2)
	assert(issub(rt2, rt1), 'br_on_cast_fail target must be a subtype of the source')
	self:popt(rt1)
	gcop(self, 25)
	self:emit(castflags(rt1, rt2))
	self:push(refdiff(rt1, rt2))
	self:emitscope(scope)
	self:pop()
	self:emitheap(rt1.heap)
	self:emitheap(rt2.heap)
	self:push(rt2)
end

function funcmeta:anyconvertextern()
	local r = self:popt(refnull(heap.extern))
	gcop(self, 26)
	self:push(mkref(heap.any, r == bot or r.null))
end
function funcmeta:externconvertany()
	local r = self:popt(refnull(heap.any))
	gcop(self, 27)
	self:push(mkref(heap.extern, r == bot or r.null))
end

function funcmeta:refi31()
	self:popt(i32)
	gcop(self, 28)
	self:push(ref(heap.i31))
end
function funcmeta:i31gets()
	self:popt(refnull(heap.i31))
	gcop(self, 29)
	self:push(i32)
end
function funcmeta:i31getu()
	self:popt(refnull(heap.i31))
	gcop(self, 30)
	self:push(i32)
end

-- Structs

local function isstruct(t)
	assert(type(t) == 'table' and t.isdef and t.kind == 'struct', 'Not a struct type')
	return t
end
local function isarray(t)
	assert(type(t) == 'table' and t.isdef and t.kind == 'array', 'Not an array type')
	return t
end

-- struct.new: field values in order on the stack
function funcmeta:structnew(t)
	isstruct(t)
	for i = #t.fields, 1, -1 do
		self:popt(unpacked(t.fields[i].type))
	end
	gcop(self, 0)
	self:emittype(t)
	self:push(ref(t))
end
function funcmeta:structnewdefault(t)
	isstruct(t)
	gcop(self, 1)
	self:emittype(t)
	self:push(ref(t))
end
-- field is a 0 based index or a name. Packed fields need signed = true or false
function funcmeta:structget(t, field, signed)
	isstruct(t)
	local idx, fe = t:field(field)
	self:popt(refnull(t))
	if fe.type == i8 or fe.type == i16 then
		assert(signed ~= nil, 'Packed field needs signed or unsigned get')
		gcop(self, signed and 3 or 4)
	else
		assert(signed == nil, 'Only packed fields are signed or unsigned')
		gcop(self, 2)
	end
	self:emittype(t)
	self:emituint(idx)
	self:push(unpacked(fe.type))
end
-- struct.set: ref, value
function funcmeta:structset(t, field)
	isstruct(t)
	local idx, fe = t:field(field)
	assert(fe.mut, 'Field is immutable')
	self:popt(unpacked(fe.type))
	self:popt(refnull(t))
	gcop(self, 5)
	self:emittype(t)
	self:emituint(idx)
end

-- Arrays

-- array.new: init value, length
function funcmeta:arraynew(t)
	isarray(t)
	self:popt(i32)
	self:popt(unpacked(t.elem.type))
	gcop(self, 6)
	self:emittype(t)
	self:push(ref(t))
end
function funcmeta:arraynewdefault(t)
	isarray(t)
	self:popt(i32)
	gcop(self, 7)
	self:emittype(t)
	self:push(ref(t))
end
-- array.new_fixed: n values on the stack
function funcmeta:arraynewfixed(t, n)
	isarray(t)
	for i = 1, n do
		self:popt(unpacked(t.elem.type))
	end
	gcop(self, 8)
	self:emittype(t)
	self:emituint(n)
	self:push(ref(t))
end
-- array.new_data: offset, length. d is a passive data segment
function funcmeta:arraynewdata(t, d)
	isarray(t)
	self:popt(i32)
	self:popt(i32)
	gcop(self, 9)
	self:emittype(t)
	self:emituint(self.mod:dataidx(d))
	self:push(ref(t))
end
-- array.get: ref, index
function funcmeta:arrayget(t, signed)
	isarray(t)
	self:popt(i32)
	self:popt(refnull(t))
	local et = t.elem.type
	if et == i8 or et == i16 then
		assert(signed ~= nil, 'Packed array needs signed or unsigned get')
		gcop(self, signed and 12 or 13)
	else
		assert(signed == nil, 'Only packed arrays are signed or unsigned')
		gcop(self, 11)
	end
	self:emittype(t)
	self:push(unpacked(et))
end
-- array.set: ref, index, value
function funcmeta:arrayset(t)
	isarray(t)
	assert(t.elem.mut, 'Array is immutable')
	self:popt(unpacked(t.elem.type))
	self:popt(i32)
	self:popt(refnull(t))
	gcop(self, 14)
	self:emittype(t)
end
function funcmeta:arraylen()
	self:popt(refnull(heap.array))
	gcop(self, 15)
	self:push(i32)
end
-- array.fill: ref, offset, value, length
function funcmeta:arrayfill(t)
	isarray(t)
	assert(t.elem.mut, 'Array is immutable')
	self:popt(i32)
	self:popt(unpacked(t.elem.type))
	self:popt(i32)
	self:popt(refnull(t))
	gcop(self, 16)
	self:emittype(t)
end
-- array.copy: dst ref, dst offset, src ref, src offset, length
function funcmeta:arraycopy(dst, src)
	isarray(dst)
	isarray(src)
	assert(dst.elem.mut, 'Array is immutable')
	self:popt(i32)
	self:popt(i32)
	self:popt(refnull(src))
	self:popt(i32)
	self:popt(refnull(dst))
	gcop(self, 17)
	self:emittype(dst)
	self:emittype(src)
end
-- array.init_data: ref, dst offset, src offset, length
function funcmeta:arrayinitdata(t, d)
	isarray(t)
	assert(t.elem.mut, 'Array is immutable')
	self:popt(i32)
	self:popt(i32)
	self:popt(i32)
	self:popt(refnull(t))
	gcop(self, 18)
	self:emittype(t)
	self:emituint(self.mod:dataidx(d))
end

local function newbuilder(m, fn, params, results)
	local fb = setmetatable({
		mod = m,
		fn = fn,
		localty = params,
		localbc = {},
		localbcn = 0,
		pcount = #params,
		bcode = {},
		stack = {},
		scope = 0,
		scopes = {},
	}, funcmt)
	fb:pushscope('func', {}, results)
	return fb
end

function modmeth:func(f)
	if self.fcache[f] then
		return self.fcache[f]
	end
	local params = {table.unpack(f.params)}
	local fb = newbuilder(self, f, params, f.results)
	local id = pushid(self._func, fb) + self.fid
	self.fcache[f] = id
	self:type(f.fty)
	local ps = {}
	for i=1, #params do
		ps[i] = i
	end
	f.bgen(fb, table.unpack(ps))
	fb:popscope()
	return id
end

-- func(params..., result, body). result can be void, a type, or a list of types
local function func(...)
	local rety
	local params, fty = {}, {}
	local n = select('#', ...)
	local bgen = select(n, ...)
	if n == 1 then
		rety = void
	else
		rety = select(n-1, ...)
		for i=1, n-2 do
			local t = select(i, ...)
			params[i] = t
			fty[i] = t
		end
	end
	if not bgen then
		bgen = rety
		rety = void
	end
	fty[#fty+1] = rety
	return {
		isfunc = true,
		rety = rety,
		results = resultsof(rety),
		fty = fty,
		params = params,
		bgen = bgen,
	}
end

-- Functions used by ref.func must be declared in an elem segment
function modmeth:declfunc(idx)
	if not self._declfunc[idx] then
		self._declfunc[idx] = true
		push(self._declfunc, idx)
	end
end

-- Table

function modmeth:table(elems)
	pushid(self._table, elems)
end

-- Memory

function modmeth:memory(mem)
	return pushid(self._memory, mem) + self.mid
end

local function memory(sz, mxsz)
	return { sz = sz, mxsz = mxsz }
end

-- Global

function modmeth:global(globe)
	return pushid(self._global, globe) + self.gid
end

-- init: a number, another immutable global, or function(f) building a constant expression.
-- Nullable refs default to ref.null
local function global(ty, mut, init)
	assert_isvty(ty)
	if init == nil then
		if type(ty) == 'table' then
			assert(ty.null, 'Non null ref global needs an init')
			local h = ty.heap
			init = function(f)
				f:refnull(h)
			end
		else
			init = 0
		end
	end
	return { type = ty, mut = nztrue(mut), init = init }
end

-- Export

function modmeth:export(name, obj)
	assert(type(name) == 'string')
	assert(utf8.len(name), "Non utf8 export")
	local kind
	if obj.isfunc then
		kind = 0
	elseif obj.istable then
		kind = 1
	elseif obj.ismem then
		kind = 2
	else
		kind = 3
	end
	push(self._export, { f = name, obj = obj, kind = kind })
	return obj
end

-- Start

function modmeth:start(fu)
	assert(not self._start and #fu.params == 0 and #fu.results == 0)
	self._start = fu
	return fu
end

-- Data

function modmeth:data(data)
	if not self.dataids[data] then
		self.dataids[data] = #self._data
		push(self._data, data)
	end
end
-- Index of a data segment used by an instruction. Needs the data count section
function modmeth:dataidx(data)
	self:data(data)
	self.usesdataidx = true
	return self.dataids[data]
end

local function data(mem, offexpr, data)
	return { mem = mem, offexpr = offexpr, data = data }
end
-- Data only used by instructions (array.new_data, array.init_data)
local function passivedata(data)
	return { passive = true, data = data }
end

-- Main

local function writeSection(chunks, id, bc)
	local header = {id}
	encode_varuint(header, #bc)
	chunks[#chunks+1] = string.char(table.unpack(header))
	local n, nn, nbc = 1, 4096, #bc
	while n <= nbc do
		if nn > nbc then
			nn = nbc
		end
		chunks[#chunks+1] = string.char(table.unpack(bc, n, nn))
		n = nn + 1
		nn = nn + 4096
	end
end
-- Sections are written even when empty, as the old encoder did, so output stays byte for byte the same
local function loopSection(elems, bcfu)
	local bc = {}
	encode_varuint(bc, #elems)
	for i = 1, #elems do
		bcfu(bc, elems[i])
	end
	return bc
end

function modmeth:constexpr(bc, ty, init)
	if type(init) == 'number' then
		if ty == i32 then
			bc[#bc+1] = 0x41
			encode_varint(bc, init)
		elseif ty == i64 then
			bc[#bc+1] = 0x42
			encode_varint(bc, init)
		elseif ty == f32 then
			bc[#bc+1] = 0x43
			encode_f32(bc, init)
		elseif ty == f64 then
			bc[#bc+1] = 0x44
			encode_f64(bc, init)
		else
			error('Unknown type: ' .. tyname(ty))
		end
	elseif type(init) == 'function' then
		local fb = newbuilder(self, { results = { ty } }, {}, { ty })
		init(fb)
		fb:popscope()
		for i = 1, #fb.bcode do
			bc[#bc+1] = fb.bcode[i]
		end
	else
		assert(init.mut == 0)
		assert(issub(init.type, ty))
		bc[#bc+1] = 0x23
		encode_varuint(bc, self:global(init))
	end
	bc[#bc+1] = 0x0b
end

function modmeth:compile()
	local chunks = {"\0asm\1\0\0\0"}

	for i=1, #self._import do
		local imp = self._import[i]
		if imp.ty == 0 then
			self:type(imp)
		end
	end
	for i=1, #self._export do
		local exp = self._export[i]
		if exp.kind == 0 then
			self:func(exp.obj)
		end
	end
	if self._start then
		self:func(self._start)
	end

	-- Every section but types is built first, since building them can add types
	local sec = {}

	sec[2] = loopSection(self._import, function(bc, imp)
		encode_string(bc, imp.m)
		encode_string(bc, imp.f)
		bc[#bc+1] = imp.ty
		if imp.ty == 0 then
			encode_varuint(bc, self:type(imp))
		elseif imp.ty == 1 then
			self:encodevt(bc, imp.elety)
			encode_limits(bc, imp.sz, imp.mxsz)
		elseif imp.ty == 2 then
			encode_limits(bc, imp.sz, imp.mxsz)
		elseif imp.ty == 3 then
			self:encodevt(bc, imp.type)
			bc[#bc+1] = imp.mut
		else
			error("Unknown import type: " .. tostring(imp.ty))
		end
	end)

	sec[3] = loopSection(self._func, function(bc, fu)
		encode_varuint(bc, self:type(fu.fn.fty))
	end)

	sec[4] = loopSection(self._table, function(bc, tbl)
		error("NYI tables")
	end)

	sec[5] = loopSection(self._memory, function(bc, mem)
		encode_limits(bc, mem.sz, mem.mxsz)
	end)

	-- a global's init can add more globals, so loop by index
	do
		local bc, n = {}, 0
		local i = 1
		while self._global[i] do
			local globe = self._global[i]
			self:encodevt(bc, globe.type)
			bc[#bc+1] = globe.mut
			self:constexpr(bc, globe.type, globe.init)
			n = n + 1
			i = i + 1
		end
		local hd = {}
		encode_varuint(hd, n)
		for j = 1, #bc do
			hd[#hd+1] = bc[j]
		end
		sec[6] = hd
	end

	sec[7] = loopSection(self._export, function(bc, expo)
		encode_string(bc, expo.f)
		bc[#bc+1] = expo.kind
		if expo.kind == 0 then
			encode_varuint(bc, self:func(expo.obj))
		elseif expo.kind == 1 then
			encode_varuint(bc, self:table(expo.obj))
		elseif expo.kind == 2 then
			encode_varuint(bc, self:memory(expo.obj))
		else
			encode_varuint(bc, self:global(expo.obj))
		end
	end)

	if self._start then
		local bc = {}
		encode_varuint(bc, self:func(self._start))
		sec[8] = bc
	end

	if #self._declfunc > 0 then
		-- one declarative segment (flag 3) of func indices (elemkind 0)
		local bc = { 1, 3, 0 }
		encode_varuint(bc, #self._declfunc)
		for i = 1, #self._declfunc do
			encode_varuint(bc, self._declfunc[i])
		end
		sec[9] = bc
	end

	sec[10] = loopSection(self._func, function(bc, fu)
		local fc = {}
		encode_varuint(fc, fu.localbcn)
		for j=1, #fu.localbc do
			fc[#fc+1] = fu.localbc[j]
		end
		for j = 1, #fu.bcode do
			fc[#fc+1] = fu.bcode[j]
		end
		fc[#fc+1] = 0x0b

		encode_varuint(bc, #fc)
		for j = 1, #fc do
			bc[#bc+1] = fc[j]
		end
	end)

	sec[11] = loopSection(self._data, function(bc, data)
		if data.passive then
			bc[#bc+1] = 1
		else
			encode_varuint(bc, self.ids[data.mem])
			if type(data.offexpr) == 'number' then
				bc[#bc+1] = 0x41
				encode_varint(bc, data.offexpr)
			else
				local gdata = data.offexpr
				assert(gdata.mut == 0)
				assert(gdata.type == i32)
				bc[#bc+1] = 0x23
				encode_varuint(bc, self:global(gdata))
			end
			bc[#bc+1] = 0x0b
		end
		encode_varuint(bc, #data.data)
		for j = 1, #data.data do
			bc[#bc+1] = data.data[j]
		end
	end)

	if self.usesdataidx then
		local bc = {}
		encode_varuint(bc, #self._data)
		sec[12] = bc
	end

	-- Types last. Encoding them can't add new ones, all deps were registered with typeidx
	sec[1] = loopSection(self._type, function(bc, group)
		if group.explicit or #group > 1 then
			bc[#bc+1] = 0x4e
			encode_varuint(bc, #group)
			for i = 1, #group do
				self:encodedef(bc, group[i])
			end
		else
			self:encodedef(bc, group[1])
		end
	end)

	-- data count (12) goes before code (10)
	local order = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 10, 11 }
	for i = 1, #order do
		local id = order[i]
		if sec[id] then
			writeSection(chunks, id, sec[id])
		end
	end

	return chunks
end

local refs = {
	anyref = refnull(heap.any),
	eqref = refnull(heap.eq),
	i31ref = refnull(heap.i31),
	structref = refnull(heap.struct),
	arrayref = refnull(heap.array),
	funcref = refnull(heap.func),
	externref = refnull(heap.extern),
	nullref = refnull(heap.none),
	exnref = refnull(heap.exn),
}
anyfunc = refs.funcref

return {
	i32 = i32,
	i64 = i64,
	f32 = f32,
	f64 = f64,
	i8 = i8,
	i16 = i16,
	anyfunc = refs.funcref,
	functy = functy,
	void = void,
	heap = heap,
	ref = ref,
	refnull = refnull,
	anyref = refs.anyref,
	eqref = refs.eqref,
	i31ref = refs.i31ref,
	structref = refs.structref,
	arrayref = refs.arrayref,
	funcref = refs.funcref,
	externref = refs.externref,
	nullref = refs.nullref,
	exnref = refs.exnref,
	issub = issub,
	tyname = tyname,
	struct = struct,
	array = array,
	functype = functype,
	rec = rec,
	mut = mut,
	mod = mod,
	func = func,
	global = global,
	data = data,
	passivedata = passivedata,
	memory = memory,
	importfunc = importfunc,
	importtable = importtable,
	importmemory = importmemory,
	importglobal = importglobal,
}