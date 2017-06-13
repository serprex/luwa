#!/usr/bin/env node
"use strict";

if (process.argv.length<3) {
	process.stdout.write("mkwasm OUT [WASM]\n");
}

const fs = require("fs"), path = require("path");
const { varint, varuint, asUtf8 } = require("../util");

function processModule(mod, n) {
	if (n >= process.argv.length) {
		fs.writeFile(process.argv[2], mod_comp(mod), () => {});
		return;
	}
	const f = process.argv[n], ext = path.extname(f);
	const src = fs.createReadStream(f);
	let cb;
	if (ext == ".wawa") {
		cb = mod_wawa;
	} else {
		console.log("Unknown ext: " + ext);
		return;
	}
	fs.readFile(f, "utf8", (err, data) => {
		cb(mod, data);
		return processModule(mod, n+1);
	});
}

processModule({
	type: [],
	global: [],
	imports: [],
	exports: {
		func: [],
		table: [],
		memory: [],
		global: [],
	},
	table: [],
	func: [],
	memory: [],
	start: null,
	element: [],
	data: [],
	names: new Map(),
	tymap: new Map(),
}, 3);

function gettype(mod, tysig = []) {
	let sig = tysig.join() || "void";
	let t = mod.tymap.get(sig);
	if (t === undefined) {
		mod.tymap.set(sig, t = mod.type.length);
		mod.type.push(tysig.map(x => {
			let t = tymap[x];
			if (t === undefined) throw "Invalid type: " + x;
			return t;
		}));
	}
	return t;
}

function mod_wawa(mod, data) {
	const lines = data.split('\n').map(line => line.replace(/\s*;.*$|\s+$/, '')).filter(line => line);
	for (let i=0; i<lines.length; i++) {
		if (/^\s*\/\*/.test(lines[i])) {
			let j = 1;
			while (!/\*\/$/.test(lines[i+j++]));
			lines.splice(i--, j);
		}
	}
	for (let i=0; i<lines.length; i++) {
		let line = lines[i];
		let expo = /^export (start|func|memory|table|global) /.test(line);
		if (expo) line = line.slice(7);
		let startf = /^start func /.test(line);
		if (startf) line = line.slice(6);
		if (/^func /.test(line)) {
			let name = line.slice(5);
			let tysig = lines[i+1].split(/\s+/), line2 = lines[i+2];
			const fu = {
				sig: -1,
				name: name,
				pcount: -1,
				locals: [],
				code: [],
				localnames: new Map(),
				scopes: new Map(),
			};
			fu.scopes.set('@' + name, 0);
			if (startf) mod.start = fu;
			for (let j=0; j<tysig.length - 1; j += 2) {
				fu.localnames.set(tysig[j], fu.locals.length);
				fu.locals.push(tysig[j+1]);
			}
			fu.pcount = fu.locals.length;
			let sig = fu.locals.slice();
			sig.push(tysig[tysig.length - 1]);
			fu.sig = gettype(mod, sig);
			if (/^\s/.test(line2)) {
				i += 2;
			} else {
				let losig = line2.split(/\s+/);
				for (let j=0; j<losig.length; j+=2) {
					fu.localnames.set(losig[j], fu.locals.length);
					fu.locals.push(losig[j+1]);
				}
				i += 3;
			}
			while (lines[i] && /^\s+/.test(lines[i])) {
				if (!/^\s*$/.test(lines[i])) {
					fu.code.push(lines[i].trim().split(/\s+/));
				}
				i++;
			}
			i--;
			if (expo) mod.exports.func.push(mod.func.length);
			mod.func.push(fu);
		}
		else if (/^table /.test(line)) {
			let name = line.slice(6);
			let tab = [];
			while (/^\s+/.test(lines[i+1])) {
				tab.push(lines[i+1].trim().split(/\s+/));
				i++;
			}
			if (expo) mod.exports.table.push(mod.table.length);
			mod.table.push({name: name, table: tab});
		}
		else if (/^import /.test(line)) {
			mod.imports.push(line.split(/\s+/));
		}
		else if (/^global /.test(line)) {
			if (expo) mod.exports.global.push(mod.global.length);
			mod.global.push(line.split(/\s+/));
		} else if (/^memory /.test(line)) {
			let [_memory, ...mems] = line.split(/\s+/);
			for (let i=0; i<mems.length; i++) {
				if (expo) mod.exports.memory.push(mod.memory.length);
				mod.memory.push({name: mems[i], size: pushLimit([], mems[i+1])});
			}
		} else {
			console.log("??", line);
		}
	}
}

