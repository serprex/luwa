"use strict";
const Table = require("./table"), util = require("./util"), utf8 = require("./utf8");
var string = module.exports = new Table();
string.set("char", utf8.get("char"));
string.set("len", string_len);
string.set("lower", string_lower);
string.set("reverse", string_reverse);
string.set("upper", string_upper);

function*string_len(stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.lower #1: expected string";
	stack[base] = s.length;
	stack.length = base + 1;
}

function*string_lower(stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.lower #1: expected string";
	stack[base] = s.toLowerCase();
	stack.length = base + 1;
}

function*string_reverse(stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.reverse #1: expected string";
	let r = '';
	for (let i=s.length-1; i>=0; i--) r += s[i];
	stack[base] = r;
	stack.length = base + 1;
}

function*string_upper(stack, base) {
	let s = util.readarg(stack, base+1);
	if (typeof s != "string") throw "string.upper #1: expected string";
	stack[base] = s.toUpperCase();
	stack.length = base + 1;
}
