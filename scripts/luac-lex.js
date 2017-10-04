#!/usr/bin/env node
const fs = require('fs'),
	rt = require('../rt'),
	lex = require('../lex'),
	util = require('../util');

function int2buf(x) {
	return ta2buf(new Uint32Array([x]));
}
function ta2buf(x) {
	return Buffer.from(x.buffer, x.byteOffset, x.byteLength);
}

fs.readFile(process.argv[2], function(err, buf){
	if (err) throw err;
	rt().then(rt => {
		rt.initstack();
		const src = rt.newstr(buf.toString('utf8'));
		rt.mod.lex(src.val);
		const tokens = rt.rawobj2js(rt.mod.nthtmp(12));
		const snr = rt.rawobj2js(rt.mod.nthtmp(4));
		const ssr = rt.rawobj2js(rt.mod.nthtmp(8));
		process.stdout.write(int2buf(tokens.length));
		process.stdout.write(ta2buf(tokens));
		process.stdout.write(int2buf(snr.length))
		for (let n of snr) {
			if (typeof n === 'number') {
				process.stdout.write(Buffer.from([1]));
				process.stdout.write(ta2buf(new Float64Array([n])));
			} else {
				process.stdout.write(Buffer.from([0]));
				process.stdout.write(ta2buf(n));
			}
		}
		process.stdout.write(int2buf(ssr.length))
		for (let s of ssr) {
			process.stdout.write(int2buf(s.length));
			process.stdout.write(ta2buf(s));
		}
	});
});
