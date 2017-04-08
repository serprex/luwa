"use strict";
module.exports = function () {
	var env = new Table();
	env.set("_G", env);
	env.set("_VERSION", "Luwa 0.0");

	var io = new Table();
	env.set("io", io);
	io.set("write", io_write);
	io.set("clock", io_clock);

	var debug = new Table();
	env.set("debug", debug);

	var string = new Table();
	env.set("string", string);

	var table = new Table();
	env.set("table", table);
	table.set("pack", table_pack);

	var math = new Table();
	env.set("math", math);
	math.set("pi", Math.PI);

	var coroutine = new Table();
	env.set("coroutine", coroutine);

	var packge = new Table();
	env.set("package", packge);

	var utf8 = new Table();
	env.set("utf8", utf8);

	env.set("type", type);
	env.set("pcall", pcall);
	env.set("error", error);
	env.set("assert", assert);
	env.set("getmetatable", getmetatable);
	env.set("setmetatable", setmetatable);
	return env;
}

const obj = require("./obj"),
	Table = require("./table"),
	runbc = require("./runbc");

function readarg(stack, base, i) {
	return base + i < stack.length ? stack[base+i] : null;
}

function type(vm, stack, base) {
	stack.length = base + 1;
	let obj = stack[base];
	if (obj === null) stack[base] = "nil";
	else {
		switch (typeof obj) {
			case "string":stack[base] = "string";return;
			case "number":stack[base] = "number";return;
			case "boolean":stack[base] = "boolean";return;
			case "function":stack[base] = "function";return;
			case "object":
				stack[base] = obj instanceof Table ? "table"
					: "userdata";
		}
	}
}

function pcall(vm, stack, base) {
	let f = stack.splice(base, 2)[1];
	if (!f) {
		throw "Unexpected nil to pcall";
	}
	try {
		if (typeof f == "function") {
			f(vm, stack, base);
		} else {
			// invoke VM
		}
	} catch (e) {
		return stack.push(false, e);
	}
	stack.splice(base, 0, true);
}

function error(vm, stack, base) {
	throw val;
}

function assert(vm, stack, base) {
	if (cond) throw val;
}

function print(vm, stack, base) {
	console.log(stack.slice(base+1));
	stack.length = base;
}

function getmetatable(vm, stack, base) {
	let arg = readarg(stack, base, 1);
	stack.length = base + 1;
	stack[base] = obj.getmetatable(arg);
}

function setmetatable(vm, stack, base) {
	let arg2 = readarg(stack, base, 2);
	stack.length = base + 1;
	obj.setmetatable(stack[base], arg2);
}

function io_write(vm, stack, base) {
	for (var i=base+1; i<stack.length; i++) {
		console.log(stack[i]);
	}
	stack.length = base;
}

function io_clock(vm, stack, base) {
	stack.length = base + 1;
	stack[base] = new Date()/1000;
}

function table_pack(vm, stack, base) {
	let t = new Table();
	t.array = stack.slice(base + 1);
	t.set("n", stack.length - base - 1);
	stack.length = base + 1;
	stack[base] = t;
}