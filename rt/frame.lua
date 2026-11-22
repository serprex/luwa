-- Call frames & metamethod lookup, as wasm helpers that microbc ops call.
-- Frame switching helpers return the pc to run next, or -1 when the main function returned.
-- Stack layout of a frame, in slots from base: the function at base-1, params, varargs,
-- locals, then 3 objframe slots (bc, consts, frees), then the operand stack
local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, R, typeof, tbl, vec, vals, int, functy, bytes, coro, nextid, newi64 =
	alloc.types, alloc.R, alloc.typeof, alloc.tbl, alloc.vec, alloc.vals, alloc.int, alloc.functy, alloc.bytes, alloc.coro,
	alloc.nextid, alloc.newi64

local _table = require '_table'
local tblget, tblset = _table.tblget, _table.tblset

local _obj = require 'obj'

local stack = require 'stack'
local tmppush, extendtmp, stacklen, setstacklen, sget, sset, scopy, df, fget, fset, fpush, fpop =
	stack.tmppush, stack.extendtmp, stack.stacklen, stack.setstacklen, stack.sget, stack.sset, stack.scopy,
	stack.df, stack.fget, stack.fset, stack.fpush, stack.fpop

require 'rt' -- GS, oluastack, ostrmt

local objframe = {
	bc = 0,
	consts = 1,
	frees = 2,
	sizeof = 3,
}
local calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}
-- retc for "keep every result"
local RETALL = 0xffff

-- Little endian i32 at bc[i]: bytecode args are 4 bytes
local bcarg = func(R.bytes, i32, i32, function(f, bc, i)
	for k = 0, 3 do
		f:load(bc)
		f:load(i)
		if k > 0 then
			f:i32(k)
			f:add()
		end
		f:arrayget(bytes, false)
		if k > 0 then
			f:i32(k * 8)
			f:shl()
			f:bor()
		end
	end
end)

local function getf(f, field)
	f:i32(df[field])
	f:call(fget)
end
local function setf(f, field, val)
	f:i32(df[field])
	val()
	f:call(fset)
end

-- Param i of the running function
local param = func(i32, V, function(f, i)
	getf(f, 'base')
	f:load(i)
	f:add()
	f:call(sget)
end)
-- How many varargs the running function got, & vararg i
local vargc = func(i32, function(f)
	getf(f, 'locals')
	getf(f, 'dotdotdot')
	f:sub()
end)
local varg = func(i32, V, function(f, i)
	getf(f, 'base')
	getf(f, 'dotdotdot')
	f:add()
	f:load(i)
	f:add()
	f:call(sget)
end)

-- Metatable of any value, nil if it has none
local getmeta = func(V, R.tbl, function(f, o)
	local ty = f:locals(i32)
	f:load(o)
	f:call(typeof)
	f:tee(ty)
	f:i32(types.tbl)
	f:eq()
	f:iff(R.tbl, function()
		f:load(o)
		f:refcast(M.ref(tbl))
		f:structget(tbl, 'meta')
	end, function()
		f:load(ty)
		f:i32(types.str)
		f:eq()
		f:iff(R.tbl, function()
			f:loadg(ostrmt)
		end, function()
			f:refnull(tbl)
		end)
	end)
end)

-- o's metatable's field key, nil if no metatable
local metaget = func(V, R.str, V, function(f, o, key)
	local m = f:locals(R.tbl)
	f:load(o)
	f:call(getmeta)
	f:tee(m)
	f:refisnull()
	f:iff(V, function()
		f:refnull(M.heap.eq)
	end, function()
		f:load(m)
		f:load(key)
		f:call(tblget)
	end)
end)

-- Metamethod for a binary op: a's, else b's
local binmeta = func(V, V, R.str, V, function(f, a, b, key)
	local h = f:locals(V)
	f:load(a)
	f:load(key)
	f:call(metaget)
	f:tee(h)
	f:refisnull()
	f:iff(V, function()
		f:load(b)
		f:load(key)
		f:call(metaget)
	end, function()
		f:load(h)
	end)
end)

