--[[
Header:
i32 ref
i8 type
]]

eq = func(i32, function(f)
	local a, b = f:params()
	local i, j = f:i32(), f:i32()
	f:load(a)
	f:i32load8u(4)
	f:load(b)
	f:i32load8u(4)
	f:ne()
	f:iff(function()
		f:i32(0)
		f:ret()
	end)
	f:block(function(bl5)
		f:block(function(bl4)
			f:block(function(bl3)
				f:block(function(bl2)
					f:block(function(b11)
						f:block(function(bl0)
							f:load(a)
							f:i32load8u(4)
							f:brtable(bl0, bl1, bl2, bl3, bl4, bl5)
						end) -- 0
						f:load(a)
						f:i64load(5)
						f:load(b)
						f:i64load(6)
						f:eq()
						f:ret()
					end) -- 1
					f:load(a)
					f:f64load(5)
					f:load(b)
					f:f64load(5)
					f:eq()
					f:ret()
				end) -- 2
				f:i32(1)
				f:ret()
			end) -- 3
			f:load(a)
			f:load(b)
			f:eq()
			f:ret()
		end) -- 4
		f:load(a)
		f:load(b)
		f:eq()
		f:ret()
	end) -- 5

	f:i32(1)
	f:load(a)
	f:load(b)
	f:eq()
	f:brif(f)
	f:drop()

	f:i32(0)
	f:load(a)
	f:i32load(5)
	f:tee(i)
	f:load(b)
	f:i32load(5)
	f:ne()
	f:brif(f)
	f:drop()

	f:i32(0)
	f:load(a)
	f:i32load16u(13)
	f:load(b)
	f:i32load16u(13)
	f:ne()
	f:brif(0)
	f:drop()

	f:i32(0)
	f:load(a)
	f:i32load8u(15)
	f:load(b)
	f:i32load8u(15)
	f:ne()
	f:brif(0)
	f:drop()

	f:i32(3)
	f:store(j)

	f:loop(i32, function(f)
		f:i32(1)
		f:load(i)
		f:load(j)
		f:leu()
		f:brif(f)
		f:drop()

		f:i32(0)
		f:load(a)
		f:load(j)
		f:add()
		f:i64load(13)
		f:load(b)
		f:load(j)
		f:add()
		f:i64load(13)
		f:ne()
		f:brif(f)
		f:drop()

		f:load(j)
		f:i32(8)
		f:add()
		f:store(j)
		f:br(loop)
	end)
end)

hash = func(i32, function(f)
	local o = f:params(i32)
	local n, m = f:i32(), f:i32()
	local h = f:i32()
	f:block(function(bl3)
	f:block(function(bl2)
	f:block(function(bl1)
	f:block(function(bl0)
	f:load(o)
	f:i32load8u(4)
	f:br_table(bl0,bl1,bl2,bl2,bl2,bl3,bl2)
	end) -- 0 i64
	f:load(o)
	f:i32load(5)
	f:load(o)
	f:i32load(9)
	f:xor()
	f:ret()
	end) -- 1 f64 TODO H(1.0) == H(1)
	f:load(o)
	f:i32load(5)
	f:load(o)
	f:i32load(9)
	f:xor()
	f:ret()
	end) -- 2 nil, bool, table
	f:load(o)
	f:ret()
	end) -- 3 string
	f:load(o)
	f:i32load(9)
	f:eqz()
	f:iff(function(blif)
		-- h = s.len^(s.len>>24|s0<<40|s1<<48|s2<<56), n=s+3, m=s+s.len
		f:load(o)
		f:load(o)
		f:i32load(5)
		f:add()
		f:store(m)

		f:load(o)
		f:i64load(5)
		f:load(o)
		f:i64load(8)
		f:xor()
		f:store(h)

		f:load(o)
		f:i32(3)
		f:add()
		f:store(n)

		f:loop(function(loop)
			f:load(n)
			f:load(m)
			f:ltu()
			f:iff(function(blif)
				-- h = (^ (+ (rol h 15) h) *n)
				f:load(h)
				f:i64(15)
				f:rotl()
				f:load(h)
				f:add()
				f:load(n)
				f:i64load(13)
				f:xor()
				f:store(h)

				f:load(n)
				f:i32(8)
				f:add()
				f:store(n)
				f:br(loop)
			end)
		end)

		f:load(o)
		f:load(h)
		f:i64(32)
		f:shru()
		f:load(h)
		f:xor()
		f:i32wrap()
		f:tee(n)
		f:i32(113)
		f:load(n)
		f:select()
		f:i32store(9)
	end)
	f:load(o)
	f:i32load(9)
end)

sizeof = func(i32, function(f)
	local o = f:params(o)
	f:block(function(bl6)
	f:block(function(bl5)
	f:block(function(bl4)
	f:block(function(bl3)
	f:block(function(bl2)
	f:block(function(bl1)
	f:block(function(bl0)
	f:load(o)
	f:i32load8u(4)
	f:brtable(bl0, bl1, bl2, bl3, bl4, bl5, bl6)
	end) -- 0 i64
	f:i32(16)
	f:ret()
	end) -- 1 f64
	f:i32(16)
	f:ret()
	end) -- 2 nil
	f:i32(8)
	f:ret()
	end) -- 3 bool
	f:i32(8)
	f:ret()
	end) -- 4 table
	f:i32(32)
	f:ret()
	end) -- 5 str
	f:load(o)
	f:i32load(5)
	f:i32(13)
	f:add()
	f:call(allocsize)
	f:ret()
	end) -- 6 vec
	f:load(o)
	f:i32load(5)
	f:i32(9)
	f:add()
	f:call(allocsize)
end)
