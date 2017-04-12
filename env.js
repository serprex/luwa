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

	env.set("string", string);

	var table = new Table();
	env.set("table", table);
	table.set("concat", table_concat);
	table.set("insert", table_insert);
	table.set("pack", table_pack);
	table.set("remove", table_remove);
	table.set("sort", table_sort);
	table.set("unpack", table_unpack);

	var math = new Table();
	env.set("math", math);
	math.set("pi", Math.PI);
	math.set("maxinteger", Math.pow(2, 53));
	math.set("mininteger", -Math.pow(2, 53));
	math.set("huge", Infinity);
	math.set("abs", math_abs);
	math.set("acos", math_acos);
	math.set("asin", math_asin);
	math.set("atan", math_atan);
	math.set("ceil", math_ceil);
	math.set("cos", math_cos);
	math.set("deg", math_deg);
	math.set("exp", math_exp);
	math.set("floor", math_floor);
	math.set("log", math_log);
	math.set("log10", math_log10);
	math.set("modf", math_modf);
	math.set("rad", math_rad);
	math.set("sin", math_sin);
	math.set("sqrt", math_sqrt);
	math.set("tan", math_tan);
	math.set("tointeger", math_tointeger);
	math.set("type", math_type);
	math.set("ult", math_ult);

	var coroutine = new Table();
	env.set("coroutine", coroutine);
	coroutine.set("create", coroutine_create);
	coroutine.set("resume", coroutine_resume);
	coroutine.set("status", coroutine_status);
	coroutine.set("yield", coroutine_yield);
	coroutine.set("wrap", coroutine_wrap);

	var packge = new Table();
	env.set("package", packge);

	env.set("utf8", utf8);

	env.set("assert", assert);
	env.set("error", error);
	env.set("ipairs", ipairs);
	env.set("pairs", pairs);
	env.set("next", next);
	env.set("tonumber", tonumber);
	env.set("tostring", tostring);
	env.set("type", type);
	env.set("pcall", pcall);
	env.set("print", print);
	env.set("rawequal", rawequal);
	env.set("rawget", rawget);
	env.set("rawlen", rawlen);
	env.set("select", select);
	env.set("getmetatable", getmetatable);
	env.set("setmetatable", setmetatable);
	return env;
}

const obj = require("./obj"),
	Table = require("./table"),
	Thread = require("./thread"),
	runbc = require("./runbc"),
	string = require("./string"),
	utf8 = require("./utf8"),
	util = require("./util");


function*assert(stack, base) {
	if (base + 1 == stack.length) throw "assert #1: expected value";
	let cond = util.readarg(stack, base+1)
	if (cond !== null && cond !== false) {
		throw base+2 >= stack.length ? "Assertion failed!" : stack[base+2];
	}
	stack[base] = cond;
	stack.length = base + 1;
}

function*error(stack, base) {
	throw util.readarg(stack, base+1);
}

function*pairs(stack, base) {
	stack.length = base + 3;
	stack[base] = next;
	stack[base+2] = null;
}

function*ipairs(stack, base) {
	stack.length = base + 3;
	stack[base] = inext;
	stack[base+2] = 0;
}

function*inext(stack, base) {
	let t = stack[base+1], key = stack[base+2] + 1;
	if (key < t.array.length) {
		stack[base] = key;
		stack[base+1] = key in t.array ? t.array[key] : null;
		stack.length = base + 2;
	} else {
		stack.length = base;
	}
}

function*next(stack, base) {
	let t = util.readarg(stack, base+1), key = util.readarg(stack, base+2);
	if (!(t instanceof Table)) {
		throw "next #1: expected table";
	}
	if (key === null) {
		if (t.keys.length) {
			let k = t.keys[0];
			stack[base] = t.get(k);
			stack[base+1] = k;
			stack.length = base + 2;
		} else {
			stack[base] = null;
			stack.length = base + 1;
		}
	} else {
		let ki = t.keyidx.get(key);
		if (ki === null) {
			throw "next: table iteration corrupted";
		} else if (ki+1 >= t.keys.length) {
			stack[base] = null;
			stack.length = base + 1;
		} else {
			let k = t.keys[++ki];
			stack[base] = k;
			stack[base+1] = t.get(k);
			stack.length = base + 2;
		}
	}
}

function*tonumber(stack, base) {
	let e = util.readarg(stack, base+1), b = util.readarg(stack, base+2);
	if (b === null) {
		if (typeof e == "number") {
			stack[base] = e;
		} else if (typeof e == "string") {
			stack[base] = parseFloat(e);
			if (Number.isNaN(stack[base])) {
				stack[base] = null;
			}
		} else {
			throw "tonumber #1: expected number or string";
		}
	} else if (typeof b == "number") {
		if (b < 2 || b > 36) {
			stack[base] = null;
		} else if(typeof e == "string") {
			stack[base] = parseInt(e, b);
		} else {
			throw "tonumber #1: expected string";
		}
	} else {
		throw "tonumber #2: expected number";
	}
	stack.length = base + 1;
}

