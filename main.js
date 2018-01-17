#!/bin/node
'use strict';
const fs = require('fs'),
	rt = require('./rt'),
	pjson = require('./package.json');

function readline() {
	var ret = '';
	const buf = new Buffer(1);
	while (true) {
		try {
			const bytesRead = fs.readSync(process.stdin.fd, buf, 0, 1);
			if (!bytesRead || buf[0] == 10) return ret;
			ret += String.fromCharCode(buf[0]);
		} catch (e) {}
	}
}

rt().then(async runt => {
	runt.mod.genesis();
	const env = runt.mkref(runt.mod.mkenv0());
	runt.mod.mkenv1();
	if (process.argv.length < 3) {
		if (process.stdin.isTTY) {
			console.log(`Luwa ${pjson.version} https://github.com/serprex/luwa`);
			while (true) {
				process.stdout.write('> ');
				const line = runt.newstr(readline().replace(/^\s*=/, 'return '));
				try {
					console.log(await runt.eval(env, line));
				} catch (e) {
					console.log(e);
				}
				runt.free(line);
			}
		} else {
			const result = [];
			process.stdin.resume();
			process.stdin.on('data', buf => result.push(buf));
			process.stdin.on('end', () => {
				const src = Buffer.concat(result);
				runt.eval(env, src.toString());
			});
		}
	} else {
	}
}).catch(e => setImmediate(() => { throw e; }));
