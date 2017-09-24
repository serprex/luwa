"use strict";
module.exports = Func;
const util = require('./util');

function Func(asm) {
	this.id = asm.id;
	this.sn = asm.lx.snr;
	this.ss = asm.lx.ssr;
	this.bc = new Uint32Array(asm.bc);
	this.fus = asm.fus;
	this.pcount = asm.pcount;
	this.lcount = asm.lcount;
	this.fcount = asm.fcount;
	this.isdotdotdot = asm.isdotdotdot;
	this.freelist = [];
	this.local2free = asm.local2free;
	for (let i=0; i<asm.gotos.length; i+=2) {
		let lpos = asm.labelpos[asm.gotos[i+1]];
		util.writeuint32(this.bc, asm.gotos[i], lpos);
	}
	for (let key in asm.frees) {
		key = +key;
		for (let [fid, val] of asm.frees[key]) {
			if (!this.freelist[fid]) this.freelist[fid] = new Map();
			this.freelist[fid].set(key, val);
		}
	}
}


