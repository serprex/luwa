-- Parser generator: turns a grammar into wasm funcs, one per named rule.
-- Rules are LL(1): the current token picks each choice. Two choices starting with the same token is
-- an error, `when` gives a choice its own test for the few spots that need to look further.
-- Actions (act) are builder code put in at that spot, they share the rule's locals through L
local M = require 'make'
local lex = require 'lex'

-- Text of tokens, for writing them in the grammar & for error messages
local tokentext = {
	_plus = '+', _minus = '-', _mul = '*', _div = '/', _mod = '%', _pow = '^', _hash = '#',
	_band = '&', _bnot = '~', _bor = '|', _lsh = '<<', _rsh = '>>', _idiv = '//',
	_eq = '==', _neq = '~=', _lt = '<', _gt = '>', _lte = '<=', _gte = '>=', _set = '=',
	_pl = '(', _pr = ')', _cl = '{', _cr = '}', _sl = '[', _sr = ']', _label = '::',
	_semi = ';', _colon = ':', _comma = ',', _dot = '.', _dotdot = '..', _dotdotdot = '...',
}
local tokname, tokid = {}, {}
for k, v in pairs(lex) do
	tokname[v] = tokentext[k] or k:sub(2)
	tokid[tokname[v]] = v
end
tokname[lex._ident] = '<name>'
tokname[lex._string] = '<string>'
tokname[lex._number] = '<number>'

local function rule(kind, r)
	r.kind = kind
	return r
end
local function norm(r)
	if type(r) == 'string' then
		return rule('tok', { tok = assert(tokid[r], r) })
	end
	return r
end
local function norms(list)
	local out = {}
	for k, r in ipairs(list) do
		out[k] = norm(r)
	end
	return out
end

local P = { tokid = tokid, tokname = tokname }
-- each in turn
function P.seq(list)
	return rule('seq', { items = norms(list) })
end
-- any number of r
function P.m(r)
	return rule('many', { r = norm(r) })
end
-- r or nothing
function P.p(r)
	return rule('opt', { r = norm(r) })
end
-- one of the rules
function P.o(list)
	return rule('alt', { alts = norms(list) })
