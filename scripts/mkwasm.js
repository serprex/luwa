#!/usr/bin/env node
"use strict";

if (process.argv.length<3) {
	process.stdout.write("mkwasm OUT [WASM]\n");
}

const fs = require("fs"), path = require("path");
const util = require("../util"), varint = util.varint, varuint = util.varuint;

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
	globals: [],
	imports: [],
	exports: [],
	funcs: [],
	memory: null,
	start: null,
	names: new Map(),
	tymap: new Map(),
}, 3);

function gettype(mod, tysig) {
	let sig = tysig.join();
	let t = mod.tymap.get(sig);
	if (t === undefined) {
		mod.tymap.set(sig, t = mod.types.length);
		mod.types.push(tysig.map(x => tymap[x]));
	}
	return t;
}

function mod_wasm(mod, data) {
	const lines = data.split('\n');
	for (let i=0; i<lines.length; i++) {
		let line = lines[i];
		if (/^use /.test(line)) continue;
		else if (/^\/\*/.test(line)) {
			while (!line[++i].test(/\*\/$/));
		}
		else if (/^func /.test(line)) {
			let name = line.slice(5);
			let tysig = line[i+1].split(/\s+/), line2 = line[i+2];
			let fu = {
				sig: null,
				name: name,
				locals: [],
				code: [],
			};
			let locals = new Map();
			for (let j=0; j<tysig.length - 1; j += 2) {
				locals.set(tysig[j], fu.locals.length);
				fu.locals.push(tysig[j+1]);
			}
			let sig = fu.locals.slice();
			sig.push(tysig[tysig.length - 1]);
			fu.sig = gettype(mod, sig);
			if (/^\s/.test(line2)) {
				i += 2;
			} else {
				let losig = line2.split(/\s+/);
				for (let j=0; j; j+=2) {
					locals.set(tysig[j], fu.locals.length);
					fu.locals.push(tysig[j+1]);
				}
				i += 3;
			}
			while (/^\s+/.test(line[i])) {
				let ln = line[i].trim().split(/\s+/);
				fu.code.push(opmap[ln[0]] || (ln[0]|0));
				// TODO implicit params
				for (let j=1; j<ln.length; j++) {
					let lv = locals.get(ln[j]);
					fu.code.push(lv === undefined ? ln[j] : lv);
				}
				i++;
			}
			i--;
			mod.funcs.push(fu);
		}
		else if (/^export /.test(line)) {
			mod.exports.push(line.slice(7));
		}
		else if (/^import /.test(line)) {
			mod.imports.push(line.split(/\s+/));
		}
		else if (/^global /.test(line)) {
			let [_global, mut, ty, name, val] = line.split(/\s+/);
			if (!val) {
				val = "0";
			}
			if (!name) {
				name = ty;
				ty = mut;
				mut = "mut";
			}
			val = +val;
			mut = mut == "mut";
			mod.names.set(name, mod.globals.length);
			mod.globals.push([mut, ty]);
		} else if (/^const /.test(line)) {
			let [_const, name, val] = line.split(/\s+/);
			mod.names.set(name, val);
		} else if (/^start /.test(line)) {
			if (mod.start) console.log("Duplicate start", mod.start, line);
			mod.start = line.slice(6);
		} else {
			console.log("??", line);
		}
	}
}

