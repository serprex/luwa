-- lua scripts/assertline.lua N file.lua
--   runs file.lua under host Lua & prints where the N-th assert call is
-- lua scripts/assertline.lua parse file.lua
--   prints each line number L where lines 1 to L load as a whole chunk
-- suite.js uses these to place luwa failures, since luwa errors have no line numbers yet
if arg[1] == 'parse' then
	local lines = {}
	for l in io.lines(arg[2], 'L') do
		lines[#lines+1] = l
		if load(table.concat(lines), '=', 't') then
			io.write(#lines, '\n')
		end
	end
	return
end
_port = true
_soft = true
local want, n, real = tonumber(arg[1]), 0, assert
local getinfo, write, exit = debug.getinfo, io.write, os.exit
assert = function(...)
	n = n + 1
	if n == want then
		local info = getinfo(2, 'Sl')
		write('\n@@', info.short_src, ':', info.currentline, '\n')
		exit(0)
	end
	return real(...)
end
dofile(arg[2])
