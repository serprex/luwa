types = {
	int = 0,
	float = 1,
	['nil'] = 2,
	nul = 2,
	bool = 3,
	tbl = 4,
	str = 5,
	vec = 6,
	buf = 7,
	functy = 8,
	coro = 9,
}
obj = {
	gc = 0,
	type = 4,
}
num = {
	val = 5,
}
int = num
float = num
bool = num
tbl = {
	id = 5,
	len = 9,
	hlen = 13,
	arr = 17, -- vec
	hash = 21, -- vec
	meta = 25, -- tbl
}
str = {
	len = 5,
	hash = 9,
	base = 13,
}
vec = {
	len = 5,
	base = 9,
}
buf = {
	len = 5,
	ptr = 9,
}
functy = {
	id = 5,
	isdotdotdot = 9,
	bc = 10,
	consts = 14,
	frees = 18,
	localc = 22,
	paramc = 26,
}
corostate = {
	dead = 0,
	norm = 1,
	live = 2,
	wait = 3,
}
coro = {
	id = 5,
	state = 9,
	caller = 10,
	stack = 14,
	data = 18,
}

allocsize = func(i32, i32, function(f, sz)
	f:i32(0)
	f:load(sz)
	f:sub()
	f:i32(7)
	f:band()
	f:load(sz)
	f:add()
end)

nextid = func(i32, function(f)
	f:loadg(idcount)
	f:loadg(idcount)
	f:i32(1)
	f:add()
	f:storeg(idcount)
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
	f:currentmemory()
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
		f:currentmemory()
		f:geu()
		f:iff(function()
			f:load(sz)
			f:currentmemory()
			f:sub()
			f:i32(1)
			f:add()
			f:growmemory()
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
	f:i32(types.int)
	f:call(newobj)
	f:tee(p)
	f:load(x)
	f:i64store(int.val)
	f:load(p)
end))

newf64 = export('newf64', func(f64, i32, function(f, x)
	local p = f:locals(i32)
	f:i32(16)
	f:i32(types.float)
	f:call(newobj)
	f:tee(p)
	f:load(x)
	f:f64store(int.val)
	f:load(p)
end))

newtbl = export('newtbl', func(i32, function(f)
	local p = f:locals(i32)
	f:i32(32)
	f:i32(types.tbl)
	f:call(newobj)
	f:storeg(otmp)

	f:loadg(otmp)
	f:call(nextid)
	f:i32store(tbl.id)

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
	local p = f:locals(i32)
	f:i32(13)
	f:load(sz)
	f:add()
	f:call(allocsize)
	f:i32(types.str)
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
	f:store(sz)

	f:switch(function()
		f:load(sz)
		f:i32(7)
		f:band()
	end, 8-str.base-7&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store(str.base)
		f:load(sz)
		f:i32(4)
		f:add()
		f:store(sz)
		f:br(scopes[8-str.base-3&7])
	end, 8-str.base-6&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store(str.base)
		f:load(sz)
		f:i32(0)
		f:i32store16(str.base + 4)
		f:br(scopes.sb7)
	end, 8-str.base-5&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store(str.base)
		f:load(sz)
		f:i32(0)
		f:i32store8(str.base + 4)
		f:br(scopes.sb7)
	end, 8-str.base-4&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store(str.base)
		f:br(scopes.sb7)
	end, 8-str.base-3&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store16(str.base)
		f:load(sz)
		f:i32(0)
		f:i32store8(str.base + 2)
		f:br(scopes.sb7)
	end, 8-str.base-2&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store16(str.base)
		f:br(scopes.sb7)
	end, 8-str.base-1&7, function(scopes)
		f:load(sz)
		f:i32(0)
		f:i32store8(str.base)
	end, 8-str.base&7, 'sb7')
	f:load(p)
end))

newvec = export('newvec', func(i32, i32, function(f, sz)
	local p, n = f:locals(i32, 2)
	f:i32(9)
	f:load(sz)
	f:add()
	f:call(allocsize)
	f:i32(types.vec)
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
	f:i32(16)
	f:i32(types.buf)
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

newfunc = export('newfunc', func(i32, function(f)
	local a = f:locals(i32)

	f:i32(32)
	f:i32(types.functy)
	f:call(newobj)
	f:tee(a)
	f:call(nextid)
	f:i32store(functy.id)

	assert(functy.consts == functy.bc + 4)
	f:load(a)
	f:i64(0)
	f:i64store(functy.bc)

	assert(functy.localc == functy.frees + 4)
	f:load(a)
	f:i64(0)
	f:i64store(functy.frees)

	f:load(a)
	f:i32(0)
	f:i32store(functy.paramc)

	f:load(a)
end))

newcoro = export('newcoro', func(i32, function(f)
	local a = f:locals(i32)

	f:i32(24)
	f:i32(types.coro)
	f:call(newobj)
	f:tee(a)
	f:call(nextid)
	f:i32store(coro.id)

	f:load(a)
	f:i32(corostate.wait)
	f:i32store8(coro.state)

	f:load(a)
	f:i32(NIL)
	f:i32store(coro.caller)

	assert(coro.data == coro.stack + 4)
	f:load(a)
	f:i64(0)
	f:i64store(coro.stack)

	f:load(a)
end))
