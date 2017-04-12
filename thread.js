module.exports = Thread;
const runbc = require("./runbc");

function Thread(stack, base) {
	this.stack = [];
	this.status = "suspended";
	let vm = stack[base+1];
	if (typeof vm == "function") {
		stack.push(...stack.splice(base + 1));
		this.vm = this.vm(this.stack, 0);
	} else {
		vm.readarg(stack, base + 1);
		this.vm = runbc._run(vm, this.stack);
	}
}
Thread.prototype.resume = function*(stack, base, pbase) {
	let cbase = this.stack.length;
	if (this.status == "running") {
		this.stack.push(...stack.splice(pbase));
	}
	stack.length = base;
	let res = this.vm.next();
	this.status = res.done ? "dead" : "running";
	stack.push(...this.stack.splice(cbase));
	this.stack.length = cbase;
}