function*tostring(stack, base) {
	let v = util.readarg(stack, base+1);
	let __tostring = obj.metaget(v, "__tostring");
	stack.length = base;
	if (__tostring) {
		stack.push(__tostring, v);
		runbc.callObj(__tostring, stack, base);
		if (stack.length == base) return stack.push(null);
	} else {
		stack[base] = v === null ? "nil" : v + "";
	}
	stack.length = base + 1;
}

function*type(stack, base) {
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
				stack[base] = obj instanceof Table ? "table" :
					obj instanceof Thread ? "thread" : "userdata";
		}
	}
}

function*pcall(stack, base) {
	let f = util.readarg(stack, base+1);
	try {
		yield *f(stack, base);
		stack.splice(base, 0, true);
	} catch (e) {
		stack.length = base + 2;
		stack[base] = false;
		stack[base + 1] = e;
	}
}

function*print(stack, base) {
	console.log(stack.slice(base+1));
	stack.length = base;
}

function*rawequal(stack, base) {
	stack[base] = util.readarg(stack, base+1) === util.readarg(stack, base+2);
	stack.length = base + 1;
}

function*rawget(stack, base) {
	let t = util.readarg(stack, base+1);
	if (!(t instanceof Table)) throw "rawget #1: expected table";
	stack[base] = t.get(util.readarg(stack, base+2));
	stack.length = base + 1;
}

function*rawlen(stack, base) {
	if (stack.length != base + 2) {
		throw "rawlen: expected 2 arguments";
	}
	if (typeof stack[base] == "string") {
		stack[base] = stack[base].length;
	} else if (stack[base] instanceof Table) {
		stack[base] = stack[base].array.length;
	} else {
		throw "rawlen #1: expected string or table"
	}
	stack.length = base + 1;
}

function*select(stack, base) {
	let i = util.readarg(stack, base+1);
	if (i === '#') {
		stack[base] = stack.length - base - 1;
	} else {
		if (typeof i != "number") throw "select #1: expected number";
		stack[base] = util.readarg(stack, base+i+1);
	}
	stack.length = base + 1;
}

function*getmetatable(stack, base) {
	let arg = util.readarg(stack, base+1);
	stack.length = base + 1;
	stack[base] = obj.getmetatable(arg);
}

function*setmetatable(stack, base) {
	let arg2 = util.readarg(stack, base+2);
	stack.length = base + 1;
	obj.setmetatable(stack[base], arg2);
}

function*io_write(stack, base) {
	for (var i=base+1; i<stack.length; i++) {
		console.log(stack[i]);
	}
	stack.length = base;
}

function*os_clock(stack, base) {
	stack[base] = new Date()/1000;
	stack.length = base + 1;
}

function*os_difftime(stack, base) {
	stack[base] = util.readarg(stack, base+1) - util.readarg(stack, base+2);
	stack.length = base + 1;
}

function*table_concat(stack, base) {
	let t = util.readarg(stack, base+1);
	if (!(t instanceof Table)) throw "table.concat #1: expected table";
	if (!t.array.length) return '';
	let sep = util.readarg(stack, base+2);
	if (sep === null) sep = '';
	let i = util.readarg(stack, base+3);
	if (i === null) i = 1;
	let j = util.readarg(stack, base+4);
	if (j === null) j = t.array.length - 1;
	if (i > j) return '';
	let ret = '';
	while (i <= j) {
		let val = t.array[i];
		if (typeof val != "number" && typeof val != "string") throw "table.concat: expected sequence of numbers & strings";
		ret += t.array[i];
	}
	stack[base] = ret;
	stack.length = base + 1;
}

function*table_insert(stack, base) {
	if (base == stack.length - 2) {
		let t = stack[base+1];
		if (!(t instanceof Table)) throw "table.insert #1: expected table";
		t.array.push(stack[base+2]);
	} else if (base == stack.length - 3) {
		let t = stack[base+1];
		if (!(t instanceof Table)) throw "table.insert #1: expected table";
		let idx = stack[base+2];
		if (typeof idx != "number") throw "table.insert #2: expected number";
		t.array.splice(stack[base+2], 0, stack[base+3]);
	} else {
		throw "table.insert: wrong number of arguments";
	}
	stack.length = base;
}

function*table_pack(stack, base) {
	let t = new Table();
	t.array = stack.slice(base + 1);
	t.set("n", stack.length - base - 1);
	stack[base] = t;
	stack.length = base + 1;
}

function*table_unpack(stack, base) {
	let t = util.readarg(stack, base+1);
	if (!(t instanceof Table)) throw "table.unpack #1: expected table";
	let i = util.readargor(stack, base+2, 1);
	let j = util.readargor(stack, base+3, t.array.length - 1);
	stack.length = base;
	while (i<=j) stack.push(t.array[i++]);
}

