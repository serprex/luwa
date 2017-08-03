--[[
VM needs to support both coroutines & yielding to JS thread at frequent intervals

stack frame layout:

objstack (none of these are allocated at call sites)
	0: intermediate stack (return values are intemediates)
	bytecode
	consts
	frees (free slots are vecs of length 1)
	locals... store local slots inline on stack frame
	datastack 17b blocks per call
		i8 call type
			0 norm Reload locals
			1 init Return stack
			2 prot Reload locals
			3 call Continue call chain
			4 push Append intermediates to table
		i32 pc
		i32 localc # of locals
		i32 retc # of values requested from call (-1 for chained calls)
		i32 base index of parameter 0 on intermediate stack

pcall sets up stack frame & returns control to calling VM loop. No nested VM loops
]]

eval = func(i32, i32, i32, function(f)
	local a, b, c, d, datastack, baseptr, valstack, valvec,
		callty, pc, localc, retc, base = f:locals(i32, 7+5)
	local offBc, offConst, offFree, offLocal = 0, 4, 8, 12

	local function loadframe()
		f:loadg(oluastack)
		f:i32load(buf.ptr)
		f:loadg(oluastack)
		f:i32load(buf.len)
		f:add()
		f:tee(a)
		loadvecminus(f, 4)
		f:tee(datastack)
		f:i32load(buf.ptr)
		f:load(datastack)
		f:i32load(buf.len)
		f:add()
		f:tee(c)
		loadstrminus(f, 4)
		f:store(base)

		f:load(c)
		loadstrminus(f, 8)
		f:store(retc)

		f:load(c)
		loadstrminus(f, 12)
		f:store(localc)

		f:load(c)
		loadstrminus(f, 16)
		f:store(pc)

		f:load(c)
		loadstrminus(f, 17, 'i32load8')
		f:store(callty)
	end
	local function readArg()
		-- 15b
		f:load(bc)
		f:load(pc)
		f:add()
		f:i32load(str.base)
		f:load(pc)
		f:i32(4)
		f:add()
		f:store(pc)
	end

	loadframe()

	f:block(function(nop)
		f:block(function(opstorelocal)
		f:block(function(oploadlocal)
		f:block(function(opconst)
		f:block(function(opcallret)
		f:block(function(opcall)
		f:block(function(opret)
		f:block(function(opmktab)
			f:block(function(opnot)
				f:block(function(opadd)
					f:block(function(oploadtrue)
						f:block(function(oploadfalse)
							f:block(function(oploadnil)
								-- switch(bc[pc++])
								f:loadg(oluastack)
								f:i32load(buf.ptr)
								f:tee(baseptr)
								f:load(baseptr)
								f:tee(valstack)
								f:i32load(vec.base)
								f:store(valvec)
								f:load(base)
								f:add()
								f:tee(baseptr)
								f:i32load(vec.base)
								f:tee(bc)
								f:load(pc)
								f:add()
								f:i32load8u(str.base)
								f:load(pc)
								f:i32(1)
								f:add()
								f:store(pc)
								f:brtable(nop, oploadnil, oploadfalse, oploadtrue, opadd, opnot, opmktab, opret, opcall, opcallret, opconst, oploadlocal, opstorelocal)
							end) -- LOAD_NIL
							f:load(valstack)
							f:i32(NIL)
							f:call(pushvec)
							f:drop()
							f:br(nop)
						end) -- LOAD_FALSE
						f:load(valstack)
						f:i32(FALSE)
						f:call(pushvec)
						f:drop()
						f:br(nop)
					end) -- LOAD_TRUE
					f:load(valstack)
					f:i32(TRUE)
					f:call(pushvec)
					f:drop()
					f:br(nop)
				end) -- BIN_ADD
				-- pop x, y
				-- metacheck
				-- typecheck
				f:br(nop)
			end) -- UNARY_NOT
			f:load(valvec)
			f:load(valstack)
			f:i32load(buf.len)
			f:add()
			f:tee(a)
			f:i32(TRUE)
			f:i32(FALSE)
			f:load(a)
			f:i32load(vec.base)
			f:i32(TRUE)
			f:geu()
			f:select()
			f:i32store(vec.base)
			f:br(nop)
		end) -- MAKE_TABLE
		f:call(newtable)
		f:store(a)
		f:loadg(oluastack)
		f:i32load(buf.ptr)
		f:load(a)
		f:call(pushvec)
		f:drop()
		f:br(nop)
	end) -- RETURN
	-- pop stack frame

		f:load(datastack)
		f:load(datastack)
		f:i32load(buf.len)
		f:i32(17)
		f:sub()
		f:i32store(buf.len)

		f:block(function(endprog)
			f:block(function(loadframe)
				-- read callty from freed memory
				f:load(callty)
				f:brtable(loadframe, endprog, loadframe)
			end) -- loadframe
			-- TODO -1 should always have a special case
			-- Address once I've worked out call chains
			f:load(retc)
			f:i32(-1)
			f:ne()
			f:load(valstack)
			f:i32load(buf.len)
			f:tee(b)
			f:load(retc)
			f:ne()
			f:band()
			-- check ne to avoid lt/gt checks most of the time
			f:iff(function()
				f:load(b)
				f:load(retc)
				f:gtu()
				f:iff(function()
					-- shrink stack
					f:loop(function(loop)
						f:load(valstack)
						f:call(popvec)
						f:load(b)
						f:i32(1)
						f:sub()
						f:tee(b)
						f:load(retc)
						f:gtu()
						f:brif(loop)
					end)
				end, function()
					-- pad stack with nils
					f:loop(function(loop)
						f:load(valstack)
						f:i32(NIL)
						f:call(pushvec)
						f:store(valstack)
						f:load(b)
						f:i32(1)
						f:add()
						f:tee(b)
						f:load(retc)
						f:ltu()
						f:brif(loop)
					end)
				end)
			end)
			-- LOADFRAME
			f:br(nop)
		end) -- endprog
		f:load(stack)
		f:ret()
	end) -- CALL
	-- push stack frame header
		f:br(nop)
	end) -- RETURN_CALL
	-- pop stack frame, then call
		f:br(nop)
	end) -- LOAD_CONST
		f:load(valstack)
		f:load(baseptr)
		f:i32load(vec.base + offConst)
		readArg()
		f:add()
		f:i32load(vec.base)
		f:call(pushvec)
		f:drop()
		f:br(nop)
	end) -- LOAD_LOCAL
		f:load(valstack)
		f:load(baseptr)
		readArg()
		f:i32load(vec.base + offLocal)
		f:call(pushvec)
		f:drop()
		f:br(nop)
	end) -- STORE_LOCAL
		f:load(baseptr)
		readArg()
		f:add()
		f:load(valstack)
		f:call(popvec)
		f:i32store(vec.base + offLocal)
		f:br(nop)
	end) -- NOP

	-- check whether to yield (for now we'll yield after each instruction)
	f:i32(0)
end)