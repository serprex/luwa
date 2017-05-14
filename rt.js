const rtwa = fetch('rt.wasm').then(r => r.arrayBuffer());
module.exports = imp => rtwa.then(
	ab => WebAssembly.instantiate(ab, {'':{m: new WebAssembly.Memory({initial:1}), r:Math.random}})
);