function pushLimit(ret, lim) {
	let [mn, mx] = lim.split(':');
	ret.push(mx === undefined?0:1);
	varuint(ret, mn|0);
	if (mx !== undefined) varuint(ret, mx|0);
	return ret;
}

function mod_comp(mod) {
	const fsig = [], tsig = [], msig = [], gsig = [], bcimp = [];
	varuint(bcimp, mod.imports.length);
	for (let i=0; i<mod.imports.length; i++) {
		let [_import, kind, name, ...data] = mod.imports[i];
		let [module, field] = name.split('.');
		varuint(bcimp, module.length);
		bcimp.push(...asUtf8(module));
		varuint(bcimp, field.length);
		bcimp.push(...asUtf8(field));
		switch (kind.slice(0, 3)) {
			case "fun": {
				mod.names.set(name, fsig.length);
				const fty = gettype(mod, data);
				fsig.push(fty);
				bcimp.push(0);
				varuint(bcimp, fty);
				break;
			}
			case "tab": {
				mod.names.set(name, tsig.length);
				bcimp.push(1);
				const ts = pushLimit([tymap[data[0]], data[1]]);
				tsig.push(ts);
				bcimp.push(...ts);
				break;
			}
			case "mem": {
				mod.names.set(name, msig.length);
				const ms = pushLimit([], data[0]);
				msig.push(ms);
				bcimp.push(2);
				bcimp.push(...ms);
				break;
			}
			case "glo": {
				mod.names.set(name, gsig.length);
				const gs = [tymap[data[0]], 0];
				gsig.push(gs);
				bcimp.push(3);
				bcimp.push(...gs);
				break;
			}
		}
	}
	const gbase = gsig.length;
	for (let i=0; i<mod.global.length; i++) {
		let [_global, mut, ty, name, val] = mod.global[i];
		if (!val) {
			val = "0";
		}
		if (!name) {
			name = ty;
			ty = mut;
			mut = "mut";
		}
		val = +val;
		mut = mut == "mut"?1:0;
		mod.names.set(name, gsig.length);
		gsig.push([tymap[ty], mut]);
	}
	for (let i=0; i<mod.func.length; i++) {
		let fu = mod.func[i];
		mod.names.set(fu.name, fsig.length);
		fsig.push(fu.sig);
	}
	for (let i=0; i<mod.func.length; i++) {
		let fu = mod.func[i];
		for (let j=0; j<fu.code.length; j++) {
			let c = fu.code[j];
			if (typeof c === "string") {
				let nc = mod.names.get(c);
				fu.code[j] = nc === undefined ? +c : nc;
			}
		}
	}

	const bc = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
	if (mod.type.length) {
		bc.push(1);
		const bcty = [];
		varuint(bcty, mod.type.length);
		for (let i=0; i<mod.type.length; i++) {
			bcty.push(0x60);
			let ty = mod.type[i];
			if (ty.length == 0 || (ty.length == 1 && ty[0] == 0x40)) {
				bcty.push(0, 0);
				continue;
			}
			let hasret = ty[ty.length-1] != 0x40;
			let pcount = ty.length - 1;
			varuint(bcty, pcount);
			for (let j=0; j<pcount; j++) {
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
	if (mod.imports.length) {
		bc.push(2);
		varuint(bc, bcimp.length);
		bc.push(...bcimp);
	}
	if (mod.func.length) {
		bc.push(3);
		const bcfu = [];
		varuint(bcfu, mod.func.length);
		for (let i=0; i<mod.func.length; i++) {
			varuint(bcfu, mod.func[i].sig);
		}
		varuint(bc, bcfu.length);
		bc.push(...bcfu);
	}
	if (mod.table.length) {
		bc.push(4);
	}
	if (mod.memory.length) {
		bc.push(5);
		const bcmem = [];
		varuint(bcmem, mod.memory.length);
		varuint(bc, bcmem.length);
		bc.push(...bcmem);
	}
	if (mod.global.length) {
		bc.push(6);
		const bcglo = [];
		varuint(bcglo, mod.global.length);
		for (let i=gbase; i<gsig.length; i++) {
			const [gty, gmut] = gsig[i];
			bcglo.push(gty, gmut);
			switch (gty) {
				case 0x7f:
					bcglo.push(opmap["i32.const"], 0, 0x0b);
					break;
				case 0x7e:
					bcglo.push(opmap["i64.const"], 0, 0x0b);
					break;
				case 0x7d:
					bcglo.push(opmap["f32.const"], 0, 0, 0, 0, 0x0b);
					break;
				case 0x7c:
					bcglo.push(opmap["f64.const"], 0, 0, 0, 0, 0, 0, 0, 0, 0x0b);
					break;
			}
		}
		varuint(bc, bcglo.length);
		bc.push(...bcglo);
	}
	const exlength = mod.exports.func.length + mod.exports.table.length + mod.exports.memory.length + mod.exports.global.length;
	if (exlength) {
		bc.push(7);
		const sects = ["func", "table", "memory", "global"], bcex = [];
		varuint(bcex, exlength);
		for (let i=0; i<sects.length; i++) {
			const modsect = mod[sects[i]];
			for (let idx of mod.exports[sects[i]]) {
				let name = modsect[idx].name;
				varuint(bcex, name.length);
				bcex.push(...asUtf8(name));
				bcex.push(i);
				varuint(bcex, mod.names.get(name));
			}
		}
		varuint(bc, bcex.length);
		bc.push(...bcex);
	}
	if (mod.start) {
		bc.push(8);
		let val = mod.names.get(mod.start.name);
		let bcstart = [];
		varuint(bcstart, val);
		varuint(bc, bcstart.length);
		bc.push(...bcstart);
	}
	if (mod.element.length) {
		bc.push(9);
	}
	if (mod.func.length) {
		bc.push(10);
		const bcco = [];
		varuint(bcco, mod.func.length);
		for (let i=0; i<mod.func.length; i++) {
			const fu = mod.func[i], cofu = [];
			console.log(i, fu.name);
			if (fu.pcount === fu.locals.length) {
				cofu.push(0);
			} else {
				let numlocent = 1;
				for (let j=fu.pcount+1; j<fu.locals.length; j++) {
					numlocent += fu.locals[j] != fu.locals[j-1];
				}
				varuint(cofu, numlocent);
				for (let j=fu.pcount; j<fu.locals.length; ) {
					const jty = tymap[fu.locals[j]], jj = j++;
					while (j<fu.locals.length && tymap[fu.locals[j]] === jty) j++;
					console.log(jty, fu.locals[j], fu.locals[jj], j, jj);
					varuint(cofu, j-jj);
					cofu.push(jty);
				}
			}
			let scope = 0;
			for (let j=0; j<fu.code.length; j++) {
				let ln = fu.code[j];
				let op = opmap[ln[0]];
				console.log(cofu.length, ln);
				if (op === undefined) console.log("Unknown op", ln);
				cofu.push(op);
				if (op >= 0x02 && op <= 0x04) scope++;
				if (op == 0x0b) scope--;
				let opf = opimm[op];
				if (opf) opf(fu, mod, cofu, ln, scope);
			}
			cofu.push(0x0b);
			varuint(bcco, cofu.length);
			bcco.push(...cofu);
		}
		varuint(bc, bcco.length);
		bc.push(...bcco);
	}
	if (mod.data.length) {
		bc.push(11);
	}
	return Buffer.from(bc);
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
	load: 0x20,
	loadl: 0x20,
	set_local: 0x21,
	store: 0x21,
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
	i64: 0x42,
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
const opimm = [];
function setopimm(f, ...args) {
	for (let i=0; i<args.length; i++) {
		opimm[opmap[args[i]]] = f;
	}
}
setopimm(block_type, "block", "loop", "if");
setopimm(relative_depth, "br", "br_if");
opimm[opmap.br_table] = br_table;
opimm[opmap.call] = function_index;
opimm[opmap.call_indirect] = call_indirect;
setopimm(local_index, "get_local", "set_local", "tee_local");
setopimm(global_index, "get_global", "set_global");
setopimm(memory_immediate, "i32.load", "i64.load", "f32.load", "f64.load",
	"i32.load8_s", "i32.load8_u", "i32.load16_s", "i32.load16_u",
	"i64.load8_s", "i64.load8_u", "i64.load16_s", "i64.load16_u", "i64.load32_s", "i64.load32_u",
	"i32.store", "i64.store", "f32.store", "f64.store", "i32.store8", "i32.store16",
	"i64.store8", "i64.store16", "i64.store32");
setopimm(reserved0, "current_memory", "grow_memory");
opimm[opmap["i32.const"]] = const_i32;
opimm[opmap["i64.const"]] = const_i64;
opimm[opmap["f32.const"]] = const_f32;
opimm[opmap["f64.const"]] = const_f64;
function local_index(fu, mod, bc, ln) {
	varuint(bc, fu.localnames.get(ln[1]));
}
function global_index(fu, mod, bc, ln) {
	varuint(bc, mod.names.get(ln[1]));
}
function relative_depth(fu, mod, bc, ln, scope) {
	let val = fu.scopes.get(ln[1]);
	varuint(bc, val === undefined ? ln[1]|0 : scope-val);
}
function br_table(fu, mod, bc, ln, scope) {
	varuint(bc, ln.length - 2);
	for (let i=1; i<ln.length; i++) {
		let val = fu.scopes.get(ln[i]);
		varuint(bc, val === undefined ? ln[i]|0 : scope-val);
	}
}
function block_type(fu, mod, bc, ln, scope) {
	if (ln.length == 1) bc.push(0x40);
	else {
		let bty = 0x40;
		for (let i=1; i<ln.length; i++) {
			if (ln[i][0] == '@') {
				fu.scopes.set(ln[i], scope);
			}
			else if (ln[i] in tymap) {
				bty = tymap[ln[i]];
			}
		}
		bc.push(bty);
	}
}
function function_index(fu, mod, bc, ln) {
	const name = mod.names.get(ln[1]);
	if (name === undefined) throw "Unknown function_index: " + ln[1];
	varuint(bc, name);
}
function call_indirect(fu, mod, bc, ln) {
	// Ahhh need to do this before we encode all types..
	bc.push(0);
}
function memory_immediate(fu, mod, bc, ln) {
	if (ln.length == 1) {
		bc.push(0, 0);
	} else if (ln.length == 2) {
		bc.push(0);
		let v = mod.names.get(ln[1]);
		if (v === undefined) v = ln[1]|0;
		varuint(bc, v);
	} else if (ln.length == 3) {
		bc.push(ln[2]|0);
		let v = mod.names.get(ln[1]);
		if (v === undefined) v = ln[1]|0;
		varuint(bc, v);
	}
}
function reserved0(fu, mod, bc, ln) {
	bc.push(0);
}
function const_i32(fu, mod, bc, ln) {
	varint(bc, ln[1]|0);
}
function const_i64(fu, mod, bc, ln) {
	varint(bc, ln[1]|0); // TODO JS doesn't do 64bit
}
function const_f32(fu, mod, bc, ln) {
	let f32 = new Float32Array([+ln[1]]);
	bc.push(...new Uint8Array(f32.buffer));
}
function const_f64(fu, mod, bc, ln) {
	let f64 = new Float64Array([+ln[1]]);
	bc.push(...new Uint8Array(f32.buffer));
}