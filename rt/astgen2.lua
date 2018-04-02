local lex = require 'lex'
local ast = require 'ast'

local function s(token)
	return {
		op = 'q',
		token = token,
		tag = -1,
	}
end
local name = s(lex._ident)
local number = s(lex._number)
local slit = s(lex._string)

local function many(rule)
	return {
		op = '*',
		rule
	}
end
local function maybe(rule)
	return {
		op = '?',
		rule
	}
end
local function seq(...)
	return {
		op = '+',
		...
	}
end
local function oof(...)
	return {
		op = '|',
		...
	}
end
local function mkrule(dst, src)
	for k,v in pairs(src) do
		dst[k] = v
	end
end
local function sf(node, id, ...)
	return mkrule(node, {
		op = '+',
		tag = id,
		...
	})
end
local function of(node, id, ...)
	return mkrule(node, {
		op = '|',
		tag = id,
		...
	})
end
local Block, Stat, Var, ExpOr, ExpAnd, Exp, Prefix, Args, Funcbody, Table, Field, Binop, Unop, Value, Index, Suffix =
	{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}

local Explist = seq(ExpOr, many(seq(s(lex._comma), ExpOr)))
local Namelist = seq(name, many(seq(s(lex._comma), name)))
local Varlist = seq(Var, many(seq(s(lex._comma), Var)))
local Fieldsep = oof(s(lex._comma), s(lex._semi))
local Call = seq(maybe(seq(s(lex._colon), name)), Args)
local Funccall = seq(Prefix, many(Suffix), Call)
sf(Block, ast.Block, many(Stat), maybe(seq(s(lex._return), maybe(Explist), maybe(s(lex._semi)))))
of(Stat, ast.Stat,
	s(lex._semi),
	seq(Varlist, s(lex._set), Explist),
	Funccall,
	seq(s(lex._label), name, s(lex._label)),
	s(lex._break),
	seq(s(lex._goto), name),
	seq(s(lex._do), Block, s(lex._end)),
	seq(s(lex._while), ExpOr, s(lex._do), Block, s(lex._end)),
	seq(s(lex._repeat), Block, s(lex._until), ExpOr),
	seq(s(lex._if), ExpOr, s(lex._then), Block, many(seq(s(lex._elseif), ExpOr, s(lex._then), Block)), maybe(seq(s(lex._else), Block)), s(lex._end)),
	seq(s(lex._for), name, s(lex._set), ExpOr, s(lex._comma), ExpOr, maybe(seq(s(lex._comma), ExpOr)), s(lex._do), Block, s(lex._end)),
	seq(s(lex._for), Namelist, s(lex._in), Explist, s(lex._do), Block, s(lex._end)),
	seq(s(lex._function), name, many(seq(s(lex._dot), name)), maybe(seq(s(lex._colon), name)), Funcbody),
	seq(s(lex._local), s(lex._function), name, Funcbody),
	seq(s(lex._local), Namelist, maybe(seq(s(lex._set), Explist)))
)
of(Var, ast.Var, name, seq(Prefix, many(Suffix), Index))
sf(ExpOr, ast.ExpOr, ExpAnd, many(seq(s(lex._or), ExpAnd)))
sf(ExpAnd, ast.ExpAnd, Exp, many(seq(s(lex._and), Exp)))
of(Exp, ast.Exp, seq(Unop, Exp), seq(Value, maybe(seq(Binop, Exp))))
of(Prefix, ast.Prefix, name, seq(s(lex._pl), ExpOr, s(lex._pr)))
of(Args, ast.Args,
	seq(s(lex._pl), maybe(Explist), s(lex._pr)),
	Table,
	slit)
sf(Funcbody, ast.Funcbody, s(lex._pl), maybe(oof(seq(Namelist, maybe(seq(s(lex._comma), s(lex._dotdotdot)))), s(lex._dotdotdot))), s(lex._pr), Block, s(lex._end))
sf(Table, ast.Table, s(lex._cl), maybe(seq(Field, many(seq(Fieldsep, Field)), maybe(Fieldsep))), s(lex._cr))
of(Field, ast.Field,
	seq(s(lex._sl), ExpOr, s(lex._sr), s(lex._set), ExpOr),
	seq(name, s(lex._set), ExpOr),
	ExpOr)
of(Binop, ast.Binop,
	s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod),
	s(lex._band), s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot),
	s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq))
of(Unop, ast.Unop, s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot))
of(Value, ast.Value,
	s(lex._nil), s(lex._false), s(lex._true), number, slit, s(lex._dotdotdot),
	seq(s(lex._function), Funcbody), Table, Funccall, Var,
	seq(s(lex._pl), ExpOr, s(lex._pr)))
of(Index, ast.Index,
	seq(s(lex._sl), ExpOr, s(lex._sr)),
	seq(s(lex._dot), name))
of(Suffix, ast.Suffix, Call, Index)

return function(lx, vals)
	print('???')
	local sb = string.byte
	local a = seq(Block, s(0))
	pprint(a)
	st = {{ i = 1, n = 1, r = a }}
	while i <= #lx do
		local tok = sb(lx, i)
		i = i+1
	end
	exit()
	local laf = {}
	while i <= #lx do
		local tok = sb(lx, i)
		local res = {}
		local lef = {}
		for j=1, #a do
			local nx = a[j][tok]
			if nx then
				local lf = laf[j]
				for k=1,#nx do
					local idx = #res+1
					res[idx] = nx[k]()
					lef[idx] = { p = res[idx].p, tag = -1, li = i, up = lf }
				end
			end
		end
		assert(#res > 0)
		a = res
		laf = lef
		if tok > 63 then
			i = i + 5
		else
			i = i + 1
		end
	end
	print(#a, table.unpack(a))
	local a1 = laf[1]
	local root = a1.up
	while root.p do
		root = root.p
	end
	a1 = a1.up
	local p = a1
	print(p.tag, 'aaaaaa')
	while p do
		print(a1, a1.up, a1.p, a1.tag, a1.li, sb(lx, a1.li), p.p, p.tag)
		assert(p.p)
		assert(p.tag == -1)
		local pp = p.p
		while pp do
			print('\t', pp, p)
			if pp.fathered then
				pp.fathered[#pp.fathered] = p
			else
				pp.fathered = {p}
			end
			p = pp
			pp = pp.p
		end
		p = p.up
	end
	local BuilderMeta = {}
	function BuilderMeta:val()
		return sb(lx, self.li)
	end
	function BuilderMeta:arg()
		return vals[string.unpack('<i4', lx, self.li+1)+1]
	end
	local BuilderMT = { __index = BuilderMeta }
	local function nodey(p)
		local node = { type = p.tag, li = p.li, fathered = {} }
		if p.fathered then
			node.fathered = {}
			for i=1, #p.fathered do
				node.fathered[i] = nodey(p.fathered[i])
			end
		end
		return setmetatable(node, BuilderMT)
	end
	print('??', root.fathered, root)
	return nodey(root)
end
