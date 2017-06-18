const rtwa = typeof fetch !== 'undefined' ?
	fetch('rt.wasm', {cache:'no-cache'}).then(r => r.arrayBuffer()) :
	new Promise((resolve, reject) =>
		require('fs').readFile(__dirname + '/rt.wasm',
			(err, data) => err ? reject(err) : resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)))
	);
function rtwathen(ab) {
	const mem = new WebAssembly.Memory({initial:1}), ffi = new FFI(mem);
	return WebAssembly.instantiate(ab, {'':{
		m: mem,
		echo: x => {
			console.log(x);
			return x;
		},
		echo2: (x, y) => {
			console.log(y, x);
			return x;
		},
		gcmark: x => {
			for (const h of ffi.handles) {
				ffi.mod.gcmark(h.val);
			}
		},
		gcfix: () => {
			let memta = new Uint8Array(mem.buffer);
			for (const h of ffi.handles) {
				h.val = util.readuint32(memta, h.val)&-8;
			}
		},
	}}).then(mod => {
		ffi.mod = mod.instance.exports;
		return ffi;
	});
}
module.exports = () => rtwa.then(rtwathen);
const util = require('./util');

function Handle(val) {
	this.val = val;
}
function FFI(mem) {
	this.mod = null;
	this.mem = mem;
	this.handles = new Set();
}
FFI.prototype.free = function(h) {
	this.handles.delete(h);
}
FFI.prototype.mkref = function(p) {
	switch (p) {
		case 0: return this.nil;
		case 4: return this.false;
		case 8: return this.true;
		default:
		let h = new Handle(p);
		this.handles.add(h);
		return h;
	}
}
FFI.prototype.newtable = function() {
	return this.mkref(this.mod.newtable());
}
FFI.prototype.newstr = function(s) {
	if (typeof s === "string") s = util.asUtf8(s);
	let o = this.mod.newstr(s.length);
	let memta = new Uint8Array(this.mem.buffer);
	memta.set(s, o+13);
	return this.mkref(o);
}
FFI.prototype.newf64 = function(f) {
	return this.mkref(this.mod.newf64(f));
}
FFI.prototype.nil = new Handle(0);
FFI.prototype.true = new Handle(8);
FFI.prototype.false = new Handle(16);
FFI.prototype.gettypeid = function(h) {
	let memta = new Uint8Array(this.mem.buffer);
	return memta[h.val+4];
}
const tys = ["number", "number", "nil", "boolean", "table", "string"];
FFI.prototype.gettype = function(h) {
	return tys[this.gettypeid(h)];
}
FFI.prototype.strbytes = function(h) {
	const memta = new Uint8Array(this.mem.buffer);
	const len = util.readuint32(memta, h.val+5);
	return memta.slice(h.val+13, h.val+13+len);
}
