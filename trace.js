"use strict";

exports.any = -1;
exports.nil = 1;
exports.bool = 2;
exports.num = 4;
exports.int = 8;
exports.str = 16;
exports.table = 32;
exports.func = 64;
exports.jsfunc = 128;
exports.TraceSet = TraceSet;
exports.TraceBlock = TraceBlock;
exports.TracePush = TracePush;
exports.TracePop = TracePop;

function TraceSet() {
	this.traces = [];
	this.traces[0] = new TraceBlock();
}

function TraceBlock() {
	this.ops = [];
	this.pop1 = 0;
	this.pop2 = 0;
	this.types1 = [];
	this.types2 = [];
	this.fork1 = null;
	this.fork2 = null;
}

function TracePop(pop) {
	this.pop = pop;
	this.push = [];
}

function TracePush(types) {
	this.count = 1;
	this.types = [];
}

function incr(a, types) {
	let tl = types.length;
	for (let e of a) {
		// assert e.push.length == tl
		if (e.push.length == tl && e.push.every((v, j) => v === types[j])) {
			e.count++;
			return e;
		}
	}
	let e = new TracePush(types);
	a.push(e);
	return e;
}

TraceSet.prototype.fork = function (blk, f1idx, f2idx = -1) {
	if (!this.traces[f1idx]) this.traces[f1idx] = new TraceBlock();
	if (~f2idx && !this.traces[f2idx]) this.traces[f2idx] = new TraceBlock();
	return blk.fork(this.traces[f1idx], this.traces[f2idx]);
}

TraceSet.prototype.incr1 = function (pop, ...types) {
	this.pop1 = pop;
	return incr(this.types1, types);
}

TraceSet.prototype.incr2 = function (pop, ...types) {
	this.pop2 = pop;
	return incr(this.types2, types);
}

TraceBlock.prototype.incr = function (idx, pop, ...types) {
	if (idx < this.ops.length) {
		this.push(pop = new TracePop(pop));
	} else {
		pop = this.ops[idx];
	}
	// this condition should be removed once all instructions are traced; until then the information is useless
	if (pop) pop.incr(types);
}

TraceBlock.prototype.fork = function (f1, f2) {
	this.fork1 = f1;
	this.fork2 = f2;
}

TracePop.prototype.get = function(types) {
	let tl = types.length;
	for (let e of this.edges) {
		if (e.push.length == tl && e.push.every((v, j) => v === types[j])) {
			return e;
		}
	}
	return null;
}

TracePop.prototype.incr = function(types) {
	return incr(this.edges, types);
}
