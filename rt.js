// rt.wasm keeps Lua values as WasmGC objects, so JS holds them directly
import * as util from './util.js';

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
	const inst = await WebAssembly.instantiate(ab, {'':{
		echo: x => {
			console.log(x);
			return x;
		},
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
	}});
	ffi.mod = inst.instance.exports;
	return ffi;
}
export default function mkrt() {
	return rtwa.then(rtwathen);
}

// Handles are left from when the GC moved objects. Now they only wrap a value
function Handle(val) {
	this.val = val;
}
function FFI() {
	this.mod = null;
	// open files for _luwa.host, by number. 0 1 2 are stdin, stdout, stderr
	this.files = [{ pos: 0, data: null, fd: 0 }, { pos: 0, data: null, fd: 1 }, { pos: 0, data: null, fd: 2 }];
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
// _luwa.host(op, a, b) from Lua. Ops get Lua values & give one back
FFI.prototype.host = function(op, a, b) {
	const m = this.mod;
	const str = v => new TextDecoder().decode(this.strbytes(v));
	const ret = v => {
		if (v === null || v === undefined) return null;
		if (v === true) return 1;
		if (v === false) return 0;
		if (typeof v === 'bigint') return m.newi64(v);
		if (typeof v === 'number') return m.newf64(v);
		if (typeof v === 'string' || v instanceof Uint8Array) return this.newstr(v).val;
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
		case 'fmt':
			return ret(fmtnum(str(a), m.typeof(b) == 0 ? m.intval(b) : m.fltval(b)));
		default:
			throw new Error('host: unknown op ' + str(op));
	}
}

// One printf spec like %5.2f, for string.format. x is a BigInt for integer specs, else a number
function fmtnum(spec, x) {
	const [, flags, width, prec, conv] = spec.match(/^%([-+ #0]*)(\d*)(?:\.(\d*))?([a-zA-Z])$/);
	const p = prec === undefined ? -1 : +prec;
	let sign = '', body;
	if ('dioxXuc'.includes(conv)) {
		if (conv == 'c') return String.fromCharCode(Number(x));
		let n = BigInt(x);
		if (conv == 'd' || conv == 'i') {
			if (n < 0n) {
				sign = '-';
				n = -n;
			}
			body = n.toString();
		} else {
			n = BigInt.asUintN(64, n);
			body = n.toString(conv == 'o' ? 8 : conv == 'u' ? 10 : 16);
			if (conv == 'X') body = body.toUpperCase();
		}
		if (p >= 0) body = p == 0 && n == 0n ? '' : body.padStart(p, '0');
		if (flags.includes('#') && n != 0n) {
			if (conv == 'x') body = '0x' + body;
			if (conv == 'X') body = '0X' + body;
			if (conv == 'o' && body[0] != '0') body = '0' + body;
		}
	} else {
		x = Number(x);
		const neg = x < 0 || Object.is(x, -0);
		if (neg) {
			sign = '-';
			x = -x;
		}
		const up = conv == conv.toUpperCase(), lc = conv.toLowerCase();
		const alt = flags.includes('#');
		if (!isFinite(x)) {
			body = isNaN(x) ? 'nan' : 'inf';
		} else if (lc == 'f') {
			body = fixed(x, p < 0 ? 6 : p);
			if (alt && p == 0) body += '.';
		} else if (lc == 'e') {
			body = expo(x, p < 0 ? 6 : p);
			if (alt && p == 0) body = body.replace('e', '.e');
		} else if (lc == 'g') {
			const P = p < 0 ? 6 : p == 0 ? 1 : p;
			const X = x == 0 ? 0 : +x.toExponential(P - 1).split('e')[1];
			body = P > X && X >= -4 ? fixed(x, P - 1 - X) : expo(x, P - 1);
			if (!alt && body.includes('.')) body = body.replace(/\.?0+(e|$)/, '$1');
		} else if (lc == 'a') {
			body = hexfloat(x, p);
		} else {
			throw new Error('invalid conversion ' + spec);
		}
		if (up) body = body.toUpperCase();
	}
	if (!sign) {
		if (flags.includes('+')) sign = '+';
		else if (flags.includes(' ')) sign = ' ';
	}
	const w = +width || 0;
	let out = sign + body;
	if (out.length < w) {
		if (flags.includes('-')) out = out.padEnd(w);
		else if (flags.includes('0') && conv != 'c' && conv != 's' && (isFinite(Number(x)) || typeof x == 'bigint') && !(p >= 0 && 'dioxXu'.includes(conv))) {
			const pre = body.match(/^0[xX]/) ? body.slice(0, 2) : '';
			out = sign + pre + body.slice(pre.length).padStart(w - sign.length - pre.length, '0');
		} else out = out.padStart(w);
	}
	return out;
}
// x >= 0 with d digits after the point. toFixed goes exponential past 1e21
function fixed(x, d) {
	if (x < 1e21) return x.toFixed(Math.min(d, 100)) + (d > 100 ? '0'.repeat(d - 100) : '');
	return BigInt(x).toString() + (d > 0 ? '.' + '0'.repeat(d) : '');
}
// x >= 0 as d.ddde+XX, at least 2 exponent digits like C
function expo(x, d) {
	const [m, e] = x.toExponential(Math.min(d, 100)).split('e');
	const en = +e;
	return m + (d > 100 ? '0'.repeat(d - 100) : '') + 'e' + (en < 0 ? '-' : '+') + String(Math.abs(en)).padStart(2, '0');
}
// x >= 0 as 0x1.hhhp+e, the way glibc does %a
function hexfloat(x, p) {
	if (x == 0) return '0x0' + (p > 0 ? '.' + '0'.repeat(p) : '') + 'p+0';
	const dv = new DataView(new ArrayBuffer(8));
	dv.setFloat64(0, x);
	const bits = dv.getBigUint64(0);
	let e = Number(bits >> 52n), frac = bits & ((1n << 52n) - 1n), lead = 1n;
	if (e == 0) {
		lead = 0n;
		e = -1022;
	} else e -= 1023;
	let h = frac.toString(16).padStart(13, '0');
	if (p >= 0 && p < 13) {
		// round to p hex digits, half to even
		const sh = BigInt((13 - p) * 4);
		let v = ((lead << 52n) | frac), q = v >> sh, r = v & ((1n << sh) - 1n), half = 1n << (sh - 1n);
		if (r > half || (r == half && (q & 1n))) q++;
		lead = q >> BigInt(p * 4);
		h = p ? (q & ((1n << BigInt(p * 4)) - 1n)).toString(16).padStart(p, '0') : '';
	} else {
		h = h.replace(/0+$/, '');
		if (p > 13) h = h.padEnd(p, '0');
	}
	return '0x' + lead.toString(16) + (h ? '.' + h : '') + 'p' + (e < 0 ? '-' : '+') + Math.abs(e);
}

// Old name, values aren't raw pointers now
FFI.prototype.rawobj2js = function(v) {
	return this.obj2js(v);
}
// Lua traceback of the running coro, read from its frames. For wasm traps,
// where the Lua state is left as it was when the op trapped
FFI.prototype.traceback = function() {
	const m = this.mod, out = [], n = m.framelen();
	const key = s => this.newstr(s).val;
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
		const fn = base > 0 && base <= m.stacksize() ? m.stackget(base - 1) : null;
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
