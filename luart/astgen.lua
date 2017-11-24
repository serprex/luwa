local lex = require 'lex'
local ast = require 'ast'

local function iternone()
end
local function iterone(x, y)
	if not y then
		return x
	end
end
local function yieldall(...)
	for yi in ... do
		coroutine.yield(yi)
	end
end
return function(lx)
	local rules = {}

	local function name(x, p)
		local t = x:next(p)
		if t:val() == lex._ident then
			return iterone, t:skipint()
		else
			return iternone
		end
	end
	local function number(x, p)
		local t = x:next(p)
		if t:val() == lex._number then
			return iterone, t:skipint()
		else
			return iternone
		end
	end
	local function slit(x, p)
		local t = x:next(p)
		if t:val() == lex._string then
			return iterone, t:skipint()
		else
			return iternone
		end
	end
	local function s(r)
		return function(x, p)
			local t = x:next(p)
			if t:val() == r then
				return iterone, t
			else
				return iternone
			end
		end
	end
	local function o(n)
		return rules[n] or function(x, p)
			return rules[n](x, p)
		end
	end
	local function seqcore(x, p, xs, i)
		if i == #xs then
			return yieldall(xs[i](x, p))
		else
			for ax in xs[i](x, p) do
				seqcore(ax, p, xs, i+1)
			end
		end
	end
	local function seq(...)
		local xs = {...}
		return function(x, p)
			return coroutine.wrap(function()
				return seqcore(x, p, xs, 1)
			end)
		end
	end
	local function sf(o, ...)
		local seqf = seq(...)
		rules[o] = function(x, p)
			return seqf(x, x:spawn(o, p))
		end
	end
	local function many(f)
		local function manyf(x, p)
			for fx in f(x, p) do
				manyf(fx, p)
			end
			coroutine.yield(x)
		end
		return function(x, p)
			return coroutine.wrap(function()
				return manyf(x, p)
			end)
		end
	end
	local function maybe(f)
		return function(x, p)
			return coroutine.wrap(function()
				yieldall(f(x, p))
				coroutine.yield(x)
			end)
		end
	end
	local function of(o, ...)
		local xs = {...}
		rules[o] = function(x, p)
			return coroutine.wrap(function()
				local p = x:spawn(o, p)
				p.type = p.type + 32
				for i=1,#xs do
					yieldall(xs[i](x, p))
					p.type = p.type + 32
				end
			end)
		end
	end
	local function oof(...)
		local xs = {...}
		return function(x, p)
			return coroutine.wrap(function()
				for i=1,#xs do
					yieldall(xs[i](x, p))
				end
			end)
		end
	end
	local Explist = seq(o(ast.ExpOr), many(seq(s(lex._comma), o(ast.ExpOr))))
	local Namelist = seq(name, many(seq(s(lex._comma), name)))
	local Varlist = seq(o(ast.Var), many(seq(s(lex._comma), o(ast.Var))))
	local Fieldsep = oof(s(lex._comma), s(lex._semi))
	local Call = seq(maybe(seq(s(lex._colon), name)), o(ast.Args))
	local Funccall = seq(o(ast.Prefix), many(o(ast.Suffix)), Call)
	sf(ast.Block, many(o(ast.Stat)), maybe(seq(s(lex._return), maybe(Explist), maybe(s(lex._semi)))))
	of(ast.Stat,
		s(lex._semi),
		seq(Varlist, s(lex._set), Explist),
		Funccall,
		seq(s(lex._label), name, s(lex._label)),
		s(lex._break),
		seq(s(lex._goto), name),
		seq(s(lex._do), o(ast.Block), s(lex._end)),
		seq(s(lex._while), o(ast.ExpOr), s(lex._do), o(ast.Block), s(lex._end)),
		seq(s(lex._repeat), o(ast.Block), s(lex._until), o(ast.ExpOr)),
		seq(s(lex._if), o(ast.ExpOr), s(lex._then), o(ast.Block), many(seq(s(lex._elseif), o(ast.ExpOr), s(lex._then), o(ast.Block))), maybe(seq(s(lex._else), o(ast.Block))), s(lex._end)),
		seq(s(lex._for), name, s(lex._set), o(ast.ExpOr), s(lex._comma), o(ast.ExpOr), maybe(seq(s(lex._comma), o(ast.ExpOr))), s(lex._do), o(ast.Block), s(lex._end)),
		seq(s(lex._for), Namelist, s(lex._in), Explist, s(lex._do), o(ast.Block), s(lex._end)),
		seq(s(lex._function), seq(name, many(seq(s(lex._dot), name)), maybe(seq(s(lex._colon), name))), o(ast.Funcbody)),
		seq(s(lex._local), s(lex._function), name, o(ast.Funcbody)),
		seq(s(lex._local), Namelist, maybe(seq(s(lex._set), Explist)))
	)
	of(ast.Var, name, seq(o(ast.Prefix), many(o(ast.Suffix)), o(ast.Index)))
	of(ast.ExpOr, seq(o(ast.ExpAnd), many(seq(s(lex._or), o(ast.ExpAnd)))))
	of(ast.ExpAnd, seq(o(ast.Exp), many(seq(s(lex._and), o(ast.Exp)))))
	of(ast.Exp, seq(o(ast.Unop), o(ast.Exp)), seq(o(ast.Value), maybe(seq(o(ast.Binop), o(ast.Exp)))))
	of(ast.Prefix, name, seq(s(lex._pl), o(ast.ExpOr), s(lex._pr)))
	of(ast.Args,
		seq(s(lex._pl), maybe(Explist), s(lex._pr)),
		o(ast.Table),
		slit)
	sf(ast.Funcbody, s(lex._pl), maybe(oof(seq(Namelist, maybe(seq(s(lex._comma), s(lex._dotdotdot)))), s(lex._dotdotdot))), s(lex._pr), o(ast.Block), s(lex._end))
	sf(ast.Table, s(lex._cl), maybe(seq(o(ast.Field), many(seq(ast.Fieldsep, o(ast.Field))), maybe(ast.Fieldsep))), s(lex._cr))
	of(ast.Field,
		seq(s(lex._sl), o(ast.ExpOr), s(lex._sr), s(lex._set), o(ast.ExpOr)),
		seq(name, s(lex._set), o(ast.ExpOr)),
		o(ast.ExpOr))
	of(ast.Binop,
		s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod),
		s(lex._band), s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot),
		s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq))
	of(ast.Unop, s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot))
	of(ast.Value,
		s(lex._nil), s(lex._false), s(lex._true), number, slit, s(lex._dotdotdot),
		seq(s(lex._function), o(ast.Funcbody)), o(ast.Table), Funccall, o(ast.Var),
		seq(s(lex._pl), o(ast.ExpOr), s(lex._pr)))
	of(ast.Index,
		seq(s(lex._sl), o(ast.ExpOr), s(lex._sr)),
		seq(s(lex._dot), name))
	of(ast.Suffix, Call, o(ast.Index))

	local BuilderMeta = {}
	local BuilderMT = { __index = BuilderMeta }
	local function Builder(li, nx, mo, fa, ty)
		return setmetatable({
			li = li,
			nx = nx,
			type = ty,
			mother = mo,
			father = fa,
			fathered = {},
		}, BuilderMT)
	end
	function BuilderMeta:val()
		return string.byte(lx.lex, self.li)
	end
	function BuilderMeta:skipint()
		self.nx = self.nx+4
		return self
	end
	function BuilderMeta:int()
		return string.unpack('<i4', lx.lex, self.li+1)
	end
	function BuilderMeta:next(p)
		return Builder(self.nx, self.nx+1, self, p, -1)
	end
	function BuilderMeta:spawn(ty, p)
		return Builder(self.li, self.nx, self, p, ty)
	end

	local root = Builder(0, 1, nil, nil, -2)
	for i=1,#lx.lex,50 do
		print(i, table.concat({string.byte(lx.lex, i, i+49)}, ','))
	end
	for k,v in ipairs(lx.ssr) do
		print(k,v)
	end
	for child in rules[ast.Block](root, root) do
		print(child, child.nx, string.byte(lx.lex, child.nx))
		if string.byte(lx.lex, child.nx) == 0 then
			repeat
				local prev_father = child
				local father = child.father
				while father do
					table.insert(father.fathered, prev_father)
					if #father.fathered > 1 then
						break
					end
					prev_father = father
					father = father.father
				end
				child = child.mother
			until not child
			root = root.fathered[1]
			root.father = nil
			root.mother = nil
			return root
		end
	end
	error('Invalid parse')
end
