--[[
struct Table {
	00 i32 ref
	04 i8 type
	05 i32 len
	09 i32 hlen
	13 vec arr
	17 vec hash
	21 tbl meta
}
]]

tabset = export('tabset', func(function(f)
	local tab, key, val = f:params(i32, i32, i32)
	local kv, mx = f:locals(i32, 2)
	f:load(tab)
	f:storeg(otmp)

	-- H <- (hash(key) % tab.hash.len) & -8
	f:load(key)
	f:call(hash)
	f:load(tab)
	f:i32load(17)
	f:tee(mx)
	f:i32load(5)
	f:remu()
	f:i32(-8)
	f:band()

	-- kv <- tab.hash + H
	f:load(mx)
	f:add()
	f:store(kv)

	-- mx <- tab.hash + tab.hash.len
	f:load(mx)
	f:load(mx)
	f:i32load(5)
	f:add()
	f:store(mx)

	f:loop(function(loop)
		-- if kv.key == nil, set
		f:load(kv)
		f:i32load(9)
		f:loadg(onil)
		f:eq()
		f:iff(function()
			f:load(kv)
			f:load(key)
			f:i32store(9)
			f:load(kv)
			f:load(val)
			f:i32store(13)

			-- hlen += 8, mx <- hlen
			f:load(tab)
			f:load(tab)
			f:i32load(9)
			f:i32(8)
			f:add()
			f:tee(mx)
			f:i32store(9)

			-- kv <- hcap. if mx+mx > hcap, rehash
			f:load(mx)
			f:load(mx)
			f:add()
			f:load(tab)
			f:i32load(17)
			f:i32load(5)
			f:tee(kv)
			f:gtu()
			f:iff(function(rehash)
				-- tab.hash = newvec, tab.hlen = 0
				f:load(kv)
				f:load(kv)
				f:add()
				f:call(newvec)
				f:store(key)

				-- val <- tab.hash, mx <- tab.hash + tab.hash.len
				-- have to do between call to newvec and updating tab.hash
				f:load(tab)
				f:i32load(17)
				f:tee(val)
				f:load(val)
				f:i32load(5)
				f:add()
				f:store(mx)

				f:loadg(otmp)
				f:tee(tab)
				f:load(key)
				f:i32store(17)

				f:load(tab)
				f:i32(0)
				f:i32store(9)

				-- rehash. val is oldhash. mx is oldhash+oldhash.len
				f:loop(function(loop)
					-- if val.key != nil && val.val != nil
					-- then tabset(tab, val.key, val.val)
					f:load(val)
					f:i32load(9)
					f:loadg(onil)
					f:ne()
					f:load(val)
					f:i32load(13)
					f:loadg(onil)
					f:ne()
					f:band()
					f:iff(function()
						f:load(tab)
						f:load(val)
						f:i32load(9)
						f:load(val)
						f:i32load(13)
						f:call(tabset)
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
			f:i32load(9)
			f:load(key)
			f:call(eq)
			f:iff(function()
				f:load(kv)
				f:load(val)
				f:i32store(13)
				f:ret()
			end)

			-- kv += 8, if kv == mx, kv = tab.hash
			f:load(kv)
			f:i32(8)
			f:add()
			f:tee(kv)
			f:load(mx)
			f:ne()
			f:brif(1)
			f:load(tab)
			f:i32load(17)
			f:store(kv)
		end)
		f:br(loop)
	end)
end))

tabget = export('tabget', func(i32, function(f)
	local tab, key = f:params(i32, i32)
	local kv, mx = f:locals(i32, 2)
	
	-- H <- (hash(key) % tab.hash.len) & -8
	f:load(key)
	f:call(hash)
	f:load(tab)
	f:i32load(17)
	f:tee(mx)
	f:i32load(5)
	f:remu()
	f:i32(-8)
	f:band()

	-- kv = tab.hash + H
	f:load(mx)
	f:add()
	f:store(kv)

	-- mx = tab.hash + tab.hash.len
	f:load(mx)
	f:load(mx)
	f:i32load(5)
	f:add()
	f:store(mx)

	f:loop(i32, function(loop)
		-- if kv.key == nil, ret nil
		f:load(kv)
		f:i32load(9)
		f:loadg(onil)
		f:eq()
		f:iff(function()
			f:loadg(onil)
			f:ret()
		end)

		-- if kv.key == key, ret val
		f:load(kv)
		f:i32load(9)
		f:load(key)
		f:call(eq)
		f:iff(function()
			f:load(kv)
			f:i32load(13)
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
		f:i32load(17)
		f:store(kv)

		f:br(loop)
	end)
end))
