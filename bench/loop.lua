-- numeric for, int & float math, locals
local s, x = 0, 0.0
for i = 1, 5000000 do
	s = s + i % 7 * 3 - (i // 5)
	x = x + i * 0.5
end
print(s, x)
