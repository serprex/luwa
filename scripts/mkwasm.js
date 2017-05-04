#!/usr/bin/env node
"use strict";

if (process.argv.length<3) {
	process.stdout.write("mkwasm OUT [WASM]\n");
}

const fs = require("fs"), path = require("path");

function processModule(mod, n) {
	if (n >= process.argv.length) {
		fs.writeFile(process.argv[2], mod_comp(mod), 'w', () => {});
		return;
	}
	const f = process.argv[n], ext = path.extname(f);
	const src = fs.createReadStream(process.argv[2]);
	let cb;
	if (ext == ".wasm") {
		cb = mod_wasm;
	} else {
		console.log("Unknown ext: " + ext);
		return;
	}
	fs.readFile(process.argv[2], "utf8", (err, data) => {
		cb(mod, data);
		return processModule(mod, n+1);
	});
}

processModule({
	types: [],
	imports: [],
	exports: [],
	funcs: [],
	codes: [],
}, 3);

function mod_wasm(mod, data) {
	const lines = data.split('\n');
	for (let i=0; i<lines.length; i++) {
		if (/^func /.test(lines[i]) {
			mod.funcs.push(lines[i].slice(5));
		}
		if (/^export /).test(lines[i]) {
			mod.exports.push(lines[i].slice(7));
		}
	}
}

function mod_comp(mod) {
}