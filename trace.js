"use strict";

const any = exports.any = -1;
const nil = exports.nil = 1;
const bool = exports.bool = 2;
const num = exports.num = 4;
const int = exports.int = 8;
const str = exports.str = 16;
const table = exports.table = 32;
const func = exports.func = 64;
const jsfunc = exports.jsfunc = 128;
const thread = exports.thread = 256;
exports.getType = getType;
exports.Context = Context;
exports.Cursor = Cursor;
exports.Edge = Edge;
exports.Id = Id;

const Vm = require("./runbc").Vm;

function getType(x) {
	let t = typeof x;
	if (t === null) {
		return nil;
	} else if (t === "number") {
		return num;
	} else if (t === "string") {
		return str;
	} else if (t === "function") {
		return func;
	} else if (t === "boolean") {
		return bool;
	} else if (t instanceof Table) {
		return table;
	} else if (t instanceof Vm) {
		return jsfunc;
	} else if (t instanceof Thread) {
		return thread;
	} else return any;
}

function Context() {
	this.idx2ids = [];
	this.heads = new Map();
}

Context.prototype.getId = function(idx, pop, types) {
	let ids = this.idx2ids[idx];
	if (!ids) ids = this.idx2ids[idx] = [];
	else {
		for (let id of ids) {
			if (id.pop == pop && id.types.length == types.length &&
				id.types.every((v, j) => types[j] === v))
			{
				return id;
			}
		}
	}
	let id = new Id(idx, pop, types);
	ids.push(id);
	return id;
}

function Cursor(ctx) {
	this.ctx = ctx;
	this.id = null;
}

Cursor.prototype.clone = function() {
	var c = new Cursor(this.ctx);
	c.id = this.id;
	return c;
}

Cursor.prototype.traceStack = function(idx, pop, stack, base) {
	return this.trace(idx, pop, ...stack.slice(base));
}

Cursor.prototype.trace = function(idx, pop, ...types) {
	let nid = this.ctx.getId(idx, pop, types), id = this.id;
	this.id = nid;
	let head = this.ctx.heads.get(id);
	if (!head) {
		head = [];
		this.ctx.heads.set(this.id, head);
	} else {
		for (let h of head) {
			if (h.tail === nid) {
				h.count++;
				return h;
			}
		}
	}
	let h = new Edge(id, nid, 1);
	head.push(h);
	return h;
}

function Id(idx, pop, types) {
	this.idx = idx;
	this.pop = pop;
	this.types = types;
}

Id.prototype.equals = function(idx, pop, types) {
	return this.idx === idx && this.pop === pop &&
		this.types.length === types.length && this.types.every((v, j) => v === types[j]);
}

function Edge(head, tail, count = 0) {
	this.head = head;
	this.tail = tail;
	this.count = count;
}
