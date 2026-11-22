local M = require 'make'
local func = M.func

local alloc = require 'alloc'
local tbl, vec, num = alloc.tbl, alloc.vec, alloc.num
local newvec, newi64 = alloc.newvec, alloc.newi64

local _obj = require 'obj'
local hash = _obj.hash

tblset = func(i32, i32, i32, void, function(f, tab, key, val)
	local kv, mx = f:locals(i32, 2)

	-- H <- (hash(key) % tab.hash.len) & -8
	f:load(key)
	f:call(hash)
	f:load(tab)
	f:i32load(tbl.hash)
	f:tee(mx)
	f:i32load(vec.len)
	f:tee(kv)
	f:remu()
	f:i32(-8)
	f:band()

	-- kv <- tab.hash + H
	f:load(mx)

	-- inject mx <- tab.hash + tab.hash.len
	f:load(mx)
	f:load(kv)
	f:add()
	f:store(mx)

	f:add()
	f:store(kv)

	f:loop(function(loop)
		-- if kv.key == nil, set
		f:load(kv)
		f:i32load(vec.base)
		f:eqz()
		f:iff(function()
			f:load(kv)
			f:load(key)
			f:i32store(vec.base)
			f:load(kv)
			f:load(val)
			f:i32store(vec.base + 4)

			-- hlen += 8, mx <- hlen
			f:load(tab)
			f:load(tab)
			f:i32load(tbl.hlen)
			f:i32(8)
			f:add()
			f:tee(mx)
			f:i32store(tbl.hlen)

			-- kv <- hcap. if mx+mx > hcap, rehash
			f:load(mx)
			f:load(mx)
			f:add()
			f:load(tab)
			f:i32load(tbl.hash)
			f:i32load(vec.len)
			f:tee(kv)
			f:gtu()
			f:iff(function(rehash)
				f:load(tab)
				f:storeg(otmp)

				-- tab.hash = newvec, tab.hlen = 0
				f:load(kv)
				f:load(kv)
				f:add()
				f:call(newvec)
				f:store(key)

				-- val <- tab.hash, mx <- tab.hash + tab.hash.len
				-- have to do between call to newvec and updating tab.hash
				f:loadg(otmp)
				f:tee(tab)
				f:i32load(tbl.hash)
				f:tee(val)
				f:load(val)
				f:i32load(vec.len)
				f:add()
				f:store(mx)

				f:load(tab)
				f:load(key)
				f:i32store(tbl.hash)

				f:load(tab)
				f:i32(0)
				f:i32store(tbl.hlen)

				-- rehash. val is oldhash. mx is oldhash+oldhash.len
				f:loop(function(loop)
					-- if val.key != nil && val.val != nil
					-- then tblset(tab, val.key, val.val)
					f:load(val)
					f:i32load(vec.base)
					f:eqz()
					f:load(val)
					f:i32load(vec.base + 4)
					f:eqz()
					f:bor()
					f:eqz()
					f:iff(function()
						f:load(tab)
						f:load(val)
						f:i32load(vec.base)
						f:load(val)
						f:i32load(vec.base + 4)
						-- this tblset will not alloc
						f:call(tblset)
					end)

					f:load(val)
					f:i32(8)
					f:add()
					f:tee(val)
					f:load(mx)
					f:eq()
					f:brtable(loop, rehash)
				end)
			end)
			f:ret()
		end, function()
			-- if kv.key = key, set
			f:load(kv)
			f:i32load(vec.base)
			f:load(key)
			f:call(_obj.eq)
			f:iff(function()
				f:load(kv)
				f:load(val)
				f:i32store(vec.base + 4)
				f:ret()
			end)

			-- kv += 8, if kv == mx, kv = tab.hash
			f:load(kv)
			f:i32(8)
			f:add()
			f:tee(kv)
			f:load(mx)
			f:ne()
			f:brif(loop)
			f:load(tab)
			f:i32load(tbl.hash)
			f:store(kv)
		end)
		f:br(loop)
	end)
end)

tblget = func(i32, i32, i32, function(f, tab, key)
	local kv, mx = f:locals(i32, 2)
	
	-- H <- (hash(key) % tab.hash.len) & -8
	f:load(key)
	f:call(hash)
	f:load(tab)
	f:i32load(tbl.hash)
	f:tee(mx)
	f:i32load(vec.len)
	f:tee(kv)
	f:remu()
	f:i32(-8)
	f:band()

	-- kv <- tab.hash + H
	f:load(mx)

	-- inject mx <- tab.hash + tab.hash.len
	f:load(mx)
	f:load(kv)
	f:add()
	f:store(mx)

	f:add()
	f:store(kv)

	f:loop(i32, function(loop)
		-- if kv.key == nil, ret nil
		f:i32(NIL)
		f:load(kv)
		f:i32load(vec.base)
		f:eqz()
		f:brif(f)
		f:drop()

		-- if kv.key == key, ret val
		f:load(kv)
		f:i32load(vec.base)
		f:load(key)
		f:call(_obj.eq)
		f:iff(function()
			f:load(kv)
			f:i32load(vec.base + 4)
			f:ret()
		end)

		-- kv += 8, if kv == mx, kv = tab.hash
		f:load(kv)
		f:i32(8)
		f:add()
		f:tee(kv)
		f:load(mx)
		f:ne()
		f:brif(loop)
		f:load(tab)
		f:i32load(tbl.hash)
		f:store(kv)

		f:br(loop)
	end)
end)

-- Length of a table's sequence: a border n where t[n] ~= nil and t[n+1] == nil (or n == 0).
-- Tables are hash only for now, so probe integer keys, starting from the last length found.
-- One int object is allocated and reused as the probe key
local tbllen = func(i32, i32, function(f, tab)
	local n, key = f:locals(i32, 2)

	f:load(tab)
	f:storeg(otmp)
	f:i64(0)
	f:call(newi64)
	f:store(key)
	-- newi64 may move tab
	f:loadg(otmp)
	f:tee(tab)
	f:i32load(tbl.len)
	f:store(n)

	-- grow while t[n+1] ~= nil
	f:block(function(done)
		f:loop(function(loop)
			f:load(key)
			f:load(n)
			f:i32(1)
			f:add()
			f:i64extendu()
			f:i64store(num.val)
			f:load(tab)
			f:load(key)
			f:call(tblget)
			f:eqz()
			f:brif(done)
			f:load(n)
			f:i32(1)
			f:add()
			f:store(n)
			f:br(loop)
		end)
	end)

	-- shrink while t[n] == nil
	f:block(function(done)
		f:loop(function(loop)
			f:load(n)
			f:eqz()
			f:brif(done)
			f:load(key)
			f:load(n)
			f:i64extendu()
			f:i64store(num.val)
			f:load(tab)
			f:load(key)
			f:call(tblget)
			f:brif(done)
			f:load(n)
			f:i32(1)
			f:sub()
			f:store(n)
			f:br(loop)
		end)
	end)

	f:load(tab)
	f:load(n)
	f:i32store(tbl.len)
	f:load(n)
end)

return {
	tblget = tblget,
	tblset = tblset,
	tbllen = tbllen,
}
