#!/usr/bin/env node
"use strict";
const assert = require("assert");
const mkrt = require("../rt");

// rt.js echoes every op through console.log, so mute it while lua runs
const log = console.log;
function quiet(fn) {
	console.log = () => {};
	return fn().finally(() => { console.log = log; });
}

// [source, expected result]. Only the last returned value comes back.
// nil is null, strings are compared as text, big ints come back as BigInt
const cases = [
	// arithmetic
	["return 1+2", 3],
	["return 7 - 10", -3],
	["return 2.5 * 2", 5],
	["return 7 / 2", 3.5],
	["return 7 // 2", 3],
	["return -7 // 2", -4],
	["return 7 % 3", 1],
	["return -7 % 3", 2],
	["return 3 % -2", -1],
	["return 5.5 % 2", 1.5],
	["return 2 ^ 10", 1024],
	["return 1 + 0.5", 1.5],
	["return 10 // 0.0", Infinity],
	["return -5", -5],
	["return -2.5", -2.5],
	// bit ops
	["return 6 & 3", 2],
	["return 6 | 3", 7],
	["return 6 ~ 3", 5],
	["return ~0", -1],
	["return ~5.0", -6],
	["return 1 << 4", 16],
	["return 256 >> 4", 16],
	["return 1 << 64", 0],
	["return -1 >> 1", 0x7fffffffffffffffn],
	// compares & logic
	["return 1 < 2", true],
	["return 2 <= 1", false],
	["return 3 > 2.5", true],
	["return 1 == 1.0", true],
	["return 1 ~= 2", true],
	["return nil == false", false],
	["return 'a' < 'b'", true],
	["return 'b' < 'a'", false],
	["return 'a' < 'ab'", true],
	["return 'ab' < 'a'", false],
	["return 'a' <= 'a'", true],
	["return 'b' > 'a'", true],
	["return 'ab' == 'a' .. 'b'", true],
	["return {} == {}", false],
	["local t = {} return t == t", true],
	["if true == false then return 1 end return 0", 0],
	["return not nil", true],
	["return not 0", false],
	["return nil or 5", 5],
	["return false and 1", false],
	["return 1 and 2", 2],
	// strings & length
	["return #'hello'", 5],
	["return #'' == 0", true],
	["return #{1, 2, 3}", 3],
	["return 'ab' .. 'cd'", "abcd"],
	["local s = '' for i = 1, 3 do s = s .. 'a' end return s", "aaa"],
	// tables
	["local t = {a = 1} t.b = 2 return t.a + t.b", 3],
	["local t = {} t[1] = 5 return t[1]", 5],
	["local t = {x = {y = 3}} return t.x.y", 3],
	["local t = {10, 20, 30, n = 3} return t[2] + t.n", 23],
	["return ({1, 2, 3})[2]", 2],
	["x = 3 * 5 + 2 return x", 17],
	// metamethods
	["local t = setmetatable({}, {__index = function(t, k) return k * 2 end}) return t[21]", 42],
	["local t = setmetatable({}, {__index = {z = 9}}) return t.z", 9],
	["local m = {__add = function(a, b) return 42 end} return setmetatable({}, m) + 1", 42],
	["local m = {__len = function() return 99 end} return #setmetatable({}, m)", 99],
	["local m = {__eq = function() return true end} return setmetatable({}, m) == setmetatable({}, m)", true],
	["local m = {__lt = function() return true end} return setmetatable({}, m) < setmetatable({}, m)", true],
	["local m = {__le = function() return false end} return setmetatable({}, m) >= setmetatable({}, m)", false],
	["local m = {__unm = function() return 4 end} return -setmetatable({}, m)", 4],
	["local m = {__concat = function() return 'c' end} return setmetatable({}, m) .. 'x'", "c"],
	// control flow
	["local y = 0 while y < 17 do y = y + 1 end return y", 17],
	["local n = 0 repeat n = n + 1 until n >= 5 return n", 5],
	["local x = 0 if x > 0 then x = 1 elseif x == 0 then x = 2 else x = 3 end return x", 2],
	["local s = 0 for i = 1, 10 do s = s + i end return s", 55],
	["local s = 0 for i = 10, 1, -2 do s = s + i end return s", 30],
	["local s = 0 for k, v in pairs({a=1, b=2, c=3}) do s = s + v end return s", 6],
	["local s = 0 for i, v in ipairs({4, 5, 6}) do s = s + i * v end return s", 32],
	["goto done do return 1 end ::done:: return 2", 2],
	// functions
	["local function f(a, b) return a * b end return f(6, 7)", 42],
	["local function fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end return fib(15)", 610],
	["local function mk() local c = 0 return function() c = c + 1 return c end end local f = mk() f() f() return f()", 3],
	["local function f() return f2() end function f2() return 7 end return f()", 7],
	["local t = {} t.f = function(self, x) return x + 1 end return t:f(1)", 2],
	["local a = {} function a.f() return 1 end return a.f()", 1],
	["local a, b = 1, 2 a, b = b, a return a - b", 1],
	// varargs
	["local function f(...) return select('#', ...) end return f(1, 2, 3)", 3],
	["local function f(...) local a, b = ... return b end return f(1, 2)", 2],
	["local function f(...) return {...} end return #f(1, 2, 3, 4)", 4],
	["local function f() return 1, 2, 3 end local t = {f()} return #t", 3],
	// builtins
	["return type(1)", "number"],
	["return type('a')", "string"],
	["return type({})", "table"],
	["return type(true)", "boolean"],
	["return type(nil)", "nil"],
	["return math.floor(3.7)", 3],
	["return math.abs(-3)", 3],
	["return math.abs(-3.5)", 3.5],
	["return math.type(1)", "integer"],
	["return math.type(1.0)", "float"],
	["return select(2, 'a', 'b', 'c')", "c"],
	["return rawget({5}, 1)", 5],
];