function mod_comp(mod) {
	const fsig = [];
	for (let i=0; i<mod.imports.length; i++) {
		let [_import, kind, name, ...data] = mod.imports[i];
		let [module, field] = name.split('.');
		// map name
		// map field?
		// optional 'as X'?
		// need to parse remaining..
		switch (kind.slice(0, 3)) {
			case "fun":
				mod.names.set(name, fsig.length);
				fsig.push(gettype(data.split(/\s+/)));
				break;
			case "tab":
				break;
			case "mem":
				break;
			case "glo":
				break;
		}
	}
	for (let i=0; i<mod.funcs.length; i++) {
		let fu = mod.funcs[i];
		mod.names.set(fu.name, fsig.length);
		fsig.push(fu.sig);
	}
	for (let i=0; i<mod.funcs.length; i++) {
		let fu = mod.funcs[i];
		for (let j=0; j<fu.code.length; j++) {
			let c = fu.code[j];
			if (typeof c === "string") {
				let nc = mod.names.get(c);
				fu.code[j] = nc === undefined ? +c : nc;
			}
		}
	}

	const bc = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
	if (mod.types.length) {
		bc.push(1);
		const bcty = [];
		varuint(bcty, mod.types.length);
		for (let i=0; i<mod.types.length; i++) {
			bcty.push(0x60);
			let ty = mod.types[i];
			if (ty.length == 0) {
				bcty.push(0, 0);
				continue;
			}
			let hasret = ty[ty.length-1] != 0x40;
			let pcount = hasret ? ty.length - 1 : ty.length;
			varuint(bcty, pcount);
			for (let j=0; j<ty.length; j++) {
				bcty.push(ty[j]);
			}
			if (hasret) {
				bcty.push(1, ty[ty.length - 1]);
			} else {
				bcty.push(0);
			}
		}
		varuint(bc, bcty.length);
		bc.push(...bcty);
	}
	if (mod.funcs.length) {
		bc.push(10);
		const bcco = [];
		varuint(bcco, mod.funcs.length);
		for (let i=0; i<mod.funcs.length; i++) {
			let fu = mod.funcs[i];
			let cofu = [];
			varuint(cofu, fu.locals.length);
			// TODO RLE
			for (let j=0; j<fu.locals.length; j++) {
				varuint(cofu, 1);
				cofu.push(fu.locals[j]);
			}
			varuint(bcco, cofu.length);
			bcco.push(...cofu);
		}
		varuint(bc, bcco.length);
		bc.push(...bcco);
	}
	return Buffer.from(body);
}

