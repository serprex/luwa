"use strict";
module.exports = Func;
const trace = require("./trace");

function Func(asm) {
	this.id = asm.id;
	this.lx = asm.lx;
	this.bc = asm.bc;
	this.fus = asm.fus;
	this.pcount = asm.pcount;
	this.lcount = asm.lcount;
	this.fcount = asm.fcount;
	this.isdotdotdot = asm.isdotdotdot;
	this.freelist = [];
	this.local2free = asm.local2free;
	this.trace = new trace.Context();
	this.labels = new Set();
	for (var i=0; i<asm.gotos.length; i+=3) {
		let lpos = asm.labelpos[asm.gotos[i+1]];
		this.bc[asm.gotos[i]] = lpos.pos;
		this.labels.add(lpos.pos);
		if (asm.gotos[i+2]) {
			this.bc[asm.gotos[i]-2] = asm.gotos[i+2] - lpos.fordepth;
		}
	}
	for (let key in asm.frees) {
		key = +key;
		for (let [fid, val] of asm.frees[key]) {
			if (!this.freelist[fid]) this.freelist[fid] = new Map();
			this.freelist[fid].set(key, val);
		}
	}
}


