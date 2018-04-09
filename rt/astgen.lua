local lex = require 'lex'
local ast = require 'ast'
local lp = require 'LuLPeg/lulpeg'
local C, Cc, Carg, P, V = lp.C, lp.Cc, lp.Carg, lp.P, lp.V
local sc, su = string.char, string.unpack

local slex, zlex = {}, {}
for k,v in pairs(lex) do
	local pv = P(sc(v))
	zlex[k] = pv * Cc()
	slex[k] = pv * Cc({ type = -1, val = v })
end
local P4arg = P(4) / 1 * Carg(1)
local function P4token(v)
	return P(sc(v)) * P4arg / function(x, vals)
		return { type = -1, val = v, arg = vals[su('<i4', x)+1] }
	end
end
local name, number, slit = P4token(lex._ident), P4token(lex._number), P4token(lex._string)

local function sf(id, rule)
	return rule * Cc() / function(...) return { type = id, ... } end
end
local function of(id, x, ...)
	x = x / function(...) return { type = id+32, ... } end
	for i=1,select('#', ...) do
		x = x+(select(i, ...) / function(...) return { type = id+i*32+32, ... } end)
	end
	return x
end
local Block, Stat, Var, ExpOr, ExpAnd, Exp, Prefix, Args, Funcbody, Table, Field, Binop, Unop, Value, Index, Suffix, SuffixI, SuffixC =
	V"Block", V"Stat", V"Var", V"ExpOr", V"ExpAnd", V"Exp", V"Prefix", V"Args", V"Funcbody", V"Table", V"Field", V"Binop", V"Unop", V"Value", V"Index", V"Suffix", V"SuffixI", V"SuffixC"
local Explist = ExpOr * (zlex._comma * ExpOr)^0
local Namelist = name * (zlex._comma * name)^0
local Varlist = Var * (zlex._comma * Var)^0
local Fieldsep = zlex._comma + zlex._semi
local Call = (zlex._colon * name)^-1 * Args
local Sexp = zlex._sl * ExpOr * zlex._sr
local Grammar = P {
	Block * -1;
	Block = sf(ast.Block, Stat^0 * (slex._return * Explist^-1 * zlex._semi^-1)^-1),
	Stat = zlex._semi + of(ast.Stat,
		Varlist * zlex._set * Explist,
		Prefix * SuffixC,
		zlex._label * name * zlex._label,
		zlex._break,
		zlex._goto * name,
		zlex._do * Block * zlex._end,
		zlex._while * ExpOr * zlex._do * Block * zlex._end,
		zlex._repeat * Block * zlex._until * ExpOr,
		zlex._if * ExpOr * zlex._then * Block * (zlex._elseif * ExpOr * zlex._then * Block)^0 * (zlex._else * Block)^-1 * zlex._end,
		zlex._for * name * zlex._set * ExpOr * zlex._comma * ExpOr * (zlex._comma * ExpOr)^-1 * zlex._do * Block * zlex._end,
		zlex._for * Namelist * zlex._in * Explist * zlex._do * Block * zlex._end,
		zlex._function * name * (zlex._dot * name)^0 * (slex._colon * name)^-1 * Funcbody,
		zlex._local * zlex._function * name * Funcbody,
		zlex._local * Namelist * (zlex._set * Explist)^-1
	),
	Var = of(ast.Var, Prefix * SuffixI, name),
	ExpOr = sf(ast.ExpOr, ExpAnd * (zlex._or * ExpAnd)^0),
	ExpAnd = sf(ast.ExpAnd, Exp * (zlex._and * Exp)^0),
	Exp = of(ast.Exp, Unop * Exp, Value * (Binop * Exp)^-1),
	Prefix = of(ast.Prefix, name, zlex._pl * ExpOr * zlex._pr),
	Args = of(ast.Args, zlex._pl * Explist^-1 * zlex._pr, Table, slit),
	Funcbody = sf(ast.Funcbody, zlex._pl * (slex._dotdotdot + (Namelist * (zlex._comma * slex._dotdotdot)^-1)^-1) * zlex._pr * Block * zlex._end),
	Table = sf(ast.Table, zlex._cl * (Field * (Fieldsep * Field)^0 * Fieldsep^-1)^-1 * zlex._cr),
	Field = of(ast.Field, Sexp * zlex._set * ExpOr, name * zlex._set * ExpOr, ExpOr),
	Binop = of(ast.Binop,
		zlex._plus, zlex._minus, zlex._mul, zlex._div, zlex._idiv, zlex._pow, zlex._mod,
		zlex._band, zlex._bnot, zlex._bor, zlex._rsh, zlex._lsh, zlex._dotdot,
		zlex._lt, zlex._lte, zlex._gt, zlex._gte, zlex._eq, zlex._neq),
	Unop = of(ast.Unop, zlex._minus, zlex._not, zlex._hash, zlex._bnot),
	Value = of(ast.Value,
		zlex._nil, zlex._false, zlex._true, number, slit, zlex._dotdotdot,
		zlex._function * Funcbody, Table, Prefix * Suffix^-1),
	Index = of(ast.Index, Sexp, zlex._dot * name),
	Suffix = of(ast.Suffix, Call * Suffix^-1, Index * Suffix^-1),
	SuffixI = of(ast.Suffix, Call * SuffixI, Index * (SuffixI^-1)),
	SuffixC = of(ast.Suffix, Call * (SuffixC^-1), Index * SuffixC),
}

return function(lx, vals)
	return assert(Grammar:match(lx, 1, vals))
end
