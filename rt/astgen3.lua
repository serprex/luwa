local lex = require 'lex'
local ast = require 'ast'
package.path = package.path .. ';LuLPeg/?.lua'
local lp = require 'lulpeg'
local C, Cc, P, V = lp.C, lp.Cc, lp.P, lp.V

local sc = string.char
local slex = {}
for k,v in pairs(lex) do
	slex[k] = P(sc(v))*Cc(v)
end

local P4r32 = P(4) / function(x) return string.unpack('<i4', x) end
local name = slex._ident * P4r32
local number = slex._number * P4r32
local slit = slex._string * P4r32

local function many(rule)
	return rule^0
end
local function maybe(rule)
	return rule^-1
end
local function sf(id, rule)
	return rule / function(...) return { tag = id, ... } end
end
local function of(id, x, ...)
	for i=1,select('#',...) do
		x = x+(select(i, ...) / function(...) return { tag = id+i*32, ... } end)
	end
	return x
end
local Block, Stat, Var, ExpOr, ExpAnd, Exp, Prefix, Args, Funcbody, Table, Field, Binop, Unop, Value, Index, Suffix =
	V"Block", V"Stat", V"Var", V"ExpOr", V"ExpAnd", V"Exp", V"Prefix", V"Args", V"Funcbody", V"Table", V"Field", V"Binop", V"Unop", V"Value", V"Index", V"Suffix"
local Explist = ExpOr * many(slex._comma * ExpOr)
local Namelist = name * many(slex._comma * name)
local Varlist = Var * many(slex._comma * Var)
local Fieldsep = slex._comma + slex._semi
local Call = maybe(slex._colon * name) * Args
local Funccall = Prefix * many(Suffix) * Call
local Grammar = P {
	Block * P("\0");
	Block = sf(ast.Block, many(Stat) * maybe(slex._return * maybe(Explist) * maybe(slex._semi))),
	Stat = of(ast.Stat,
		slex._semi,
		Varlist * slex._set * Explist,
		Funccall,
		slex._label * name * slex._label,
		slex._break,
		slex._goto * name,
		slex._do * Block * slex._end,
		slex._while * ExpOr * slex._do * Block * slex._end,
		slex._repeat * Block * slex._until * ExpOr,
		slex._if * ExpOr * slex._then * Block * many(slex._elseif * ExpOr * slex._then * Block) * maybe(slex._else * Block) * slex._end,
		slex._for * name * slex._set * ExpOr * slex._comma * ExpOr * maybe(slex._comma * ExpOr) * slex._do * Block * slex._end,
		slex._for * Namelist * slex._in * Explist * slex._do * Block * slex._end,
		slex._function * name * many(slex._dot * name) * maybe(slex._colon * name) * Funcbody,
		slex._local * slex._function * name * Funcbody,
		slex._local * Namelist * maybe(slex._set * Explist)
	),
	Var = of(ast.Var, name, Prefix * many(Suffix) * Index),
	ExpOr = sf(ast.ExpOr, ExpAnd * many(slex._or * ExpAnd)),
	ExpAnd = sf(ast.ExpAnd, Exp * many(slex._and * Exp)),
	Exp = of(ast.Exp, Unop * Exp, Value * maybe(Binop * Exp)),
	Prefix = of(ast.Prefix, name, slex._pl * ExpOr * slex._pr),
	Args = of(ast.Args,
		slex._pl * maybe(Explist) * slex._pr,
		Table,
		slit),
	Funcbody = sf(ast.Funcbody, slex._pl * maybe(Namelist * maybe(slex._comma * slex._dotdotdot) + slex._dotdotdot) * slex._pr * Block * slex._end),
	Table = sf(ast.Table, slex._cl * maybe(Field * many(Fieldsep * Field) * maybe(Fieldsep)) * slex._cr),
	Field = of(ast.Field,
		slex._sl * ExpOr * slex._sr * slex._set * ExpOr,
		name * slex._set * ExpOr,
		ExpOr),
	Binop = of(ast.Binop,
		slex._plus, slex._minus, slex._mul, slex._div, slex._idiv, slex._pow, slex._mod,
		slex._band, slex._bnot, slex._bor, slex._rsh, slex._lsh, slex._dotdot,
		slex._lt, slex._lte, slex._gt, slex._gte, slex._eq, slex._neq),
	Unop = of(ast.Unop, slex._minus, slex._not, slex._hash, slex._bnot),
	Value = of(ast.Value,
		slex._nil, slex._false, slex._true, number, slit, slex._dotdotdot,
		slex._function * Funcbody, Table, Funccall, Var,
		slex._pl * ExpOr * slex._pr),
	Index = of(ast.Index,
		slex._sl * ExpOr * slex._sr,
		slex._dot * name),
	Suffix = of(ast.Suffix, Call, Index),
}

return function(lx, vals)
	pprint(Grammar:match(lx))
	print('???')
	os.exit()
end
