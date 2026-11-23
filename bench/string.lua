-- concat, string library calls
local parts = {}
for i = 1, 100000 do
	parts[#parts+1] = tostring(i) .. ','
end
local s = table.concat(parts)
local c = 0
for w in s:gmatch('%d+') do c = c + #w end
print(#s, c, s:sub(1, 20), s:upper():len())
