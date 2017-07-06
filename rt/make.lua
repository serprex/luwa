#!/usr/bin/lua

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
	exportfun = {},
	exporttab = {},
	exportmem = {},
	exportglo = {},
	start = nil,
	element = {},
	code = {},
	data = {},
	impfid = 0,
	fid = 0,
	tymap = {},
	fumap = {},
}

-- Type
function Mod:decltype(...)
	local types = table.pack(...)
	if types[1] == void then
		types[1] = nil
		types.n = 0
	end
	return self:typefromsig(table.concat(types))
end

function Mod:typefromsig(sig)
	local t = self.tymap[sig]
	if not t then
		t = #self.type+1
		self.tymap[sig] = t
		self.type[t] = types
	end
	return t
end

-- Import
function importfunc(m, f, ...)
	local impf = { m = m, f = f, ty = 0, type = Mod.decletype(...), id = Mod.impfid }
	Mod.impfid = Mod.impfid + 1
	push(Mod.import, impf)
	return impf
end
function importtable(m, f)
	push(Mod.import, { m = m, f = f, ty = 1 })
end
function importmemory(m, f, sz, mxsz)
	push(Mod.import, { m = m, f = f, ty = 2, sz = sz, mxsz = mxsz })
end
function importglobal(m, f, ty, mut)
	if not mut then
		mut = 0
	elseif mut == true then
		mut = 1
	end
	push(Mod.import, { m = m, f = f, ty = 3, type = ty, mut = mut })
end

-- Function
local funcmeta = {}
local funcmt = { __index = funcmeta }
local push, pop = table.insert, table.remove

