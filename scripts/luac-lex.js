#!/usr/bin/env node
"use strict";
const fs = require('fs'),
	util = require('../util'),
	{ promisify } = require('util'),
	readFile = promisify(fs.readFile);

function int2buf(x) {
	return Buffer.from([x, x>>8, x>>16, x>>24]);
}
function readint(mem, idx) {
	return mem[idx]|mem[idx+1]<<8|mem[idx+2]<<16|mem[idx+3]<<24;
}
(async function() {
	const rtsrc = await readFile(__dirname + '/lex.wasm');
	const mem = new WebAssembly.Memory({initial:1});
	const handles = new Set();
	function mkref(x) {
		const h = {val:x}
		handles.add(h);
		return h;
	}
	const module = await WebAssembly.instantiate(
		rtsrc.buffer.slice(rtsrc.byteOffset, rtsrc.byteOffset + rtsrc.byteLength),
		{'':{
			m: mem,
			echo: x => {console.error(x);return x},
			echoptr: x => x,
			sin: Math.sin,
			cos: Math.cos,
			asin: Math.asin,
			acos: Math.acos,
			atan: Math.atan,
			atan2: Math.atan2,
			exp: Math.exp,
			log: Math.log,
			pow: Math.pow,
			gcmark: x => {
				for (const h of handles) {
					mod.gcmark(h.val);
				}
			},
			gcfix: () => {
				const memta = new Uint8Array(mem.buffer);
				for (const h of handles) {
					h.val = util.readuint32(memta, h.val)&-8;
				}
			},
		}}
	);
	const mod = module.instance.exports;
	const luastack = mkref(mod.newcoro());
	mod.setluastack(luastack.val);
	const newvec = mkref(mod.newvecbuf(32));
	let mem8 = new Uint8Array(mem.buffer);
	mem8[luastack.val+14] = newvec.val;
	mem8[luastack.val+15] = newvec.val >> 8;
	mem8[luastack.val+16] = newvec.val >> 16;
	mem8[luastack.val+17] = newvec.val >> 24;

	const srcbuf = await readFile(process.argv[2]);
	const src = mkref(mod.newstr(srcbuf.length));
	mem8 = new Uint8Array(mem.buffer);
	srcbuf.copy(mem8, src.val+13);
	mod.lex(src.val);
	const tokens = mkref(mod.nthtmp(8));
	const values = mkref(mod.nthtmp(4));
	mem8 = new Uint8Array(mem.buffer);
	const tokenlen = readint(mem8, tokens.val + 5);
	const tokenstart = tokens.val + 13;
	process.stdout.write(int2buf(tokenlen));
	process.stdout.write(Buffer.from(mem.buffer, tokenstart, tokenlen));
	const valuelen = readint(mem8, values.val + 5)>>2;
	process.stdout.write(int2buf(valuelen));
	for (let i=0; i<valuelen; i++) {
		const ptr = readint(mem8, values.val + 9 + i*4);
		const ptrtype = Buffer.from(mem.buffer, ptr+4, 1);
		process.stdout.write(ptrtype);
		if (ptrtype[0] == 5) {
			const slen = readint(mem8, ptr + 5);
			process.stdout.write(int2buf(slen));
			process.stdout.write(Buffer.from(mem.buffer, ptr+13, slen));
		} else {
			process.stdout.write(Buffer.from(mem.buffer, ptr+5, 8));
		}
	}
})().catch(e => setImmediate(() => {
	throw e;
}));