end
-- the rule named name. args(f, L) pushes its params, sink(f, L) takes its results (they're dropped without one)
function P.V(name, args, sink)
	return rule('ref', { name = name, args = args, sink = sink })
end
-- a token with a value (name, number or string). fn(f, L) runs while it's still the current token
function P.val(t, fn)
	return rule('val', { tok = t, fn = fn })
end
-- the name word, after a when that checked it
function P.kw(word)
	return rule('kw', { tok = lex._ident })
end
-- builder code, reads nothing
function P.act(fn)
	return rule('act', { fn = fn })
end
-- r, chosen when test(f, L) leaves a true i32 instead of by the next token
function P.when(test, r)
	return rule('when', { test = test, r = norm(r) })
end
-- token close that ends what token open started. line(f, L) pushes the line open was on, for the error
function P.close(close, open, line)
	return rule('close', { tok = assert(tokid[close], close), open = assert(tokid[open], open), line = line })
end
-- Operators by how tightly they bind, see subexpr in lparser.c. A rule of its own taking the limit,
-- giving L.e. t has unops (token list), uprio, value (a ref), binops ({ token, left, right } list) &
-- the actions: onunop after the unop's operand (op in L.op, operand in L.e),
-- onleft before reading the right operand (L.e is the left one), onbinop after it (in L.e2)
function P.prec(t)
	return rule('prec', t)
end
-- A named rule: params & locals are { name, type } lists, results a list of types. body reads the tokens
function P.rule(t)
	t.isrule = true
	return t
end

-- The tokens r can start with, & whether it can read nothing
local G
local function first(r)
	if r.first then
		return r.first, r.nullable
	end
	local k, f, null = r.kind, {}, false
	r.first, r.nullable = f, false -- for rules that refer to themselves
	local function add(x)
		local xf, xn = first(x)
		for t in pairs(xf) do
			f[t] = true
		end
		return xn
	end
	if r.isrule then
		null = add(r.body)
	elseif k == 'tok' or k == 'val' or k == 'kw' or k == 'close' then
		f[r.tok] = true
	elseif k == 'seq' then
		null = true
		for _, x in ipairs(r.items) do
			if not add(x) then
				null = false
				break
			end
		end
	elseif k == 'many' or k == 'opt' then
		add(r.r)
		null = true
	elseif k == 'alt' then
		for _, x in ipairs(r.alts) do
			null = add(x) or null
		end
	elseif k == 'when' then
		-- its test picks it, so it never reads nothing as far as the choice around it goes
		add(r.r)
	elseif k == 'ref' then
		null = add(assert(G[r.name], r.name))
	elseif k == 'prec' then
		for _, t in ipairs(r.unops) do
			f[assert(tokid[t], t)] = true
		end
		add(r.value)
	else
		null = true
	end
	r.first, r.nullable = f, null
	return f, null
end

local opts
local funcs = {}
local gen

-- i32 on the stack: is it a token in set
local function inset(f, L, set)
	local list = {}
	for t in pairs(set) do
		list[#list+1] = t
	end
	table.sort(list)
	if #list == 0 then
		f:i32(0)
		return
	end
	local lo, hi = list[1], list[#list]
	if hi - lo < 64 then
		-- 1 << (tok - lo) & mask, with tok - lo < 64 unsigned
		local mask = 0
		for _, t in ipairs(list) do
			mask = mask | (1 << (t - lo))
		end
		opts.tok(f)
		if lo > 0 then
			f:i32(lo)
			f:sub()
		end
		f:tee(L._t)
		f:i32(64)
		f:ltu()
		f:iff(i32, function()
			f:i64(mask)
			f:load(L._t)
			f:i64extendu()
			f:shru()
			f:i32wrap()
			f:i32(1)
			f:band()
		end, function()
			f:i32(0)
		end)
	else
		for i, t in ipairs(list) do
			opts.tok(f)
			f:i32(t)
			f:eq()
			if i > 1 then
				f:bor()
			end
		end
	end
end
-- the test m & p use to see if r is next
local function starts(f, L, r)
	if r.kind == 'when' then
		return r.test(f, L)
	end
	return inset(f, L, (first(r)))
end

-- Branch to labels[k] for the choice the token picks. Tests first, then by token, else default
local function pick(f, L, alts, labels, failfn)
	local bytok, default = {}, nil
	for k, a in ipairs(alts) do
		if a.kind == 'when' then
			a.test(f, L)
			f:brif(labels[k])
		else
			local fs, null = first(a)
			for t in pairs(fs) do
				assert(not bytok[t], 'grammar: two choices start with ' .. tostring(tokname[t]))
				bytok[t] = k
			end
			if null then
				assert(not default, 'grammar: two choices can read nothing')
				default = k
			end
		end
	end
	local toks = {}
	for t in pairs(bytok) do
		toks[#toks+1] = t
	end
	table.sort(toks)
	if #toks <= 4 then
		for _, t in ipairs(toks) do
			opts.tok(f)
			f:i32(t)
			f:eq()
			f:brif(labels[bytok[t]])
		end
		if default then
			f:br(labels[default])
		else
			failfn()
		end
	else
		f:block(function(nomatch)
			local targets = {}
			for t = 0, toks[#toks] do
				targets[t+1] = bytok[t] and labels[bytok[t]] or nomatch
			end
			targets[#targets+1] = nomatch
			opts.tok(f)
			f:brtable(table.unpack(targets))
		end)
		if default then
			f:br(labels[default])
		else
			failfn()
		end
	end
end

-- One of alts, by pick. Each alt's code goes after the block its label ends
local function choice(f, L, alts, failfn)
	local labels = {}
	f:block(function(out)
		local function nest(k)
			if k > #alts then
				return pick(f, L, alts, labels, failfn)
			end
			f:block(function(lab)
				labels[k] = lab
				nest(k + 1)
			end)
			gen(f, L, alts[k])
			f:br(out)
		end
		nest(1)
	end)
end

-- token t is next, or it's an error
local function expect(f, L, t, failfn)
	opts.tok(f)
	f:i32(t)
	f:ne()
	f:iff(failfn)
end

function gen(f, L, r)
	local k = r.kind
	if k == 'tok' then
		expect(f, L, r.tok, function() opts.expected(f, L, r.tok) end)
		f:call(opts.next)
	elseif k == 'close' then
		expect(f, L, r.tok, function() opts.closeerr(f, L, r.tok, r.open, r.line) end)
		f:call(opts.next)
	elseif k == 'val' then
		expect(f, L, r.tok, function() opts.expected(f, L, r.tok) end)
		if r.fn then
			r.fn(f, L)
		end
		f:call(opts.next)
	elseif k == 'kw' then
		f:call(opts.next)
	elseif k == 'seq' then
		for _, x in ipairs(r.items) do
			gen(f, L, x)
		end
	elseif k == 'many' then
		assert(not select(2, first(r.r)), 'grammar: m of a rule that can read nothing')
		f:loop(function(loop)
			starts(f, L, r.r)
			f:iff(function()
				gen(f, L, r.r)
				f:br(loop)
			end)
		end)
	elseif k == 'opt' then
		starts(f, L, r.r)
		f:iff(function()
			gen(f, L, r.r)
		end)
	elseif k == 'alt' then
		choice(f, L, r.alts, function() opts.unexpected(f, L) end)
	elseif k == 'when' then
		gen(f, L, r.r)
	elseif k == 'ref' then
		if r.args then
			r.args(f, L)
		end
		f:call(assert(funcs[r.name], r.name))
		if r.sink then
			r.sink(f, L)
		else
			for _ in ipairs(G[r.name].results or {}) do
				f:drop()
			end
		end
	elseif k == 'act' then
		r.fn(f, L)
	else
		error('grammar: no rule kind ' .. tostring(k))
	end
end

-- Token push(f) gives -> priority, by br_table. 0 for tokens not in map
local function prio(f, map, push)
	local maxt = 0
	for t in pairs(map) do
		maxt = math.max(maxt, t)
	end
	f:block(i32, function(out)
		local byprio, prios = {}, {}
		for t, p in pairs(map) do
			if not byprio[p] then
				byprio[p] = true
				prios[#prios+1] = p
			end
		end
		table.sort(prios)
		local labels = {}
		local function nest(k)
			if k > #prios then
				f:block(function(none)
					local targets = {}
					for t = 0, maxt do
						local p = map[t]
						local idx
						for j, q in ipairs(prios) do
							if q == p then
								idx = j
							end
						end
						targets[t+1] = idx and labels[idx] or none
					end
					targets[#targets+1] = none
					push(f)
					f:brtable(table.unpack(targets))
				end)
				f:i32(0)
				f:br(out)
				return
			end
			f:block(function(lab)
				labels[k] = lab
				nest(k + 1)
			end)
			f:i32(prios[k])
			f:br(out)
		end
		nest(1)
	end)
end

local function genprec(f, L, r)
	local isunop = {}
	for _, t in ipairs(r.unops) do
		isunop[tokid[t]] = true
	end
	local left, right = {}, {}
	for _, b in ipairs(r.binops) do
		local t = assert(tokid[b[1]], b[1])
		left[t], right[t] = b[2], b[3]
	end
	local self = funcs[r.name]
	inset(f, L, isunop)
	f:iff(function()
		opts.tok(f)
		f:store(L.op)
		opts.line(f)
		f:store(L.opline)
		f:call(opts.next)
		f:i32(r.uprio)
		f:call(self)
		f:store(L.e)
		r.onunop(f, L)
	end, function()
		gen(f, L, r.value)
	end)
	f:block(function(done)
		f:loop(function(loop)
			prio(f, left, opts.tok)
			f:load(L.limit)
			f:leu()
			f:brif(done)
			opts.tok(f)
			f:store(L.op)
			opts.line(f)
			f:store(L.opline)
			r.onleft(f, L)
			f:call(opts.next)
			-- the right operand's limit, by the op
			prio(f, right, function() f:load(L.op) end)
			f:call(self)
			f:store(L.e2)
			r.onbinop(f, L)
			f:br(loop)
		end)
	end)
	f:load(L.e)
end

-- Make a func for each rule in grammar g. o has the hooks the generated code uses:
-- tok(f) pushes the current token, line(f) its line, next (func) reads the next one,
-- expected(f, L, t), unexpected(f, L) & closeerr(f, L, t, open, line) raise syntax errors
function P.gen(g, o)
	G, opts = g, o
	-- sorted, so the output doesn't depend on pairs order
	local names = {}
	for name in pairs(g) do
		names[#names+1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local r = g[name]
		if not r.isrule then
			r = P.rule{ body = r }
			g[name] = r
		end
		local params = {}
		if r.body.kind == 'prec' then
			r.body.name = name
			r.params = { { 'limit', i32 } }
			r.results = { i32 }
			r.locals = r.locals or {}
			for _, l in ipairs{ { 'op', i32 }, { 'opline', i32 }, { 'e', i32 }, { 'e2', i32 } } do
				table.insert(r.locals, l)
			end
		end
		for i, p in ipairs(r.params or {}) do
			params[i] = p[2]
		end
		local results = r.results or {}
		local args = { table.unpack(params) }
		args[#args+1] = #results == 0 and void or (#results == 1 and results[1] or results)
		args[#args+1] = function(f, ...)
			local L = {}
			local ps = { ... }
			for i, p in ipairs(r.params or {}) do
				L[p[1]] = ps[i]
			end
			L._t = f:locals(i32)
			L.pl = f:locals(i32)
			for _, l in ipairs(r.locals or {}) do
				L[l[1]] = f:locals(l[2])
			end
			if r.body.kind == 'prec' then
				genprec(f, L, r.body)
			else
				gen(f, L, r.body)
				if r.result then
					r.result(f, L)
				end
			end
		end
		local fn = M.func(table.unpack(args))
		fn.name = 'parse.' .. name
		funcs[name] = fn
	end
	for _, name in ipairs(names) do
		local r = g[name]
		first(r)
	end
	return funcs
end

return P
