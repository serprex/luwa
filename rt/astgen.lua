local lex = require 'lex'
local ast = require 'ast'
package.path = package.path .. ';LuLPeg/?.lua'
local lp = require 'lulpeg'
local C, Cc, Carg, P, V = lp.C, lp.Cc, lp.Carg, lp.P, lp.V

local sc = string.char
local unpack = string.unpack
local slex, zlex = {}, {}
for k,v in pairs(lex) do
	zlex[k] = P(sc(v)) * Cc()
	slex[k] = zlex[k]*Cc({ type = -1, val = v })
end

local P4arg = P(4) / function(x) return (unpack('<i4', x)) end * Carg(1)
local function P4token(v)
	return P(sc(v)) * P4arg / function(x, vals)
		return { type = -1, val = v, arg = vals[x+1] }
	end
end
local name = P4token(lex._ident)
local number = P4token(lex._number)
local slit = P4token(lex._string)

local function many(rule)
	return rule^0
end
local function maybe(rule)
	return rule^-1
end
local function sf(id, rule)
	return rule / function(...) return { type = id, ... } end
end
local function of(id, x, ...)
	for i=1,select('#',...) do
		x = x+(select(i, ...) / function(...) return { type = id+i*32, ... } end)
	end
	return x
end
local Block, Stat, Var, ExpOr, ExpAnd, Exp, Prefix, Args, Funcbody, Table, Field, Binop, Unop, Value, Index, SuffixI, SuffixC =
	V"Block", V"Stat", V"Var", V"ExpOr", V"ExpAnd", V"Exp", V"Prefix", V"Args", V"Funcbody", V"Table", V"Field", V"Binop", V"Unop", V"Value", V"Index", V"SuffixI", V"SuffixC"
local Explist = ExpOr * many(zlex._comma * ExpOr)
local Namelist = name * many(zlex._comma * name)
local Varlist = Var * many(zlex._comma * Var)
local Fieldsep = zlex._comma + zlex._semi
local Call = maybe(zlex._colon * name) * Args
local Funccall = Prefix * SuffixC
local Grammar = P {
	Block * P"\0";
	Block = sf(ast.Block, many(Stat) * maybe(slex._return * maybe(Explist) * maybe(zlex._semi))),
	Stat = of(ast.Stat,
		zlex._semi,
		Varlist * zlex._set * Explist,
		Funccall,
		zlex._label * name * zlex._label,
		zlex._break,
		zlex._goto * name,
		zlex._do * Block * zlex._end,
		zlex._while * ExpOr * zlex._do * Block * zlex._end,
		zlex._repeat * Block * zlex._until * ExpOr,
		zlex._if * ExpOr * zlex._then * Block * many(zlex._elseif * ExpOr * zlex._then * Block) * maybe(zlex._else * Block) * zlex._end,
		zlex._for * name * zlex._set * ExpOr * zlex._comma * ExpOr * maybe(zlex._comma * ExpOr) * zlex._do * Block * zlex._end,
		zlex._for * Namelist * zlex._in * Explist * zlex._do * Block * zlex._end,
		zlex._function * name * many(zlex._dot * name) * maybe(slex._colon * name) * Funcbody,
		zlex._local * zlex._function * name * Funcbody,
		zlex._local * Namelist * maybe(zlex._set * Explist)
	),
	Var = of(ast.Var, Prefix * SuffixI, name),
	ExpOr = sf(ast.ExpOr, ExpAnd * many(zlex._or * ExpAnd)),
	ExpAnd = sf(ast.ExpAnd, Exp * many(zlex._and * Exp)),
	Exp = of(ast.Exp, Unop * Exp, Value * maybe(Binop * Exp)),
	Prefix = of(ast.Prefix, name, zlex._pl * ExpOr * zlex._pr),
	Args = of(ast.Args,
		zlex._pl * maybe(Explist) * zlex._pr,
		Table,
		slit),
	Funcbody = sf(ast.Funcbody, zlex._pl * maybe(Namelist * maybe(zlex._comma * slex._dotdotdot) + slex._dotdotdot) * zlex._pr * Block * zlex._end),
	Table = sf(ast.Table, zlex._cl * maybe(Field * many(Fieldsep * Field) * maybe(Fieldsep)) * zlex._cr),
	Field = of(ast.Field,
		zlex._sl * ExpOr * zlex._sr * zlex._set * ExpOr,
		name * zlex._set * ExpOr,
		ExpOr),
	Binop = of(ast.Binop,
		zlex._plus, zlex._minus, zlex._mul, zlex._div, zlex._idiv, zlex._pow, zlex._mod,
		zlex._band, zlex._bnot, zlex._bor, zlex._rsh, zlex._lsh, zlex._dotdot,
		zlex._lt, zlex._lte, zlex._gt, zlex._gte, zlex._eq, zlex._neq),
	Unop = of(ast.Unop, zlex._minus, zlex._not, zlex._hash, zlex._bnot),
	Value = of(ast.Value,
		zlex._nil, zlex._false, zlex._true, number, slit, zlex._dotdotdot,
		zlex._function * Funcbody, Table, Funccall, Var,
		zlex._pl * ExpOr * zlex._pr),
	Index = of(ast.Index,
		zlex._sl * ExpOr * zlex._sr,
		zlex._dot * name),
	SuffixI = of(ast.Suffix, Call * (SuffixI^1), Index * (SuffixI^0)),
	SuffixC = of(ast.Suffix, Call * (SuffixC^0), Index * (SuffixC^1)),
}

return function(lx, vals)
	return Grammar:match(lx, 1, vals)
end
