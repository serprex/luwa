importmemory('', 'm', 1)
igcfix = importfunc('', 'gcfix')
igcmark = importfunc('', 'gcmark')
echo = importfunc('', 'echo', i32, i32)

echodrop = func(function(f)
	local x = f:params(i32)
	f:load(x)
	f:call(echo)
	f:drop()
end)

echodrop2 = func(i32, function(f)
	local x, y = f:params(i32, i32)
	f:load(x)
	f:load(y)
	f:call(echodrop)
	f:call(echo)
end)
