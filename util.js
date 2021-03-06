'use strict';
exports.varint = varint;
exports.varuint = varuint;
exports.pushString = pushString;
exports.asUtf8 = asUtf8;
exports.fromUtf8 = fromUtf8;
exports.readvarint = readvarint;
exports.readvaruint = readvaruint;
exports.readuint32 = readuint32;
exports.writeuint32 = writeuint32;

function varint(v, value) {
	while (true) {
		let b = value & 127;
		value >>= 7;
		if ((!value && ((b & 0x40) == 0)) || (value == -1 && ((b & 0x40) == 0x40))) {
			return v.push(b);
		}
		else {
			v.push(b | 128);
		}
	}
}

function varuint(v, value) {
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

if (typeof TextEncoder === 'undefined') {
	(typeof window === 'undefined' ? global : window).TextEncoder = function() {
	};
	TextEncoder.prototype.encode = function(s) {
		let u8 = unescape(encodeURIComponent(s));
		let ret = new Uint8Array(u8.length);
		for (let i=0; i<ret.length; i++) {
			ret[i] = u8.charCodeAt(i);
		}
		return ret;
	}
}
if (typeof TextDecoder === 'undefined') {
	(typeof window === 'undefined' ? global : window).TextDecoder = function() {
	};
	TextDecoder.prototype.decode = function(utf8) {
		return decodeURIComponent(escape(String.fromCharCode.apply(null, utf8)));
	}
}

const te = new TextEncoder(), td = new TextDecoder();
function pushString(v, str) {
	v.push(...te.encode(str));
}

function asUtf8(str) {
	return te.encode(str);
}

function fromUtf8(utf8) {
	return td.decode(utf8);
}

function readvarint(v, idx) {
	let ret = 0, shift = 0;
	while (true) {
		let byte = v[idx++];
		ret |= (byte & 127) << shift;
		shift += 7;
		if (!(byte & 128)) {
			return byte & 0x40 ? ret - (1 << shift) : ret;
		}
	}
}

function readvaruint(v, idx) {
	let ret = 0, shift = 0;
	while (true) {
		let byte = v[idx++];
		ret |= (byte & 127) << shift;
		if (!(byte & 128)) return ret;
		shift += 7;
	}
}

function readuint32(v, idx) {
	return v[idx]|v[idx+1]<<8|v[idx+2]<<16|v[idx+3]<<24;
}

function writeuint32(v, idx, i) {
	v[idx] = i;
	v[idx+1] = i>>8;
	v[idx+2] = i>>16;
	v[idx+3] = i>>24;
}
