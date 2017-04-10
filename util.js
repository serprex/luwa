function readarg(stack, i) {
	return i < stack.length ? stack[i] : null;
}
exports.readarg = readarg;

exports.readargor = function readargor(stack, i, or) {
	let a = readarg(stack, i);
	return a === null ? or : a;
}
