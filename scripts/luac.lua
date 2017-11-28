#!/usr/bin/env lua
package.path = 'luart/?.lua;' .. package.path
local astgen = require 'astgen'
local bcgen = require 'bcgen'

local function pprintcore(x, dep, hist)
   local a = string.rep(' ', dep)
   if hist[x] then
      return print(a .. '...', x)
   end
   hist[x] = true
   if type(x.val) == 'function' then
      print(a .. 'val:', x:val())
   end
   for k,v in pairs(x) do
      if k ~= 'mother' and k ~= 'father' then
         if type(v) == 'table' then
            print(a .. tostring(k), v)
            pprintcore(v, dep+1, hist)
         elseif k == 'lex' and type(v) == 'string' then
            print(a .. k, table.concat(table.pack(string.byte(v, 1, #v)), ','))
         else
            print(a .. tostring(k),v)
         end
      end
   end
end
local function pprint(x)
   return pprintcore(x, 0, {})
end
local function sanitize_func(c)
   if c == "'" then
      return "\\'"
   end
   local b = string.byte(c)
   if b < 32 or b > 126 then
      return string.format('\\x%.2x', b)
   end
end
local function sanitize(s)
   return "'" .. s:gsub('.', sanitize_func) .. "'"
end

local result = {}
for i=2,select('#', ...) do
   local srcfile = select(i, ...)
   local data = io.popen("./scripts/luac-lex.js '" .. srcfile:gsub("'", "'\\''") .. "'"):read('*a')
   local lx, offs = string.unpack('<s4', data)
   local snrlen, offs = string.unpack('<i4', data, offs)
   local snr, ssr = {}, {}
   for i=1,snrlen do
      if string.byte(data, offs) == 0 then
         snr[#snr+1], offs = string.unpack('<i8', data, offs+1)
      else
         snr[#snr+1], offs = string.unpack('d', data, offs+1)
      end
   end
   local ssrlen, offs = string.unpack('<i4', data, offs)
   for i=1,ssrlen do
      ssr[#ssr+1], offs = string.unpack('<s4', data, offs)
   end
   local lx = { lex = lx, snr = snr, ssr = ssr }
   local root = astgen(lx)
   -- print('AST')
   -- pprint(root)
   local bcg = bcgen(lx, root)
   -- print('ASM')
   -- pprint(bcg)

   local funcnums = 0
   local prevsult = {
      integer = {},
      float = {},
      string = {},
   }
   local strconst = {}
   local funcnames = {}
   local funcprefix = string.gsub(srcfile, '^.*/(.*)%.lua$', '%1')
   local function func2lua(func, toplevel)
      local name = funcprefix .. funcnums
      funcnums = funcnums + 1
      local subfuncs = {}
      local consts = {}
      for i=1, #func.consts do
         local c = func.consts[i]
         local ct = math.type(c) or type(c)
         consts[#consts+1] = strconst[ct](c)
      end
      result[#result+1] = "{'" .. name .. "'," .. func.pcount .. "," .. tostring(func.isdotdotdot) .. "," .. sanitize(string.char(table.unpack(func.bc))) .. ",{" .. table.concat(consts, ',') .. "}," .. #func.locals .. "}"
      return name
   end
   function strconst.integer(c)
      if prevsult.integer[c] then
         return prevsult.integer[c]
      else
         local pack = sanitize(string.pack('<i8', c))
         result[#result+1] = "string.unpack('<i8'," .. pack .. ")"
         prevsult.integer[c] = 'function() return GN.integer[' .. pack .. '] end'
         return prevsult.integer[c]
      end
   end
   function strconst.float(c)
      if prevsult.float[c] then
         return prevsult.float[c]
      else
         local pack = sanitize(string.pack('<d', c))
         result[#result+1] = "string.unpack('<d'," .. pack .. ")"
         prevsult.float[c] = 'function() return GN.float[' .. pack .. '] end'
         return prevsult.float[c]
      end
   end
   function strconst.string(c)
      if prevsult.string[c] then
         return prevsult.string[c]
      else
         local pack = sanitize(c)
         result[#result+1] = pack
         prevsult.string[c] = 'function() return GS[' .. pack .. '] end'
         return prevsult.string[c]
      end
   end
   function strconst.table(c)
      return 'function() return GF.' .. func2lua(c) .. ' end'
   end
   func2lua(bcg)
end
local f = assert(io.open(..., 'w'))
f:write('return function() return ')
f:write(table.concat(result, ','))
f:write(' end')
f:close()
