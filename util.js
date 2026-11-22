const te = new TextEncoder(), td = new TextDecoder();
export function asUtf8(str) {
	return te.encode(str);
}

export function fromUtf8(utf8) {
	return td.decode(utf8);
}
