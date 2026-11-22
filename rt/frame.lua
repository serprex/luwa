-- Call frames & metamethod lookup, as wasm helpers that microbc ops call.
-- Frame switching helpers return the pc to run next, or -1 when the main function returned
local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local types, obj, str, vec, buf, tbl, functy, coro, nextid, newobj, newi64, newstr, newvec =
	alloc.types, alloc.obj, alloc.str, alloc.vec, alloc.buf, alloc.tbl, alloc.functy, alloc.coro,
	alloc.nextid, alloc.newobj, alloc.newi64, alloc.newstr, alloc.newvec

local _table = require '_table'
local tblget, tblset = _table.tblget, _table.tblset

local stack = require 'stack'
local tmppush, extendtmp = stack.tmppush, stack.extendtmp

local util = require 'util'
local extendstr, extendvec, memcpy4, memcpy1rl = util.extendstr, util.extendvec, util.memcpy4, util.memcpy1rl

require 'rt' -- GS, NIL/FALSE/TRUE, oluastack, ostrmt

local dataframe = {
	type = str.base + 0,
	pc = str.base + 1,
	base = str.base + 5, -- Base. params here
	dotdotdot = str.base + 9, -- base+dotdotdot = excess params here. Ends at base+locals
	retb = str.base + 11, -- base+retb = put return vals here
	retc = str.base + 13, -- base+retc = stack should be post return. 0xffff for piped return
	locals = str.base + 15, -- base+locals = locals here
	frame = str.base + 17, -- base+frame = objframe here
	sizeof = 19,
}
local objframe = {
	bc = vec.base + 0,
	consts = vec.base + 4,
	frees = vec.base + 8,
	tmpbc = 12,
	tmpconsts = 8,
	tmpfrees = 4,
	sizeof = 12,
}
local calltypes = {
	norm = 0, -- Reload locals
	init = 1, -- Return stack to coro src, src nil for main
	prot = 2, -- Reload locals
	call = 3, -- Continue call chain
	push = 4, -- Append intermediates to table
	bool = 5, -- Cast result to bool
}

-- Address of the top dataframe. Global: std*.lua use it too
loadframebase = func(i32, function(f)
	local a = f:locals(i32)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:i32load(buf.ptr)
	f:load(a)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
end)

-- Lua stack: values sit at ptr + vec.base + offset, offsets run from 0 to len
local function stackbuf(f)
	f:loadg(oluastack)
	f:i32load(coro.stack)
end
local function stackptr(f)
	stackbuf(f)
	f:i32load(buf.ptr)
end
local function stacklen(f)
	stackbuf(f)
	f:i32load(buf.len)
end

-- Metatable of any value, nil if it has none
local getmeta = func(i32, i32, function(f, o)
	local ty = f:locals(i32)
	f:load(o)
	f:i32load8u(obj.type)
	f:tee(ty)
	f:i32(types.tbl)
	f:eq()
	f:iff(i32, function()
		f:load(o)
		f:i32load(tbl.meta)
	end, function()
		f:loadg(ostrmt)
		f:i32(NIL)
		f:load(ty)
		f:i32(types.str)
		f:eq()
		f:select()
	end)
end)

-- o's metatable's field key, nil if no metatable
local metaget = func(i32, i32, i32, function(f, o, key)
	local m = f:locals(i32)
	f:load(o)
	f:call(getmeta)
	f:tee(m)
	f:iff(i32, function()
		f:load(m)
		f:load(key)
		f:call(tblget)
	end, function()
		f:i32(NIL)
	end)
end)

-- Metamethod for a binary op: a's, else b's
local binmeta = func(i32, i32, i32, i32, function(f, a, b, key)
	local h = f:locals(i32)
	f:load(a)
	f:load(key)
	f:call(metaget)
	f:tee(h)
	f:load(b)
	f:load(key)
	f:call(metaget)
	f:load(h)
	f:select()
end)

-- Receiver for idxwalk's result when it's an __index function to call, otherwise 0
local idxself = M.global(i32, true)

