#!/usr/bin/lua

local typeval = {
	i32 = 0x7f,
	i64 = 0x7e,
	f32 = 0x7d,
	f64 = 0x7c,
	anyfunc = 0x70,
	func = 0x60,
	void = 0x40,
}
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

function funcmeta:i32(x)
	local xty = type(x)
	if xty == 'string' then
		local n = #self.locals+1
		self.locals[n] = 'i32'
		return n
	else
		self:emit(0x41)
		self:emitint(x)
		self:push('i32')
	end
end
function funcmeta:load(x)
	self:emit(0x20)
	self:emituint(x)
	self:push(self.locals[x])
end
function funcmeta:store(x)
	self:emit(0x21)
	self:emituint(x)
	self:pop()
end
function funcmeta:tee(x)
	self:emit(0x22)
	self:emituint(x)
end
function funcmeta:drop()
	self:emit(0x1a)
	self:pop()
end
function funcmeta:select()
	-- TODO typesig
	self:emit(0x1b)
end
function funcmeta:iff(ty, brif)
	local tyty, tyval = type(ty)
	self:emit(0x04)
	if tyty == 'string' then
		tyval = typeval[ty]
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
	if tyty == 'string' then
		tyval = typeval[ty]
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
mkbinop('eqz', { i32 = 0x45, i64 = 0x50 }, 'i32')
mkbinop('eq', { i32 = 0x46, i64 = 0x51, f32 = 0x5b, f64 = 0x61 }, 'i32')
mkbinop('ne', { i32 = 0x47, i64 = 0x52, f32 = 0x5c, f64 = 0x62 }, 'i32')
mkbinop('lts', { i32 = 0x48, i64 = 0x53 }, 'i32')
mkbinop('ltu', { i32 = 0x49, i64 = 0x54 }, 'i32')
mkbinop('gts', { i32 = 0x4a, i64 = 0x55 }, 'i32')
mkbinop('gtu', { i32 = 0x4b, i64 = 0x56 }, 'i32')
mkbinop('leu', { i32 = 0x4c, i64 = 0x57 }, 'i32')
mkbinop('les', { i32 = 0x4d, i64 = 0x58 }, 'i32')
mkbinop('ges', { i32 = 0x4e, i64 = 0x59 }, 'i32')
mkbinop('geu', { i32 = 0x4f, i64 = 0x5a }, 'i32')
mkbinop('add', { i32 = 0x6a, i64 = 0x7c, f32 = 0x91, f64 = 0xa0 })
mkbinop('sub', { i32 = 0x6b, i64 = 0x7d, f32 = 0x92, f64 = 0xa1 })

function func(name)
	local f = setmetatable({
		name = name,
		locals = {},
		bcode = {},
		scope = 0,
		stack = {},
		polystack = false,
	}, funcmt)
	return function(block) block(f) end
end

local files = table.pack(...)
for f = 2, #files do
	dofile(files[f])
end

--local outf = io.open(files[1], 'w')
--outf:write(compile())
--outf:close()
