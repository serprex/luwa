"use strict";
const lex = require("./lex");

function varint (v, value) {
	while (true) {
		let b = value & 127;
		value >>= 7;
		if ((!value && ((b & 0x40) == 0)) || ((value == -1 && ((b & 0x40) == 0x40)))) {
			return v.push(b);
		}
		else {
			v.push(b | 128);
		}
	}
}

function varuint (v, value) {
	while (true) {
		let b = value & 127;
		value >>= 7;
		if (value) {
			v.push(b | 128);
		} else {
			return v.push(b);
		}
	}
}

function pushString(v, str) {
	for (let i=0; i<str.length; i++) {
		v.push(str.charCodeAt(i));
	}
}

function pushArray(sink, data) {
	return Array.prototype.push.apply(sink, data);
}

exports.runSource = function(source, imp){
	// 0000:cdff stack
	// ce00:f5ff source
	// f600:ffff xbits
	console.log(new lex.Lex(source));
	console.time("start");
	const code = new Uint8Array(imp[""].m.buffer);
}
