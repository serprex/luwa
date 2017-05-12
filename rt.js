const rtwa = fetch('rt.wasm').then(r => r.arrayBuffer());
module.exports = imp => rtwa.then(ab => WebAssembly.instantiate(ab, imp));
