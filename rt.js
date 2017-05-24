const rtwa = typeof fetch !== 'undefined' ?
	fetch('rt.wasm').then(r => r.arrayBuffer()) :
	new Promise((resolve, reject) =>
		require('fs').readFile(__dirname + '/rt.wasm',
			(err, data) => err ? reject(err) : resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)))
	);
function rtwathen(ab) {
	const mem = new WebAssembly.Memory({initial:1}), ffi = new FFI(mem);
	return WebAssembly.instantiate(ab, {'':{
		m: mem,
		gcfix: () => {
			let memta = new Uint8Array(mem.buffer);
			for (let h of ffi.handles) {
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
	if (this.handles.delete(h)) {
		this.mod.rmroot(h.val);
	}
}
FFI.prototype.newtable = function() {
	let h = new Handle(this.mod.addroot(this.mod.newtable()));
	this.handles.add(h);
	return h;
}
FFI.prototype.newstr = function(s) {
	if (typeof s === "string") s = util.asUtf8(s);
	let o = this.mod.addroot(this.mod.newstr(s.length));
	let memta = new Uint8Array(this.mem.buffer);
	memta.set(s, o+13);
	let h = new Handle(o);
	this.handles.add(h);
	return h;
}
FFI.prototype.newf64 = function(f) {
	let h = new Handle(this.mod.addroot(this.mod.newf64(f)));
	this.handles.add(h);
	return h;
}
FFI.prototype.gettypeid = function(h) {
	let memta = new Uint8Array(this.mem.buffer);
	return memta[h.val+4];
}
const tys = ["number", "number", "nil", "boolean", "table", "string"];
FFI.prototype.gettype = function(h) {
	let ty = this.gettypeid(h);
	return tys[ty];
}