-- a[b], following __index tables. When it reaches an __index function,
-- returns that function & sets idxself to the value to call it with
local idxwalk = func(i32, i32, i32, function(f, a, b)
	local ty, v, h = f:locals(i32, 3)
	f:i32(0)
	f:storeg(idxself)
	f:loop(function(loop)
		-- TODO Lua limits chains to 2000 length to try detect infinite loops
		f:load(a)
		f:i32load8u(obj.type)
		f:tee(ty)
		f:i32(types.tbl)
		f:eq()
		f:iff(function()
			f:load(a)
			f:load(b)
			f:call(tblget)
			f:tee(v)
			f:iff(function()
				f:load(v)
				f:ret()
			end)
			f:load(a)
			f:i32(GS.__index)
			f:call(metaget)
			f:tee(h)
			f:eqz()
			f:iff(function()
				f:i32(NIL)
				f:ret()
			end)
		end, function()
			f:load(ty)
			f:i32(types.vec)
			f:eq()
			f:iff(function()
				-- vecs (eg the lexer's value list) index from 1 with integers, nil past the end
				f:load(b)
				f:i32load8u(obj.type)
				f:i32(types.int)
				f:ne()
				f:iff(function()
					f:unreachable()
				end)
				f:load(b)
				f:i64load(alloc.num.val)
				f:i32wrap()
				f:i32(1)
				f:sub()
				f:i32(2)
				f:shl()
				f:tee(v)
				-- unsigned compare also catches keys below 1
				f:load(a)
				f:i32load(vec.len)
				f:ltu()
				f:iff(i32, function()
					f:load(a)
					f:load(v)
					f:add()
					f:i32load(vec.base)
				end, function()
					f:i32(NIL)
				end)
				f:ret()
			end)
			f:load(a)
			f:i32(GS.__index)
			f:call(metaget)
			f:tee(h)
			f:eqz()
			f:iff(function()
				-- TODO error: attempt to index a value
				f:unreachable()
			end)
		end)
		f:load(h)
		f:i32load8u(obj.type)
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

-- New string a..b
local strconcat = func(i32, i32, i32, function(f, a, b)
	local s = f:locals(i32)
	f:load(a)
	f:i32load(str.len)
	f:load(b)
	f:i32load(str.len)
	f:add()
	f:call(newstr)
	f:tee(s)
	f:i32(str.base)
	f:add()
	f:load(a)
	f:i32(str.base)
	f:add()
	f:load(a)
	f:i32load(str.len)
	f:call(memcpy1rl)

	f:load(s)
	f:i32(str.base)
	f:add()
	f:load(a)
	f:i32load(str.len)
	f:add()
	f:load(b)
	f:i32(str.base)
	f:add()
	f:load(b)
	f:i32load(str.len)
	f:call(memcpy1rl)
	f:load(s)
end)

-- Push a dataframe. dotdotdot, locals & frame are filled in by setupframe
local pushframe = func(i32, i32, i32, void, function(f, callty, base, retc)
	local fr = f:locals(i32)
	f:loadg(oluastack)
	f:i32load(coro.data)
	f:i32(dataframe.sizeof)
	f:call(extendstr)
	f:tee(fr)
	f:i32load(buf.ptr)
	f:load(fr)
	f:i32load(buf.len)
	f:add()
	f:i32(dataframe.sizeof)
	f:sub()
	f:tee(fr)
	f:load(callty)
	f:i32store8(dataframe.type)

	f:load(fr)
	f:i32(0)
	f:i32store(dataframe.pc)

	f:load(fr)
	f:load(base)
	f:i32store(dataframe.base)

	-- results go where the function was
	f:load(fr)
	f:i32(-4)
	f:i32store16(dataframe.retb)

	f:load(fr)
	f:load(retc)
	f:i32store16(dataframe.retc)
end)

-- Finish the top frame: its function is at base-4, args from base to the end of the stack.
-- Adds missing params, locals & the objframe after the args
local setupframe = func(function(f)
	local fr, base, fn, argc4, paramc4, localc4, locals = f:locals(i32, 7)
	f:call(loadframebase)
	f:tee(fr)
	f:i32load(dataframe.base)
	f:store(base)

	stacklen(f)
	f:load(base)
	f:sub()
	f:store(argc4)

	stackptr(f)
	f:load(base)
	f:add()
	f:i32load(vec.base - 4)
	f:tee(fn)
	-- TODO __call metamethod, error otherwise
	f:i32load8u(obj.type)
	f:i32(types.functy)
	f:ne()
	f:iff(function()
		f:unreachable()
	end)

	f:load(fn)
	f:i32load(functy.paramc)
	f:i32(2)
	f:shl()
	f:store(paramc4)

	f:load(fn)
	f:i32load(functy.localc)
	f:i32(2)
	f:shl()
	f:store(localc4)

	-- locals start after params & varargs: max(args, params)
	f:load(argc4)
	f:load(paramc4)
	f:load(argc4)
	f:load(paramc4)
	f:gts()
	f:select()
	f:store(locals)

	-- new slots are nil
	f:load(locals)
	f:load(argc4)
	f:sub()
	f:load(localc4)
	f:add()
	f:i32(objframe.sizeof)
	f:add()
	f:call(extendtmp)

	f:load(fr)
	f:load(paramc4)
	f:i32store16(dataframe.dotdotdot)

	f:load(fr)
	f:load(locals)
	f:i32store16(dataframe.locals)

	f:load(fr)
	f:load(locals)
	f:load(localc4)
	f:add()
	f:tee(locals)
	f:i32store16(dataframe.frame)

	-- extendtmp may have moved the stack
	stackptr(f)
	f:load(base)
	f:add()
	f:load(locals)
	f:add()
	f:tee(fr)
	f:load(fn)
	f:i32load(functy.bc)
	f:i32store(objframe.bc)

	f:load(fr)
	f:load(fn)
	f:i32load(functy.consts)
	f:i32store(objframe.consts)

	f:load(fr)
	f:load(fn)
	f:i32load(functy.frees)
	f:i32store(objframe.frees)
end)

-- Call the function under the top argc values, keeping 1 result.
-- nextpc is where the current frame carries on after
local callmeta = func(i32, i32, i32, i32, function(f, argc, callty, nextpc)
	f:call(loadframebase)
	f:load(nextpc)
	f:i32store(dataframe.pc)

	f:load(callty)
	stacklen(f)
	f:load(argc)
	f:i32(2)
	f:shl()
	f:sub()
	f:i32(1)
	f:call(pushframe)
	f:call(setupframe)
	f:i32(0)
end)

-- Copy this frame's varargs (base+dotdotdot up to base+locals) to the top of the stack.
-- Returns their size in bytes
local pushvarg = func(i32, function(f)
	local fr, n, len, src = f:locals(i32, 4)
	f:call(loadframebase)
	f:tee(fr)
	f:i32load16u(dataframe.locals)
	f:load(fr)
	f:i32load16u(dataframe.dotdotdot)
	f:sub()
	f:tee(n)
	f:i32(0)
	f:gts()
	f:iff(i32, function()
		f:load(fr)
		f:i32load(dataframe.base)
		f:load(fr)
		f:i32load16u(dataframe.dotdotdot)
		f:add()
		f:store(src)
		stacklen(f)
		f:store(len)
		f:load(n)
		f:call(extendtmp)

		-- extendtmp may have moved the stack
		stackptr(f)
		f:i32(vec.base)
		f:add()
		f:tee(fr)
		f:load(len)
		f:add()
		f:load(fr)
		f:load(src)
		f:add()
		f:load(n)
		f:call(memcpy4)
		f:load(n)
	end, function()
		f:i32(0)
	end)
end)

-- Push the first n varargs, nil past the last one
local loadvarg = func(i32, void, function(f, n)
	local fr, i, vlen = f:locals(i32, 3)
	f:call(loadframebase)
	f:tee(fr)
	f:i32load16u(dataframe.locals)
	f:load(fr)
	f:i32load16u(dataframe.dotdotdot)
	f:sub()
	f:store(vlen)
	f:load(n)
	f:i32(2)
	f:shl()
	f:store(n)
	f:block(function(done)
		f:loop(function(loop)
			f:load(i)
			f:load(n)
			f:geu()
			f:brif(done)

			f:load(i)
			f:load(vlen)
			f:lts()
			f:iff(i32, function()
				-- tmppush may have moved the stack, so find the slot each time
				stackptr(f)
				f:load(fr)
				f:i32load(dataframe.base)
				f:add()
				f:load(fr)
				f:i32load16u(dataframe.dotdotdot)
				f:add()
				f:load(i)
				f:add()
				f:i32load(vec.base)
			end, function()
				f:i32(NIL)
			end)
			f:call(tmppush)

			f:load(i)
			f:i32(4)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
end)

-- Stack is table, then n values. Set t[1..n] to them & leave only the table
local appendn = func(i32, void, function(f, n)
	local first, i, k = f:locals(i32, 3)
	stacklen(f)
	f:load(n)
	f:i32(2)
	f:shl()
	f:tee(n)
	f:sub()
	f:store(first)
	f:block(function(done)
		f:loop(function(loop)
			f:load(i)
			f:load(n)
			f:geu()
			f:brif(done)

			f:load(i)
			f:i32(2)
			f:shru()
			f:i32(1)
			f:add()
			f:i64extendu()
			f:call(newi64)
			f:store(k)

			stackptr(f)
			f:load(first)
			f:add()
			f:i32load(vec.base - 4)
			f:load(k)
			stackptr(f)
			f:load(first)
			f:add()
			f:load(i)
			f:add()
			f:i32load(vec.base)
			f:call(tblset)

			f:load(i)
			f:i32(4)
			f:add()
			f:store(i)
			f:br(loop)
		end)
	end)
	stackbuf(f)
	f:load(first)
	f:i32store(buf.len)
end)

-- Like appendn, then append this frame's varargs too
local appendvarg = func(i32, void, function(f, n)
	f:load(n)
	f:call(pushvarg)
	f:i32(2)
	f:shru()
	f:add()
	f:call(appendn)
end)

-- Copy of function proto, with the top n stack values popped into its frees
local makeclosure = func(i32, i32, i32, function(f, proto, n)
	local fn, frees, len = f:locals(i32, 3)
	f:i32(functy.sizeof)
	f:i32(types.functy)
	f:call(newobj)
	f:store(fn)
	-- copy proto's fields, but not its gc word (newobj set ours).
	-- 4 byte steps from type onwards, ends at sizeof
	for offs=obj.type,functy.sizeof-4,4 do
		f:load(fn)
		f:load(proto)
		f:i32load(offs)
		f:i32store(offs)
	end
	f:load(fn)
	f:call(nextid)
	f:i32store(functy.id)

	f:load(n)
	f:iff(function()
		f:load(n)
		f:i32(2)
		f:shl()
		f:tee(n)
		f:call(newvec)
		f:store(frees)

		stacklen(f)
		f:load(n)
		f:sub()
		f:store(len)

		f:load(frees)
		f:i32(vec.base)
		f:add()
		stackptr(f)
		f:i32(vec.base)
		f:add()
		f:load(len)
		f:add()
		f:load(n)
		f:call(memcpy4)

		f:load(fn)
		f:load(frees)
		f:i32store(functy.frees)

		stackbuf(f)
		f:load(len)
		f:i32store(buf.len)
	end)
	f:load(fn)
end)

-- Call op family. Bytecode args from pc: retc, n, then n arg counts, outermost call first.
-- Stack holds f1 args1.. f2 args2.. ... fn argsn.., the innermost call runs first.
-- Outer calls get frames now (type call) & are set up as each inner one returns
local function mkcallchain(varg)
	return func(i32, i32, i32, i32, function(f, bc, pc, callty)
		local argp, n, i, off, vb = f:locals(i32, 5)
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32(str.base)
		f:add()
		f:tee(argp)
		f:i32load(4)
		f:store(n)

		if varg then
			f:call(pushvarg)
			f:store(vb)
		end

		f:call(loadframebase)
		f:load(pc)
		f:load(n)
		f:i32(2)
		f:add()
		f:i32(2)
		f:shl()
		f:add()
		f:i32store(dataframe.pc)

		-- off = where the outermost function sits
		stacklen(f)
		f:load(vb)
		f:sub()
		f:store(off)
		f:loop(function(loop)
			f:load(off)
			f:load(argp)
			f:load(i)
			f:i32(2)
			f:shl()
			f:add()
			f:i32load(8)
			f:i32(2)
			f:shl()
			f:i32(4)
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
			f:i32(4)
			f:add()
			f:i32(-1)
			f:load(argp)
			f:i32load(0)
			f:load(i)
			f:select()
			f:call(pushframe)

			f:load(off)
			f:load(argp)
			f:load(i)
			f:i32(2)
			f:shl()
			f:add()
			f:i32load(8)
			f:i32(2)
			f:shl()
			f:i32(4)
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
	local fr, base, retb, ty, c, e, a, b, d, key, off = f:locals(i32, 11)
	f:call(loadframebase)
	f:tee(fr)
	f:i32load(dataframe.base)
	f:store(base)

	f:load(fr)
	f:i32load16s(dataframe.retb)
	f:load(base)
	f:add()
	f:store(retb)

	f:load(fr)
	f:i32load16u(dataframe.retc)
	f:store(key)

	f:block(function(copied)
		f:load(fr)
		f:i32load8u(dataframe.type)
		f:tee(ty)
		f:i32(calltypes.init)
		f:eq()
		f:iff(function()
			-- if init: setup ret for resume call in caller coro
			f:loadg(oluastack)
			f:i32load(coro.caller)
			f:tee(a)
			f:iff(function()
				-- extend caller stack to fit our ret stack
				f:load(a)
				f:i32load(coro.stack)
				f:tee(a)
				f:load(a)
				f:i32load(buf.len)
				f:store(b)

				stacklen(f)
				f:load(base)
				f:sub()
				f:load(fr)
				f:i32load16u(dataframe.frame)
				f:i32(objframe.sizeof)
				f:add()
				f:sub()

				f:call(extendvec)
				f:tee(a)
				f:i32load(buf.ptr)
				f:load(b)
				f:add()

				stackbuf(f)
				f:tee(b)
				f:i32load(buf.ptr)
				f:load(base)
				f:add()
				f:call(loadframebase)
				f:i32load16u(dataframe.frame)
				f:add()
				f:i32(dataframe.sizeof)
				f:add()
				f:tee(d)

				f:load(b)
				f:i32load(buf.len)
				f:load(d)
				f:sub()
				f:call(memcpy4)

				-- oluastack = oluastack.caller
				f:loadg(oluastack)
				f:i32load(coro.caller)
				f:storeg(oluastack)

				f:call(loadframebase)
				f:tee(fr)
				f:i32load(dataframe.base)
				f:store(base)
			end, function()
				-- main returned, caller works things out
				f:i32(-1)
				f:ret()
			end)
		end)

		-- first result made true/false, false if none
		f:load(ty)
		f:i32(calltypes.bool)
		f:eq()
		f:iff(function()
			stackptr(f)
			f:tee(b)
			f:load(retb)
			f:add()

			f:load(base)
			f:load(fr)
			f:i32load16u(dataframe.frame)
			f:add()
			f:i32(objframe.sizeof)
			f:add()
			f:tee(a)
			stacklen(f)
			f:eq()
			f:iff(i32, function()
				f:i32(FALSE)
			end, function()
				f:i32(TRUE)
				f:i32(FALSE)
				f:load(a)
				f:load(b)
				f:add()
				f:i32load(vec.base)
				f:i32(TRUE)
				f:geu()
				f:select()
			end)
			f:i32store(vec.base)
			f:i32(4)
			f:store(c)
			f:br(copied)
		end)

		-- TODO stack pop needs to be different for coro
		f:load(base)
		f:load(fr)
		f:i32load16u(dataframe.frame)
		f:add()
		f:i32(objframe.sizeof)
		f:add()
		f:store(e)

		-- push frames keep every result, their retc is how many fixed values sit below the function
		f:load(key)
		f:i32(65535)
		f:eq()
		f:load(ty)
		f:i32(calltypes.push)
		f:eq()
		f:bor()
		f:iff(i32, function()
			stacklen(f)
			f:load(e)
			f:sub()
		end, function()
			f:load(key)
			f:i32(2)
			f:shl()
		end)
		f:tee(c)
		f:iff(function()
			-- too few results: nil fill
			f:loop(function(loop)
				f:load(e)
				f:load(c)
				f:add()
				stacklen(f)
				f:gtu()
				f:iff(function()
					f:i32(NIL)
					f:call(tmppush)
					f:br(loop)
				end)
			end)

			stackptr(f)
			f:i32(vec.base)
			f:add()
			f:tee(a)
			f:load(retb)
			f:add()
			f:load(a)
			f:load(e)
			f:add()
			f:load(c)
			f:call(memcpy4)
		end)
	end)

	-- pop stack frame
	stackbuf(f)
	f:load(retb)
	f:load(c)
	f:add()
	f:i32store(buf.len)

	f:loadg(oluastack)
	f:i32load(coro.data)
	f:tee(a)
	f:load(a)
	f:i32load(buf.len)
	f:i32(dataframe.sizeof)
	f:sub()
	f:i32store(buf.len)

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
		f:i32(2)
		f:shru()
		f:add()
		f:call(appendn)
	end)

	f:call(loadframebase)
	f:i32load(dataframe.pc)
end)

return {
	dataframe = dataframe,
	objframe = objframe,
	calltypes = calltypes,
	getmeta = getmeta,
	metaget = metaget,
	binmeta = binmeta,
	idxself = idxself,
	idxwalk = idxwalk,
	strconcat = strconcat,
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
