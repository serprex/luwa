#!/usr/bin/env node
import readline from 'node:readline';
import fs from 'node:fs';
import rt from './rt.js';
const pjson = JSON.parse(fs.readFileSync(new URL('package.json', import.meta.url)));

rt().then(async runt => {
	runt.mod.genesis();
	const env = runt.mkref(runt.mod.initPrelude());
	await runt.evalWait();
	if (process.argv.length < 3) {
		if (process.stdin.isTTY) {
			console.log(`Luwa ${pjson.version} https://github.com/serprex/luwa`);
			const rl = readline.createInterface({
				input: process.stdin,
				output: process.stdout,
				prompt: '> ',
			});
			// the vm has one stack, so run lines one at a time
			let pending = Promise.resolve();
			rl.on('line', ioline => {
				pending = pending.then(async () => {
					const line = runt.newstr(ioline.replace(/^\s*=/, 'return '));
					try {
						console.log(await runt.eval(env, line));
					} catch (e) {
						console.log(e);
					}
					runt.free(line);
					rl.prompt();
				});
			}).on('close', () => pending.then(() => process.exit(0)));
			rl.prompt();
		} else {
			const result = [];
			process.stdin.resume();
			process.stdin.on('data', buf => result.push(buf));
			process.stdin.on('end', () => {
				const src = Buffer.concat(result);
				const line = runt.newstr(src.toString());
				runt.eval(env, line).then(() => runt.free(line));
			});
		}
	} else {
		// luwa script.lua args...: like lua, arg[0] is the script & the rest are also its ...
		const m = runt.mod, argt = runt.newtbl();
		process.argv.slice(2).forEach((a, i) => m.tblset(argt.val, m.newi64(BigInt(i)), runt.newstr(a).val));
		m.tblset(env.val, runt.newstr('arg').val, argt.val);
		const run = runt.newstr('local f = assert(loadfile(arg[0])) return f(table.unpack(arg, 1, #arg))');
		await runt.eval(env, run);
	}
}).catch(e => setImmediate(() => { throw e; }));
