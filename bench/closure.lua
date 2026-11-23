-- closures, upvalues, method calls with a metatable
local Acc = {}
Acc.__index = Acc
function Acc.new() return setmetatable({ n = 0 }, Acc) end
function Acc:add(v) self.n = self.n + v end
local function counter()
	local c = 0
	return function() c = c + 1 return c end
end
local a, total = Acc.new(), 0
for i = 1, 300000 do
	local f = counter()
	f() f()
	a:add(f())
end
print(a.n)
