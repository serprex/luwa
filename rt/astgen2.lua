local lex = require 'lex'
local ast = require 'ast'

local rules = {}

local function merge(res, xs)
	for i=1,#xs do
		local arg = xs[i]()
		for k,v in pairs(arg) do
			local rk = res[k]
			if not rk then
				rk = {}
				res[k] = rk
			end
			for j=1,#v do
				rk[#rk+1] = v[j]
			end
		end
	end
	return res
end

local function s(token)
	return function(Next)
		return function() return { [token] = {Next} } end
	end
end
local name = s(lex._ident)
local number = s(lex._number)
local slit = s(lex._string)

local function o(id)
	return rules[id] or function(Next)
		return rules[id](Next)
	end
end

local function many(rule)
	return function(Next)
		local result
		return function()
			local root = {}
			result = merge(root, {
				rule(function() return root end),
				Next,
			})
			return result
		end
	end
end
local function maybe(rule)
	return function(Next)
		local result
		return function()
			if not result then
				result = merge({}, {
					rule(Next),
					Next,
				})
			end
			return result
		end
	end
end
local function seq(...)
	local xs = {...}
	return function(Next)
		for i=#xs, 1, -1 do
			Next = xs[i](Next)
		end
		return Next
	end
end
local function oof(...)
	local xs = {...}
	return function(Next)
		local result
		return function()
			if not result then
				ys = {}
				for i=1, #xs do
					ys[i] = xs[i](Next)
				end
				result = merge({}, ys)
			end
			return result
		end
	end
end
local function rettagcore(id, res, ...)
	return res, id, ...
end
local function rettag(f, id)
	return function()
		return rettagcore(id, f())
	end
end
local function sf(id, ...)
	local sq = seq(...)
	rules[id] = function(Next)
		return rettag(sq(Next), id)
	end
end
local function of(id, ...)
	local xs = {...}
	rules[id] = function(Next)
		local result
		return function()
			result = {}
			for i=1,#xs do
				local arg, node = xs[i](Next)()
				for k,v in pairs(arg) do
					local rk = result[k]
					if not rk then
						rk = {}
						result[k] = rk
					end
					for j=1,#v do
						rk[#rk+1] = rettag(v[j], id|i<<5)
					end
				end
			end
			return result
		end
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
	seq(s(lex._function), name, many(seq(s(lex._dot), name)), maybe(seq(s(lex._colon), name)), o(ast.Funcbody)),
	seq(s(lex._local), s(lex._function), name, o(ast.Funcbody)),
	seq(s(lex._local), Namelist, maybe(seq(s(lex._set), Explist)))
)
of(ast.Var, name, seq(o(ast.Prefix), many(o(ast.Suffix)), o(ast.Index)))
sf(ast.ExpOr, o(ast.ExpAnd), many(seq(s(lex._or), o(ast.ExpAnd))))
sf(ast.ExpAnd, o(ast.Exp), many(seq(s(lex._and), o(ast.Exp))))
of(ast.Exp, seq(o(ast.Unop), o(ast.Exp)), seq(o(ast.Value), maybe(seq(o(ast.Binop), o(ast.Exp)))))
of(ast.Prefix, name, seq(s(lex._pl), o(ast.ExpOr), s(lex._pr)))
of(ast.Args,
	seq(s(lex._pl), maybe(Explist), s(lex._pr)),
	o(ast.Table),
	slit)
sf(ast.Funcbody, s(lex._pl), maybe(oof(seq(Namelist, maybe(seq(s(lex._comma), s(lex._dotdotdot)))), s(lex._dotdotdot))), s(lex._pr), o(ast.Block), s(lex._end))
sf(ast.Table, s(lex._cl), maybe(seq(o(ast.Field), many(seq(Fieldsep, o(ast.Field))), maybe(Fieldsep))), s(lex._cr))
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

return function(lx, vals)
	local sb = string.byte
	local i, a = 1, {(seq(o(ast.Block), s(0))(function()
		return true
	end)())}
	while i <= #lx do
		local tok = sb(lx, i)
		local res = {}
		for j=1, #a do
			local nx = a[j][tok]
			if nx then
				for k=1,#nx do
					res[#res+1] = nx[k]()
				end
			end
		end
		print(i, #res)
		assert(#res > 0)
		a = res
		if tok > 63 then
			i = i + 5
		else
			i = i + 1
		end
	end
	print(#a, table.unpack(a))
end
