#!/usr/bin/env node
"use strict";
// Lexes a file with scripts/lex.wasm, writes the tokens & values for scripts/luac.lua:
// token string as <s4, value count as <i4, then each value as a type byte & its data
const fs = require('fs');

function int2buf(x) {
	return Buffer.from([x, x>>8, x>>16, x>>24]);
}
(async function() {
	const wasm = fs.readFileSync(__dirname + '/lex.wasm');
	const { instance } = await WebAssembly.instantiate(wasm);
	const mod = instance.exports;
	const bytes = s => {
		const n = mod.strlen(s), r = Buffer.alloc(n);
		for (let i = 0; i < n; i++) r[i] = mod.strget(s, i);
		return r;
	};

	const srcbuf = fs.readFileSync(process.argv[2]);
	const src = mod.newstr(srcbuf.length);
	for (let i = 0; i < srcbuf.length; i++) mod.strset(src, i, srcbuf[i]);
	const [tokens, values] = mod.lex(src);
	const out = [];
	const tok = bytes(tokens);
	out.push(int2buf(tok.length), tok);
	const n = mod.veclen(values);
	out.push(int2buf(n));
	for (let i = 0; i < n; i++) {
		const v = mod.vecget(values, i), ty = mod.typeof(v);
		out.push(Buffer.from([ty]));
		if (ty == 4) {
			const s = bytes(v);
			out.push(int2buf(s.length), s);
		} else {
			const b = Buffer.alloc(8);
			if (ty == 0) b.writeBigInt64LE(mod.intval(v));
			else b.writeDoubleLE(mod.fltval(v));
			out.push(b);
		}
	}
	process.stdout.write(Buffer.concat(out));
})().catch(e => setImmediate(() => {
	throw e;
}));
