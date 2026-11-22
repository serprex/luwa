#!/usr/bin/env node
import assert from "node:assert";
import mkrt from "../rt.js";

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
	// numbers as strings, compared with Lua 5.5
	["return tostring(1)", "1"],
	["return tostring(nil)", "nil"],
	["return 1 .. ''", "1"],
	["return -12 .. 'x'", "-12x"],
	["return math.mininteger .. ''", "-9223372036854775808"],
	["return tostring(true)", "true"],
	["return 1.5 .. ''", "1.5"],
	["return 2.0 .. ''", "2.0"],
	["return -0.0 .. ''", "-0.0"],
	["return 0.1 + 0.2 .. ''", "0.30000000000000004"],
	["return 1e100 .. ''", "1e+100"],
	["return 1e-5 .. ''", "1e-05"],
	["return 0.0001 .. ''", "0.0001"],
	["return 1e14 .. ''", "100000000000000.0"],
	["return 1e15 .. ''", "1e+15"],
	["return 1e13 .. ''", "10000000000000.0"],
	["return 1/0 .. ''", "inf"],
	["return -1/0 .. ''", "-inf"],
	["return 5e-324 .. ''", "4.94065645841247e-324"],
	["return 1/3 .. ''", "0.33333333333333331"],
	["return 9223372036854775808 .. ''", "9.2233720368547758e+18"],
	["return 0.3 == 3/10", true],
	["return 2.2250738585072011e-308 .. ''", "2.2250738585072009e-308"],
	["return 1.7976931348623158e308 .. ''", "1.7976931348623157e+308"],
	["local a = {b = {}} function a.b.f() return 1 end return a.b.f()", 1],
	// string coercion, tonumber & tostring
	["return '10' + 1", 11],
	["return '0x10' * 2", 32],
	["return ' 1.5 ' + 0", 1.5],
	["return -'2'", -2],
	["return tonumber('  -7  ')", -7],
	["return tonumber('1e')", null],
	["return tonumber('0x')", null],
	["return tonumber('1 2')", null],
	["return tonumber('.5')", 0.5],
	["return tonumber('-9223372036854775808') == math.mininteger", true],
	["return tonumber('z', 36)", 35],
	["return tonumber('-ff', 16)", -255],
	["local t = {} return tostring(t) == tostring(t)", true],
	["return tostring({}) ~= tostring({})", true],
	// pcall & error
	["return select(2, pcall(function() error('x') end))", "x"],
	["return select('#', pcall(function() return 1, 2, 3 end))", 4],
	["local ok = pcall(error, 'x') return ok", false],
	["return select(2, pcall(function() local t = nil return t + 1 end))", "invalid operation"],
	["local ok, e = pcall(function() error({code = 7}) end) return e.code", 7],
	["local ok, e = pcall(function() pcall(error, 1) error(2) end) return e", 2],
	["local function f(n) if n == 0 then error('deep') end return f(n-1) end return select(2, pcall(f, 50))", "deep"],
	["local f, e = load('return 1 +') return type(e)", "string"],
	// coroutines
	["local co = coroutine.create(function() coroutine.yield(1) end) local ok, v = coroutine.resume(co) return v", 1],
	["local co = coroutine.create(function(a, b) local c = coroutine.yield(a + b) local d, e = coroutine.yield(c * 2) return d + e end) local _, x = coroutine.resume(co, 1, 2) local _, y = coroutine.resume(co, 10) local _, z = coroutine.resume(co, 3, 4) return x * 10000 + y * 100 + z", 32007],
	["local co = coroutine.create(function() return 1 end) coroutine.resume(co) return coroutine.status(co)", "dead"],
	["local co = coroutine.create(function() coroutine.yield() end) coroutine.resume(co) return coroutine.status(co)", "suspended"],
	["local co co = coroutine.create(function() return coroutine.status(co) end) local _, s = coroutine.resume(co) return s", "running"],
	["local co = coroutine.create(function() end) coroutine.resume(co) return select(2, coroutine.resume(co))", "cannot resume dead coroutine"],
	["local co = coroutine.create(function() error('boom') end) local ok, e = coroutine.resume(co) return tostring(ok) .. e .. coroutine.status(co)", "falseboomdead"],
	["local s = 0 for v in coroutine.wrap(function() for i = 1, 5 do coroutine.yield(i) end end) do s = s + v end return s", 15],
	["local co = coroutine.wrap(function() return coroutine.isyieldable() end) return co()", true],
	["return coroutine.isyieldable()", false],
	["local inner = coroutine.wrap(function() coroutine.yield(1) coroutine.yield(2) end) local outer = coroutine.wrap(function() coroutine.yield(inner() + 10) coroutine.yield(inner() + 20) end) return outer() + outer()", 33],
	["local co = coroutine.create(function() local ok, e = pcall(function() coroutine.yield(1) error('in') end) coroutine.yield(e) return 'end' end) local _, a = coroutine.resume(co) local _, b = coroutine.resume(co) local _, c = coroutine.resume(co) return a .. b .. c", "1inend"],
	["return select(2, pcall(coroutine.yield, 1))", "attempt to yield from outside a coroutine"],
	// string library
	["return ('hello'):sub(2, -2)", "ell"],
	["return ('hello'):sub(9)", ""],
	["return select(2, ('hello world'):find('o w'))", 7],
	["return ('a.b'):find('.', 1, true)", 2],
	["return ('key = val'):match('(%w+)%s*=%s*(%w+)')", "val"],
	["return ('x(a(b)c)y'):match('%b()')", "(a(b)c)"],
	["return (('THE (quick) fox'):find('%f[%a]%a+', 5))", 6],
	["return (string.gsub('hello world', 'o', '0'))", "hell0 w0rld"],
	["return select(2, string.gsub('abc', '%w', '%0%0'))", 3],
	["return (string.gsub('abc', '%w', {a = 1, b = false}))", "1bc"],
	["return (string.gsub('hello', '', '-'))", "-h-e-l-l-o-"],
	["return (string.gsub('abc', '(%w)', function(c) return c:upper() .. '.' end))", "A.B.C."],
	["local s = '' for k, v in string.gmatch('a=1, b=2', '(%w+)=(%w+)') do s = s .. k .. v end return s", "a1b2"],
	["return string.rep('ab', 3, '-')", "ab-ab-ab"],
	["return ('MiXeD'):lower() .. ('MiXeD'):upper()", "mixedMIXED"],
	["return ('abc'):reverse()", "cba"],
	["return string.format('%5d|%-5s|%05.1f|%x|%X', 42, 'ab', 3.14159, 255, 255)", "   42|ab   |003.1|ff|FF"],
	["return string.format('%g %g %g', 1e20, 0.0001, 100)", "1e+20 0.0001 100"],
	["return string.format('%q', 'a\\nb\\\"\\0')", "\"a\\\nb\\\"\\0\""],
	["return string.format('%s %s %%', nil, 1.5)", "nil 1.5 %"],
	["return string.format('%.3s', 'abcdef')", "abc"],
	["return string.format('%d', -9223372036854775807 - 1)", "-9223372036854775808"],
	["return string.unpack('<i8', string.pack('<i8', -5))", 9],
	["return (string.unpack('<i8', string.pack('<i8', -5)))", -5],
	["return (string.unpack('>I2', '\\1\\2'))", 258],
	["return (string.unpack('<d', string.pack('<d', 1.5)))", 1.5],
	["return (string.unpack('<s4', string.pack('<s4', 'abc')))", "abc"],
	["return (string.unpack('z', 'ab\\0c'))", "ab"],
	["return #string.pack('<i2i3', 1, 2)", 5],
	["return utf8.len('h\\u{e9}llo')", 5],
	["return select(2, utf8.len('a\\xff'))", 2],
	["return utf8.char(72, 233, 0x20ac)", "H\u00e9\u20ac"],
	// table library
	["return table.concat({1, 2, 'x'}, ', ')", "1, 2, x"],
	["return table.concat({}, ',')", ""],
	["return select('#', table.unpack({1, 2, 3}))", 3],
	["return select(2, table.unpack({1, 2, 3}, 2))", 3],
	["local t = table.move({1, 2, 3}, 1, 3, 2) return t[1] + t[2] * 10 + t[3] * 100 + t[4] * 1000", 3211],
	["local t = {3, 1, 2} table.sort(t) return t[1] * 100 + t[2] * 10 + t[3]", 123],
	// io, os, require
	["return io.type(io.stdout)", "file"],
	["return io.type(42) == nil", true],
	["return #io.open('package.json'):read('a') > 0", true],
	["return select(2, io.open('no/such/file')) ~= nil", true],
	["local f = io.open('package.json') local l = f:read('l') f:close() return l", "{"],
	["local f = io.open('package.json') f:close() return io.type(f)", "closed file"],
	["local n = 0 for l in io.lines('package.json') do n = n + 1 end return n > 1", true],
	["return type(os.getenv('PATH'))", "string"],
	["return os.getenv('no such var surely')", null],
	["return require('string') == string", true],
	["return (package.searchpath('rt.sys', './?.lua'))", "./rt/sys.lua"],
	["return #require('rt.sys') > 0", true],
	["return select(2, pcall(require, 'no.such.mod')):sub(1, 25)", "module 'no.such.mod' not "],
	["local i = 0 local f = load(function() i = i + 1 return ({'return ', '4'})[i] end) return f()", 4],
	["local t = setmetatable({}, {__newindex = function(t, k, v) rawset(t, k, v * 2) end}) t.a = 2 return t.a", 4],
	["local t = setmetatable({}, {__call = function(self, x) return x end}) return t(5)", 5],
	["return math.tointeger(3.0)", 3],
	["return math.tointeger(3.5) == nil", true],
];

// Source that should raise an error
const errors = [
	"return (string.gsub('abc', '%w', {a = true}))",
	"return ('x'):rep(2, {})",
	"return #5",
	"return -{}",
	"return {} + 1",
	"return {} < {}",
	"local t = nil t.x = 1",
	"local t = {} t.x.y = 1",
	"return 7 // 0",
	"return 'a' + 1",
];

// Known gaps (see plans/plan.md). Reported, but don't fail the run
const todo = [
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
