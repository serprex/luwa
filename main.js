#!/bin/node
const fs = require("fs"),
	rt = require('./rt');

function readline() {
	var ret = "";
	const buf = new Buffer(1);
	while (true) {
		try {
			const bytesRead = fs.readSync(process.stdin.fd, buf, 0, 1);
			if (!bytesRead || buf[0] == 10) return ret;
			ret += String.fromCharCode(buf[0]);
		} catch (e) {}
	}
}

rt().then(runt => {
	if (process.argv.length < 3) {
		while (true) {
			process.stdout.write("> ");
			const line = readline().replace(/^\s*=/, "return ");
			try {
				console.log(...lua.eval(runt, line));
			} catch (e) {
				console.log("Error:", e);
			}
		}
	} else {
		const lex = require('./lex');
		fs.readFile(process.argv[process.argv.length-1], 'utf8', (err, src) => {
			console.time('lex');
			const l = new lex.Lex2(runt, src);
			console.log(l.lex);
			l.free();
			console.timeEnd('lex');

			/*
			lua.runSource(src, { "": {
				p: x => process.stdout.write(x + " "),
				q: x => process.stdout.write(String.fromCharCode(x)),
				i: () => readline()|0,
				c: () => readline().charCodeAt(0)|0,
				m: new WebAssembly.Memory({ initial: 1 }),
			}});
			*/
		});
	}
}).catch(e => setImmediate(() => { throw e; }));
