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
		let s = "0123456789";
		for (var i=0; i<10; i++) s += s;
		let s1 = rt.newstr(s);
		console.log(s1);
		let s2 = rt.newstr(s);
		console.log(s1, s2);
		let s3 = rt.newstr(s);
		console.log(s1, s2, s3);
		let s4 = rt.newstr(s);
		console.log(s1, s2, s3, s4);
		let s5 = rt.newstr(s);
		console.log(s1, s2, s3, s4, s5);
		let s6 = rt.newstr(s);
		console.log(s1, s2, s3, s4, s5, s6);
		console.log("6", rt.mem.buffer.byteLength);
		//rt.free(s6);
		let s7 = rt.newstr(s);
		console.log(s1, s2, s3, s4, s5, s6, s7);
		console.log("7", rt.mem.buffer.byteLength);
		let s8 = rt.newstr(s);
		console.log(s1, s2, s3, s4, s5, s6, s7, s8);
		console.log("8", rt.mem.buffer.byteLength);
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
