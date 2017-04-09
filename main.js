#!/bin/node --expose-wasm
var lua = require("./luwa");
var fs = require("fs");
function readline() {
	var ret = "";
	var buf = new Buffer(1);
	while (true) {
		var bytesRead = fs.readSync(process.stdin.fd, buf, 0, 1);
		if (!bytesRead || buf[0] == 10) return ret;
		ret += String.fromCharCode(buf[0]);
	}
}
fs.readFile(process.argv[process.argv.length-1], 'utf8', (err, src) => {
	lua.runSource(src, { "": {
		p: x => process.stdout.write(x + " "),
		q: x => process.stdout.write(String.fromCharCode(x)),
		i: () => readline()|0,
		c: () => readline().charCodeAt(0)|0,
		m: new WebAssembly.Memory({ initial: 1 }),
	}});
});
