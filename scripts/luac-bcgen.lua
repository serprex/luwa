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
local ast = require 'ast'
print(ast { lex = lx, snr = snr, ssr = ssr })

