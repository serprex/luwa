local lex = require 'lex'
local ast = require 'ast'
local sb, su = string.byte, string.unpack

local function t_trunc(t, from)
	for i=from,#t do
		t[i] = nil
	end
end

-- token offset -> line from the lexer, nil when there are no lines (the build's own compile).
-- far is the furthest token offset any rule looked at, where a syntax error is
local lines, far

local slex, zlex = {}, {}
for k,v in pairs(lex) do
	zlex[k] = function(str, i, res, ri)
		if sb(str, i) == v then
			return i+1, ri
		end
		if i > far then
			far = i
		end
	end
	local tok = { type = -1, val = v }
	slex[k] = function(str, i, res, ri)
		if sb(str, i) == v then
			res[ri] = tok
			return i+1, ri+1
		end
		if i > far then
			far = i
		end
	end
end
local function tokenarg(ch)
	return function(str, i, res, ri, vals)
		if sb(str, i) == ch then
			res[ri] = { type = -1, val = ch, arg = vals[su('<i4', str, i+1)+1], line = lines and lines[i] }
			return i+5, ri+1
		end
		if i > far then
			far = i
		end
	end
end
local name, number, slit = tokenarg(lex._ident), tokenarg(lex._number), tokenarg(lex._string)
-- 'global' lexes as a name, so it still works as one where it can't start a declaration
local function kwglobal(str, i, res, ri, vals)
	if sb(str, i) == lex._ident and vals[su('<i4', str, i+1)+1] == 'global' then
		return i+5, ri
	end
	if i > far then
		far = i
	end
end
local function seq(rules)
	return function(str, i, res, ri, vals)
		for xi=1,#rules do
			i, ri = rules[xi](str, i, res, ri, vals)
			if not i then
				return
			end
		end
		return i, ri
	end
end
-- Results of sf & of rules, by rule then position: { next i, node } or false.
-- Without it the parser backtracks over the same nested functions again & again,
-- which takes exponential time in nesting depth
local memo
local function memoize(build)
	local key = {}
	return function(str, i, res, ri, vals)
		local mt = memo[key]
		if not mt then
			mt = {}
			memo[key] = mt
		end
		local hit = mt[i]
		if hit == nil then
			local nxi, node = build(str, i, vals)
			hit = nxi and { nxi, node } or false
			mt[i] = hit
		end
		if hit then
			res[ri] = hit[2]
			return hit[1], ri+1
		end
	end
end
local function sf(id, rule)
	return memoize(function(str, i, vals)
		local subres, subri = {}
		local start = i
		i, subri = rule(str, i, subres, 1, vals)
		if i then
			t_trunc(subres, subri)
			subres.type = id
			if lines then
				subres.line = lines[start]
				-- last token's line, when it's a 1 byte token like end
				subres.lastline = lines[i-1]
			end
			return i, subres
		end
	end)
end
local function of(id, ...)
	local rules = {...}
	return memoize(function(str, i, vals)
		local subres = {}
		for xi=1, #rules do
			local nxi, subri = rules[xi](str, i, subres, 1, vals)
			if nxi then
				t_trunc(subres, subri)
				subres.type = id+xi*32
				if lines then
					subres.line = lines[i]
				end
				return nxi, subres
			end
		end
	end)
end
local function m(rule)
	return function(str, i, res, ri, vals)
		while true do
			local nxi, nxri = rule(str, i, res, ri, vals)
			if not nxi then
				return i, ri
			end
			i, ri = nxi, nxri
		end
	end
end
local function p(rule)
	return function(str, i, res, ri, vals)
		local nxi, nxri = rule(str, i, res, ri, vals)
		if nxi then
			return nxi, nxri
		else
			return i, ri
		end
	end
end
local function o(rules)
	return function(str, i, res, ri, vals)
		for xi=1, #rules do
			local nxi, nxri = rules[xi](str, i, res, ri, vals)
			if nxi then
				return nxi, nxri
			end
		end
	end
end
local G
local function V(name)
	return function(...)
		return G[name](...)
	end
end
local Block, Stat, Var, ExpOr, ExpAnd, Exp, Prefix, Args, Funcbody, Table, Field, Binop, Unop, Value, Index, Suffix, SuffixI, SuffixC, Attrib =
	V"Block", V"Stat", V"Var", V"ExpOr", V"ExpAnd", V"Exp", V"Prefix", V"Args", V"Funcbody", V"Table", V"Field", V"Binop", V"Unop", V"Value", V"Index", V"Suffix", V"SuffixI", V"SuffixC", V"Attrib"
local Explist = seq{ExpOr, m(seq{zlex._comma, ExpOr})}
local Namelist = seq{name, m(seq{zlex._comma, name})}
-- an attrib before the first name applies to every name
local Attnamelist = seq{p(Attrib), name, p(Attrib), m(seq{zlex._comma, name, p(Attrib)})}
local Varlist = seq{Var, m(seq{zlex._comma, Var})}
local Fieldsep = o{zlex._comma, zlex._semi}
local Call = seq{p(seq{zlex._colon, name}), Args}
local Sexp = seq{zlex._sl, ExpOr, zlex._sr}
G = {
	Block = sf(ast.Block, seq{m(Stat), p(seq{slex._return, p(Explist), p(zlex._semi)})}),
	Stat = o{zlex._semi, of(ast.Stat,
		seq{Varlist, zlex._set, Explist},
		seq{Prefix, SuffixC},
		seq{zlex._label, name, zlex._label},
		zlex._break,
		seq{zlex._goto, name},
		seq{zlex._do, Block, zlex._end},
		seq{zlex._while, ExpOr, zlex._do, Block, zlex._end},
		seq{zlex._repeat, Block, zlex._until, ExpOr},
		seq{zlex._if, ExpOr, zlex._then, Block, m(seq{zlex._elseif, ExpOr, zlex._then, Block}), p(seq{zlex._else, Block}), zlex._end},
		seq{zlex._for, name, zlex._set, ExpOr, zlex._comma, ExpOr, p(seq{zlex._comma, ExpOr}), zlex._do, Block, zlex._end},
		seq{zlex._for, Namelist, zlex._in, Explist, zlex._do, Block, zlex._end},
		seq{zlex._function, name, m(seq{zlex._dot, name}), m(seq{slex._colon, name}), Funcbody},
		seq{zlex._local, zlex._function, name, Funcbody},
		seq{zlex._local, Attnamelist, p(seq{zlex._set, Explist})},
		seq{kwglobal, zlex._function, name, Funcbody},
		seq{kwglobal, p(Attrib), zlex._mul},
		seq{kwglobal, Attnamelist, p(seq{zlex._set, Explist})}
	)},
	Attrib = sf(ast.Attrib, seq{zlex._lt, name, zlex._gt}),
	Var = of(ast.Var, seq{Prefix, SuffixI}, name),
	ExpOr = sf(ast.ExpOr, seq{ExpAnd, m(seq{zlex._or, ExpAnd})}),
	ExpAnd = sf(ast.ExpAnd, seq{Exp, m(seq{zlex._and, Exp})}),
	Exp = of(ast.Exp, seq{Unop, Exp}, seq{Value, p(seq{Binop, Exp})}),
	Prefix = of(ast.Prefix, name, seq{zlex._pl, ExpOr, zlex._pr}),
	Args = of(ast.Args, seq{zlex._pl, p(Explist), zlex._pr}, Table, slit),
	Funcbody = sf(ast.Funcbody, seq{zlex._pl, p(o{seq{slex._dotdotdot, p(name)}, seq{Namelist, p(seq{zlex._comma, slex._dotdotdot, p(name)})}}), zlex._pr, Block, zlex._end}),
	Table = sf(ast.Table, seq{zlex._cl, p(seq{Field, m(seq{Fieldsep, Field}), p(Fieldsep)}), zlex._cr}),
	Field = of(ast.Field, seq{Sexp, zlex._set, ExpOr}, seq{name, zlex._set, ExpOr}, ExpOr),
	Binop = of(ast.Binop,
		zlex._plus, zlex._minus, zlex._mul, zlex._div, zlex._idiv, zlex._pow, zlex._mod,
		zlex._band, zlex._bnot, zlex._bor, zlex._rsh, zlex._lsh, zlex._dotdot,
		zlex._lt, zlex._lte, zlex._gt, zlex._gte, zlex._eq, zlex._neq),
	Unop = of(ast.Unop, zlex._minus, zlex._not, zlex._hash, zlex._bnot),
	Value = of(ast.Value,
		zlex._nil, zlex._false, zlex._true, number, slit, zlex._dotdotdot,
		seq{zlex._function, Funcbody}, Table, seq{Prefix, p(Suffix)}),
	Index = of(ast.Index, Sexp, seq{zlex._dot, name}),
	Suffix = of(ast.Suffix, seq{Call, p(Suffix)}, seq{Index, p(Suffix)}),
	SuffixI = of(ast.Suffix, seq{Call, SuffixI}, seq{Index, p(SuffixI)}),
	SuffixC = of(ast.Suffix, seq{Call, p(SuffixC)}, seq{Index, SuffixC}),
}

local Block = G.Block

-- Text of tokens for syntax errors
local tokentext = {
	_plus = '+', _minus = '-', _mul = '*', _div = '/', _mod = '%', _pow = '^', _hash = '#',
	_band = '&', _bnot = '~', _bor = '|', _lsh = '<<', _rsh = '>>', _idiv = '//',
	_eq = '==', _neq = '~=', _lt = '<', _gt = '>', _lte = '<=', _gte = '>=', _set = '=',
	_pl = '(', _pr = ')', _cl = '{', _cr = '}', _sl = '[', _sr = ']', _label = '::',
	_semi = ';', _colon = ':', _comma = ',', _dot = '.', _dotdot = '..', _dotdotdot = '...',
}
local tokname = {}
for k, v in pairs(lex) do
	tokname[v] = tokentext[k] or k:sub(2)
end
local function near(lx, vals, i)
	local t = sb(lx, i)
	if not t then
		return '<eof>'
	end
	if t >= lex._ident then
		local v = vals[su('<i4', lx, i+1)+1]
		if t & 192 == lex._string then
			return "'\"" .. v .. "\"'"
		elseif t & 192 == lex._number then
			return "'" .. tostring(v) .. "'"
		end
		return "'" .. v .. "'"
	end
	return "'" .. tokname[t] .. "'"
end

-- lns: token offset -> line from the lexer. chunk: source name for errors.
-- Without them (the build compiling the prelude) nodes get no lines
return function(lx, vals, lns, chunk)
	local res = {}
	local prevmemo, prevlines, prevfar = memo, lines, far
	memo, lines, far = {}, lns, 0
	local i = Block(lx, 1, res, 1, vals)
	local f = far
	memo, lines, far = prevmemo, prevlines, prevfar
	if not i or i <= #lx then
		if not chunk then
			error('syntax error')
		end
		-- the furthest token looked at is where parsing went wrong. Past the end, use the last line
		local line = lns and lns[f]
		if not line and lns then
			for j = f, 1, -1 do
				if lns[j] then
					line = lns[j]
					break
				end
			end
		end
		error(chunk .. ':' .. (line or '?') .. ': syntax error near ' .. near(lx, vals, f), 0)
	end
	return res[1]
end
