#!/usr/bin/lua

local push, pop = table.insert, table.remove

i32 = 0x7f
i64 = 0x7e
f32 = 0x7d
f64 = 0x7c
void = 0x40

Mod = {
	type = {},
	import = {},
	func = {},
	table = {},
	memory = {},
	global = {},
	export = {},
	start = nil,
	element = {},
	code = {},
	data = {},
	impfid = 0,
	imptid = 0,
	impmid = 0,
	impgid = 0,
	fid = 0,
	tid = 0,
	mid = 0,
	gid = 0,
	tymap = {},
}

function encode_varint(dst, val)
	while true do
		local b = val & 0x7f
		val = math.floor(val / 128) -- Lua's >> is unsigned
		if (val == 0 and (b & 0x40) == 0) or (val == -1 and ((b & 0x40) == 0x40)) then
			dst[#dst+1] = b
			return
		else
			dst[#dst+1] = b | 0x80
		end
	end
end
function encode_varuint(dst, val)
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
function encode_f32(dst, val)
	local repr = string.pack('<f', val)
	for i = 1, 4 do
		dst[#dst+1] = string.byte(repr, i)
	end
end
function encode_f64(dst, val)
	local repr = string.pack('<d', val)
	for i = 1, 8 do
		dst[#dst+1] = string.byte(repr, i)
	end
end
function encode_string(dst, str)
	encode_varuint(dst, #str)
	for i = 1, #str do
		dst[#dst+1] = string.byte(str, i)
	end
end

function assert_isvty(ty)
	assert(ty == i32 or ty == i64 or ty == f32 or ty == f64, ty)
end

function remove_from(tbl, n)
	for i = n, #tbl do
		tbl[i] = nil
	end
end

-- Type
function Mod:decltype(types)
	if types[1] == void then
		assert(#types == 1)
		types = {}
	end
	local sig = table.concat(types)
	local t = self.tymap[sig]
	if not t then
		t = #self.type+1
		self.tymap[sig] = t
		self.type[t] = types
	end
	return t-1
end

-- Import
function importfunc(m, f, ...)
	local sig = {...}
	local impf = { m = m, f = f, ty = 0, type = sig, tid = Mod:decltype(sig), id = Mod.impfid }
	Mod.impfid = Mod.impfid + 1
	push(Mod.import, impf)
	return impf
end
function importtable(m, f)
	local impt = { m = m, f = f, ty = 1, id = Mod.imptid }
	Mod.imptid = Mod.imptid + 1
	push(Mod.import, impt)
	return impt
end
function importmemory(m, f, sz, mxsz)
	local impm = { m = m, f = f, ty = 2, sz = sz, mxsz = mxsz, id = Mod.impmid }
	Mod.impmid = Mod.impmid + 1
	push(Mod.import, impm)
	return impm
end
function importglobal(m, f, ty, mut)
	if not mut then
		mut = 0
	elseif mut ~= 0 then
		mut = 1
	end
	local impg = { m = m, f = f, ty = 3, type = ty, mut = mut, id = Mod.impgid }
	Mod.impgid = Mod.impgid + 1
	push(Mod.import, impg)
	return impg
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
		scp = 0
	end
	return encode_varuint(self.bcode, self.scope - scp)
end

function funcmeta:push(ty)
	assert_isvty(ty)
	self.stack[#self.stack+1] = ty
end
function funcmeta:pop()
	local r = self.stack[#self.stack]
	self.stack[#self.stack] = nil
	return r
end
function funcmeta:peek()
	return self.stack[#self.stack]
end

function funcmeta:params(...)
	assert(#self.locals == 0)
	self.locals = {...}
	self.pcount = #self.locals
	local ret = {}
	for i = 1, self.pcount do
		ret[i] = i
	end
	return table.unpack(ret)
end

function funcmeta:i32(x)
	local xty = type(x)
	if xty == 'number' then
		self:emit(0x41)
		self:emitint(x)
		self:push(i32)
	else
		local n = #self.locals+1
		self.locals[n] = 0x7f
		return n
	end
end
function funcmeta:i64(x)
	local xty = type(x)
	if xty == 'number' then
		self:emit(0x42)
		self:emitint(x)
		self:push(i64)
	else
		local n = #self.locals+1
		self.locals[n] = 0x7e
		return n
	end
end
function funcmeta:f32(x)
	local xty = type(x)
	if xty == 'number' then
		self:emit(0x43)
		encode_f32(self.bcode, x)
		self:push(f32)
	else
		local n = #self.locals+1
		self.locals[n] = 0x7d
		return n
	end
end
function funcmeta:f64(x)
	local xty = type(x)
	if xty == 'number' then
		self:emit(0x44)
		encode_f64(self.bcode, x)
		self:push(f64)
	else
		local n = #self.locals+1
		self.locals[n] = 0x7c
		return n
	end
end
function funcmeta:unreachable()
	self:emit(0x00)
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
	local sclen = #self.stack + 1
	self.scope = self.scope + 1
	block(self.scope)
	self:emit(0x0b)
	self.scope = self.scope - 1
	self.polystack = false
	remove_from(self.stack, sclen)
	if tyval ~= 0x40 then
		self:push(tyval)
	end
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
	local sclen = #self.stack + 1
	self.scope = self.scope + 1
	block(self.scope)
	self:emit(0x0b)
	self.scope = self.scope - 1
	self.polystack = false
	remove_from(self.stack, sclen)
	if tyval ~= 0x40 then
		self:push(tyval)
	end
end
function funcmeta:load(x)
	self:emit(0x20)
	self:emituint(x-1)
	self:push(self.locals[x])
end
function funcmeta:store(x)
	self:emit(0x21)
	self:emituint(x-1)
	assert(self:pop() == self.locals[x])
end
function funcmeta:tee(x)
	self:emit(0x22)
	self:emituint(x-1)
	assert(self:peek() == self.locals[x])
end
function funcmeta:loadg(x)
	self:emit(0x23)
	self:emituint(x.id+Mod.impgid)
	self:push(x.type)
end
function funcmeta:storeg(x)
	self:emit(0x24)
	self:emituint(x.id+Mod.impgid)
	assert(self:pop() == x.type)
end
function funcmeta:drop()
	self:emit(0x1a)
	self:pop()
end
function funcmeta:select()
	-- TODO typesig
	assert(self:pop() == i32)
	local a = self:pop()
	local b = self:pop()
	assert(a == b)
	self:emit(0x1b)
	self:push(a)
end
function funcmeta:iff(ty, brif, brelse)
	local tyty, tyval = type(ty)
	self:emit(0x04)
	if tyty == 'number' then
		tyval = ty
	else
		tyval = 0x40
		brelse = brif
		brif = ty
	end
	self:emit(tyval)
	self.scope = self.scope + 1

	local sclen = #self.stack + 1
	brif(self.scope)
	self.polystack = false
	remove_from(self.stack, sclen)
	if brelse then
		self:emit(0x05)
		brelse(self.scope)
		self.polystack = false
		remove_from(self.stack, sclen)
	end
	self:emit(0x0b)
	self.scope = self.scope - 1
	if tyval ~= 0x40 then
		self:push(tyval)
	end
end

function funcmeta:br(scope)
	self.polystack = true
	self:emit(0x0c)
	return self:emitscope(scope)
end
function funcmeta:brif(scope)
	self:emit(0x0d)
	return self:emitscope(scope)
end
function funcmeta:brtable(...)
	self:emit(0x0e)
	local n = select('#', ...)
	assert(n > 0)
	self:emituint(n-1)
	for i = 1, n do
		self:emitscope(select(i, ...))
	end
end
function funcmeta:ret()
	self.polystack = true
	self:emit(0x0f)
end
function funcmeta:current_memory()
	self:emit(0x3f)
	self:emit(0)
	self:push(i32)
end
function funcmeta:grow_memory()
	assert(self:peek() == i32)
	self:emit(0x40)
	self:emit(0)
end

function mkopcore(self, name, tymap, a, tyret)
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
function mkunop(name, tymap, tyret)
	funcmeta[name] = function(self)
		local a = self:pop()
		if not a then
			return error('Stack underflow')
		end
		return mkopcore(self, name, tymap, a, tyret)
	end
end
function mkbinop(name, tymap, tyret)
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

function mkstoreop(name, opcode, ty)
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
function mkloadop(name, opcode, ty)
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
	if getmetatable(f) == funcmt then
		self:emituint(Mod.impfid + f.id)
		for i = 1, f.pcount do
			assert(self:pop() == f.locals[f.pcount-i+1])
		end
		if f.rety and f.rety ~= 0x40 then
			self:push(f.rety)
		end
	else
		self:emituint(f.id)
		local pcount, ret = #f.type-1, f.type[#f.type]
		for i = 1, pcount do
			assert(self:pop() == f.type[pcount-i+1])
		end
		if ret and ret ~= 0x40 then
			self:push(ret)
		end
	end
end

function func(rety, bgen)
	local sig
	if not bgen then
		bgen = rety
		rety = void
		sig = ""
	else
		sig = rety .. ""
	end
	-- TODO create a separate context object
	-- which will be used for calling block
	-- takes out scope/stack/polystack
	local f = setmetatable({
		rety = rety,
		locals = {},
		pcount = 0,
		sig = sig,
		bcode = {},
		scope = 0,
		stack = {},
		polystack = false, -- TODO polystack should work with unreachable scopes (eg block i32 ret loop i64 end end)
		bgen = bgen,
		id = Mod.fid,
		tid = -1,
	}, funcmt)
	Mod.fid = Mod.fid + 1
	push(Mod.func, f)
	return f
end

-- Table

-- Memory

-- Global

function global(ty, mut, func)
	fty = type(func)
	assert_isvty(ty)
	if not mut then
		mut = 0
	elseif mut ~= 0 then
		mut = 1
	end
	if not func then
		func = 0
	end
	local globe = { type = ty, mut = mut, init = func, id = Mod.gid }
	push(Mod.global, globe)
	Mod.gid = Mod.gid + 1
	return globe
end

-- Export

function export(name, obj)
	assert(type(name) == 'string')
	local kind
	if obj.bcode then
		kind = 0
	elseif obj.istable then
		kind = 1
	elseif obj.ismem then
		kind = 2
	elseif obj.mut then
		kind = 3
	end
	push(Mod.export, { f = name, obj = obj, kind = kind })
	return obj
end

-- Start

function start(fu)
	assert(not Mod.start and fu.pcount == 0 and (not fu.rety or fu.rety == void))
	Mod.start = fu
	return fu
end

-- Element

-- Data

-- Main

local files = {...}
for f = 2, #files do
	dofile(files[f])
end

local outf = io.open(files[1], 'w')

outf:write("\0asm\1\0\0\0")

local function writeSection(id, bc)
	outf:write(string.char(id))
	local bclen = {}
	encode_varuint(bclen, #bc)
	outf:write(string.char(table.unpack(bclen)))
	local n, nn, nbc = 1, 4096, #bc
	while n <= nbc do
		if nn > nbc then
			nn = nbc
		end
		outf:write(string.char(table.unpack(bc, n, nn)))
		n = nn + 1
		nn = nn + 4096
	end
end

for i = 1, #Mod.func do
	local fu = Mod.func[i]
	fu:bgen()
	local fty = {}
	for i = 1, fu.pcount do
		fty[i] = fu.locals[i]
	end
	local rety
	if not fu.rety then
		rety = void
	else
		rety = fu.rety
	end
	fty[#fty+1] = rety
	fu.tid = Mod:decltype(fty)
end

if #Mod.type > 0 then
	local bc = {}
	encode_varuint(bc, #Mod.type)
	for i = 1, #Mod.type do
		local ty = Mod.type[i]
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
	end
	writeSection(1, bc)
end

if #Mod.import > 0 then
	local bc = {}
	encode_varuint(bc, #Mod.import)
	for i = 1, #Mod.import do
		local imp = Mod.import[i]
		encode_string(bc, imp.m)
		encode_string(bc, imp.f)
		bc[#bc+1] = imp.ty
		if imp.ty == 0 then
			encode_varuint(bc, imp.tid)
		elseif imp.ty == 1 then
			error('NYI table imp')
		elseif imp.ty == 2 then
			if imp.mxsz then
				bc[#bc+1] = 1
				encode_varuint(bc, imp.sz)
				encode_varuint(bc, imp.mxsz)
			else
				bc[#bc+1] = 0
				encode_varuint(bc, imp.sz)
			end
		elseif imp.ty == 3 then
			error('NYI global imp')
		else
			error("Unknown import type: " .. imp.ty)
		end
	end
	writeSection(2, bc)
end

if #Mod.func > 0 then
	local bc = {}
	encode_varuint(bc, #Mod.func)
	for i = 1, #Mod.func do
		encode_varuint(bc, Mod.func[i].tid)
	end
	writeSection(3, bc)
end

if #Mod.global > 0 then
	local bc = {}
	encode_varuint(bc, #Mod.global)
	for i = 1, #Mod.global do
		local globe = Mod.global[i]
		local ty, init = globe.type, globe.init
		bc[#bc+1] = ty
		bc[#bc+1] = globe.mut
		if type(init) == 'number' then
			if ty == i32 then
				bc[#bc+1] = 0x41
				encode_varint(bc, init)
				bc[#bc+1] = 0x0b
			elseif ty == i64 then
				bc[#bc+1] = 0x42
				encode_varint(bc, init)
				bc[#bc+1] = 0x0b
			elseif ty == f32 then
				bc[#bc+1] = 0x43
				encode_f32(bc, init)
				bc[#bc+1] = 0x0b
			else
				bc[#bc+1] = 0x44
				encode_f64(bc, init)
				bc[#bc+1] = 0x0b
			end
		else
			error('NYI get_global init_expr')
		end
	end
	writeSection(6, bc)
end

if #Mod.export then
	local bc = {}
	encode_varuint(bc, #Mod.export)
	for i = 1, #Mod.export do
		local expo = Mod.export[i]
		encode_string(bc, expo.f)
		bc[#bc+1] = expo.kind
		if expo.kind == 0 then
			encode_varuint(bc, Mod.impfid + expo.obj.id)
		elseif expo.kind == 1 then
			encode_varuint(bc, Mod.imptid + expo.obj.id)
		elseif expo.kind == 2 then
			encode_varuint(bc, Mod.impmid + expo.obj.id)
		else
			encode_varuint(bc, Mod.impgid + expo.obj.id)
		end
	end
	writeSection(7, bc)
end

if Mod.start then
	local bc = {}
	encode_varuint(bc, Mod.impfid + Mod.start.id)
	writeSection(8, bc)
end

if #Mod.func > 0 then
	local bc = {}
	encode_varuint(bc, #Mod.func)
	for i = 1, #Mod.func do
		local fu, fc = Mod.func[i], {}
		local j, nlocals, gcnt = fu.pcount+1, #fu.locals, 0
		for k = j, nlocals do
			if fu.locals[k] ~= fu.locals[k+1] then
				gcnt = gcnt + 1
			end
		end
		encode_varuint(fc, gcnt)
		while j <= nlocals do
			local jty, k = fu.locals[j], 1
			while j + k <= nlocals and fu.locals[j+k] == jty do
				k = k + 1
			end
			print(i, k, jty)
			encode_varuint(fc, k)
			fc[#fc+1] = jty
			j = j + k
		end
		for j = 1, #fu.bcode do
			fc[#fc+1] = fu.bcode[j]
		end
		fc[#fc+1] = 0x0b

		print(Mod.impfid + i - 1, table.concat(fc, ':'))
		encode_varuint(bc, #fc)
		for j = 1, #fc do
			bc[#bc+1] = fc[j]
		end
	end
	writeSection(10, bc)
end

outf:close()
