#!/bin/node
'use strict';
const readline = require('readline'),
	rt = require('./rt'),
	pjson = require('./package.json');

rt().then(async runt => {
	runt.mod.genesis();
	const env = runt.mkref(runt.mod.initPrelude());
	await runt.evalWait();
	if (process.argv.length < 3) {
		if (process.stdin.isTTY) {
			console.log(`Luwa ${pjson.version} https://github.com/serprex/luwa`);
			return;
			const rl = readline.createInterface({
				input: process.stdin,
				output: process.stdout,
				prompt: '> ',
			});
			rl.on('line', async ioline => {
				const line = runt.newstr(ioline.replace(/^\s*=/, 'return '));
				try {
					console.log(await runt.eval(env, line));
				} catch (e) {
					console.log(e);
				}
				runt.free(line);
			}).on('close', () => process.exit(0));
			rl.prompt();
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
