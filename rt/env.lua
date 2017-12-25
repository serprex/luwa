local addkv2env = func(i32, i32, void, function(f, k, v)
	f:call(param0)
	f:i32load(vec.base)
	f:load(k)
	f:load(v)
	f:call(tblset)
end)

local addkv2luwa = func(i32, i32, void, function(f, k, v)
	f:call(param0)
	f:i32load(vec.base + 4)
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

	local function addfun(fn, ...)
		for i=1,select('#', ...),2 do
			local k, v = select(i, ...)
			f:i32(k)
			f:i32(v)
			f:call(fn)
		end
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

	f:call(newtbl)
	f:call(tmppush)

	f:i32(GF.prelude0)
	f:call(init)

	addfun(addkv2env,
		GS.select, GF.select,
		GS.pcall, GF.pcall,
		GS.error, GF.error,
		GS.type, GF.type)
	addfun(addkv2luwa,
		GS.lex, GF.lex,
		GS.astgen, GF.lastgen0,
		GS.bcgen, GF.lbcgen0,
		GS.fn_set_localc, GF.fn_set_localc,
		GS.fn_set_paramc, GF.fn_set_paramc,
		GS.fn_set_isdotdotdot, GF.fn_set_isdotdotdot,
		GS.fn_set_bc, GF.fn_set_bc,
		GS.fn_set_frees, GF.fn_set_frees,
		GS.fn_set_consts, GF.fn_set_consts,
		GS.vec_new, GF.vec_new)

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