#!/usr/bin/env node
"use strict";
const fs = require('fs'),
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
			echo: x => x,
			echoptr: x => x,
			sin: Math.sin,
			cos: Math.cos,
			asin: Math.asin,
			acos: Math.acos,
			atan: Math.atan,
			atan2: Math.atan2,
			exp: Math.exp,
			log: Math.log,
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
	const tokens = mkref(mod.nthtmp(12));
	const snr = mkref(mod.nthtmp(4));
	const ssr = mkref(mod.nthtmp(8));
	mem8 = new Uint8Array(mem.buffer);
	const tokenlen = readint(mem8, tokens.val + 5);
	const tokenstart = tokens.val + 13;
	process.stdout.write(int2buf(tokenlen));
	process.stdout.write(Buffer.from(mem.buffer, tokenstart, tokenlen));
	const snrlen = readint(mem8, snr.val + 5)>>2;
	process.stdout.write(int2buf(snrlen))
	for (let i=0; i<snrlen; i++) {
		const nptr = readint(mem8, snr.val + 9 + i*4);
		process.stdout.write(Buffer.from(mem.buffer, nptr+5, 9));
	}
	const ssrlen = readint(mem8, ssr.val + 5)>>2;
	process.stdout.write(int2buf(ssrlen))
	for (let i=0; i<ssrlen; i++) {
		const sptr = readint(mem8, ssr.val + 9 + i*4);
		const slen = readint(mem8, sptr + 5);
		process.stdout.write(int2buf(slen));
		process.stdout.write(Buffer.from(mem.buffer, sptr+13, slen));
	}
})().catch(e => setImmediate(() => {
	throw e;
}));