-- Receiver for idxwalk's result when it's an __index function to call, otherwise nil
local idxself = M.global(V, true)

-- a[b], following __index tables. When it reaches an __index function,
-- returns that function & sets idxself to the value to call it with
local idxwalk = func(V, V, V, function(f, a, b)
	local ty, i = f:locals(i32, 2)
	local v, h = f:locals(V, 2)
	local arr = f:locals(R.vals)
	f:refnull(M.heap.eq)
	f:storeg(idxself)
	f:loop(function(loop)
		-- TODO Lua limits chains to 2000 length to try detect infinite loops
		f:load(a)
		f:call(typeof)
		f:tee(ty)
		f:i32(types.tbl)
		f:eq()
		f:iff(function()
			f:load(a)
			f:refcast(R.tbl)
			f:load(b)
			f:call(tblget)
			f:tee(v)
			f:refisnull()
			f:eqz()
			f:iff(function()
				f:load(v)
				f:ret()
			end)
			f:load(a)
			f:loadg(GS.__index)
			f:call(metaget)
			f:tee(h)
			f:refisnull()
			f:iff(function()
				f:refnull(M.heap.eq)
				f:ret()
			end)
		end, function()
			f:load(ty)
			f:i32(types.vec)
			f:eq()
			f:iff(function()
				-- vecs (eg the lexer's value list) index from 1 with integers, nil past the end
				f:load(b)
				f:call(typeof)
				f:i32(types.int)
				f:ne()
				f:iff(function()
					f:unreachable()
				end)
				f:load(b)
				f:refcast(M.ref(int))
				f:structget(int, 'val')
				f:i32wrap()
				f:i32(1)
				f:sub()
				f:tee(i)
				-- unsigned compare also catches keys below 1
				f:load(a)
				f:refcast(M.ref(vec))
				f:structget(vec, 'arr')
				f:tee(arr)
				f:arraylen()
				f:ltu()
				f:iff(V, function()
					f:load(arr)
					f:load(i)
					f:arrayget(vals)
				end, function()
					f:refnull(M.heap.eq)
				end)
				f:ret()
			end)
			f:load(a)
			f:loadg(GS.__index)
			f:call(metaget)
			f:tee(h)
			f:refisnull()
			f:iff(function()
				-- TODO error: attempt to index a value
				f:unreachable()
			end)
		end)
		f:load(h)
		f:call(typeof)
		f:i32(types.functy)
		f:eq()
		f:iff(function()
			f:load(a)
			f:storeg(idxself)
			f:load(h)
			f:ret()
		end)
		-- __index is a table (or string): index it next
		f:load(h)
		f:store(a)
		f:br(loop)
	end)
	f:unreachable()
end)

-- Push a frame. dotdotdot, locals & frame are filled in by setupframe
local pushframe = func(i32, i32, i32, void, function(f, callty, base, retc)
	f:call(fpush)
	setf(f, 'type', function() f:load(callty) end)
	setf(f, 'base', function() f:load(base) end)
	-- results go where the function was
	setf(f, 'retb', function() f:i32(-1) end)
	setf(f, 'retc', function() f:load(retc) end)
end)

-- Finish the top frame for fn, whose args go from base to the end of the stack.
-- Adds missing params, locals & the objframe after the args
local framefor = func(R.functy, void, function(f, fn)
	local base, argc, paramc, localc, locals = f:locals(i32, 5)
	getf(f, 'base')
	f:tee(base)
	f:call(stacklen)
	f:load(base)
	f:sub()
	f:store(argc)
	f:drop()

	f:load(fn)
	f:structget(functy, 'paramc')
	f:store(paramc)
	f:load(fn)
	f:structget(functy, 'localc')
	f:store(localc)

	-- locals start after params & varargs: max(args, params)
	f:load(argc)
	f:load(paramc)
	f:load(argc)
	f:load(paramc)
	f:gts()
	f:select()
	f:store(locals)

	-- new slots are nil
	f:load(locals)
	f:load(argc)
	f:sub()
	f:load(localc)
	f:add()
	f:i32(objframe.sizeof)
	f:add()
	f:call(extendtmp)

	setf(f, 'dotdotdot', function() f:load(paramc) end)
	setf(f, 'locals', function() f:load(locals) end)
	setf(f, 'frame', function()
		f:load(locals)
		f:load(localc)
		f:add()
		f:tee(locals)
	end)

	f:load(base)
	f:load(locals)
	f:add()
	f:tee(base)
	f:load(fn)
	f:structget(functy, 'bc')
	f:call(sset)

	f:load(base)
	f:i32(1)
	f:add()
	f:load(fn)
	f:structget(functy, 'consts')
	f:call(sset)

	f:load(base)
	f:i32(2)
	f:add()
	f:load(fn)
	f:structget(functy, 'frees')
	f:call(sset)
end)

-- Finish the top frame, its function is at base-1
local setupframe = func(function(f)
	local fn = f:locals(V)
	getf(f, 'base')
	f:i32(1)
	f:sub()
	f:call(sget)
	f:tee(fn)
	-- TODO __call metamethod, error otherwise
	f:call(typeof)
	f:i32(types.functy)
	f:ne()
	f:iff(function()
		f:unreachable()
	end)
	f:load(fn)
	f:refcast(R.functy)
	f:call(framefor)
end)

-- Call the function under the top argc values, keeping 1 result.
-- nextpc is where the current frame carries on after
local callmeta = func(i32, i32, i32, i32, function(f, argc, callty, nextpc)
	setf(f, 'pc', function() f:load(nextpc) end)
	f:load(callty)
	f:call(stacklen)
	f:load(argc)
	f:sub()
	f:i32(1)
	f:call(pushframe)
	f:call(setupframe)
	f:i32(0)
end)

-- Copy this frame's varargs to the top of the stack. Returns how many
local pushvarg = func(i32, function(f)
	local n, len, src = f:locals(i32, 3)
	getf(f, 'locals')
	getf(f, 'dotdotdot')
	f:sub()
	f:tee(n)
	f:i32(0)
	f:gts()
	f:iff(i32, function()
		getf(f, 'base')
		getf(f, 'dotdotdot')
		f:add()
		f:store(src)
		f:call(stacklen)
		f:store(len)
		f:load(n)
		f:call(extendtmp)
		f:load(len)
		f:load(src)
		f:load(n)
		f:call(scopy)
		f:load(n)
	end, function()
		f:i32(0)
	end)
end)

-- Push the first n varargs, nil past the last one
local loadvarg = func(i32, void, function(f, n)
	local i, vlen, src = f:locals(i32, 3)
	getf(f, 'locals')
	getf(f, 'dotdotdot')
	f:sub()
	f:store(vlen)
	getf(f, 'base')
	getf(f, 'dotdotdot')
	f:add()
	f:store(src)
	f:block(function(done)
		f:loop(function(loop)
			f:load(i)
			f:load(n)
			f:geu()
			f:brif(done)

			f:load(i)
			f:load(vlen)
			f:lts()
			f:iff(V, function()
				f:load(src)
				f:load(i)
				f:add()
				f:call(sget)
			end, function()
				f:refnull(M.heap.eq)
			end)
			f:call(tmppush)

			f:load(i)
			f:i32(1)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
end)

-- Stack is table, then n values. Set t[1..n] to them & leave only the table
local appendn = func(i32, void, function(f, n)
	local first, i = f:locals(i32, 2)
	local t = f:locals(R.tbl)
	f:call(stacklen)
	f:load(n)
	f:sub()
	f:tee(first)
	f:i32(1)
	f:sub()
	f:call(sget)
	f:refcast(R.tbl)
	f:store(t)
	f:block(function(done)
		f:loop(function(loop)
			f:load(i)
			f:load(n)
			f:geu()
			f:brif(done)

			f:load(t)
			f:load(i)
			f:i32(1)
			f:add()
			f:i64extendu()
			f:call(newi64)
			f:load(first)
			f:load(i)
			f:add()
			f:call(sget)
			f:call(tblset)

			f:load(i)
			f:i32(1)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
	f:load(first)
	f:call(setstacklen)
end)

-- Like appendn, then append this frame's varargs too
local appendvarg = func(i32, void, function(f, n)
	f:load(n)
	f:call(pushvarg)
	f:add()
	f:call(appendn)
end)

-- Copy of function proto, with the top n stack values popped into its frees
local makeclosure = func(V, i32, V, function(f, protov, n)
	local proto = f:locals(R.functy)
	local frees = f:locals(R.vals)
	local len = f:locals(i32)
	f:load(protov)
	f:refcast(R.functy)
	f:store(proto)

	f:load(n)
	f:iff(R.vals, function()
		f:load(n)
		f:arraynewdefault(vals)
		f:tee(frees)
		f:i32(0)
		f:loadg(gstack)
		f:structget(alloc.stack, 'arr')
		f:call(stacklen)
		f:load(n)
		f:sub()
		f:tee(len)
		f:load(n)
		f:arraycopy(vals, vals)
		f:load(len)
		f:call(setstacklen)
		f:load(frees)
	end, function()
		f:load(proto)
		f:structget(functy, 'frees')
	end)
	f:store(frees)

	f:i32(types.functy)
	f:call(nextid)
	f:load(proto)
	f:structget(functy, 'isdotdotdot', false)
	f:load(proto)
	f:structget(functy, 'bc')
	f:load(proto)
	f:structget(functy, 'consts')
	f:load(frees)
	f:load(proto)
	f:structget(functy, 'localc')
	f:load(proto)
	f:structget(functy, 'paramc')
	f:structnew(functy)
end)

-- Call op family. Bytecode args from pc: retc, n, then n arg counts, outermost call first.
-- Stack holds f1 args1.. f2 args2.. ... fn argsn.., the innermost call runs first.
-- Outer calls get frames now (type call) & are set up as each inner one returns
local function mkcallchain(varg)
	return func(R.bytes, i32, i32, i32, function(f, bc, pc, callty)
		local n, i, off, vb, cnt = f:locals(i32, 5)
		local function arg(k)
			f:load(bc)
			f:load(pc)
			k()
			f:i32(2)
			f:shl()
			f:add()
			f:call(bcarg)
		end
		arg(function() f:i32(1) end)
		f:store(n)

		if varg then
			f:call(pushvarg)
			f:store(vb)
		end

		setf(f, 'pc', function()
			f:load(pc)
			f:load(n)
			f:i32(2)
			f:add()
			f:i32(2)
			f:shl()
			f:add()
		end)

		-- off = where the outermost function sits
		f:call(stacklen)
		f:load(vb)
		f:sub()
		f:store(off)
		f:loop(function(loop)
			f:load(off)
			arg(function()
				f:load(i)
				f:i32(2)
				f:add()
			end)
			f:i32(1)
			f:add()
			f:sub()
			f:store(off)

			f:load(i)
			f:i32(1)
			f:add()
			f:tee(i)
			f:load(n)
			f:ltu()
			f:brif(loop)
		end)

		f:i32(0)
		f:store(i)
		f:loop(function(loop)
			f:i32(calltypes.call)
			f:load(callty)
			f:load(i)
			f:select()
			f:load(off)
			f:i32(1)
			f:add()
			f:i32(RETALL)
			arg(function() f:i32(0) end)
			f:load(i)
			f:select()
			f:call(pushframe)

			f:load(off)
			arg(function()
				f:load(i)
				f:i32(2)
				f:add()
			end)
			f:i32(1)
			f:add()
			f:add()
			f:store(off)

			f:load(i)
			f:i32(1)
			f:add()
			f:tee(i)
			f:load(n)
			f:ltu()
			f:brif(loop)
		end)
		f:call(setupframe)
		f:i32(0)
	end)
end
local callchain = mkcallchain(false)
local callchainvarg = mkcallchain(true)

-- Return op: results are everything after the objframe
local retframe = func(i32, function(f)
	local base, retb, ty, c, e, key, len = f:locals(i32, 7)
	getf(f, 'base')
	f:tee(base)
	getf(f, 'retb')
	f:add()
	f:store(retb)
	getf(f, 'retc')
	f:store(key)
	getf(f, 'type')
	f:store(ty)
	f:load(base)
	getf(f, 'frame')
	f:add()
	f:i32(objframe.sizeof)
	f:add()
	f:store(e)
	f:call(stacklen)
	f:store(len)

	f:block(function(copied)
		f:load(ty)
		f:i32(calltypes.init)
		f:eq()
		f:iff(function()
			f:loadg(oluastack)
			f:structget(coro, 'caller')
			f:refisnull()
			f:iff(function()
				-- main returned, results stay on the stack for the caller
				f:i32(-1)
				f:ret()
			end)
			-- TODO a coroutine finished: hand results to the caller
			f:unreachable()
		end)

		-- first result made true/false, false if none
		f:load(ty)
		f:i32(calltypes.bool)
		f:eq()
		f:iff(function()
			f:load(retb)
			f:load(e)
			f:load(len)
			f:eq()
			f:iff(i32, function()
				f:i32(0)
			end, function()
				f:load(e)
				f:call(sget)
				f:call(_obj.truthy)
			end)
			f:refi31()
			f:call(sset)
			f:i32(1)
			f:store(c)
			f:br(copied)
		end)

		-- push frames keep every result, their retc is how many fixed values sit below the function
		f:load(key)
		f:i32(RETALL)
		f:eq()
		f:load(ty)
		f:i32(calltypes.push)
		f:eq()
		f:bor()
		f:iff(i32, function()
			f:load(len)
			f:load(e)
			f:sub()
		end, function()
			f:load(key)
		end)
		f:tee(c)
		f:iff(function()
			-- too few results: nil fill
			f:load(e)
			f:load(c)
			f:add()
			f:load(len)
			f:gts()
			f:iff(function()
				f:load(e)
				f:load(c)
				f:add()
				f:load(len)
				f:sub()
				f:call(extendtmp)
			end)
			f:load(retb)
			f:load(e)
			f:load(c)
			f:call(scopy)
		end)
	end)

	-- pop stack frame
	f:load(retb)
	f:load(c)
	f:add()
	f:call(setstacklen)
	f:call(fpop)

	-- call frame: results are now args of the next function in the chain,
	-- whose frame is on top with pc 0
	f:load(ty)
	f:i32(calltypes.call)
	f:eq()
	f:iff(function()
		f:call(setupframe)
	end)

	-- push frame: stack is table, key fixed values, then results from retb on.
	-- Append values & results as t[1..], then leave only the table
	f:load(ty)
	f:i32(calltypes.push)
	f:eq()
	f:iff(function()
		f:load(key)
		f:load(c)
		f:add()
		f:call(appendn)
	end)

	getf(f, 'pc')
end)

return {
	objframe = objframe,
	calltypes = calltypes,
	RETALL = RETALL,
	bcarg = bcarg,
	getf = getf,
	setf = setf,
	param = param,
	vargc = vargc,
	varg = varg,
	getmeta = getmeta,
	metaget = metaget,
	binmeta = binmeta,
	idxself = idxself,
	idxwalk = idxwalk,
	pushframe = pushframe,
	framefor = framefor,
	setupframe = setupframe,
	callmeta = callmeta,
	callchain = callchain,
	callchainvarg = callchainvarg,
	retframe = retframe,
	pushvarg = pushvarg,
	loadvarg = loadvarg,
	appendn = appendn,
	appendvarg = appendvarg,
	makeclosure = makeclosure,
}
