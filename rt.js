const rtwa = typeof fetch !== 'undefined' ?
	fetch('rt.wasm').then(r => r.arrayBuffer()) :
	new Promise((resolve, reject) =>
		require('fs').readFile(__dirname + '/rt.wasm',
			(err, data) => err ? reject(err) : resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)))
	);
module.exports = imp => rtwa.then(
	ab => {
		const mem = new WebAssembly.Memory({initial:1});
		return WebAssembly.instantiate(ab, {'':{m: mem}}).then(mod => [mod, mem]);
	}
);
