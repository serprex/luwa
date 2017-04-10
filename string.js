"use strict";
const Table = require("./table"), util = require("./util"), utf8 = require("./utf8");
var string = module.exports = new Table();
string.set("char", utf8.get("char"));
string.set("len", string_len);
string.set("lower", string_lower);
string.set("upper", string_upper);

function string_len(vm, stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.lower #1: expected string";
	stack[base] = s.length;
	stack.length = base + 1;
}

function string_lower(vm, stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.lower #1: expected string";
	stack[base] = s.toLowerCase();
	stack.length = base + 1;
}

function string_upper(vm, stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.upper #1: expected string";
	stack[base] = s.toUpperCase();
	stack.length = base + 1;
}
