(function(){"use strict";
const lua = require("./luwa");
const taBoard = document.getElementById("taBoard");
const prOut = document.getElementById("prOut");
const assert = {
	equal: (x, y) => {
		if (x != y) {
			throw ["assert.equal", x, y];
		} else {
			console.log("assert.equal", x, y);
		}
	}
};
document.getElementById("btnRt").addEventListener("click", (s, e) => {
	require("./rt")().then(rt => {
		console.log(window.mod = rt);
		let newt = rt.newtable();
		let news = rt.newstr("asdf");
		let newf = rt.newf64(4.2);
		let nil = rt.mkref(rt.mod.tabget(newt.val, news.val));
		rt.mod.tabset(newt.val, news.val, newf.val);
		assert.equal(nil.val, 0); // todo should export a getter for nil/true/false
		assert.equal(rt.mod.tabget(newt.val, news.val), newf.val);
		console.log("Tested newtab/tabget/tabset. Next: string gc pressure");
		let s = "0123456789", ss = [];
		for (var i=0; i<10; i++) s += s;
		for (var j=0; j<2; j++) {
			for (var i=0; i<8; i++) {
				ss.push(rt.newstr(s));
				console.log(rt.mem.buffer.byteLength, ss, rt.handles);
			}
			while (ss.length) {
				rt.free(ss.pop());
			}
			console.log("Freed" + (j?"":". Now to do it again"));
		}
	}).catch(err => {
		console.log("ERR", err);
	});
});
document.getElementById("btnGo").addEventListener("click", (s, e) => {
	const imp = {
		"": {
			p: x => prOut.textContent += x + " ",
			q: x => prOut.textContent += String.fromCharCode(x),
			i: () => prompt("Number", "")|0,
			c: () => prompt("Character", "").charCodeAt(0)|0,
			m: new WebAssembly.Memory({ initial: 1 }),
		}
	};
	prOut.textContent = "";
	lua.runSource(taBoard.value, imp);
});
})();
