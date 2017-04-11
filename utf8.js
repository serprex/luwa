"use strict";
const Table = require("./table"), util = require("./util");
var utf8 = module.exports =  new Table();
utf8.set("char", utf8_char);
utf8.set("charpattern", "[\0-\x7f\xc2-\xf4][\x80-\xbf]*");

function utf8_char(vm, stack, base) {
	let ret = "";
	for (var i = base+1; i<stack.length; i++) {
		// TODO reject invalid character codes
		if (typeof stack[i] != "number") throw "utf8.char: expected numbers";
		ret += String.fromCharCode(stack[i]);
	}
	stack[base] = ret;
	stack.length = base + 1;
}

