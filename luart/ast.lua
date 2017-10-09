local lex = require 'lex'
local function iternone()
end
local function iterone(x)
	return function()
		local y = x
		x = nil
		return y
	end
end
local function parse(self, lx)
	local rules = {}

	local function yieldall(it)
		for yi in it do
			coroutine.yield(yi)
		end
	end
	local function name(x, p)
		local t = x:next(p)
		if t:val() == lex._ident then
			return iterone(t:skipint())
		else
			return iternone
		end
	end
	local function number(x, p)
		local t = x:next(p)
		if t:val() == lex._number then
			return iterone(t:skipint())
		else
			return iternone
		end
	end
	local function slit(x, p)
		local t = x:next(p)
		if t:val() == lex._string then
			return iterone(t:skipint())
		else
			return iternone
		end
	end
	local function s(r)
		return function(x, p)
			local t = x:next(p)
			if t:val() == r then
				return iterone(t)
			else
				return iternone
			end
		end
	end
	local function o(n)
		return function(x, p)
			return rules[n](x, p)
		end
	end
	local function seqcore(x, p, xs, i)
		if i == #xs then
			yieldall(xs[i](x, p))
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
	function many(f)
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
	function maybe(f)
		return function(x, p)
			return coroutine.wrap(function()
				yieldall(f(x, p))
				coroutine.yield(x)
			end)
		end
	end
	function of(o, ...)
		local xs = {...}
		rules[o] = function(x, p)
			return coroutine.wrap(function()
				local p = x:spawn(o, p)
				for i=1,#xs do
					yieldall(xs[i](x, p))
					p.type = p.type + 32
				end
			end)
		end
	end
	function oof(...)
		local xs = {...}
		return function(x, p)
			return coroutine.wrap(function()
				for i=1,#xs do
					yieldall(xs[i](x, p))
				end
			end)
		end
	end
	local Block = 1
	local Stat = 2
	local Retstat = 3
	local Label = 4
	local Funcname = 5
	local Var = 6
	local Exp = 7
	local Prefix = 8
	local Functioncall = 9
	local Args = 10
	local Funcbody = 11
	local Tableconstructor = 12
	local Field = 13
	local Binop = 14
	local Unop = 15
	local Value = 16
	local Index = 17
	local Call = 18
	local Suffix = 19
	local ExpOr = 20
	local ExpAnd = 21
	local Explist = seq(o(ExpOr), many(seq(s(lex._comma), o(ExpOr))))
	local Namelist = seq(name, many(seq(s(lex._comma), name)))
	local Varlist = seq(o(Var), many(seq(s(lex._comma), o(Var))))
	local Fieldsep = oof(s(lex._comma), s(lex._semi))
	sf(Block, many(o(Stat)), maybe(o(Retstat)))
	of(Stat,
		s(lex._semi),
		seq(Varlist, s(lex._set), Explist),
		o(Functioncall),
		o(Label),
		s(lex._break),
		seq(s(lex._goto), name),
		seq(s(lex._do), o(Block), s(lex._end)),
		seq(s(lex._while), o(ExpOr), s(lex._do), o(Block), s(lex._end)),
		seq(s(lex._repeat), o(Block), s(lex._until), o(ExpOr)),
		seq(s(lex._if), o(ExpOr), s(lex._then), o(Block), many(seq(s(lex._elseif), o(ExpOr), s(lex._then), o(Block))), maybe(seq(s(lex._else), o(Block))), s(lex._end)),
		seq(s(lex._for), name, s(lex._set), o(ExpOr), s(lex._comma), o(ExpOr), maybe(seq(s(lex._comma), o(ExpOr))), s(lex._do), o(Block), s(lex._end)),
		seq(s(lex._for), Namelist, s(lex._in), Explist, s(lex._do), o(Block), s(lex._end)),
		seq(s(lex._function), o(Funcname), o(Funcbody)),
		seq(s(lex._local), s(lex._function), name, o(Funcbody)),
		seq(s(lex._local), Namelist, maybe(seq(s(lex._set), Explist)))
	)
	sf(Retstat, s(lex._return), maybe(Explist), maybe(s(lex._semi)))
	sf(Label, s(lex._label), name, s(lex._label))
	sf(Funcname, name, many(seq(s(lex._dot), name)), maybe(seq(s(lex._colon), name)))
	of(Var, name, seq(o(Prefix), many(o(Suffix)), o(Index)))
	of(ExpOr, seq(o(ExpAnd), many(seq(s(lex._or), o(ExpAnd)))))
	of(ExpAnd, seq(o(Exp), many(seq(s(lex._and), o(Exp)))))
	of(Exp, seq(o(Unop), o(Exp)), seq(o(Value), maybe(seq(o(Binop), o(Exp)))))
	of(Prefix, name, seq(s(lex._pl), o(ExpOr), s(lex._pr)))
	sf(Functioncall, o(Prefix), many(o(Suffix)), o(Call))
	of(Args,
		seq(s(lex._pl), maybe(Explist), s(lex._pr)),
		o(Tableconstructor),
		slit)
	sf(Funcbody, s(lex._pl), maybe(oof(seq(Namelist, maybe(seq(s(lex._comma), s(lex._dotdotdot)))), s(lex._dotdotdot))), s(lex._pr), o(Block), s(lex._end))
	sf(Tableconstructor, s(lex._cl), maybe(seq(o(Field), many(seq(Fieldsep, o(Field))), maybe(Fieldsep))), s(lex._cr))
	of(Field,
		seq(s(lex._sl), o(ExpOr), s(lex._sr), s(lex._set), o(ExpOr)),
		seq(name, s(lex._set), o(ExpOr)),
	o(ExpOr))
	of(Binop,
		s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod),
		s(lex._band), s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot),
		s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq))
	of(Unop, s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot))
	of(Value,
		s(lex._nil), s(lex._false), s(lex._true), number, slit, s(lex._dotdotdot),
		seq(s(lex._function), o(Funcbody)), o(Tableconstructor), o(Functioncall), o(Var),
		seq(s(lex._pl), o(ExpOr), s(lex._pr)))
	of(Index,
		seq(s(lex._sl), o(ExpOr), s(lex._sr)),
		seq(s(lex._dot), name))
	of(Call,
		o(Args),
		seq(s(lex._colon), name, o(Args)))
	of(Suffix, o(Call), o(Index))

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
		return string.unpack('<i4', lx.lex, self.nx)
	end
	function BuilderMeta:next(p)
		local newmo = self
		if self.type == -1 then
			newmo = self.mother
		end
		return Builder(self.nx, self.nx+1, newmo, p, -1)
	end
	function BuilderMeta:spawn(ty, p)
		local newmo = self
		if self.type == -1 then
			newmo = self.mother
		end
		return Builder(self.li, self.nx, newmo, p, ty)
	end

	local root = Builder(0, 1, nil, nil, -2)
	for i=1,#lx.lex,50 do
		print(i, table.concat({string.byte(lx.lex, i, i+49)}, ','))
	end
	for k,v in ipairs(lx.ssr) do
		print(k,v)
	end
	for child in rules[Block](root, root) do
		print(child, child.nx)
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
end

return setmetatable({
	Block = Block,
	Stat = Stat,
	Retstat = Retstat,
	Label = Label,
	Funcname = Funcname,
	Var = Var,
	Exp = Exp,
	Prefix = Prefix,
	Functioncall = Functioncall,
	Args = Args,
	Funcbody = Funcbody,
	Tableconstructor = Tableconstructor,
	Field = Field,
	Binop = Binop,
	Unop = Unop,
	Value = Value,
	Index = Index,
	Call = Call,
	Suffix = Suffix,
	ExpOr = ExpOr,
	ExpAnd = ExpAnd,
}, { __call = parse })
