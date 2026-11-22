local lex = require 'lex'
local ast = require 'ast'
local bc = require 'bc'

local function nop()
end

local asmmeta = {}
local asmmt = { __index = asmmeta }
local function Assembler()
	return setmetatable({
		params = {},
		locals = {},
		frees = {},
		isdotdotdot = false,
		scopes = nil,
		breaks = nil,
		consts = {},
		labels = {},
		gotos = {},
		labelscope = {},
		gotoscope = {},
		-- label node -> how many names its block has declared where it is
		labelcount = {},
		-- label node -> count to use when it ends its block, see visitScope Block
		endlabel = {},
		funcs = {},
		namety = {},
		rconsts = {
			integer = {},
			float = {},
			string = {},
			table = {},
			['function'] = {},
		},
		names = {},
		bc = {},
		-- (pc, line) pairs, added when the line changes. An op's line is the last pair at or before it
		lineinfo = {},
		-- pc after an op that can fail -> list of what made its operands, like "local 't'", or false.
		-- Errors & debug.getinfo look these up by the pc a frame has after that op
		opnames = {},
		-- what made the value on top of the stack, if it's a variable or field
		desc = nil,
		curline = nil,
		-- how many <close> variables are in scope where code is being emitted
		tbcn = 0,
		-- label node -> tbcn where it is, goto pc -> { tbcn at the goto, pc of the count to patch }
		labeltbc = {},
		gototbc = {},
		-- locals in declaration order as { namety, startpc, endpc }, & the ones in scope while emitting.
		-- For debug.getlocal
		locvars = {},
		actives = {},
	}, asmmt)
end

