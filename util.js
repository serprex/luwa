export function varint(v, value) {
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

export function varuint(v, value) {
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

const te = new TextEncoder(), td = new TextDecoder();
export function pushString(v, str) {
	v.push(...te.encode(str));
}

export function asUtf8(str) {
	return te.encode(str);
}

export function fromUtf8(utf8) {
	return td.decode(utf8);
}

export function readvarint(v, idx) {
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

export function readvaruint(v, idx) {
	let ret = 0, shift = 0;
	while (true) {
		let byte = v[idx++];
		ret |= (byte & 127) << shift;
		if (!(byte & 128)) return ret;
		shift += 7;
	}
}

export function readuint32(v, idx) {
	return v[idx]|v[idx+1]<<8|v[idx+2]<<16|v[idx+3]<<24;
}

export function writeuint32(v, idx, i) {
	v[idx] = i;
	v[idx+1] = i>>8;
	v[idx+2] = i>>16;
	v[idx+3] = i>>24;
}