function*table_remove(stack, base) {
	let t = util.readarg(stack, base+1);
	if (!(t instanceof Table)) throw "table.unpack #1: expected table";
	let i = util.readarg(stack, base+2);
	if (i === null) {
		t.array.pop();
		stack.length = base;
	} else {
		if (typeof i != "number") throw "table.unpack #2: expected number";
		if (t.array.length == 0 && i === 0) {
			stack.length = base;
		} else if (i > 0 && i < t.array.length) {
			stack[base] = t.array.splice(i, 1)[0];
			stack.length = base + 1;
		} else {
			throw "position out of bounds";
		}
	}
}

function*table_sort(stack, base) {
	let t = readarg(stack, base+1), comp = readarg(stack, base+2);
	if (!(t instanceof Table)) throw "table.unpack #1: expected table";
	if (comp === null) {
		t.array.sort();
	} else {
		throw "TODO";
	}
}

function*math_abs(stack, base) {
	stack[base] = Math.abs(stack[base+1]);
	stack.length = base + 1;
}

function*math_acos(stack, base) {
	stack[base] = Math.acos(stack[base+1]);
	stack.length = base + 1;
}

function*math_asin(stack, base) {
	stack[base] = Math.asin(stack[base+1]);
	stack.length = base + 1;
}

function*math_atan(stack, base) {
	let x = util.readarg(stack, base+1), y = util.readarg(stack, base+2);
	stack[base] = y === null ? Math.atan(x) : Math.atan2(x, y);
	stack.length = base + 1;
}

function*math_ceil(stack, base) {
	stack[base] = Math.ceil(stack[base+1]);
	stack.length = base + 1;
}

function*math_cos(stack, base) {
	stack[base] = Math.cos(stack[base+1]);
	stack.length = base + 1;
}

function*math_deg(stack, base) {
	stack[base] = stack[base+1] * (180 / Math.PI);
	stack.length = base + 1;
}

function*math_exp(stack, base) {
	stack[base] = Math.exp(stack[base+1]);
	stack.length = base + 1;
}

function*math_floor(stack, base) {
	stack[base] = Math.floor(stack[base+1]);
	stack.length = base + 1;
}

function*math_log(stack, base) {
	let n = util.readarg(stack, base+1);
	let b = util.readarg(stack, base+2);
	stack[base] = b === null ? Math.log(n) : Math.log(n, b);
	stack.length = base + 1;
}

function*math_log10(stack, base) {
	stack[base] = Math.log10(stack[base+1]);
	stack.length = base + 1;
}

function*math_modf(stack, base) {
	stack[base+1] = stack[base]%1;
	stack[base] >>= 0;
	stack.length = base + 2;
}

function*math_rad(stack, base) {
	stack[base] = stack[base+1] * (Math.PI / 180);
	stack.length = base + 1;
}

function*math_sin(stack, base) {
	stack[base] = Math.sin(stack[base+1]);
	stack.length = base + 1;
}

function*math_sqrt(stack, base) {
	stack[base] = Math.sqrt(stack[base+1]);
	stack.length = base + 1;
}

function*math_tan(stack, base) {
	stack[base] = Math.tan(stack[base+1]);
	stack.length = base + 1;
}

function*math_tointeger(stack, base) {
	let v = stack[base+1];
	stack[base] = v === v|0 ? v : null;
	stack.length = base + 1;
}

function*math_type(stack, base) {
	let v = stack[base+1];
	stack[base] = v === v|0 ? "integer" : "float";
	stack.length = base + 1;
}

function*math_ult(stack, base) {
	let u32 = new Uint32Array([stack[base+1], stack[base+2]]);
	stack[base] = u32[0] < u32[1];
	stack.length = base + 1;
}

function*coroutine_create(stack, base) {
	stack[base] = new Thread(stack, base);
	stack.length = base + 1;
}

function*coroutine_resume(stack, base) {
	let thread = util.readarg(stack, base+1);
	if (!(thread instanceof Thread)) throw "coroutine.resume #1: expected thread";
	try {
		yield*thread.resume(stack, base, base+2);
		stack.splice(base, 0, true);
	} catch (e) {
		stack.length = base + 2;
		stack[base] = false;
		stack[base+1] = e;
	}
}

function*coroutine_status(stack, base) {
	let thread = util.readarg(stack, base+1);
	if (!(thread instanceof Thread)) throw "coroutine.status #1: expected thread";
	stack[base] = thread.status;
	stack.length = base + 1;
}

function*coroutine_yield(stack, base) {
	stack.splice(base, 1);
	yield;
}

function coroutine_wrap(stack, base) {
	let thread = util.readarg(stack, base+1);
	if (!(thread instanceof Thread)) throw "coroutine.status #1: expected thread";
	stack[base] = function*(stack, base){
		yield*thread.resume(stack, base, base+1);
	};
	stack.length = base + 1;
}
