"use strict";
module.exports = function () {
	var env = new Table();
	env.set("_G", env);
	env.set("_VERSION", "Luwa 0.0");

	var io = new Table();
	env.set("io", io);
	io.set("write", io_write);

	var os = new Table();
	env.set("os", os);
	os.set("clock", os_clock);
	os.set("difftime", os_difftime);

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
	math.set("maxinteger", Math.pow(2, 53));
	math.set("mininteger", -Math.pow(2, 53));
	math.set("huge", Infinity);
	math.set("abs", math_abs);
	math.set("acos", math_acos);
	math.set("asin", math_asin);
	math.set("ceil", math_ceil);
	math.set("cos", math_cos);
	math.set("deg", math_deg);
	math.set("exp", math_exp);
	math.set("floor", math_floor);
	math.set("rad", math_rad);
	math.set("sin", math_sin);
	math.set("sqrt", math_sqrt);
	math.set("tan", math_tan);
	math.set("tointeger", math_tointeger);
	math.set("type", math_type);
	math.set("ult", math_ult);

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
	env.set("print", print);
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

function os_clock(vm, stack, base) {
	stack.length = base + 1;
	stack[base] = new Date()/1000;
}

function os_difftime(vm, stack, base) {
	stack[base] = readarg(stack, base, 1) - readarg(stack, base, 2);
	stack.length = base + 1;
}

function table_pack(vm, stack, base) {
	let t = new Table();
	t.array = stack.slice(base + 1);
	t.set("n", stack.length - base - 1);
	stack.length = base + 1;
	stack[base] = t;
}

function math_abs(vm, stack, base) {
	stack[base] = Math.abs(stack[base+1]);
	stack.length = base + 1;
}

function math_acos(vm, stack, base) {
	stack[base] = Math.acos(stack[base+1]);
	stack.length = base + 1;
}

function math_asin(vm, stack, base) {
	stack[base] = Math.asin(stack[base+1]);
	stack.length = base + 1;
}

function math_ceil(vm, stack, base) {
	stack[base] = Math.ceil(stack[base+1]);
	stack.length = base + 1;
}

function math_cos(vm, stack, base) {
	stack[base] = Math.cos(stack[base+1]);
	stack.length = base + 1;
}

function math_deg(vm, stack, base) {
	stack[base] = stack[base+1] * (180 / Math.PI);
	stack.length = base + 1;
}

function math_exp(vm, stack, base) {
	stack[base] = Math.exp(stack[base+1]);
	stack.length = base + 1;
}

function math_floor(vm, stack, base) {
	stack[base] = Math.floor(stack[base+1]);
	stack.length = base + 1;
}

function math_rad(vm, stack, base) {
	stack[base] = stack[base+1] * (Math.PI / 180);
	stack.length = base + 1;
}

function math_sin(vm, stack, base) {
	stack[base] = Math.sin(stack[base+1]);
	stack.length = base + 1;
}

function math_sqrt(vm, stack, base) {
	stack[base] = Math.sqrt(stack[base+1]);
	stack.length = base + 1;
}

function math_tan(vm, stack, base) {
	stack[base] = Math.tan(stack[base+1]);
	stack.length = base + 1;
}

function math_tointeger(vm, stack, base) {
	let v = stack[base+1];
	stack[base] = v === v|0 ? v : null;
	stack.length = base + 1;
}

function math_type(vm, stack, base) {
	let v = stack[base+1];
	stack[base] = v === v|0 ? "integer" : "float";
	stack.length = base + 1;
}

function math_ult(vm, stack, base) {
	let u32 = new Uint32Array([stack[base+1], stack[base+2]]);
	stack[base] = u32[0] < u32[1];
	stack.length = base + 1;
}