function asmmeta:push(op, ...)
	local line = self.curline
	if line and line ~= self.lastline then
		self.lastline = line
		local li = self.lineinfo
		li[#li+1] = #self.bc
		li[#li+1] = line
	end
	self.bc[#self.bc+1] = assert(op)
	for i=1,select('#', ...) do
		self:patch(#self.bc+1, (select(i, ...)))
	end
end
function asmmeta:patch(idx, x)
	self.bc[idx],self.bc[idx+1],self.bc[idx+2],self.bc[idx+3] = string.byte(string.pack('<i4', assert(x)), 1, 4)
end
function asmmeta:breakscope(f)
	self.breaks = { prev = self.breaks, tbcn = self.tbcn }
	f(self)
	for i=1,#self.breaks do
		self:patch(self.breaks[i], #self.bc)
	end
	self.breaks = self.breaks.prev
end
function asmmeta:scope(f)
	self.scopes = setmetatable({ prev = self.scopes }, { __index = self.scopes })
	f()
	for i=1, #self.scopes do
		local name = self.scopes[i]
		self.names[name] = self.names[name].prev
	end
	self.scopes = self.scopes.prev
end
function asmmeta:const(c)
	local ty = math.type(c) or type(c)
	local n = self.rconsts[ty][c]
	if not n then
		n = #self.consts
		self.consts[n+1] = c
		self.rconsts[ty][c] = n
	end
	return n
end

function asmmeta:name(n, isparam)
	assert(type(n) == 'string')
	local prevscope = self.names[n]
	local paramidx
	if isparam then
		paramidx = #self.params
	end
	-- seq is declaration order, so code gen never depends on pairs order
	self.nameseq = (self.nameseq or 0) + 1
	local newscope = { prev = prevscope, func = self, isparam = paramidx, seq = self.nameseq, name = n }
	if isparam then
		self.params[#self.params+1] = newscope
	end
	self.scopes[#self.scopes+1] = n
	self.names[n] = newscope
	return newscope
end

-- Declare a global name, or with n = '*' the default for names not declared.
-- names['*'] is nil (all names are global), { strict = true } (names must be declared), or a global * declaration
function asmmeta:globaldecl(n, decl)
	decl.prev = self.names[n]
	decl.global = true
	self.scopes[#self.scopes+1] = n
	self.names[n] = decl
	-- after n, so a goto error names n rather than this implicit '*'
	if n ~= '*' and not self.names['*'] then
		self:globaldecl('*', { strict = true })
	end
end

-- Close the k newest <close> variables, by calling the prelude's helper (from fakereqenv).
-- Returns the pc of k's const index, so a goto can patch it once the count is known
function asmmeta:tbcclose(k, force)
	if k > 0 or force then
		self:push(bc.LoadConst, self:const(assert(_tbcclose, 'no to-be-closed helper')))
		local kpc = #self.bc + 2
		self:push(bc.LoadConst, self:const(k))
		self:push(bc.Call, 0, 1, 1)
		-- names the __close calls in tracebacks
		self:opname({ "metamethod 'close'", call = true })
		return kpc
	end
end
-- After the value v of a <close> variable is stored, check it can be closed & keep it to close later.
-- v is left by emit()
function asmmeta:tbcpush(emit, name)
	self:push(bc.LoadConst, self:const(assert(_tbcpush, 'no to-be-closed helper')))
	emit()
	self:push(bc.LoadConst, self:const(name))
	self:push(bc.Call, 0, 1, 2)
	self:opname({ false, call = true })
	self.tbcn = self.tbcn + 1
end

local function consterr(n)
	error("attempt to assign to const variable '" .. n .. "'")
end
-- isstore: node is assigned to, so check it isn't const
function asmmeta:usename(node, isstore)
	local name = self.names[node.arg]
	if not name then
		name = self.names['*']
		if name and name.strict then
			error("variable '" .. node.arg .. "' not declared")
		end
	end
	if name and isstore and name.attrib then
		consterr(node.arg)
	end
	if name and not name.global then
		self.namety[node] = name
	else
		name = assert(self.names._ENV)
		if name.global then
			error("_ENV is global when accessing variable '" .. node.arg .. "'")
		end
		self.namety[node] = { env = name }
	end
	if name.func ~= self then
		if name.free then
			name.free[self] = true
		else
			name.free = { [self] = true }
		end
	end
end

local namety_loads = {
	Param = bc.LoadParam,
	Local = bc.LoadLocal,
	ParamBox = bc.LoadParamBox,
	LocalBox = bc.LoadLocalBox,
	FreeBox = bc.LoadFreeBox,
	Env = bc.Idx,
}
local namety_stores = {
	Param = bc.StoreParam,
	Local = bc.StoreLocal,
	ParamBox = bc.StoreParamBox,
	LocalBox = bc.StoreLocalBox,
	FreeBox = bc.StoreFreeBox,
	Env = bc.TblSet,
}
local function idxtbl(tbl, namety)
	local idx = #tbl
	tbl[namety] = idx
	tbl[idx+1] = namety
	return idx
end
function asmmeta:nameidx(namety)
	assert(namety)
	-- check outer function's names first: their params are our frees
	if namety.func ~= self then
		return self.frees[namety] or idxtbl(self.frees, namety)
	elseif namety.isparam then
		return namety.isparam
	else
		return self.locals[namety] or idxtbl(self.locals, namety)
	end
end
function asmmeta:opnamety(ops, name, namety)
	-- globals ({env = _ENV's namety}) have no slot of their own, don't give them one
	local idx = not namety.env and self:nameidx(namety)
	if namety.env then
		self:opnamety(namety_loads, nil, namety.env)
		self:push(bc.LoadConst, self:const(name.arg))
		self:push(ops.Env)
		self:opname({ self:scopedesc(namety.env, '_ENV') })
	elseif namety.free then
		if namety.func ~= self then
			self:push(ops.FreeBox, idx)
		elseif namety.isparam then
			self:push(ops.ParamBox, idx)
		else
			self:push(ops.LocalBox, idx)
		end
	elseif namety.isparam then
		self:push(ops.Param, idx)
	else
		self:push(ops.Local, idx)
	end
end
-- What a variable is, for error messages: "local 'x'", "upvalue 'x'" or "global 'x'"
function asmmeta:scopedesc(namety, n)
	if namety.env then
		return "global '" .. n .. "'"
	elseif namety.func ~= self then
		return "upvalue '" .. n .. "'"
	else
		return "local '" .. n .. "'"
	end
end
function asmmeta:opname(descs)
	self.opnames[#self.bc] = descs
end
function asmmeta:loadname(name)
	self:opnamety(namety_loads, name, self.namety[name])
	self.desc = self:scopedesc(self.namety[name], name.arg)
end
function asmmeta:storename(name)
	return self:opnamety(namety_stores, name, self.namety[name])
end
-- A captured local gets a fresh box each time it's declared,
-- so closures made in a loop each keep their own variable
function asmmeta:boxname(name)
	local namety = self.namety[name]
	if namety and namety.free and namety.func == self and not namety.isparam then
		self:push(bc.BoxLocal, self:nameidx(namety))
	end
end
-- Raise "global 'x' already defined" if global x isn't nil, before global x = e sets it
function asmmeta:checkglobal(name)
	self:loadname(name)
	self.desc = nil
	self:push(bc.ErrNNil, self:const(name.arg))
end
-- A local comes into scope at the current pc
function asmmeta:activate(namety)
	local v = { namety = namety, startpc = #self.bc }
	self.locvars[#self.locvars+1] = v
	self.actives[#self.actives+1] = v
end
-- Locals declared after the first n0 go out of scope here
function asmmeta:deactivate(n0)
	local a = self.actives
	for i=#a, n0+1, -1 do
		a[i].endpc = #self.bc
		a[i] = nil
	end
end
-- The last k locals were declared last first, put them in order
function asmmeta:inorder(k)
	local a, lv = self.actives, self.locvars
	for i = 1, k // 2 do
		local j, m = #a - k + i, #a + 1 - i
		a[j], a[m] = a[m], a[j]
		j, m = #lv - k + i, #lv + 1 - i
		lv[j], lv[m] = lv[m], lv[j]
	end
end
function asmmeta:declname(name)
	self:boxname(name)
	self:storename(name)
	self:activate(self.namety[name])
end

local nextNode = {}
for k,ty in pairs(ast) do
	nextNode[ty] = function(node, i)
		while i <= #node do
			local child = node[i]
			i = i + 1
			if (child.type & 31) == ty then
				return i, child
			end
		end
	end
end

local function hasToken(node, ty)
	for i=1, #node do
		local child = node[i]
		if child.type == -1 and child.val == ty then
			return true
		end
	end
	return false
end

local function nextMask(ty)
	return function(node, i)
		while i <= #node do
			local child = node[i]
			i = i + 1
			if child.type == -1 and child.val == ty then
				return i, child
			end
		end
	end
end
local nextString = nextMask(lex._string)
local nextNumber = nextMask(lex._number)
local nextIdent = nextMask(lex._ident)

local function selectNodes(node, ty)
	return nextNode[ty], node, 1
end
local function selectNode(node, ty)
	local i, n = nextNode[ty](node, 1)
	return n
end

local function selectIdents(node)
	return nextIdent, node, 1
end
local function selectIdent(node)
	local i, n = nextIdent(node, 1)
	return n
end

-- An attnamelist's names as { name = ident, attrib = 'const' or 'close' or nil }
local function attnames(node)
	local list, all = {}
	for i=1, #node do
		local c = node[i]
		if c.type == -1 and c.val == lex._ident then
			list[#list+1] = { name = c, attrib = all }
		elseif c.type == ast.Attrib then
			local a = selectIdent(c).arg
			if a ~= 'const' and a ~= 'close' then
				error("unknown attribute '" .. a .. "'")
			end
			if #list == 0 then
				all = a
			else
				list[#list].attrib = a
			end
		end
	end
	return list
end

local unOps = { bc.Neg, bc.Not, bc.Len, bc.BNot }
local binOps = { bc.Add, bc.Sub, bc.Mul, bc.Div, bc.IDiv, bc.Pow, bc.Mod,
	bc.BAnd, bc.BXor, bc.BOr, bc.Shr, bc.Shl, bc.Concat,
	bc.CmpLt, bc.CmpLe, bc.CmpGt, bc.CmpGe, bc.CmpEq }
local scopeStatSwitch, emitStatSwitch, emitValueSwitch, emitFieldSwitch, visitScope, emitScope

local function singleNode(self, node, ty, fn, ...)
	local sn = selectNode(node, ty)
	if sn then
		return fn(self, sn, ...)
	end
end
local function multiNodes(self, node, ty, fn, ...)
	for i, node in selectNodes(node, ty) do
		fn(self, node, ...)
	end
end
local function scopeNode(self, node, ty, ...)
	return singleNode(self, node, ty, visitScope[ty], ...)
end
local function emitNode(self, node, ty, ...)
	return singleNode(self, node, ty, visitEmit[ty], ...)
end
local function scopeNodes(self, node, ty, ...)
	return multiNodes(self, node, ty, visitScope[ty], ...)
end
local function emitNodes(self, node, ty, ...)
	return multiNodes(self, node, ty, visitEmit[ty], ...)
end

local ExpUnop, ExpValue = ast.Exp+32, ast.Exp+64
local precedenceTable = {7, 7, 8, 8, 8, 9, 8, 5, 4, 3, 6, 6, 2, 1, 1, 1, 1, 1, 1}
-- Unary ops bind tighter than everything but ^
local unopPrecedence = 8.5
local function precedence(node)
	local ty = node.type&31
	if ty == ast.Binop then
		return precedenceTable[node.type >> 5]
	elseif ty == ast.Unop then
		return unopPrecedence
	else
		return 0
	end
end
-- An Exp's values & operators in postfix order, as a list.
-- The parser nests `#a + b` as #(a + b), so unary ops are reordered here too
local function shunt(node)
	local out, ops = {}, {}
	while true do
		while node.type == ExpUnop do
			ops[#ops+1] = selectNode(node, ast.Unop)
			node = selectNode(node, ast.Exp)
		end
		if #node ~= 3 then
			break
		end
		local lson, op, rson = table.unpack(node)
		out[#out+1] = lson
		while #ops > 0 do
			local oprec = precedence(op)
			-- ^ is right associative
			if precedence(ops[#ops]) < oprec or oprec == 9 then
				break
			end
			out[#out+1] = ops[#ops]
			ops[#ops] = nil
		end
		ops[#ops+1] = op
		node = rson
	end
	out[#out+1] = selectNode(node, ast.Value)
	for i=#ops, 1, -1 do
		out[#out+1] = ops[i]
	end
	return out
end

scopeStatSwitch = {
	function(self, node) -- 1 vars=exps
		scopeNodes(self, node, ast.ExpOr)
		scopeNodes(self, node, ast.Var)
	end,
	function(self, node) -- 2 call
		scopeNode(self, node, ast.Prefix)
		scopeNodes(self, node, ast.Suffix)
		scopeNode(self, node, ast.Args)
	end,
	function(self, node, block) -- 3 label
		-- a name can be reused in other blocks, not in this block or one around it
		local name = selectIdent(node).arg
		local sc = self.scopes
		while sc do
			local ls = self.labelscope[sc]
			if ls and ls[name] then
				error("label '" .. name .. "' already defined")
			end
			sc = sc.prev
		end
		local ls = self.labelscope[self.scopes]
		if not ls then
			ls = {}
			self.labelscope[self.scopes] = ls
		end
		ls[name] = node
		self.labelcount[node] = self.endlabel[node] or #self.scopes
	end,
	nop, -- 4 break
	function(self, node) -- 5 goto
		-- remember how many names each block around has declared here,
		-- so a goto forward past a declaration can be caught
		local counts, sc = {}, self.scopes
		while sc do
			counts[sc] = #sc
			sc = sc.prev
		end
		self.gotoscope[node] = { sc = self.scopes, counts = counts }
	end,
	function(self, node) -- 6 do-end
		self:scope(function()
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 7 while
		self:scope(function()
			scopeNode(self, node, ast.ExpOr)
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 8 repeat
		self:scope(function()
			scopeNode(self, node, ast.Block, true)
			scopeNode(self, node, ast.ExpOr)
		end)
	end,
	function(self, node) -- 9 if
		scopeNodes(self, node, ast.ExpOr)
		for i, block in selectNodes(node, ast.Block) do
			self:scope(function()
				visitScope[ast.Block](self, block)
			end)
		end
	end,
	function(self, node) -- 10 for
		self:scope(function()
			scopeNodes(self, node, ast.ExpOr)
			local name = selectIdent(node)
			self:name(name.arg).attrib = 'const'
			self:usename(name)
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 11 generic for
		self:scope(function()
			scopeNodes(self, node, ast.ExpOr)
			-- only the first name is read only in 5.5
			local first = true
			for i, name in selectIdents(node) do
				local n = self:name(name.arg)
				if first then
					n.attrib = 'const'
					first = false
				end
				self:usename(name)
			end
			scopeNode(self, node, ast.Block)
		end)
	end,
	function(self, node) -- 12 func
		local i, first = nextIdent(node, 1)
		-- function f() assigns f, function a.f() doesn't assign a
		self:usename(first, not nextIdent(node, i) and not hasToken(node, lex._colon))
		-- name for debug info: a.b:c
		local fname = first.arg
		local ismeth = hasToken(node, lex._colon)
		local j, n = i, nil
		while true do
			j, n = nextIdent(node, j)
			if not n then
				break
			end
			fname = fname .. ((ismeth and not nextIdent(node, j)) and ':' or '.') .. n.arg
		end
		self.funcname = fname
		scopeNode(self, node, ast.Funcbody, ismeth)
	end,
	function(self, node) -- 13 local func
		local name = selectIdent(node)
		self:name(name.arg)
		self:usename(name)
		self.funcname = name.arg
		scopeNode(self, node, ast.Funcbody)
	end,
	function(self, node) -- 14 locals=exps
		scopeNodes(self, node, ast.ExpOr)
		local closes = 0
		for i, v in ipairs(attnames(node)) do
			-- TODO <close> is only read only for now, __close isn't called
			if v.attrib == 'close' then
				closes = closes + 1
				if closes > 1 then
					error('multiple to-be-closed variables in local list')
				end
			end
			self:name(v.name.arg).attrib = v.attrib
			self:usename(v.name)
		end
	end,
	function(self, node) -- 15 global func
		local name = selectIdent(node)
		self:globaldecl(name.arg, {})
		self:usename(name)
		self.funcname = name.arg
		scopeNode(self, node, ast.Funcbody)
	end,
	function(self, node) -- 16 global *
		local attrib = selectNode(node, ast.Attrib)
		attrib = attrib and selectIdent(attrib).arg
		if attrib and attrib ~= 'const' then
			error(attrib == 'close' and 'global variables cannot be to-be-closed' or "unknown attribute '" .. attrib .. "'")
		end
		self:globaldecl('*', { attrib = attrib })
	end,
	function(self, node) -- 17 globals=exps
		scopeNodes(self, node, ast.ExpOr)
		local hasexps = selectNode(node, ast.ExpOr)
		for i, v in ipairs(attnames(node)) do
			if v.attrib == 'close' then
				error('global variables cannot be to-be-closed')
			end
			self:globaldecl(v.name.arg, { attrib = v.attrib })
			if hasexps then
				self:usename(v.name)
			end
		end
	end,
}
local function emitCall(self, node, outputs)
	local methname = selectIdent(node)
	local fdesc = self.desc or false
	if methname then
		local temp = idxtbl(self.locals, methname)
		self:push(bc.StoreLocal, temp)
		self:push(bc.LoadLocal, temp)
		self:push(bc.LoadConst, self:const(methname.arg))
		self:push(bc.Idx)
		self:opname({ fdesc })
		self:push(bc.LoadLocal, temp)
		fdesc = "method '" .. methname.arg .. "'"
	end
	-- a method call passes self as an extra first arg
	local r = emitNode(self, node, ast.Args, outputs, methname and 1 or 0, fdesc)
	self.desc = nil
	return r
end
local function emitExplist(self, node, outputs)
	local n, lastv = 0
	for i, v in selectNodes(node, ast.ExpOr) do
		if lastv then
			if outputs == 0 then
				visitEmit[ast.ExpOr](self, lastv, 0)
			else
				if outputs ~= -1 then
					outputs = outputs - 1
				end
				n = n + visitEmit[ast.ExpOr](self, lastv, 1)
			end
		end
		lastv = v
	end
	if lastv then
		return n, visitEmit[ast.ExpOr](self, lastv, outputs)
	elseif outputs > 0 then
		-- no expressions, eg `local a, b`: all nil
		for i=1,outputs do
			self:push(bc.LoadNil)
		end
		return n, outputs
	else
		return n, 0
	end
end
emitStatSwitch = {
	function(self, node) -- 1 vars=exps
		local vars = {}
		for i, v in selectNodes(node, ast.Var) do
			vars[#vars+1] = v
		end
		emitExplist(self, node, #vars)
		-- TODO evaluate in order
		for i=#vars,1,-1 do
			visitEmit[ast.Var](self, vars[i], false)
		end
	end,
	function(self, node) -- 2 call
		emitNode(self, node, ast.Prefix)
		emitNodes(self, node, ast.Suffix, function(node)
			emitCall(self, node, 0)
		end)
	end,
	function(self, node) -- 3 label
		self.labels[node] = #self.bc
		self.labeltbc[node] = self.tbcn
	end,
	function(self, node) -- 4 break
		assert(self.breaks, "break outside of loop")
		self:tbcclose(self.tbcn - self.breaks.tbcn)
		self.breaks[#self.breaks+1] = #self.bc+2
		self:push(bc.Jmp, 0)
	end,
	function(self, node) -- 5 goto
		local name = selectIdent(node)
		local namei = name.arg
		-- the nearest label of that name in this block or one around it
		local info = self.gotoscope[node]
		local sc, label = info.sc
		while sc do
			label = self.labelscope[sc] and self.labelscope[sc][namei]
			if label then
				break
			end
			sc = sc.prev
		end
		if not label then
			error("no visible label '" .. namei .. "' for goto")
		end
		-- the label can't see a name the goto doesn't
		local gc = info.counts[sc]
		if self.labelcount[label] > gc then
			-- sc has at least gc+1 names of its own, so sc[gc+1] is its own
			error("<goto " .. namei .. "> at line " .. (node.line or self.curline or 0) ..
				" jumps into the scope of '" .. sc[gc + 1] .. "'")
		end
		-- close the <close> variables the jump leaves, how many is known once the label is emitted
		local kpc = self.tbcn > 0 and self:tbcclose(0, true)
		self.gotos[#self.bc+2] = label
		if kpc then
			self.gototbc[#self.bc+2] = { tbcn = self.tbcn, pc = kpc }
		end
		self:push(bc.Jmp, 0)
	end,
	function(self, node) -- 6 do-end
		return emitNode(self, node, ast.Block)
	end,
	function(self, node) -- 7 while
		self:breakscope(function()
			local soc = #self.bc
			emitNode(self, node, ast.ExpOr, 1)
			local jmp = #self.bc+2
			self:push(bc.JifNot, 0)
			emitNode(self, node, ast.Block)
			self:push(bc.Jmp, soc)
			self:patch(jmp, #self.bc)
		end)
	end,
	function(self, node) -- 8 repeat
		self:breakscope(function()
			local soc = #self.bc
			-- the block's locals are in scope in until, so they're closed after it on both ways out
			local tbc0, n0 = emitNode(self, node, ast.Block, true)
			emitNode(self, node, ast.ExpOr, 1)
			self:tbcclose(self.tbcn - tbc0)
			self.tbcn = tbc0
			self:deactivate(n0)
			self:push(bc.JifNot, soc)
		end)
	end,
	function(self, node) -- 9 if
		local eob, condbr = {}
		for i=1, #node do
			local child = node[i]
			local ty = child.type&31
			if ty == ast.ExpOr then
				visitEmit[ast.ExpOr](self, child, 1)
				condbr = #self.bc+2
				self:push(bc.JifNot, 0)
			elseif ty == ast.Block then
				visitEmit[ast.Block](self, child)
				-- jump to the end, unless this is the last branch
				if i < #node then
					eob[#eob+1] = #self.bc+2
					self:push(bc.Jmp, 0)
				end
				if condbr then
					self:patch(condbr, #self.bc)
					condbr = nil
				end
			end
		end
		for i=1,#eob do
			self:patch(eob[i], #self.bc)
		end
	end,
	function(self, node) -- 10 for
		-- TODO float increment causes initial value to be a float
		local exps=0
		for i, n in selectNodes(node, ast.ExpOr) do
			visitEmit[ast.ExpOr](self, n, 1)
			exps = exps+1
		end
		if exps == 2 then
			self:push(bc.LoadConst, self:const(1))
		end
		local tempi = idxtbl(self.locals, {})
		local tempc = idxtbl(self.locals, {})
		local temps = idxtbl(self.locals, {})
		local temptemp = idxtbl(self.locals, {})
		self:push(bc.StoreLocal, temps)
		self:push(bc.StoreLocal, tempc)
		self:push(bc.StoreLocal, tempi)
		self:push(bc.LoadLocal, temps)
		self:push(bc.LoadConst, self:const(0))
		self:push(bc.CmpGe)
		self:push(bc.StoreLocal, temptemp)
		local incrdecr = #self.bc
		self:push(bc.LoadLocal, tempi)
		self:push(bc.LoadLocal, tempc)
		self:push(bc.LoadLocal, temptemp)
		-- exit when i < c for a negative step, i > c otherwise
		local cmp0 = #self.bc+2
		self:push(bc.Jif, 0)
		self:push(bc.CmpLt)
		local cmp1 = #self.bc+2
		self:push(bc.Jmp, 0)
		self:patch(cmp0, #self.bc)
		self:push(bc.CmpGt)
		self:patch(cmp1, #self.bc)
		local forxit = #self.bc+2
		self:push(bc.Jif, 0)
		self:push(bc.LoadLocal, tempi)
		local n0 = #self.actives
		self:declname(selectIdent(node))
		self:breakscope(function()
			emitNode(self, node, ast.Block)
			self:push(bc.LoadLocal, tempi)
			self:push(bc.LoadLocal, temps)
			self:push(bc.Add)
			self:push(bc.StoreLocal, tempi)
			self:push(bc.Jmp, incrdecr)
		end)
		self:deactivate(n0)
		self:patch(forxit, #self.bc)
	end,
	function(self, node) -- 11 generic for
		-- a 4th value is closed when the loop ends. Not in the prelude, which is built without the helpers
		local closing = _tbcpush ~= nil
		emitExplist(self, node, closing and 4 or 3)
		local tempf = idxtbl(self.locals, {})
		local temps = idxtbl(self.locals, {})
		local tempv = idxtbl(self.locals, {})
		if closing then
			local tempc = idxtbl(self.locals, {})
			self:push(bc.StoreLocal, tempc)
			self:tbcpush(function() self:push(bc.LoadLocal, tempc) end, '(for state)')
		end
		self:push(bc.StoreLocal, tempv)
		self:push(bc.StoreLocal, temps)
		self:push(bc.StoreLocal, tempf)
		local begfor = #self.bc
		self:push(bc.LoadLocal, tempf)
		self:push(bc.LoadLocal, temps)
		self:push(bc.LoadLocal, tempv)
		local vars = {}
		for i, v in selectIdents(node) do
			vars[#vars+1] = v
		end
		self:push(bc.Call, #vars, 1, 2) -- f(s, ctl): 2 args
		self:opname({ "for iterator 'for iterator'", call = true })
		local n0 = #self.actives
		for i=#vars,2,-1 do
			self:declname(vars[i])
		end
		self:push(bc.StoreLocal, tempv)
		self:push(bc.LoadLocal, tempv)
		self:push(bc.LoadNil)
		self:push(bc.CmpEq)
		local forxit = #self.bc+2
		self:push(bc.Jif, 0)
		self:push(bc.LoadLocal, tempv)
		self:declname(vars[1])
		self:inorder(#vars)
		self:breakscope(function()
			emitNode(self, node, ast.Block)
			self:push(bc.Jmp, begfor)
		end)
		self:deactivate(n0)
		self:patch(forxit, #self.bc)
		if closing then
			-- breaks land here too, so they don't close it themselves (breakscope saw it counted)
			self:tbcclose(1)
			self.tbcn = self.tbcn - 1
		end
	end,
	function(self, node) -- 12 func
		emitNode(self, node, ast.Funcbody)
		local first, nlast = true
		for i, name in selectIdents(node) do
			if nlast then
				if first then
					self:loadname(nlast)
					first = false
				else
					self:push(bc.LoadConst, self:const(nlast.arg))
					self:push(bc.Idx)
				end
			end
			nlast = name
		end
		if first then
			self:storename(nlast)
		else
			self:push(bc.LoadConst, self:const(nlast.arg))
			self:push(bc.TblSet)
		end
	end,
	function(self, node) -- 13 local func
		-- box first, so a recursive function captures its own box
		local name = selectIdent(node)
		self:boxname(name)
		emitNode(self, node, ast.Funcbody)
		self:storename(name)
		self:activate(self.namety[name])
	end,
	function(self, node) -- 14 locals=exps
		local vars = {}
		for i, v in selectIdents(node) do
			vars[#vars+1] = v
		end
		emitExplist(self, node, #vars)
		for i=#vars,1,-1 do
			self:declname(vars[i])
		end
		self:inorder(#vars)
		for i=1,#vars do
			if self.namety[vars[i]].attrib == 'close' then
				self:tbcpush(function() self:loadname(vars[i]) end, vars[i].arg)
			end
		end
	end,
	function(self, node) -- 15 global func
		emitNode(self, node, ast.Funcbody)
		self:checkglobal(selectIdent(node))
		self:storename(selectIdent(node))
	end,
	nop, -- 16 global *
	function(self, node) -- 17 globals=exps
		-- without = the globals keep their values
		if selectNode(node, ast.ExpOr) then
			local vars = {}
			for i, v in selectIdents(node) do
				vars[#vars+1] = v
			end
			emitExplist(self, node, #vars)
			for i=#vars,1,-1 do
				self:checkglobal(vars[i])
				self:storename(vars[i])
			end
		end
	end,
}
local function emit0(fn)
	return function(self, node, outputs)
		if outputs == 0 then
			return 0
		else
			return fn(self, node, outputs)
		end
	end
end
emitValueSwitch = {
	emit0(function(self, node, outputs) -- 1 nil
		self:push(bc.LoadNil)
		return 1
	end),
	emit0(function(self, node, outputs) -- 2 false
		self:push(bc.LoadFalse)
		return 1
	end),
	emit0(function(self, node, outputs) -- 3 true
		self:push(bc.LoadTrue)
		return 1
	end),
	emit0(function(self, node, outputs) -- 4 num
		local i, val = nextNumber(node, 1)
		self:push(bc.LoadConst, self:const(val.arg))
		return 1
	end),
	emit0(function(self, node, outputs) -- 5 str
		local i, val = nextString(node, 1)
		self:push(bc.LoadConst, self:const(val.arg))
		return 1
	end),
	emit0(function(self, node, outputs) -- 6 ...
		if self.vargname then
			-- with a named vararg table t, ... is t[1..t.n]: call the prelude's helper on t
			self:push(bc.LoadConst, self:const(assert(_vargunpack, 'no vararg table helper')))
			self:loadname(self.vargname)
			self.desc = nil
			if outputs == -1 then
				return { 1, descs = { false, call = true }, line = self.curline }
			end
			self:push(bc.Call, outputs, 1, 1)
			self:opname({ false, call = true })
			return outputs
		end
		if outputs == -1 then
			return { varg = true }
		else
			self:push(bc.LoadVarg, outputs)
			return outputs
		end
	end),
	emit0(function(self, node, outputs) -- 7 Funcbody
		emitNode(self, node, ast.Funcbody)
		return 1
	end),
	function(self, node, outputs) -- 8 Table
		emitNode(self, node, ast.Table)
		return 1
	end,
	function(self, node, outputs) -- 9 Prefix Suffix?
		emitNode(self, node, ast.Prefix)
		local res = 1
		emitNodes(self, node, ast.Suffix, function(node)
			if node.type >> 5 == 1 then
				res = emitCall(self, node, outputs)
			else
				emitNode(self, node, ast.Index, true)
			end
		end)
		return res
	end,
}
emitFieldSwitch = {
	function(self, node) -- 1 [exp] = exp
		local f, obj, idx = selectNodes(node, ast.ExpOr)
		local i, key = f(obj, idx)
		visitEmit[ast.ExpOr](self, key, 1)
		local i, val = f(obj, i)
		visitEmit[ast.ExpOr](self, val, 1)
		self:push(bc.TblAdd)
	end,
	function(self, node) -- 2 name = exp
		local i, val = nextIdent(node, 1)
		self:push(bc.LoadConst, self:const(val.arg))
		emitNode(self, node, ast.ExpOr, 1)
		self:push(bc.TblAdd)
	end,
	function(self, node, ary) -- 3 exp
		ary[#ary+1] = node
	end
}
visitScope = {
	[ast.Block] = function(self, node, isrepeat)
		-- Labels with only labels after them end the block, so the block's names are out of scope there.
		-- Not so before a return, or in repeat, where until can see the names
		if not isrepeat and not hasToken(node, lex._return) then
			local stats = {}
			for i, st in selectNodes(node, ast.Stat) do
				stats[#stats+1] = st
			end
			local start = #self.scopes
			for i=#stats, 1, -1 do
				if stats[i].type >> 5 ~= 3 then
					break
				end
				self.endlabel[stats[i]] = start
			end
		end
		scopeNodes(self, node, ast.Stat, node)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Stat] = function(self, node, block)
		return scopeStatSwitch[node.type >> 5](self, node, block)
	end,
	[ast.Var] = function(self, node)
		if node.type >> 5 == 1 then
			scopeNode(self, node, ast.Prefix)
			scopeNodes(self, node, ast.Suffix)
			scopeNode(self, node, ast.Index)
		else
			self:usename(selectIdent(node), true)
		end
	end,
	[ast.Exp] = function(self, node)
		scopeNodes(self, node, ast.Value)
		scopeNodes(self, node, ast.Exp)
	end,
	[ast.Prefix] = function(self, node)
		if node.type >> 5 == 1 then
			self:usename(selectIdent(node))
		else
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Args] = function(self, node)
		local t = node.type >> 5
		if t == 1 then
			scopeNodes(self, node, ast.ExpOr)
		elseif t == 2 then
			scopeNode(self, node, ast.Table)
		end
	end,
	[ast.Funcbody] = function(self, node, isMeth)
		-- names before ... are params, a name after it (5.5 `...t`) gets a table of the varargs
		local names, vargname, isvarg = {}
		for i=1, #node do
			local c = node[i]
			if c.type == -1 and c.val == lex._dotdotdot then
				isvarg = true
			elseif c.type == -1 and c.val == lex._ident then
				if isvarg then
					vargname = c
				else
					names[#names+1] = c
				end
			end
		end
		local asm = Assembler()
		asm.scopes = self.scopes
		asm.names = self.names
		asm.isdotdotdot = isvarg
		asm.vargname = vargname
		asm.fname = self.funcname
		self.funcname = nil
		asm.linedefined = node.line
		asm.lastlinedefined = node.lastline
		asm:scope(function()
			if isMeth then
				asm:name('self', true)
			end
			for i=1,#names do
				asm:name(names[i].arg, true)
			end
			if vargname then
				-- the vararg table's name is read-only
				asm:name(vargname.arg).attrib = 'const'
				asm:usename(vargname)
			end
			scopeNode(asm, node, ast.Block)
		end)
		asm:genBoxPrologue()
		if vargname then
			-- t = { n = number of varargs, ... }
			asm:push(bc.TblNew)
			asm:push(bc.LoadConst, asm:const('n'))
			asm:push(bc.VargCount)
			asm:push(bc.TblAdd)
			asm:push(bc.AppendVarg, 0)
			asm:declname(vargname)
		end
		emitNode(asm, node, ast.Block)
		asm:synth()
		-- Capture exactly asm's frees in index order. This includes frees only
		-- passed through to nested functions, which aren't in asm.namety
		local func = { func = asm }
		for i, v in ipairs(asm.frees) do
			v.free[self] = true
			func[i] = v
		end
		self.funcs[node] = func
	end,
	[ast.Table] = function(self, node)
		scopeNodes(self, node, ast.Field)
	end,
	[ast.Field] = function(self, node)
		scopeNodes(self, node, ast.ExpOr)
	end,
	[ast.Binop] = nop,
	[ast.Unop] = nop,
	[ast.Value] = function(self, node)
		local t = node.type >> 5
		if t == 7 then
			scopeNode(self, node, ast.Funcbody)
		elseif t == 8 then
			scopeNode(self, node, ast.Table)
		elseif t == 9 then
			scopeNode(self, node, ast.Prefix)
			scopeNodes(self, node, ast.Suffix)
			scopeNode(self, node, ast.Args)
		elseif t == 10 then
			scopeNode(self, node, ast.Var)
		elseif t == 11 then
			scopeNode(self, node, ast.ExpOr)
		else
			assert(t ~= 6 or self.isdotdotdot, '... outside of ... context')
		end
	end,
	[ast.Index] = function(self, node)
		if node.type >> 5 == 1 then
			scopeNode(self, node, ast.ExpOr)
		end
	end,
	[ast.Suffix] = function(self, node)
		if node.type >> 5 == 1 then
			scopeNode(self, node, ast.Args)
		else
			scopeNode(self, node, ast.Index)
		end
		return scopeNode(self, node, ast.Suffix)
	end,
	[ast.ExpOr] = function(self, node)
		return scopeNodes(self, node, ast.ExpAnd)
	end,
	[ast.ExpAnd] = function(self, node)
		return scopeNodes(self, node, ast.Exp)
	end,
}
local function emitShortCircuitFactory(ty, opcode)
	return function(self, node, out)
		local prod
		if #node == 1 then
			prod = visitEmit[ty](self, node[1], out)
		else
			-- Jump between operands, all jumps land after the last operand.
			-- Note selectNodes' i is the next child index, not a count
			local labs, first = {}, true
			for i, n in selectNodes(node, ty) do
				if not first then
					labs[#labs+1] = #self.bc+2
					self:push(opcode, 0)
				end
				first = false
				visitEmit[ty](self, n, 1)
			end
			for j=1,#labs do
				self:patch(labs[j], #self.bc)
			end
			prod = 1
		end
		if out ~= -1 then
			-- too few values: pad with nil. too many: pop the extra
			for i=prod+1, out do
				self:push(bc.LoadNil)
			end
			for i=prod-1, out, -1 do
				self:push(bc.Pop)
			end
			return out
		else
			return prod
		end
	end
end
visitEmit = {
	-- keep: leave closing <close> variables & ending locals' scope to the caller, which gets the counts
	[ast.Block] = function(self, node, keep)
		local tbc0, n0 = self.tbcn, #self.actives
		emitNodes(self, node, ast.Stat)
		if hasToken(node, lex._return) then
			-- results are on the stack, then <close> variables are closed, then they're returned
			local n, res = emitExplist(self, node, -1)
			if type(res) == 'number' then
				self:tbcclose(self.tbcn)
				self:push(bc.Return)
			elseif #res > 0 then
				-- No tail calls yet: call keeping all results (retc 0xffff), then return them
				self.curline = res.line or self.curline
				self:push(res.varg and bc.CallVarg or bc.Call, 0xffff, #res, table.unpack(res))
				self:opname(res.descs)
				self:tbcclose(self.tbcn)
				self:push(bc.Return)
			else
				self:tbcclose(self.tbcn)
				self:push(bc.ReturnVarg)
			end
		elseif keep then
			return tbc0, n0
		else
			self:tbcclose(self.tbcn - tbc0)
		end
		self.tbcn = tbc0
		self:deactivate(n0)
	end,
	[ast.Stat] = function(self, node)
		return emitStatSwitch[node.type >> 5](self, node)
	end,
	[ast.Var] = function(self, node, isload)
		if node.type >> 5 == 1 then
			emitNode(self, node, ast.Prefix)
			emitNodes(self, node, ast.Suffix, function(node)
				emitNode(self, node, ast.Index, isload)
			end)
		else
			local name = selectIdent(node)
			if isload then
				self:loadname(name)
			else
				self:storename(name)
			end
		end
	end,
	[ast.Exp] = function(self, node, out)
		if node.type == ExpValue and #node == 1 then
			return visitEmit[ast.Value](self, node[1], out)
		end
		-- what made each operand on the stack, for error messages
		local descs = {}
		for _, op in ipairs(shunt(node)) do
			local ty = op.type & 31
			if ty == ast.Binop then
				visitEmit[ast.Binop](self, op)
				local d2 = table.remove(descs)
				local d1 = table.remove(descs)
				self:opname({ d1 or false, d2 or false })
				descs[#descs+1] = false
			elseif ty == ast.Unop then
				visitEmit[ast.Unop](self, op)
				self:opname({ table.remove(descs) or false })
				descs[#descs+1] = false
			else
				assert(ty == ast.Value)
				visitEmit[ast.Value](self, op, 1)
				descs[#descs+1] = op.type >> 5 == 9 and self.desc or false
			end
		end
		self.desc = nil
		return 1
	end,
	[ast.Prefix] = function(self, node)
		if node.type >> 5 == 1 then
			self:loadname(selectIdent(node))
		else
			emitNode(self, node, ast.ExpOr, 1)
			self.desc = nil
		end
	end,
	[ast.Args] = function(self, node, outputs, selfargs, fdesc)
		local ty, res = node.type >> 5
		if ty == 1 then
			local n
			n, res = emitExplist(self, node, -1)
			if type(res) == 'number' then
				res = { n + res }
			else
				-- Call reads arg counts outermost call first
				table.insert(res, 1, n)
			end
			-- names of the functions in the call chain, outermost first like the counts
			local descs = { fdesc or false, call = true }
			for i, d in ipairs(res.descs or {}) do
				descs[i+1] = d
			end
			res.descs = descs
		elseif ty == 2 then
			emitNode(self, node, ast.Table)
			res = { 1 }
		else
			self:push(bc.LoadConst, self:const(node[1].arg))
			res = { 1 }
		end
		res[1] = res[1] + selfargs
		res.descs = res.descs or { fdesc or false, call = true }
		res.line = self.curline
		if outputs == -1 then
			return res
		else
			local op
			if res.varg then
				op = bc.CallVarg
			else
				op = bc.Call
			end
			self:push(op, outputs, #res, table.unpack(res))
			self:opname(res.descs)
			return outputs
		end
	end,
	[ast.Funcbody] = function(self, node)
		local func = self.funcs[node]
		for i=1, #func do
			local name = func[i]
			local idx = self:nameidx(name)
			if name.func ~= self then
				self:push(bc.LoadFree, idx)
			elseif name.isparam then
				self:push(bc.LoadParam, idx)
			else
				self:push(bc.LoadLocal, idx)
			end
		end
		self:push(bc.LoadFunc, #func, self:const(func.func))
	end,
	[ast.Table] = function(self, node)
		self:push(bc.TblNew)
		local ary = {}
		emitNodes(self, node, ast.Field, ary)
		if #ary > 0 then
			for i=1,#ary-1 do
				emitNode(self, ary[i], ast.ExpOr, 1)
			end
			local res = emitNode(self, ary[#ary], ast.ExpOr, -1)
			if type(res) == 'number' then
				assert(res == 1, 'Somehow appending finite multiple values to table')
				self:push(bc.Append, #ary)
			elseif not res.varg then
				assert(#res > 0, 'None varg, no call, yet complex append')
				self.curline = res.line or self.curline
				self:push(bc.AppendCall, #ary-1, #res, table.unpack(res))
				self:opname(res.descs)
			elseif #res > 0 then
				self.curline = res.line or self.curline
				self:push(bc.AppendCallVarg, #ary-1, #res, table.unpack(res))
				self:opname(res.descs)
			else
				self:push(bc.AppendVarg, #ary-1)
			end
		end
	end,
	[ast.Field] = function(self, node, ary)
		return emitFieldSwitch[node.type >> 5](self, node, ary)
	end,
	[ast.Binop] = function(self, node)
		local op = binOps[node.type >> 5]
		if op then
			self:push(op)
		else
			self:push(bc.CmpEq)
			self:push(bc.Not)
		end
	end,
	[ast.Unop] = function(self, node)
		self:push(unOps[node.type >> 5])
	end,
	[ast.Value] = function(self, node, outputs)
		self.desc = nil
		local results = emitValueSwitch[node.type >> 5](self, node, outputs)
		if outputs ~= -1 then
			-- too few values: pad with nil. too many: pop the extra
			for i=results+1, outputs do
				self:push(bc.LoadNil)
			end
			for i=results-1, outputs, -1 do
				self:push(bc.Pop)
			end
			return outputs
		else
			return results
		end
	end,
	[ast.Index] = function(self, node, isload)
		local tdesc = self.desc or false
		local key
		if node.type >> 5 == 1 then
			emitNode(self, node, ast.ExpOr, 1)
		else
			key = selectIdent(node).arg
			self:push(bc.LoadConst, self:const(key))
		end
		if isload then
			self:push(bc.Idx)
		else
			self:push(bc.TblSet)
		end
		self:opname({ tdesc })
		self.desc = key and "field '" .. key .. "'" or nil
	end,
	[ast.Suffix] = function(self, node, tailfn)
		local nx = selectNode(node, ast.Suffix)
		if not nx then
			return tailfn(node)
		elseif node.type >> 5 == 1 then
			emitCall(self, node, 1)
		else
			emitNode(self, node, ast.Index, true)
		end
		return visitEmit[ast.Suffix](self, nx, tailfn)
	end,
	[ast.ExpOr] = emitShortCircuitFactory(ast.ExpAnd, bc.JifOrPop),
	[ast.ExpAnd] = emitShortCircuitFactory(ast.Exp, bc.JifNotOrPop),
}

function asmmeta:genBoxPrologue()
	for i=1,#self.params do
		local v = self.params[i]
		if v.free and v.func == self then
			self:push(bc.BoxParam, v.isparam)
		end
	end
	local pastlocal, boxed = {}, {}
	for k,v in pairs(self.namety) do
		-- params were boxed above
		if v.free and v.func == self and not v.isparam and not pastlocal[v] then
			pastlocal[v] = true
			boxed[#boxed+1] = v
		end
	end
	table.sort(boxed, function(a, b) return a.seq < b.seq end)
	for i=1,#boxed do
		self:push(bc.BoxLocal, self:nameidx(boxed[i]))
	end
end

function asmmeta:synth()
	for k, v in pairs(self.namety) do
		if not (v.isparam or self.locals[v] or self.frees[v]) then
			self.namety[k] = nil
		end
	end
	self:push(bc.Return)
	for k,v in pairs(self.gotos) do
		self:patch(k, self.labels[v])
		local t = self.gototbc[k]
		if t then
			self:patch(t.pc, self:const(t.tbcn - self.labeltbc[v]))
		end
	end
	local freenames = {}
	for i, v in ipairs(self.frees) do
		freenames[i] = v.name or '?'
	end
	self.freenames = freenames
	-- locals for debug.getlocal: { name, isparam, slot index, startpc, endpc }, params first.
	-- The main chunk's _ENV param is an upvalue in C Lua, so it's left out
	self:deactivate(0)
	local lv = {}
	for i = self.envparam and 2 or 1, #self.params do
		local v = self.params[i]
		lv[#lv+1] = { v.name, true, v.isparam, 0, #self.bc }
	end
	for _, v in ipairs(self.locvars) do
		local nt = v.namety
		if nt.isparam then
			lv[#lv+1] = { nt.name, true, nt.isparam, v.startpc, v.endpc }
		else
			lv[#lv+1] = { nt.name, false, self:nameidx(nt), v.startpc, v.endpc }
		end
	end
	self.locvars = lv
	return self
end

-- Every visit tracks the line of the node it's on, so pushed ops get the right line.
-- The line goes back to the parent's once a child is done, so a parent's op after its children gets the parent's line.
-- errline is the last line seen, for compile errors
local errline
local function lined(t)
	for k, fn in pairs(t) do
		t[k] = function(self, node, ...)
			local l = node.line
			if not l then
				return fn(self, node, ...)
			end
			errline = l
			local prev = self.curline
			self.curline = l
			local a, b = fn(self, node, ...)
			self.curline = prev
			return a, b
		end
	end
end
lined(visitScope)
lined(visitEmit)

local function gen(root)
	local asm = Assembler()
	asm.isdotdotdot = true
	asm:scope(function()
		asm:name('_ENV', true)
		asm.envparam = true
		visitScope[ast.Block](asm, root)
	end)
	asm:genBoxPrologue()
	visitEmit[ast.Block](asm, root)
	return asm:synth()
end
-- chunk is the source name for errors, like file.lua. Errors then start with chunk:line:
return function(root, chunk)
	if not chunk then
		return gen(root)
	end
	errline = nil
	local ok, asm = pcall(gen, root)
	if not ok then
		if type(asm) == 'string' then
			asm = chunk .. ':' .. (errline or '?') .. ': ' .. asm
		end
		error(asm, 0)
	end
	return asm
end