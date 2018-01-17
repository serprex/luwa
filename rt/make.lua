local push, pop = table.insert, table.remove
i32, i64, f32, f64, anyfunc, functy, void = 0x7f, 0x7e, 0x7d, 0x7c, 0x70, 0x60, 0x40
local i32, i64, f32, f64, anyfunc, functy, void = 0x7f, 0x7e, 0x7d, 0x7c, 0x70, 0x60, 0x40
local imptypes = { [0] = 'fid', [1] = 'tid', [2] = 'mid', [3] = 'gid' }
local modmeth = {}
local modmt = { __index = modmeth }

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
		fcache = {},
		ids = {},
		fid = 0,
		tid = 0,
		mid = 0,
		gid = 0,
		tymap = {},
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

local function assert_isvty(ty)
	return assert(ty == i32 or ty == i64 or ty == f32 or ty == f64, ty)
end

local function remove_from(tbl, n)
	for i = n, #tbl do
		tbl[i] = nil
	end
end

-- Type
function modmeth:type(types)
	if types[1] == void then
		assert(#types == 1)
		types = {}
	end
	local sig = string.char(table.unpack(types))
	local t = self.tymap[sig]
	if not t then
		t = #self._type+1
		self.tymap[sig] = t
		self._type[t] = types
	end
	return t-1
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
local function importglobal(m, f, ty, mut)
	assert(utf8.len(m) and utf8.len(f), "Non utf8 global import")
	return { m = m, f = f, ty = 3, type = ty, mut = nztrue(mut) }
end

-- Function
local funcmeta = {}
local funcmt = { __index = funcmeta }

function funcmeta:prstack()
	return print(table.concat(self.stack, ", "))
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
function funcmeta:emitscope(scp)
	if scp == self then
		scp = 1
	end
	assert(scp > 0)
	assert(not self.blockty[scp] or self.scopety[scp] == 0x40 or self.scopety[scp] == self:peek())
	return encode_varuint(self.bcode, self.scope - scp)
end

function funcmeta:push(ty)
	assert_isvty(ty)
	self.stack[#self.stack+1] = ty
end
function funcmeta:pop()
	local r = self:peek()
	self.stack[#self.stack] = nil
	return r
end
function funcmeta:peek()
	assert(#self.stack > self.stackmin[self.scope])
	return self.stack[#self.stack]
end
function funcmeta:pushscope(scty, blty)
	self.scope = self.scope + 1
	self.stackmin[self.scope] = #self.stack
	self.polystack[self.scope] = false
	self.scopety[self.scope] = scty
	self.blockty[self.scope] = blty
end
function funcmeta:popscope()
	local tyval = self.scopety[self.scope]
	local sclen = self.stackmin[self.scope]
	if not self.polystack[self.scope] then
		if tyval ~= 0x40 then
			assert(self.stack[#self.stack] == tyval and #self.stack == sclen + 1, 'Expected single result on stack')
		else
			assert(#self.stack == sclen, 'Unexpected stack leftovers')
		end
	elseif tyval ~= 0x40 then
		remove_from(self.stack, sclen + 1)
		self:push(tyval)
	else
		remove_from(self.stack, sclen + 1)
	end
	self.scope = self.scope - 1
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
	self.localbc[#self.localbc+1] = lty
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
	self.polystack[self.scope] = true
end
function funcmeta:nop()
	self:emit(0x01)
end
function funcmeta:block(ty, block)
	local tyty, tyval = type(ty)
	if tyty == 'number' then
		tyval = ty
	else
		tyval = 0x40
		block = ty
	end
	self:emit(0x02)
	self:emit(tyval)
	self:pushscope(tyval, true)
	block(self.scope)
	self:popscope()
	self:emit(0x0b)
end
function funcmeta:loop(ty, block)
	local tyty, tyval = type(ty)
	if tyty == 'number' then
		tyval = ty
	else
		tyval = 0x40
		block = ty
	end
	self:emit(0x03)
	self:emit(tyval)
	self:pushscope(tyval, false)
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
	assert(self:pop() == self.localty[x])
end
function funcmeta:tee(x)
	self:emit(0x22)
	self:emituint(x-1)
	assert(self:peek() == self.localty[x])
end
function funcmeta:loadg(x)
	self:emit(0x23)
	self:emituint(self.mod:global(x))
	self:push(x.type)
end
function funcmeta:storeg(x)
	assert(x.mut)
	self:emit(0x24)
	self:emituint(self.mod:global(x))
	assert(self:pop() == x.type)
end
function funcmeta:drop()
	self:emit(0x1a)
	self:pop()
end
function funcmeta:select()
	assert(self:pop() == i32)
	local a = self:pop()
	assert(a == self:peek())
	self:emit(0x1b)
end
function funcmeta:iff(ty, brif, brelse)
	local tyty, tyval = type(ty)
	assert(self:pop() == i32)
	self:emit(0x04)
	if tyty == 'number' then
		tyval = ty
	else
		tyval = 0x40
		brelse = brif
		brif = ty
	end
	assert(brelse or tyval == 0x40)
	self:emit(tyval)
	self:pushscope(tyval, true)
	brif(self.scope)
	self:popscope()

	if brelse then
		if tyval ~= 0x40 then
			self:pop()
		end
		self:emit(0x05)
		self:pushscope(tyval, true)
		brelse(self.scope)
		self:popscope()
	end
	self:emit(0x0b)
end

function funcmeta:br(scope)
	self.polystack[self.scope] = true
	self:emit(0x0c)
	return self:emitscope(scope)
end
function funcmeta:brif(scope)
	assert(self:pop() == i32)
	self:emit(0x0d)
	return self:emitscope(scope)
end
function funcmeta:brtable(...)
	self.polystack[self.scope] = true
	assert(self:pop() == i32)
	self:emit(0x0e)
	local n = select('#', ...)
	assert(n > 0)
	self:emituint(n-1)
	for i = 1, n do
		local scp = assert(select(i, ...), i)
		self:emitscope(scp)
	end
end
function funcmeta:ret()
	assert(not self.fn.rety or self.fn.rety == 0x40 or self:peek() == self.fn.rety)
	self.polystack[self.scope] = true
	self:emit(0x0f)
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

function funcmeta:switch(expr, ...)
	local scopes = {}
	local function jmp()
		expr(scopes)
		if scopes[-1] then
			scopes[#scopes+1] = scopes[-1]
		end
		while #scopes > 1 and scopes[#scopes] == scopes[#scopes-1] do
			scopes[#scopes] = nil
		end
		return self:brtable(assert(scopes[0]), table.unpack(scopes))
	end
	for idx=1,select('#', ...) do
		local x = assert(select(idx, ...), idx)
		local xt, oldj = type(x), jmp
		if xt == 'function' then
			function jmp(scp)
				self:block(oldj)
				return x(scopes)
			end
		elseif xt == 'table' then
			function jmp(scp)
				local lastx = assert(x[#x])
				for i=1,#x-1 do
					assert(not scopes[x[i]])
					scopes[x[i]] = lastx
				end
				return oldj(scp)
			end
		else
			function jmp(scp)
				assert(not scopes[x])
				scopes[x] = assert(scp)
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
		return error(name .. ' not implemented for ' .. a)
	end
end
local function mkunop(name, tymap, tyret)
	funcmeta[name] = function(self)
		local a = self:pop()
		assert(a, 'Stack underflow')
		return mkopcore(self, name, tymap, a, tyret)
	end
end
local function mkbinop(name, tymap, tyret)
	funcmeta[name] = function(self)
		local a = self:pop()
		local b = self:pop()
		if not a or not b then
			print(b, a)
			return error('Stack underflow')
		elseif a ~= b then
			print(b, a)
			return error('Type mismatch')
		end
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
		assert(self:pop() == ty)
		assert(self:pop() == i32)
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
		assert(self:pop() == i32)
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

function funcmeta:call(f)
	self:emit(0x10)
	local pcount, ret, params
	if f.isfunc then
		params, pcount, ret = f.params, #f.params, f.rety
		self:emituint(self.mod:func(f))
	else
		params, pcount, ret = f, #f-1, f[#f]
		self:emituint(self.mod:import(f))
	end
	for i = 1, pcount do
		assert(self:pop() == params[pcount-i+1])
	end
	if ret and ret ~= 0x40 then
		self:push(ret)
	end
end

function modmeth:func(f)
	if self.fcache[f] then
		return self.fcache[f]
	end
	local params = {table.unpack(f.params)}
	local fb = setmetatable({
		mod = self,
		fn = f,
		localty = params,
		localbc = {},
		localbcn = 0,
		pcount = #params,
		bcode = {},
		stack = {},
		scope = 0,
		scopety = {},
		stackmin = {},
		polystack = {},
		blockty = {},
	}, funcmt)
	local id = pushid(self._func, fb) + self.fid
	self.fcache[f] = id
	self:type(f.fty)
	local ps = {}
	for i=1, #params do
		ps[i] = i
	end
	fb:pushscope(f.rety, true)
	f.bgen(fb, table.unpack(ps))
	fb:popscope()
	return id
end

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
		fty = fty,
		params = params,
		bgen = bgen,
	}
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

local function nztrue(x)
	if not x or x == 0 then
		return 0
	else
		return 1
	end
end

local function global(ty, mut, func)
	assert_isvty(ty)
	return { type = ty, mut = nztrue(mut), init = func or 0 }
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
	assert(not self._start and fu.pcount == 0 and (not fu.rety or fu.rety == void))
	self._start = fu
	return fu
end

-- Data

function modmeth:data(data)
	push(self._data, data)
end

local function data(mem, offexpr, data)
	return { mem = mem, offexpr = offexpr, data = data }
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
local function loopSection(chunks, id, elems, bcfu)
	if #elems then
		local bc = {}
		encode_varuint(bc, #elems)
		for i = 1, #elems do
			bcfu(bc, elems[i])
		end
		writeSection(chunks, id, bc)
	end
end

function modmeth:compile()
	local chunks = {"\0asm\1\0\0\0"}

	local impty = {}
	for i=1, #self._import do
		local imp = self._import[i]
		if imp.ty == 0 then
			impty[imp] = self:type(imp)
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

	loopSection(chunks, 1, self._type, function(bc, ty)
		bc[#bc+1] = 0x60
		if #ty == 0 then
			bc[#bc+1] = 0
			bc[#bc+1] = 0
		else
			local ret = ty[#ty]
			local pcount = #ty-1
			encode_varuint(bc, pcount)
			for j = 1, pcount do
				bc[#bc+1] = ty[j]
			end
			if ret == 0x40 then
				bc[#bc+1] = 0
			else
				bc[#bc+1] = 1
				bc[#bc+1] = ret
			end
		end
	end)

	loopSection(chunks, 2, self._import, function(bc, imp)
		encode_string(bc, imp.m)
		encode_string(bc, imp.f)
		bc[#bc+1] = imp.ty
		if imp.ty == 0 then
			encode_varuint(bc, impty[imp])
		elseif imp.ty == 1 then
			encode_varuint(bc, imp.elety)
			encode_limits(bc, imp.sz, imp.mxsz)
		elseif imp.ty == 2 then
			encode_limits(bc, imp.sz, imp.mxsz)
		elseif imp.ty == 3 then
			encode_varuint(imp.type)
			encode_varuint(imp.mut)
		else
			error("Unknown import type: " .. imp.ty)
		end
	end)

	loopSection(chunks, 3, self._func, function(bc, fu)
		encode_varuint(bc, self:type(fu.fn.fty))
	end)

	loopSection(chunks, 4, self._table, function(bc, tbl)
		error("NYI tables")
	end)

	loopSection(chunks, 5, self._memory, function(bc, mem)
		encode_limits(mem.sz, mem.mxsz)
	end)

	loopSection(chunks, 6, self._global, function(bc, globe)
		local ty, init = globe.type, globe.init
		bc[#bc+1] = ty
		bc[#bc+1] = globe.mut
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
			else
				bc[#bc+1] = 0x44
				encode_f64(bc, init)
			end
		else
			assert(not init.mut)
			assert(init.type == ty)
			bc[#bc+1] = 0x23
			encode_varuint(bc, self:global(x))
		end
		bc[#bc+1] = 0x0b
	end)

	loopSection(chunks, 7, self._export, function(bc, expo)
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
		writeSection(chunks, 8, bc)
	end

	loopSection(chunks, 10, self._func, function(bc, fu)
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

	loopSection(chunks, 11, self._data, function(bc, data)
		encode_varuint(bc, self.ids[data.mem])
		if type(data.offexpr) == 'number' then
			bc[#bc+1] = 0x41
			encode_varint(bc, data.offexpr)
		else
			local gdata = data.offexpr
			assert(not gdata.mut)
			assert(gdata.type == i32)
			bc[#bc+1] = 0x23
			encode_varuint(bc, self:global(gdata))
		end
		bc[#bc+1] = 0x0b
		encode_varuint(bc, #data.data)
		for j = 1, #data.data do
			bc[#bc+1] = data.data[j]
		end
	end)

	return chunks
end

return {
	i32 = i32,
	i64 = i64,
	f32 = f32,
	f64 = f64,
	anyfunc = anyfunc,
	functy = functy,
	void = void,
	mod = mod,
	func = func,
	global = global,
	data = data,
	importfunc = importfunc,
	importtable = importtable,
	importmemory = importmemory,
	importglobal = importglobal,
}
