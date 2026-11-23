-- while loops, booleans in a table
local function sieve(n)
	local p, c = {}, 0
	for i = 2, n do p[i] = true end
	local i = 2
	while i * i <= n do
		if p[i] then
			local j = i * i
			while j <= n do p[j] = false j = j + i end
		end
		i = i + 1
	end
	for i = 2, n do if p[i] then c = c + 1 end end
	return c
end
local c = 0
for r = 1, 5 do c = c + sieve(200000) end
print(c)
