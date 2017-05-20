const rtwa = fetch('rt.wasm').then(r => r.arrayBuffer());
module.exports = imp => rtwa.then(
	ab => {
		const mem = new WebAssembly.Memory({initial:1});
		return WebAssembly.instantiate(ab, {'':{m: mem}}).then(mod => [mod, mem]);
	}
);
