otypes = {
	int = 0,
	float = 1,
	['nil'] = 2,
	bool = 3,
	tbl = 4,
	str = 5,
	vec = 6,
	buf = 7,
	functy = 8,
	coroty = 9,
}
obj = {
	gc = 0,
	type = 4,
}
num = {
	gc = 0,
	type = 4,
	val = 5,
}
int = num
float = num
bool = num
tbl = {
	gc = 0,
	type = 4,
	-- TODO id = 5,
	len = 5,
	hlen = 9,
	arr = 13, -- vec
	hash = 17, -- vec
	meta = 21, -- tbl
}
str = {
	gc = 0,
	type = 4,
	len = 5,
	hash = 9,
	base = 13,
}
vec = {
	gc = 0,
	type = 4,
	len = 5,
	base = 9,
}
buf = {
	gc = 0,
	type = 4,
	len = 5,
	ptr = 9,
}
functy = {
	gc = 0,
	type = 4,
	id = 5,
	consts = 9,
	bc = 13,
	isdotdotdot = 17,
	freelist = 18,
}
coro = {
	gc = 0,
	type = 4,
	id = 5,
	state = 9,
	stack = 13,
}

allocsize = func(i32, i32, function(f, sz)
	f:load(sz)
	f:i32(7)
	f:band()
	f:iff(i32, function()
		f:load(sz)
		f:i32(-8)
		f:band()
		f:i32(8)
		f:add()
	end, function()
		f:load(sz)
	end)
end)

newobj = func(i32, i32, i32, function(f, sz, t)
	local p, ht = f:locals(i32, 2)
	f:loadg(heaptip)
	f:tee(p)
	f:load(sz)
	f:add()
	f:tee(ht)
	f:i32(16)
	f:shru()
	f:current_memory()
	f:geu()
	f:iff(function()
		f:call(gccollect)

		f:loadg(heaptip)
		f:tee(p)
		f:load(sz)
		f:add()
		f:storeg(heaptip)
		f:loadg(heaptip)
		f:i32(16)
		f:shru()
		f:tee(sz)
		f:current_memory()
		f:geu()
		f:iff(function()
			f:load(sz)
			f:current_memory()
			f:sub()
			f:i32(1)
			f:add()
			f:grow_memory()
			f:drop()
		end)
	end, function()
		f:load(ht)
		f:storeg(heaptip)
	end)
	-- store header to p
	f:load(p)
	f:loadg(markbit)
	f:i32store(obj.gc)
	f:load(p)
	f:load(t)
	f:i32store8(obj.type)
	f:load(p)
end)

newi64 = export('newi64', func(i64, i32, function(f, x)
	local p = f:locals(i32)
	f:i32(16)
	f:i32(otypes.int)
	f:call(newobj)
	f:tee(p)
	f:load(x)
	f:i64store(int.val)
	f:load(p)
end))

newf64 = export('newf64', func(f64, i32, function(f, x)
	local p = f:locals(i32)
	f:i32(16)
	f:i32(otypes.float)
	f:call(newobj)
	f:tee(p)
	f:load(x)
	f:f64store(int.val)
	f:load(p)
end))

newtable = export('newtable', func(i32, function(f)
	local p = f:locals(i32)
	f:i32(32)
	f:i32(otypes.tbl)
	f:call(newobj)
	f:storeg(otmp)

	assert(tbl.hlen == tbl.len + 4)
	f:loadg(otmp) -- len, hlen = 0
	f:i64(0)
	f:i64store(tbl.len)

	assert(tbl.hash == tbl.arr + 4)
	-- Need to set arr/hash before alloc in case of gc
	f:loadg(otmp) -- arr, hash = nil
	assert(NIL == 0)
	f:i64(0)
	f:i64store(tbl.arr)

	f:loadg(otmp) -- meta = nil
	f:i32(NIL)
	f:i32store(tbl.meta)

	f:loadg(otmp) -- arr = newvec(4*4)
	f:i32(16)
	f:call(newvec)
	f:i32store(tbl.arr)

	f:loadg(otmp) -- hash = newvec(4*8)
	f:i32(32)
	f:call(newvec)
	f:i32store(tbl.hash)

	f:loadg(otmp)
end))

