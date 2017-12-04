local addkv2env = func(i32, i32, void, function(f, k, v)
	f:call(param0)
	f:i32load(vec.base)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

local addkv2top = func(i32, i32, void, function(f, k, v)
	f:i32(4)
	f:call(nthtmp)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

mkenv = func(function(f)
	local a = f:locals(i32)

	local function addfun(k, v)
		f:i32(k)
		f:i32(v)
		f:call(addkv2env)
	end

	local function addmod(name, ...)
		if select('#', ...) == 0 then
			f:i32(name)
			f:call(newtbl)
			f:call(addkv2env)
		else
			f:call(newtbl)
			f:call(tmppush)
			for i=1,select('#', ...),2 do
				local k, v = select(i, ...)
				f:i32(k)
				f:i32(v)
				f:call(addkv2top)
			end
			f:i32(name)
			f:i32(4)
			f:call(nthtmp)
			f:call(addkv2env)
			f:call(tmppop)
		end
	end

	f:call(newtbl)
	f:call(tmppush)

	f:i32(GF.prelude0)
	f:call(init)

	addfun(GS.select, GF.select)
	addfun(GS.pcall, GF.pcall)
	addfun(GS.error, GF.error)

	addmod(GS.coroutine,
		GS.create, GF.coro_create,
		GS.resume, GF.coro_resume,
		GS.yield, GF.coro_yield,
		GS.running, GF.coro_running,
		GS.status, GF.coro_status)
	addmod(GS.debug,
		GS.getmetatable, GF.debug_getmetatable,
		GS.setmetatable, GF.debug_setmetatable)
	addmod(GS.io)
	addmod(GS.math,
		GS.type, GF.math_type)
	addmod(GS.os)
	addmod(GS.package)
	addmod(GS.string)
	addmod(GS.table)
	addmod(GS.utf8)

	f:loop(function(loop)
		f:call(eval)
		f:eqz()
		f:brif(loop)
	end)
end)