const tymap = {
	i32: 0x7f,
	i64: 0x7e,
	f32: 0x7d,
	f64: 0x7c,
	anyfunc: 0x70,
	func: 0x60,
	void: 0x40,
};
const opmap = {
	unreachable: 0x00,
	nop: 0x01,
	block: 0x02,
	loop: 0x03,
	if: 0x04,
	else: 0x05,
	end: 0x0b,
	br: 0x0c,
	br_if: 0x0d,
	brif: 0x0d,
	br_table: 0x0e,
	return: 0x0f,
	ret: 0x0f,
	call: 0x10,
	call_indirect: 0x11,
	calli: 0x11,
	drop: 0x1a,
	select: 0x1b,
	get_local: 0x20,
	loadl: 0x20,
	set_local: 0x21,
	storel: 0x21,
	tee_local: 0x22,
	tee: 0x22,
	get_global: 0x23,
	loadg: 0x23,
	set_global: 0x24,
	storeg: 0x24,
	"i32.load": 0x28,
	read32: 0x28,
	"i64.load": 0x29,
	read64: 0x29,
	"f32.load": 0x2a,
	"f64.load": 0x2b,
	"i32.load8_s": 0x2c,
	"i32.load8_u": 0x2d,
	"i32.load16_s": 0x2e,
	"i32.load16_u": 0x2f,
	"i64.load8_s": 0x30,
	"i64.load8_u": 0x31,
	"i64.load16_s": 0x32,
	"i64.load16_u": 0x33,
	"i64.load32_s": 0x34,
	"i64.load32_u": 0x35,
	"i32.store": 0x36,
	"i64.store": 0x37,
	"f32.store": 0x38,
	"f64.store": 0x39,
	"i32.store8": 0x3a,
	"i32.store16": 0x3b,
	"i64.store8": 0x3c,
	"i64.store16": 0x3d,
	"i64.store32": 0x3e,
	"current_memory": 0x3f,
	"grow_memory": 0x40,
	"i32.const": 0x41,
	i32: 0x41,
	"i64.const": 0x42,
	i64: 0x42
	"f32.const": 0x43,
	f32: 0x43,
	"f64.const": 0x44,
	f64: 0x44,
	"i32.eqz": 0x45,
	"i32.eq": 0x46,
	"i32.ne": 0x47,
	"i32.lt_s": 0x48,
	"i32.lt_u": 0x49,
	"i32.gt_s": 0x4a,
	"i32.gt_u": 0x4b,
	"i32.le_s": 0x4c,
	"i32.le_u": 0x4d,
	"i32.ge_s": 0x4e,
	"i32.ge_u": 0x4f,
	"i64.eqz": 0x50,
	"i64.eq": 0x51,
	"i64.ne": 0x52,
	"i64.lt_s": 0x53,
	"i64.lt_u": 0x54,
	"i64.gt_s": 0x55,
	"i64.gt_u": 0x56,
	"i64.le_s": 0x57,
	"i64.le_u": 0x58,
	"i64.ge_s": 0x59,
	"i64.ge_u": 0x5a,
	"f32.eq": 0x5b,
	"f32.ne": 0x5c,
	"f32.lt": 0x5d,
	"f32.gt": 0x5e,
	"f32.le": 0x5f,
	"f32.ge": 0x60,
	"f64.eq": 0x61,
	"f64.ne": 0x62,
	"f64.lt": 0x63,
	"f64.gt": 0x64,
	"f64.le": 0x65,
	"f64.ge": 0x66,
	"i32.clz": 0x67,
	"i32.ctz": 0x68,
	"i32.popcnt": 0x69,
	"i32.add": 0x6a,
	"i32.sub": 0x6b,
	"i32.mul": 0x6c,
	"i32.div_s": 0x6d,
	"i32.div_u": 0x6e,
	"i32.rem_s": 0x6f,
	"i32.rem_u": 0x70,
	"i32.and": 0x71,
	"i32.or": 0x72,
	"i32.xor": 0x73,
	"i32.shl": 0x74,
	"i32.shr_s": 0x75,
	"i32.shr_u": 0x76,
	"i32.rotl": 0x77,
	"i32.rotr": 0x78,
	"i64.clz": 0x79,
	"i64.ctz": 0x7a,
	"i64.popcnt": 0x7b,
	"i64.add": 0x7c,
	"i64.sub": 0x7d,
	"i64.mul": 0x7e,
	"i64.div_s": 0x7f,
	"i64.div_u": 0x80,
	"i64.rem_s": 0x81,
	"i64.rem_u": 0x82,
	"i64.and": 0x83,
	"i64.or": 0x84,
	"i64.xor": 0x85,
	"i64.shl": 0x86,
	"i64.shr_s": 0x87,
	"i64.shr_u": 0x88,
	"i64.rotl": 0x89,
	"i64.rotr": 0x8a,
	"f32.abs": 0x8b,
	"f32.neg": 0x8c,
	"f32.ceil": 0x8d,
	"f32.floor": 0x8e,
	"f32.trunc": 0x8f,
	"f32.nearest": 0x90,
	"f32.sqrt": 0x91,
	"f32.add": 0x92,
	"f32.sub": 0x93,
	"f32.mul": 0x94,
	"f32.div": 0x95,
	"f32.min": 0x96,
	"f32.max": 0x97,
	"f32.copysign": 0x98,
	"f64.abs": 0x99,
	"f64.neg": 0x9a,
	"f64.ceil": 0x9b,
	"f64.floor": 0x9c,
	"f64.trunc": 0x9d,
	"f64.nearest": 0x9e,
	"f64.sqrt": 0x9f,
	"f64.add": 0xa0,
	"f64.sub": 0xa1,
	"f64.mul": 0xa2,
	"f64.div": 0xa3,
	"f64.min": 0xa4,
	"f64.max": 0xa5,
	"f64.copysign": 0xa6,
	"i32.wrap/i64": 0xa7,
	"i32.trunc_s/f32": 0xa8,
	"i32.trunc_u/f32": 0xa9,
	"i32.trunc_s/f64": 0xaa,
	"i32.trunc_u/f64": 0xab,
	"i64.extend_s/i32": 0xac,
	"i64.extend_u/i32": 0xad,
	"i64.trunc_s/f32": 0xae,
	"i64.trunc_u/f32": 0xaf,
	"i64.trunc_s/f64": 0xb0,
	"i64.trunc_u/f64": 0xb1,
	"f32.convert_s/i32": 0xb2,
	"f32.convert_u/i32": 0xb3,
	"f32.convert_s/i64": 0xb4,
	"f32.convert_s/i64": 0xb5,
	"f32.demote/f64": 0xb6,
	"f64.convert_s/i32": 0xb7,
	"f64.convert_u/i32": 0xb8,
	"f64.convert_s/i64": 0xb9,
	"f64.convert_s/i64": 0xba,
	"f64.promote/f32": 0xbb,
	"i32.reinterpret/f32": 0xbc,
	"i64.reinterpret/f64": 0xbd,
	"f32.reinterpret/i32": 0xbe,
	"f64.reinterpret/i64": 0xbf,
};