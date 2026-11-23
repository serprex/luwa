// rt.wasm keeps Lua values as WasmGC objects, so JS holds them directly

const wasmurl = new URL('rt.wasm', import.meta.url);
const isnode = typeof process !== 'undefined' && process.versions && process.versions.node;
const rtwa = isnode ?
	// node has fetch too, but it can't fetch file: urls
	import('node:fs/promises').then(fs => fs.readFile(wasmurl)) :
	fetch(wasmurl, {cache:'no-cache'}).then(r => r.arrayBuffer());
// files & processes, only under node
const [nodefs, nodecp] = isnode ?
	await Promise.all([import('node:fs'), import('node:child_process')]) : [null, null];

async function rtwathen(ab) {
	const ffi = new FFI();
	const host = {
		echoobj: x => {
			const v = ffi.obj2js(x);
			console.log(v instanceof Uint8Array ? new TextDecoder().decode(v) : v);
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
		host: (op, a, b) => ffi.host(op, a, b),
		jitreq: fn => ffi.jit && ffi.jit.queue.push(fn),
	};
	const inst = await WebAssembly.instantiate(ab, {'': host});
	ffi.mod = inst.instance.exports;
	const nojit = isnode && process.env.LUWA_NOJIT;
	ffi.jit = nojit ? null : new JIT(host, ffi.mod);
	return ffi;
}

// The JIT. rt.wasm joins the code for a batch of hot functions into a module
// in its memory (rt/jit.lua), this compiles it & gives each function its code
function JIT(host, mod) {
	this.imports = { '': host, rt: mod };
	this.mod = mod;
	// functions that got hot since the last flush
	this.queue = [];
}
// Compile what got hot into one module, creating a module has a fixed cost
JIT.prototype.flush = function() {
	const m = this.mod, fns = this.queue;
	this.queue = [];
	if (!fns.length) return;
	const t0 = JIT.time && performance.now();
	const start = m.jitbegin(fns.length);
	// 0 for a function the JIT can't handle, its export is there but not used
	const ok = fns.map(fn => m.jitbody(fn));
	const len = m.jitend();
	const t1 = JIT.time && performance.now();
	let inst;
	try {
		inst = new WebAssembly.Instance(new WebAssembly.Module(new Uint8Array(m.jitmem.buffer, start, len)), this.imports);
	} catch (e) {
		// a bug in the JIT. Keep interpreting
		console.error('jit:', e.message);
		return;
	}
	if (JIT.time) {
		JIT.time.join += t1 - t0;
		JIT.time.compile += performance.now() - t1;
		JIT.time.fns += fns.length;
		JIT.time.bytes += len;
	}
	for (let i = 0; i < fns.length; i++) if (ok[i]) m.jitset(fns[i], inst.exports['f' + i]);
}
// LUWA_JITTIME=1 prints how long joining & compiling took
JIT.time = isnode && process.env.LUWA_JITTIME ? { join: 0, compile: 0, fns: 0, bytes: 0 } : null;
if (JIT.time) process.on('exit', () => {
	const t = JIT.time;
	console.error(`jit: ${t.fns} fns, ${t.bytes} bytes, join ${t.join.toFixed(2)}ms, compile ${t.compile.toFixed(2)}ms`);
});
export default function mkrt() {
	return rtwa.then(rtwathen);
}

function FFI() {
	this.mod = null;
	// open files for _luwa.host, by number. 0 1 2 are stdin, stdout, stderr
	this.files = [{ pos: 0, data: null, fd: 0 }, { pos: 0, data: null, fd: 1 }, { pos: 0, data: null, fd: 2 }];
}
FFI.prototype.newtbl = function() {
	return this.mod.newtbl();
}
FFI.prototype.newstr = function(s) {
	if (typeof s === "string") s = new TextEncoder().encode(s);
	const o = this.mod.newstr(s.length);
	for (let i = 0; i < s.length; i++) {
		this.mod.strset(o, i, s[i]);
	}
	return o;
}
FFI.prototype.newf64 = function(f) {
	return this.mod.newf64(f);
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
			return v === null ? null : !!m.boolval(v);
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
// _luwa.host(op, a, b) from Lua. Ops get Lua values & give one back
FFI.prototype.host = function(op, a, b) {
	const m = this.mod;
	const str = v => new TextDecoder().decode(this.strbytes(v));
	const ret = v => {
		if (v === null || v === undefined) return null;
		if (v === true) return m.newbool(1);
		if (v === false) return m.newbool(0);
		if (typeof v === 'bigint') return m.newi64(v);
		if (typeof v === 'number') return m.newf64(v);
		if (typeof v === 'string' || v instanceof Uint8Array) return this.newstr(v);
		throw new Error('host: bad result ' + v);
	};
	const fd = () => this.files[Number(m.intval(a))];
	switch (str(op)) {
		case 'open': {
			const name = str(a), mode = str(b);
			try {
				const f = { pos: 0, data: null, fd: -1 };
				if (mode[0] == 'r' && !mode.includes('+')) {
					f.data = nodefs.readFileSync(name);
				} else {
					f.fd = nodefs.openSync(name, mode.replace('b', ''));
				}
				this.files.push(f);
				return ret(BigInt(this.files.length - 1));
			} catch (e) {
				return ret(`${name}: ${e.code == 'ENOENT' ? 'No such file or directory' : e.message}`);
			}
		}
		case 'popen': {
			try {
				const data = nodecp.execSync(str(a), { stdio: ['inherit', 'pipe', 'inherit'], maxBuffer: 1 << 30 });
				this.files.push({ pos: 0, data, fd: -1 });
				return ret(BigInt(this.files.length - 1));
			} catch (e) {
				return ret(e.message);
			}
		}
		case 'read': {
			// fmt is 'a', 'l', 'L', or a byte count
			const f = fd();
			if (f.data === null) {
				f.data = f.fd == 0 && nodefs ? nodefs.readFileSync(0) : new Uint8Array(0);
			}
			const d = f.data, n = d.length;
			if (m.typeof(b) == 0) {
				const cnt = Number(m.intval(b));
				if (f.pos >= n && cnt > 0) return null;
				const r = d.subarray(f.pos, f.pos + cnt);
				f.pos += r.length;
				return ret(r);
			}
			const fmt = str(b);
			if (fmt == 'a') {
				const r = d.subarray(f.pos);
				f.pos = n;
				return ret(r);
			}
			if (f.pos >= n) return null;
			let e = d.indexOf(10, f.pos);
			if (e == -1) e = n;
			const r = d.subarray(f.pos, fmt == 'L' && e < n ? e + 1 : e);
			f.pos = Math.min(e + 1, n);
			return ret(r);
		}
		case 'write': {
			const f = fd(), bytes = this.strbytes(b);
			if (nodefs) nodefs.writeSync(f.fd, bytes);
			else console.log(new TextDecoder().decode(bytes));
			return 1;
		}
		case 'close': {
			const f = fd();
			if (f.fd > 2) nodefs.closeSync(f.fd);
			f.fd = -1;
			f.data = null;
			return 1;
		}
		case 'flush':
			return 1;
		case 'getenv':
			return isnode ? ret(process.env[str(a)]) : null;
		case 'clock':
			return ret(isnode ? process.cpuUsage().user / 1e6 : performance.now() / 1000);
		case 'time':
			return ret(BigInt(Math.floor(Date.now() / 1000)));
		case 'exit':
			if (isnode) process.exit(Number(m.intval(a)));
			return null;
		case 'remove':
			try {
				nodefs.unlinkSync(str(a));
				return 1;
			} catch (e) {
				return ret(`${str(a)}: ${e.message}`);
			}
		default:
			throw new Error('host: unknown op ' + str(op));
	}
}

// Lua traceback of the running coro, read from its frames. For wasm traps,
// where the Lua state is left as it was when the op trapped
FFI.prototype.traceback = function() {
	const m = this.mod, out = [], n = m.framelen();
	const key = s => this.newstr(s);
	const kshort = key('short_src'), klines = key('lines'), kwhat = key('what'), kdef = key('linedefined');
	// like C Lua only the first 10 & last 11 frames, deep recursion has millions
	const skipfrom = n > 22 ? 10 : n, skipto = n > 22 ? n - 11 : n;
	let above = -1, inC = false;
	for (let i = 0; i < n; i++) {
		const ty = m.framefield(i, 0), pc = m.framefield(i, 1), base = m.framefield(i, 2);
		// a frame under a call type frame (3) is an outer call that hasn't started
		const pending = above === 3;
		above = ty;
		if (i >= skipfrom && i < skipto) {
			if (i === skipfrom) out.push(`...\t(skipping ${skipto - skipfrom} frames)`);
			inC = false;
			continue;
		}
		if (pending) continue;
		// the main init frame (type 1, retb 0) shows no function
		const main = ty === 1 && m.framefield(i, 4) === 0;
		const fn = !main && base > 0 && base <= m.stacksize() ? m.stackget(base - 1) : null;
		const info = fn === null ? null : m.fninfo(fn);
		if (info === null) {
			// builtins & prelude functions, one line for a run of them
			if (!inC) out.push('[C]: in ?');
			inC = true;
			continue;
		}
		inC = false;
		// pc is just past the frame's current op, except on top where the op hasn't finished
		const at = i === 0 ? pc + 1 : pc;
		const lines = m.tblget(info, klines);
		let line = -1;
		for (let k = 1; ; k += 2) {
			const p = m.tblget(lines, m.newi64(BigInt(k)));
			if (p === null || Number(m.intval(p)) > at - 1) break;
			line = Number(m.intval(m.tblget(lines, m.newi64(BigInt(k + 1)))));
		}
		const str = v => new TextDecoder().decode(this.strbytes(v));
		const src = str(m.tblget(info, kshort));
		const what = str(m.tblget(info, kwhat));
		const desc = what === 'main' ? 'main chunk' : `function <${src}:${m.intval(m.tblget(info, kdef))}>`;
		out.push(`${src}:${line > 0 ? line + ':' : ''} in ${desc}`);
	}
	return 'stack traceback:\n\t' + out.join('\n\t');
}
FFI.prototype.evalWait = function() {
	return new Promise((resolve, reject) =>
		(function core(ffi, mod) {
			// run many steps per host round trip
			try {
				for (let i = 0; i < 10000; i++) {
					if (mod.eval()) return resolve();
					if (ffi.jit && ffi.jit.queue.length) ffi.jit.flush();
				}
			} catch (e) {
				// a wasm trap, like Error's unreachable. Add where Lua was
				try {
					const tb = ffi.traceback();
					e.luaTraceback = tb;
					if (typeof e.stack === 'string') e.stack += '\nLua ' + tb;
				} catch (e2) {}
				return reject(e);
			}
			setImmediate(core, ffi, mod);
		})(this, this.mod)
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
FFI.prototype.compile = function(env, str) {
	const loadfn = this.mod.tblget(env, this.newstr('load'));
	if (loadfn === null) throw new Error("_ENV missing 'load' function");
	return this.rawexec(loadfn, str);
}
FFI.prototype.eval = async function(env, str, ...param) {
	const fn = await this.compile(env, str);
	if (fn === null) throw new Error("Failed to compile");
	return this.obj2js(await this.rawexec(fn, ...param));
}