newstr = export('newstr', func(i32, i32, function(f, sz)
	local p, psz = f:locals(i32, 2)
	f:i32(13)
	f:load(sz)
	f:add()
	f:call(allocsize)
	f:i32(otypes.str)
	f:call(newobj)
	f:tee(p)
	f:load(sz)
	f:i32store(str.len)
	f:load(p)
	f:i32(0)
	f:i32store(str.hash)

	f:load(p)
	f:load(sz)
	f:add()
	f:store(psz)

	f:block(function(bl7)
		f:block(function(bl6)
			f:block(function(bl5)
				f:block(function(bl4)
					f:block(function(bl3)
						f:block(function(bl2)
							f:block(function(bl1)
								f:block(function(bl0)
									f:load(sz)
									f:i32(7)
									f:band()
									f:brtable(bl4, bl5, bl6, bl7, bl0, bl1, bl2, bl3)
								end) -- 0
								f:load(psz)
								f:i32(0)
								f:i32store(str.base)
								f:load(psz)
								f:i32(0)
								f:i32store16(str.base + 4)
								f:load(psz)
								f:i32(0)
								f:i32store8(str.base + 2)
								f:br(bl7)
							end) -- 1
							f:load(psz)
							f:i32(0)
							f:i32store(str.base)
							f:load(psz)
							f:i32(0)
							f:i32store16(str.base + 4)
							f:br(bl7)
						end) -- 2
						f:load(psz)
						f:i32(0)
						f:i32store(str.base)
						f:load(psz)
						f:i32(0)
						f:i32store8(str.base + 4)
						f:br(bl7)
					end) -- 3
					f:load(psz)
					f:i32(0)
					f:i32store(str.base)
					f:br(bl7)
				end) -- 4
				f:load(psz)
				f:i32(0)
				f:i32store16(str.base)
				f:load(psz)
				f:i32(0)
				f:i32store8(str.base + 2)
				f:br(bl7)
			end) -- 5
			f:load(psz)
			f:i32(0)
			f:i32store16(str.base)
			f:br(bl7)
		end) -- 6
		f:load(psz)
		f:i32(0)
		f:i32store8(str.base)
	end) -- 7
	f:load(p)
end))

newvec = export('newvec', func(i32, i32, function(f, sz)
	local p, n = f:locals(i32, 2)
	f:i32(9)
	f:load(sz)
	f:add()
	f:call(allocsize)
	f:i32(otypes.vec)
	f:call(newobj)
	f:tee(p)
	f:load(sz)
	f:i32store(vec.len)

	-- need to start with (sz - n)%8 == 0
	f:load(sz)
	f:i32(4)
	f:band()
	f:iff(function()
		f:load(p)
		f:i32(NIL)
		f:i32store(vec.base)
		f:i32(4)
		f:store(n)
	end)

	f:loop(i32, function(loop) -- fill vec with references to nil
		f:load(p)
		f:load(n)
		f:load(sz)
		f:eq()
		f:brif(f)
		f:load(n)
		f:add()
		assert(NIL == 0)
		f:i64(0)
		f:i64store(vec.base)

		f:load(n)
		f:i32(8)
		f:add()
		f:store(n)
		f:br(loop)
	end)
end))

newbuf = func(i32, function(f)
	local p = f:locals(i32)
	f:i32(13)
	f:i32(otypes.buf)
	f:call(newobj)
	f:tee(p)
	f:loadg(otmp)
	f:i32store(buf.ptr)

	f:load(p)
	f:i32(0)
	f:i32store(buf.len)

	f:load(p)
end)

newstrbuf = export('newstrbuf', func(i32, i32, function(f, sz)
	f:load(sz)
	f:call(newstr)
	f:storeg(otmp)
	f:call(newbuf)
end))

newvecbuf = export('newvecbuf', func(i32, i32, function(f, sz)
	f:load(sz)
	f:call(newvec)
	f:storeg(otmp)
	f:call(newbuf)
end))