// Source that should raise an error
const errors = [
	"return #5",
	"return -{}",
	"return {} + 1",
	"return {} < {}",
	"local t = nil t.x = 1",
	"local t = {} t.x.y = 1",
	"return 7 // 0",
];

// Known gaps (see plans/plan.md). Reported, but don't fail the run
const todo = [
	["return tostring(1)", "1"],
	["return tostring(nil)", "nil"],
	["return 1 .. ''", "1"],
	["return '10' + 1", 11],
	["local t = setmetatable({}, {__newindex = function(t, k, v) rawset(t, k, v * 2) end}) t.a = 2 return t.a", 4],
	["local t = setmetatable({}, {__call = function(self, x) return x end}) return t(5)", 5],
	["return select(2, pcall(function() error('x') end))", "x"],
	["local co = coroutine.create(function() coroutine.yield(1) end) local ok, v = coroutine.resume(co) return v", 1],
	["local a = {b = {}} function a.b.f() return 1 end return a.b.f()", 1],
];

// A fresh runtime for each run, an error leaves the vm in a bad state
async function run(src) {
	const rt = await mkrt();
	return quiet(async () => {
		rt.mod.genesis();
		const env = rt.mkref(rt.mod.initPrelude());
		await rt.evalWait();
		const line = rt.newstr(src);
		const v = await rt.eval(env, line);
		return v instanceof Uint8Array ? Buffer.from(v).toString() : v;
	});
}
function same(got, want) {
	return Object.is(got, want) || (typeof want === "number" && got === want);
}
const show = v => typeof v === "bigint" ? v + "n" : JSON.stringify(v) ?? String(v);

(async () => {
	// tables, straight through exports
	const rt = await mkrt();
	await quiet(async () => {
		rt.mod.genesis();
		rt.mkref(rt.mod.initPrelude());
		await rt.evalWait();
	});
	const newt = rt.newtbl();
	const news = rt.newstr("asdf");
	const newf = rt.newf64(4.2);
	assert.equal(rt.mod.tblget(newt.val, news.val), rt.nil.val);
	rt.mod.tblset(newt.val, news.val, newf.val);
	assert.equal(rt.mod.tblget(newt.val, news.val), newf.val);
	rt.free(news);
	rt.free(newf);
	rt.free(newt);

	const fails = [];
	for (const [src, want] of cases) {
		let got;
		try {
			got = await run(src);
		} catch (e) {
			fails.push(`${src}\n  error: ${e.message}`);
			continue;
		}
		if (!same(got, want)) {
			fails.push(`${src}\n  got ${show(got)}, want ${show(want)}`);
		}
	}
	for (const src of errors) {
		let got;
		try {
			got = await run(src);
		} catch (e) {
			continue;
		}
		fails.push(`${src}\n  got ${show(got)}, want an error`);
	}
	for (const [src, want] of todo) {
		let ok = false;
		try {
			ok = same(await run(src), want);
		} catch (e) {}
		if (ok) {
			log(`todo now passes, move it to cases: ${src}`);
		}
	}

	const total = cases.length + errors.length;
	if (fails.length) {
		log(fails.join("\n"));
		log(`${fails.length} of ${total} failed`);
		process.exit(1);
	}
	log(`ok, ${total} passed, ${todo.length} todo`);
})().catch(err => {
	console.log = log;
	console.log(err);
	process.exit(1);
});
