eval = func(i32, function(f)
	local base = f:params(i32)
	-- stack frame consists of
	-- tmpstack: locals, frees, consts, bytecode, stack
	-- datastack: tmpframesz, ispcall?, pc

	f:block(function(nop)
		f:block(function(opmktab)
			f:block(function(opnot)
				f:block(function(opadd)
					f:block(function(oploadtrue)
						f:block(function(oploadfalse)
							f:block(function(oploadnil)
								-- switch(bc[pc++])
								f:load(bc)
								f:load(pc)
								f:add()
								f:i32load8u(str.base)
								f:load(pc)
								f:i32(4)
								f:add()
								f:store(pc)
								f:brtable(nop, oploadnil, oploadfalse, oploadtrue, opadd, opnot, opmktab)
							end) -- LOAD_NIL
							f:i32(NIL)
							f:call(tmppush)
							f:br(nop)
						end) -- LOAD_FALSE
						f:i32(FALSE)
						f:call(tmppush)
						f:br(nop)
					end) -- LOAD_TRUE
					f:i32(TRUE)
					f:call(tmppush)
					f:br(nop)
				end) -- BIN_ADD
				-- pop x, y
				-- metacheck
				-- typecheck
				f:br(nop)
			end) -- UNARY_NOT
			f:i32(TRUE)
			f:i32(FALSE)
			f:i32(1)
			f:call(nthtmp)
			f:i32(TRUE)
			f:geu()
			f:select()
			f:i32(1)
			f:call(setnthtmp)
			f:br(nop)
		end) -- MAKE_TABLE
		f:call(newtable)
		f:call(tmppush)
		f:br(nop)
	end) -- NOP

	-- check whether to yield (for now we'll yield after each instruction)
	f:load(base)
end)
