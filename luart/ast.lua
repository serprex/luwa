local lex = require'lex'

local Block = 0
local Stat = 1
local Retstat = 2
local Label = 3

function name(lx, x, p)
	local t = x:next(p)
	if t:val(lx) == lex._ident then
		return coroutine.yield(t:skipint(lx))
	end
end

function number(lx, x, p)
	local t = x:next(p)
	if t:val(lx) == lex._number then
		return coroutine.yield(t:skipint(lx))
	end
end

function slit(lx, x, p)
	local t = x:next(p)
	if t:val(lx) == lex._string then
		return coroutine.yield(t:skipint(lx))
	end
end

function s(r)
	return function(lx, x, p)
		local t = x:next(p)
		if t:val(lx) == r then
			return coroutine.yield(t)
		end
	end
end

function o(n)
	return function(lx, x, p)
		return rules[n](lx, x, p)
	end
end

function yieldall(succ, ...)
	if succ then
		coroutine.yield(...)
	end
	return succ
end

function seqcore(lx, x, p, xs, i)
	if i == #xs then
		return xs[i](lx, x, p)
	else
		for ax in coroutine.wrap(xs[i], lx, x, p) do
			seqcore(lx, ax, p, i+1)
		end
	end
end
function seq(xs)
	return function(lx, x, p)
		return seqcore(lx, x, p, xs, 0)
	end
end

function sf(o, xs)
	local seqf = seq(xs)
	rules[o] = function(lx, x, p)
		return seqf(lx, x, x:spawn(o, p))
	end
end

function manyf(f, lx, x, p)
	for fx in coroutine.wrap(f, lx, x, p) do
		manyf(lx, fx, p)
	end
	return coroutine.yield(x)
end
function many(f)
	return function(lx, x, p)
		return manyf(f, lx, x, p)
	end
end
