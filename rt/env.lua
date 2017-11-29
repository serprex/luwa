local addkv2otmp = func(i32, i32, void, function(f, k, v)
	f:loadg(otmp)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

mkenv = func(function(f)
	local a = f:locals(i32)

	local function addkv(k, v)
		f:i32(k)
		f:i32(v)
		f:call(addkv2otmp)
	end

	local function addmod(name, ...)
		if select('#', ...) == 0 then
			f:call(newtbl)
			f:store(a)
			f:loadg(otmp)
			f:i32(name)
			f:load(a)
		else
			f:call(newtbl)
			f:storeg(otmp)
			for i=1,select('#', ...),2 do
				addkv(select(i, ...))
			end
			f:call(param0)
			f:i32load(vec.base)
			f:i32(name)
			f:loadg(otmp)
		end
		f:call(tblset)
	end

	f:i32(GF.prelude0)
	f:call(init)

	f:call(newtbl)
	f:storeg(otmp)

	f:call(param0)
	f:loadg(otmp)
	f:i32store(vec.base)

	addkv(GS.select, GF.select)
	addkv(GS.pcall, GF.pcall)
	addkv(GS.error, GF.error)

	addmod(GS.coroutine,
		GS.create, GF.coro_create,
		GS.resume, GF.coro_resume,
		GS.yield, GF.coro_yield,
		GS.running, GF.coro_running,
		GS.status, GF.coro_status)
	addmod(GS.debug,
		GS.setmetatable, GF.debug_getmetatable)
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
		f:brif(loop)
	end)
end)