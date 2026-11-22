// rt.wasm keeps Lua values as WasmGC objects, so JS holds them directly
const isnode = typeof process !== 'undefined' && process.versions && process.versions.node;
const rtwa = isnode ?
	// node has fetch too now, so check for node first
	new Promise((resolve, reject) =>
		require('fs').readFile(__dirname + '/rt.wasm',
			(err, data) => err ? reject(err) : resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)))
	) :
	fetch('rt.wasm', {cache:'no-cache'}).then(r => r.arrayBuffer());

async function rtwathen(ab) {
	const ffi = new FFI();
	const inst = await WebAssembly.instantiate(ab, {'':{
		echo: x => {
			console.log(x);
			return x;
		},
		echoobj: x => {
			console.log(ffi.obj2js(x));
		},
		sin: Math.sin,
		cos: Math.cos,
		tan: Math.tan,
		asin: Math.asin,
		acos: Math.acos,
		atan: Math.atan,
		atan2: Math.atan2,
		random: Math.random,
		exp: Math.exp,
		log: Math.log,
		pow: Math.pow,
	}});
	ffi.mod = inst.instance.exports;
	return ffi;
}
module.exports = () => rtwa.then(rtwathen);
const util = require('./util');

// Handles are left from when the GC moved objects. Now they only wrap a value
function Handle(val) {
	this.val = val;
}
function FFI() {
	this.mod = null;
}
FFI.prototype.free = function(h) {}
FFI.prototype.mkref = function(p) {
	return new Handle(p);
}
FFI.prototype.newtbl = function() {
	return this.mkref(this.mod.newtbl());
}
FFI.prototype.newstr = function(s) {
	if (typeof s === "string") s = util.asUtf8(s);
	const o = this.mod.newstr(s.length);
	for (let i = 0; i < s.length; i++) {
		this.mod.strset(o, i, s[i]);
	}
	return this.mkref(o);
}
FFI.prototype.newf64 = function(f) {
	return this.mkref(this.mod.newf64(f));
}
// nil is null, false & true are i31 refs, which JS sees as 0 & 1
FFI.prototype.nil = new Handle(null);
FFI.prototype.false = new Handle(0);
FFI.prototype.true = new Handle(1);
const tys = ["number", "number", null, "table", "string", "vec", "buf", "function", "thread"];
FFI.prototype.gettype = function(h) {
	return tys[this.mod.typeof(h.val)] || (h.val === null ? 'nil' : 'boolean');
}
FFI.prototype.strbytes = function(v) {
	const n = this.mod.strlen(v), r = new Uint8Array(n);
	for (let i = 0; i < n; i++) r[i] = this.mod.strget(v, i);
	return r;
}
FFI.prototype.obj2js = function(v, memo = new Map()) {
	if (memo.has(v)) return memo.get(v);
	const m = this.mod;
	switch (m.typeof(v)) {
		case 0: {
			// int64: a plain number when it fits, else a BigInt
			const n = m.intval(v);
			return Number.isSafeInteger(Number(n)) ? Number(n) : n;
		}
		case 1:
			return m.fltval(v);
		case 2:
			return v === null ? null : !!v;
		case 3: {
			const map = new Map(), r = { hash: map, meta: null };
			memo.set(v, r);
			for (let [k, val] = m.tblnext(v, null); k !== null; [k, val] = m.tblnext(v, k)) {
				map.set(this.obj2js(k, memo), this.obj2js(val, memo));
			}
			r.meta = this.obj2js(m.tblmeta(v), memo);
			return r;
		}
		case 4:
			return this.strbytes(v);
		case 5: {
			const ret = [];
			memo.set(v, ret);
			for (let i = 0, n = m.veclen(v); i < n; i++) {
				ret.push(this.obj2js(m.vecget(v, i), memo));
			}
			return ret;
		}
		case 7:
			return { function: v };
		case 8:
			return { thread: v };
		default:
			return "Unknown type: " + m.typeof(v);
	}
}
// Old name, values aren't raw pointers now
FFI.prototype.rawobj2js = function(v) {
	return this.obj2js(v);
}
FFI.prototype.evalWait = function() {
	return new Promise((resolve, reject) =>
		(function core(mod) {
			// setTimeout waits at least 1ms, so run many steps per wait
			try {
				for (let i = 0; i < 10000; i++) {
					if (mod.eval()) return resolve();
				}
			} catch (e) {
				// a wasm trap, like Error's unreachable
				return reject(e);
			}
			setTimeout(core, 0, mod);
		})(this.mod)
	);
}
FFI.prototype.rawexec = function(fn, ...param) {
	// TODO have a flag for when mid computation?

	this.mod.tmpclear();
	for (const v of param) {
		this.mod.tmppush(v);
	}
	this.mod.init(fn);
	// Resolves to top of stack once done. With several results that's the last one
	return this.evalWait().then(() => this.mod.stacklen() ? this.mod.nthtmp(1) : null);
}
FFI.prototype.exec = function(fn, ...param) {
	return this.rawexec(fn.val, ...param.map(x => x.val))
}
FFI.prototype.compile = function(env, str) {
	const loadstr = this.newstr('load');
	const loadfn = this.mod.tblget(env.val, loadstr.val);
	if (loadfn === null) throw new Error("_ENV missing 'load' function");
	return this.rawexec(loadfn, str.val);
}
FFI.prototype.eval = async function(env, str, ...param) {
	const fn = await this.compile(env, str);
	if (fn === null) throw new Error("Failed to compile");
	return this.obj2js(await this.rawexec(fn, ...param.map(x => x.val)));
}
