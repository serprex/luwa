"use strict";

const trace = require("./trace"),
	Func = require("./func"),
	opc = require("./bc"),
	util = require("./util");
const varint = util.varint, varuint = util.varuint;


/*
local i = 0 # LOAD_NUM 0, STORE_LOCAL 1
while i < 10000 # $l, LOAD_LOCAL 1, LOAD_NUM 1, LT, JIFNOT $e
do i = i + 1 # LOAD_LOCAL 1, LOAD_NUM 2, ADD, STORE_LOCAL 1
end # GOTO $l, $e, RETURN
*/
exports.compile = function(func, pc, trctx, trcur, imps) {
	trcur = trcur.clone();
	let localmap = [], localc = 1,
		blockmap = [], blocks = [], blockc = 0;
	let heads = trctx.heads.get(trcur.id);
	let bc = func.bc;
	function getLocal(local) {
		let a = localmap[local];
		if (a === undefined) {
			a = localmap[local] = localc++;
		}
		return a;
	}
	function getBlockByPc(p) {
		let a = blockmap[p];
		if (a === undefined) {
			a = blockmap[p] = blockc++;
			blocks[a] = [];
		}
		return a;
	}
	function blockJump(id) {
		block.push(0x41);
		varint(block, id);
		block.push(0x21, 0);
	}
	function blockpile(pc) {
		let bid = getBlockByPc(pc);
		let block = blocks[bid];
		if (block.length) return bid;
		while (true) {
			if (func.labels.has(pc)) {
				let nbid = blockpile(pc);
				blockJump(nbid);
				return bid;
			}
			let op = bc[pc], arg = bc[pc+1], arg2 = bc[pc+2];
			pc += (op >> 6) + 1;
			switch (op) {
				case opc.BIN_ADD:
					block.push(0x6a);
					break;
				case opc.BIN_LT:
					block.push(0x48);
					break;
				case opc.LOAD_NUM:
					block.push(0x41);
					varint(block, func.sn[arg]);
					break;
				case opc.STORE_LOCAL:
					block.push(0x21);
					varuint(block, getLocal(arg));
					break;
				case opc.LOAD_LOCAL:
					block.push(0x20);
					varuint(block, getLocal(arg));
					break;
				case opc.JIFNOT: {
					let bbid = blockpile(arg);
					let elsebid = blockpile(pc);
					block.push(0x45, 0x04, 0x7f, 0x41);
					varint(block, elsebid);
					block.push(0x05, 0x41);
					varint(block, bbid);
					block.push(0x0b, 0x21, 0);
					return bid;
				}
				case opc.GOTO: {
					let nbid = blockpile(arg);
					blockJump(nbid);
					return bid;
				}
				default:
					// TODO emit return-to-js
					return bid;
			}
		}
	}
	const wasm = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];

	wasm.push(1);
	const type = [1];
	// void -> void
	type.push(0x7f, 0, 0x7f, 0);
	varuint(wasm, type.length);
	wasm.push(...type);

	wasm.push(2);
	const imp = [1];
	imp.push(0, 1, "m".charCodeAt(0), 2, 0, 1);
	varuint(wasm, imp.length);
	wasm.push(...imp);

	wasm.push(3);
	const functions = [1];
	functions.push(1);
	varuint(wasm, functions.length);
	wasm.push(...functions);

	wasm.push(7);
	const exports = [1];
	exports.push(1, "f".charCodeAt(0), 0, 0);
	varuint(wasm, exports.length);
	wasm.push(...exports);

	bc.push(10);
	blockpile(pc);
	const code = [10], body = [1, 3, 0x7f];
	body.push(0x03, 0x40);
	for (var i=0; i<=blocks.length; i++) {
		body.push(0x02, 0x40);
	}
	body.push(0x20, 1, 0x0e);
	varuint(body, blocks.length - 1);
	for (var i=0; i<blocks.length - 1; i++) {
		varuint(body, i);
	}
	body.push(0x0b);
	for (var i=0; i<blocks.length; i++) {
		body.push(...blocks[i]);
		body.push(0x0c);
		varuint(body, blocks.length - i);
		body.push(0x0b);
	}
	body.push(0x0b, 0, 0x0b);
	varuint(code, body.length);
	code.push(code, ...body);
	varuint(wasm, code.length);
	wasm.push(...code);
	return WebAssembly.instantiate(new Uint8Array(wasm), imps);
}
