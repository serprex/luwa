-- array & hash reads and writes
local t = {}
for i = 1, 200000 do t[i] = i * 2 end
local s = 0
for r = 1, 10 do
	for i = 1, #t do s = s + t[i] end
end
local h = {}
for i = 1, 100000 do h['k' .. (i % 1000)] = i end
local n = 0
for k, v in pairs(h) do n = n + v end
print(s, n)