function encode_varint(dst, val)
	while true do
		local b = val & 0x7f
		val = val >> 7
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
function encode_string(dst, str)
	encode_varuint(dst, #str)
	for i = 1, #str do
		dst[#dst+1] = string.byte(str, i)
	end
end

function remove_from(tbl, n)
	for i = n, #tbl do
		tbl[i] = nil
	end
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

function funcmeta:push(ty)
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
	self.locals = table.pack(...)
	self.pcount = #self.locals
	local ret = {}
	for i = 1, self.pcount do
		ret[i] = i
	end
	self.sig = table.concat(self.locals) .. self.sig
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
		local repr = string.pack('<f', x)
		for i = 1, 4 do
			self:emit(string.byte(repr, n))
		end
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
		self:emit(0x43)
		local repr = string.pack('<d', x)
		for i = 1, 8 do
			self:emit(string.byte(repr, n))
		end
		self:push(f64)
	else
		local n = #self.locals+1
		self.locals[n] = 0x7c
		return n
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
	self:pop()
end
function funcmeta:tee(x)
	self:emit(0x22)
	self:emituint(x-1)
end
function funcmeta:drop()
	self:emit(0x1a)
	self:pop()
end
function funcmeta:select()
	-- TODO typesig
	self:pop()
	local a = self:pop()
	local b = self:pop()
	assert(a == b)
	self:emit(0x1b)
	self:push(a)
end
function funcmeta:iff(ty, brif)
	local tyty, tyval = type(ty)
	self:emit(0x04)
	if tyty == 'number' then
		tyval = ty
	else
		tyval = 0x40
		brif = ty
	end
	self:emit(tyval)
	self.scope = self.scope + 1

	local sclen = #self.stack + 1
	brif(self.scope)
	self.polystack = false
	remove_from(self.stack, sclen)
	self:emit(0x0b)

	self.scope = self.scope - 1
	if tyval ~= 0x40 then
		self:push(tyval)
	end
end
function funcmeta:ifelse(ty, brif, brelse)
	local tyty, tyval = type(ty)
	self:emit(0x04)
	if tyty == 'number' then
		tyval = ty
	else
		tyval = 0x40
		brelse = brelse
		brif = ty
	end
	self:emit(tyval)
	self.scope = self.scope + 1

	local sclen = #self.stack + 1
	brif(self.scope)
	self.polystack = false
	remove_from(self.stack, sclen)
	self:emit(0x05)

	brelse(self.scope)
	self.polystack = false
	remove_from(self.stack, sclen)
	self:emit(0x0b)

	self.scope = self.scope - 1
	if tyval ~= 0x40 then
		self:push(tyval)
	end
end

function funcmeta:emitscope(scope)
	if scope == self then
		return self:emituint(self.scope)
	else
		return self:emituint(self.scope - scope)
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
function funcmeta:ret()
	self.polystack = true
	self:emit(0x0f)
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
		local ty = tymap[a]
		if ty then
			self:emit(ty)
			if tyret then
				self:push(tyret)
			else
				self:push(a)
			end
		else
			error(name .. ' not implemented for ' .. a)
		end
	end
end
mkbinop('eqz', { i32 = 0x45, i64 = 0x50 }, i32)
mkbinop('eq', { i32 = 0x46, i64 = 0x51, f32 = 0x5b, f64 = 0x61 }, i32)
mkbinop('ne', { i32 = 0x47, i64 = 0x52, f32 = 0x5c, f64 = 0x62 }, i32)
mkbinop('lts', { i32 = 0x48, i64 = 0x53 }, i32)
mkbinop('ltu', { i32 = 0x49, i64 = 0x54 }, i32)
mkbinop('gts', { i32 = 0x4a, i64 = 0x55 }, i32)
mkbinop('gtu', { i32 = 0x4b, i64 = 0x56 }, i32)
mkbinop('leu', { i32 = 0x4c, i64 = 0x57 }, i32)
mkbinop('les', { i32 = 0x4d, i64 = 0x58 }, i32)
mkbinop('ges', { i32 = 0x4e, i64 = 0x59 }, i32)
mkbinop('geu', { i32 = 0x4f, i64 = 0x5a }, i32)
mkbinop('add', { i32 = 0x6a, i64 = 0x7c, f32 = 0x91, f64 = 0xa0 })
mkbinop('sub', { i32 = 0x6b, i64 = 0x7d, f32 = 0x92, f64 = 0xa1 })

function funcmeta:call(f)
	self:emit(0x10)
	self:emituint(M.impfid + f.id)
	-- TODO typeck
end

function func(name, rety, block)
	local sig
	if not block then
		block = rety
		rety = void
		sig = ""
	else
		sig = rety .. ""
	end
	-- TODO create a separate context object
	-- which will be used for calling block
	-- takes out scope/stack/polystack
	local f = setmetatable({
		name = name,
		rety = rety,
		locals = {},
		pcount = 0,
		sig = sig,
		bcode = {},
		scope = 0,
		stack = {},
		polystack = false,
		block = block,
		id = Mod.fid,
	}, funcmt)
	Mod.fid = Mod.fid + 1
	Mod.fumap[name] = f
	push(Mod.func, f)
	return f
end

-- Table

-- Memory

-- Global

-- Export

-- Start

-- Element

-- Data

-- Main

local files = table.pack(...)
for f = 2, #files do
	print(files[f])
	dofile(files[f])
end

local outf = io.open(files[1], 'w')

outf:write("\0asm\1\0\0\0")

local function writeSection(id, bc)
	outf:write(string.char(id))
	local bclen = {}
	encode_varuint(bclen, #bc)
	outf:write(string.char(table.unpack(bclen)))
	-- TODO chunk unpacking
	outf:write(string.char(table.unpack(bc)))
end

for i = 1, #Mod.func do
	Mod.func[i]:block()
	Mod:typefromsig(Mod.func[i].sig)
end

if #Mod.type > 0 then
	local bc = {}
	encode_varuint(bc, #Mod.type)
	for i = 1, #Mod.type do
		local ty = Mod.type[i]
		local ret = ty[#ty]
		if ret == 0x40 then
			ty[#ty] = nil
		end
		bc[#bc+1] = 0x60
		encode_varuint(bc, #ty)
		for j = 1, #ty do
			bc[#bc+1] = ty
		end
		if ret == 0x40 then
			bc[#bc+1] = 0
		else
			bc[#bc+1] = 1
			bc[#bc+1] = ret
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
		bc[#bc+1] = string.char(imp.ty)
		if imp.ty == 0 then
			encode_varuint(bc, imp.type)
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
		encode_varuint(bc, Mod.tymap[Mod.func[i].sig])
	end
	writeSection(3, bc)
end

outf:close()
