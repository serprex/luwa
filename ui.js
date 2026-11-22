import mkrt from './rt.js';
import { fromUtf8 } from './util.js';

const taBoard = document.getElementById('taBoard');
const prOut = document.getElementById('prOut');
prOut.textContent = '';

// Turn a value from obj2js into text for prOut
function show(v) {
	if (v instanceof Uint8Array) return fromUtf8(v);
	if (typeof v === 'bigint') return v + 'n';
	if (v && v.hash instanceof Map) return 'table';
	if (v && v.function) return 'function';
	if (v && v.thread) return 'thread';
	return String(v);
}

// A fresh runtime per run, since an error leaves the vm in a bad state
async function boot() {
	const rt = await mkrt();
	window.rt = rt;
	rt.mod.genesis();
	const env = rt.mkref(rt.mod.initPrelude());
	await rt.evalWait();
	return { rt, env };
}

document.getElementById('btnGo').addEventListener('click', async () => {
	prOut.textContent = 'running...';
	try {
		const { rt, env } = await boot();
		prOut.textContent = show(await rt.eval(env, rt.newstr(taBoard.value)));
	} catch (e) {
		console.error(e);
		prOut.textContent = String(e);
	}
});
