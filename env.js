"use strict";
const obj = require("./obj"),
	Table = require("./table");

function pcall(vm, stack) {
	try {
		// do call
	} catch (e) {
		stack.push(false, e);
	}
}

function error(vm, stack) {
	throw val;
}

function assert(vm, stack) {
	if (cond) throw val;
}

module.exports = function api() {
	var _G = new Table();
	var io = new Table();
	io.set("write", x => console.log(x));
	io.set("clock", () => Date.now());
	_G.set("io", io);
	_G.set("pcall", pcall);
	_G.set("error", error);
	_G.set("assert", assert);
	_G.set("getmetatable", obj.getmetatable);
	_G.set("setmetatable", obj.setmetatable);
	_G.set("_G", _G);
	return _G;
}