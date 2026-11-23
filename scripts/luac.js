#!/usr/bin/env node
// Compiles Lua files with scripts/comp.wasm, for rt/bootrt.lua at build time. Writes a Lua chunk
// returning each file's main function as { p = params, v = isvararg, l = locals, b = bytecode, k = consts },
// consts as { kind, value }: 's' string, 'i' int & 'f' float as 8 packed bytes, 'F' a function
import fs from 'node:fs';

const x = (await WebAssembly.instantiate(fs.readFileSync(new URL('comp.wasm', import.meta.url)))).instance.exports;
const mkstr = b => {
	const s = x.newstr(b.length);
	for (let i = 0; i < b.length; i++) x.strset(s, i, b[i]);
	return s;
};
const bytes = s => {
	const n = x.strlen(s), r = Buffer.alloc(n);
	for (let i = 0; i < n; i++) r[i] = x.strget(s, i);
	return r;
};
const lstr = b => {
	let r = '"';
	for (const c of b) r += (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 32 ? String.fromCharCode(c) : '\\' + String(c).padStart(3, '0');
	return r + '"';
};
function fn2lua(fn) {
	const k = [];
	for (let i = 0; i < x.fnnconst(fn); i++) {
		const c = x.fnconst(fn, i), ty = x.typeof(c), b = Buffer.alloc(8);
		if (ty == 4) k.push(`{'s',${lstr(bytes(c))}}`);
		else if (ty == 0) { b.writeBigInt64LE(x.intval(c)); k.push(`{'i',${lstr(b)}}`); }
		else if (ty == 1) { b.writeDoubleLE(x.fltval(c)); k.push(`{'f',${lstr(b)}}`); }
		else if (ty == 7) k.push(`{'F',${fn2lua(c)}}`);
		else throw new Error('unknown const type ' + ty);
	}
	const bc = Buffer.alloc(x.fnbclen(fn));
	for (let i = 0; i < bc.length; i++) bc[i] = x.fnbcget(fn, i);
	return `{p=${x.fnparamc(fn)},v=${!!x.fnisvarg(fn)},l=${x.fnlocalc(fn)},b=${lstr(bc)},k={${k.join(',')}}}`;
}
const out = [];
for (const file of process.argv.slice(2)) {
	const src = fs.readFileSync(file);
	// the prelude is built without tail calls, debug info or the <close> & vararg table helpers
	const fn = x.compile(mkstr(src), null, null, 2, null, null, null);
	if (fn == null) {
		const a = x.errarg.value;
		console.error(`${file}:${x.errline.value}: compile error ${x.errcode.value}${a == null ? '' : ' ' + bytes(a)}`);
		process.exit(1);
	}
	out.push(fn2lua(fn));
}
process.stdout.write('return {' + out.join(',') + '}');
