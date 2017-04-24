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
	for (let key in asm.frees) {
		key = +key;
		for (let [fid, val] of asm.frees[key]) {
			if (!this.freelist[fid]) this.freelist[fid] = new Map();
			this.freelist[fid].set(key, val);
		}
	}
}


