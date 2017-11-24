#!/usr/bin/env lua
local data = io.read('*a')
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
package.path = 'luart/?.lua;' .. package.path
local astgen = require 'astgen'
local bcgen = require 'bcgen'
local lx = { lex = lx, snr = snr, ssr = ssr }
local root = astgen(lx)
local function pprintcore(x, dep, hist)
   local a = {}
   for i=1,dep do
      a[i] = ' '
   end
   local a = table.concat(a, ' ')
   --local a = tostring(dep)
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
         print(a .. tostring(k))
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
print('AST')
pprint(root)
local bcg = bcgen(lx, root)
print('ASM')
pprint(bcg)

