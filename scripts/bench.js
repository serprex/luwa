#!/usr/bin/env node
// Times bench/*.lua in luwa & in the reference Lua built to wasm (scripts/mkreflua.sh), both on node.
// Each run is a fresh node process, the best of -n runs is shown (default 3).
// Outputs are compared, a mismatch is marked.
//   scripts/bench.js              every bench
//   scripts/bench.js fib loop     only these
//   scripts/bench.js -n 5         best of 5
//   scripts/bench.js --native     also time the host's lua
//   scripts/bench.js --wasi       (internal) run bench/lua.wasm with the args after it
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const here = fileURLToPath(import.meta.url);
const root = path.join(path.dirname(here), "..");
const benchdir = path.join(root, "bench");
const reflua = path.join(benchdir, "lua.wasm");

const argv = process.argv.slice(2);
if (argv[0] === "--wasi") {
	const { WASI } = await import("node:wasi");
	const wasi = new WASI({
		version: "preview1",
		args: ["lua", ...argv.slice(1)],
		env: {},
		preopens: { "/": "/" },
		returnOnExit: true,
	});
	const { instance } = await WebAssembly.instantiate(fs.readFileSync(reflua), wasi.getImportObject());
	process.exitCode = wasi.start(instance);
} else {
	let runs = 3, native = false;
	const names = [];
	for (let i = 0; i < argv.length; i++) {
		if (argv[i] === "-n") runs = +argv[++i];
		else if (argv[i] === "--native") native = true;
		else names.push(argv[i]);
	}
	const files = names.length ? names :
		fs.readdirSync(benchdir).filter(f => f.endsWith(".lua")).map(f => f.slice(0, -4)).sort();
	if (!fs.existsSync(reflua)) {
		console.error("bench/lua.wasm missing, run scripts/mkreflua.sh");
		process.exit(1);
	}
	const engines = [
		["luwa", f => ["node", [path.join(root, "main.js"), f]]],
		["ref", f => ["node", ["--no-warnings", here, "--wasi", f]]],
	];
	if (native) engines.push(["native", f => ["lua", [f]]]);

	// Best wall time in seconds & the output of the last run
	function time(cmd, args) {
		let best = Infinity, out = "", ok = true;
		for (let i = 0; i < runs; i++) {
			const t0 = process.hrtime.bigint();
			const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 600000 });
			const dt = Number(process.hrtime.bigint() - t0) / 1e9;
			best = Math.min(best, dt);
			out = (r.stdout || "") + (r.stderr || "");
			ok = r.status === 0;
		}
		return { t: best, out: out.trim(), ok };
	}

	const head = ["bench", ...engines.map(e => e[0]), "luwa/ref"];
	console.log(head.join("\t"));
	for (const name of files) {
		const file = path.join(benchdir, name + ".lua");
		const res = engines.map(([, mk]) => time(...mk(file)));
		const cols = res.map(r => r.ok ? r.t.toFixed(3) : "err");
		const ratio = res[0].ok && res[1].ok ? (res[0].t / res[1].t).toFixed(2) + "x" : "-";
		let note = "";
		if (res[0].out !== res[1].out) note = `\toutput differs: luwa '${res[0].out.slice(0, 60)}' ref '${res[1].out.slice(0, 60)}'`;
		console.log([name, ...cols, ratio].join("\t") + note);
	}
}
