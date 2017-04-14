"use strict";
const opc = require("./bc"),
	env = require("./env"),
	obj = require("./obj"),
	Table = require("./table");

function Vm(func) {
	this.pc = 0;
	this.func = func;
	this.locals = [];
	this.frees = [];
	this.dotdotdot = null;
}

Vm.prototype.readarg = function(stack, base) {
	for (var i=0; i<this.func.pcount; i++) {
		let freeid = this.func.local2free[i];
		let val = base+i+1 < stack.length ? stack[base+i+1] : null;
		if (freeid === undefined) {
			this.locals[i] = val;
		} else {
			this.frees[freeid] = val;
		}
	}
	if (this.func.isdotdotdot) {
		this.dotdotdot = stack.slice(base + this.func.pcount + 1);
	}
	stack.length = base;
}

function*callObj(subvm, stack, base) {
	if (typeof subvm === 'function') {
		yield*subvm(stack, base);
	} else {
		subvm.readarg(stack, base);
		yield*_run(subvm, stack);
	}
}

function*_run(vm, stack) {
	var bc = vm.func.bc, lx = vm.func.lx;
	while (true){
		let op = bc[vm.pc], arg, arg2, arg3;
		switch (op >> 6) {
			// thru
			case 3:arg3 = bc[vm.pc+3];
			case 2:arg2 = bc[vm.pc+2];
			case 1:arg = bc[vm.pc+1];
		}
		vm.pc += (op >> 6) + 1;
		switch (op) {
			case opc.LOAD_NIL: {
				stack.push(null);
				break;
			}
			case opc.LOAD_FALSE: {
				stack.push(false);
				break;
			}
			case opc.LOAD_TRUE: {
				stack.push(true);
				break;
			}
			case opc.BIN_PLUS: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b + a);
				break;
			}
			case opc.BIN_MINUS: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b - a);
				break;
			}
			case opc.BIN_MUL: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b * a);
				break;
			}
			case opc.BIN_DIV: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b / a);
				break;
			}
			case opc.BIN_IDIV: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b / a | 0);
				break;
			}
			case opc.BIN_POW: {
				let a = stack.pop(), b = stack.pop();
				stack.push(Math.pow(b, a));
				break;
			}
			case opc.BIN_MOD: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b % a);
				break;
			}
			case opc.BIN_BAND: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b & a);
				break;
			}
			case opc.BIN_BNOT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b ^ a);
				break;
			}
			case opc.BIN_BOR: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b | a);
				break;
			}
			case opc.BIN_RSH: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b >> a);
				break;
			}
			case opc.BIN_LSH: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b << a);
				break;
			}
			case opc.BIN_DOTDOT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b.toString() + a.toString());
				break;
			}
			case opc.BIN_LT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b < a);
				break;
			}
			case opc.BIN_LTE: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b <= a);
				break;
			}
			case opc.BIN_GT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b > a);
				break;
			}
			case opc.BIN_GTE: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b >= a);
				break;
			}
			case opc.BIN_EQ: {
				let a = stack.pop(), b = stack.pop();
				if (a === b) {
					stack.push(true);
				} else if (!(a instanceof Table) || !(b instanceof Table)) {
					stack.push(false);
				} else {
					let a__eq = obj.metaget(a, "__eq"),
						b__eq = obj.metaget(b, "__eq");
					if (a__eq == b__eq) {
						let stl = stack.length;
						stack.push(a__eq, a, b);
						yield*callObj(vm, stack, stl);
						stack.length = stl + 1;
						stack[stl] = stack[stl] !== false && stack[stl] !== null;
					} else {
						stack.push(false);
					}
				}
				break;
			}
			case opc.BIN_NEQ: {
				let a = stack.pop(), b = stack.pop();
				if (a === b) {
					stack.push(false);
				} else if (!(a instanceof Table) || !(b instanceof Table)) {
					stack.push(true);
				} else {
					let a__eq = obj.metaget(a, "__eq"),
						b__eq = obj.metaget(b, "__eq");
					if (a__eq == b__eq) {
						let stl = stack.length;
						stack.push(a__eq, a, b);
						yield*callObj(vm, stack, stl);
						stack.length = stl + 1;
						stack[stl] = stack[stl] === false || stack[stl] === null;
					} else {
						stack.push(true);
					}
				}
				break;
			}
			case opc.UNARY_MINUS: {
				let a = stack.pop(), n = obj.numcoerce(a);
				if (n !== null) {
					stack.push(-n);
				} else if (a instanceof Table) {
					let __unm = obj.metaget(a, "__unm");
					if (__unm) {
						let stl = stack.length;
						stack.push(__unm, a);
						yield*callObj(vm, stack, stl);
						stack.length = stl + 1;
					} else {
						throw "Attempted to negate table without __unm";
					}
				} else {
					throw "Attempted to negate of non number";
				}
				break;
			}
			case opc.UNARY_NOT: {
				let a = stack.pop();
				stack.push(a !== false && a !== null);
				break;
			}
			case opc.UNARY_HASH: {
				let a = stack.pop();
				if (typeof a == 'string') {
					stack.push(a.length);
				} else if (a instanceof Table) {
					let __len = obj.metaget(a, "__len");
					if (__len) {
						let stl = stack.length;
						stack.push(__len, a);
						yield*callObj(vm, stack, stl);
						stack.length = stl + 1;
					} else {
						stack.push(a.getlength());
					}
				} else {
					throw "Attempted to get length of non string, non table";
				}
				break;
			}
			case opc.UNARY_BNOT: {
				let a = stack.pop();
				stack.push(~a);
				break;
			}
			case opc.MAKE_TABLE: {
				stack.push(new Table());
				break;
			}
			case opc.FOR2: {
				let a = stack.pop(), b = stack.pop();
				if (b > a) {
					vm.pc = arg;
				}
				else {
					stack.push(b+1, a, b);
				}
				break;
			}
			case opc.FOR3: {
				let a = stack.pop(), b = stack.pop(), c = stack.pop(), ca = c+a;
				if (Math.abs(ca - b) > Math.abs(c - b) && b != c) {
					vm.pc = arg;
				}
				else {
					stack.push(ca, b, a, c);
				}
				break;
			}
			case opc.LOAD_FUNC: {
				let f = vm.func.fus[arg];
				let subvm = new Vm(f);
				for (let i=0; i<f.fcount; i++) {
					subvm.frees[i] = { value: null };
				}
				let freelist = vm.func.freelist[f.id];
				if (freelist) {
					for (let [ff, cf] of freelist) {
						subvm.frees[cf] = vm.frees[ff];
					}
				}
				stack.push(subvm);
				break;
			}
			case opc.POP: {
				stack.length -= arg;
				break;
			}
			case opc.LOAD_INDEX: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b.get(a));
				break;
			}
			case opc.STORE_INDEX: {
				let a = stack.pop(), b = stack.pop(), c = stack.pop();
				b.set(a, c); // TODO should be c.set(b, a)
				break;
			}
			case opc.LOAD_NUM: {
				stack.push(lx.snr[arg]);
				break;
			}
			case opc.LOAD_STR: {
				stack.push(lx.ssr[arg]);
				break;
			}
			case opc.LOAD_DEREF: {
				stack.push(vm.frees[arg].value);
				break;
			}
			case opc.STORE_DEREF: {
				vm.frees[arg].value = stack.pop();
				break;
			}
			case opc.GOTO: {
				vm.pc = arg;
				break;
			}
			case opc.LOAD_LOCAL: {
				stack.push(vm.locals[arg]);
				break;
			}
			case opc.STORE_LOCAL: {
				vm.locals[arg] = stack.pop();
				break;
			}
			case opc.RETURN: {
				return;
			}
			case opc.RETURN_VARG: {
				stack.push(...vm.dotdotdot);
				return;
			}
			case opc.APPEND_VARG: {
				let t = stack[stack.length - 1];
				for (let i = 0; i < vm.dotdotdot.length; i++) {
					t.set(arg + i, vm.dotdotdot[i]);
				}
				break;
			}
			case opc.LOAD_VARG: {
				for (let i=0; i<arg; i++) {
					if (i < vm.dotdotdot.length) {
						stack.push(vm.dotdotdot[i]);
					} else {
						stack.push(null);
					}
				}
				break;
			}
			case opc.TABLE_SET: {
				let a = stack.pop(), b = stack.pop(), c = stack.pop();
				c.set(b, a);
				stack.push(c);
				break;
			}
			case opc.JIF: {
				let a = stack.pop();
				if (a !== false && a !== null) vm.pc = arg;
				break;
			}
			case opc.JIFNOT: {
				let a = stack.pop();
				if (a === false || a === null) vm.pc = arg;
				break;
			}
			case opc.LOAD_METH: {
				let a = stack.pop();
				stack.push(obj.index(a, lx.ssr[arg]), a);
				break;
			}
			case opc.JIF_OR_POP: {
				let a = stack.pop();
				if (a !== false && a !== null) {
					stack.push(a);
					vm.pc = arg;
				}
				break;
			}
			case opc.JIFNOT_OR_POP: {
				let a = stack.pop();
				if (a === false || a === null) {
					stack.push(a);
					vm.pc = arg;
				}
				break;
			}
			case opc.APPEND: {
				let a = stack.pop(), b = stack.pop();
				b.set(arg, a);
				stack.push(b);
				break;
			}
			case opc.APPEND_CALL: {
				let endstl = stack.length;
				vm.pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[vm.pc-i] + 1;
					let subvm = stack[endstl], sret;
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[vm.pc-arg2] + 1;
				let subvm = stack[endstl];
				yield*callObj(subvm, stack, endstl);
				let table = stack[endstl - 1];
				for (let i=endstl; i<stack.length; i++) {
					table.set(i-endstl+arg, stack[i]);
				}
				stack.length = endstl;
				break;
			}
			case opc.APPEND_VARG_CALL: {
				let endstl = stack.length;
				vm.pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[vm.pc-i] + 1;
					let subvm = stack[endstl];
					if (!i) {
						stack.push(...vm.dotdotdot);
					}
					yield*callObj(subvm, stack, endstl);
					endstl -=  bc[vm.pc-i-1] + 1;
				}
				endstl -=  bc[vm.pc-arg2] + 1;
				let subvm = stack[endstl];
				if (arg2 == 1) {
					stack.push(...vm.dotdotdot);
				}
				yield*callObj(subvm, stack, endstl);
				let table = stack[endstl - 1];
				for (let i=endstl; i<stack.length; i++) {
					table.set(i-endstl+arg, stack[i]);
				}
				stack.length = endstl;
				break;
			}
			case opc.RETURN_CALL: {
				let endstl = stack.length;
				vm.pc += arg;
				for (var i=1; i<arg; i++) {
					endstl -=  bc[vm.pc-i] + 1;
					let subvm = stack[endstl];
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[vm.pc-arg] + 1;
				let subvm = stack[endstl];
				if (typeof subvm === 'function') {
					return yield*subvm(stack, endstl);
				} else {
					vm = subvm;
					vm.readarg(stack, endstl);
					bc = vm.func.bc;
					lx = vm.func.lx;
				}
				break;
			}
			case opc.RETURN_VARG_CALL: {
				let endstl = stack.length;
				vm.pc += arg;
				for (var i=1; i<arg; i++) {
					endstl -=  bc[vm.pc-i] + 1;
					let subvm = stack[endstl];
					if (!i) {
						stack.push(...vm.dotdotdot);
					}
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[vm.pc-arg] + 1;
				let subvm = stack[endstl];
				if (arg == 1) {
					stack.push(...vm.dotdotdot);
					arg = false;
				}
				if (typeof subvm === 'function') {
					return yield*subvm(stack, endstl);
				} else {
					vm = subvm;
					vm.readarg(stack, endstl);
					bc = vm.func.bc;
					lx = vm.func.lx;
				}
				break;
			}
			case opc.CALL: {
				let endstl = stack.length;
				vm.pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[vm.pc-i] + 1;
					let subvm = stack[endstl];
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[vm.pc-arg2] + 1;
				let subvm = stack[endstl];
				yield*callObj(subvm, stack, endstl);
				while (stack.length < endstl + arg) {
					stack.push(null);
				}
				stack.length = endstl + arg;
				break;
			}
			case opc.VARG_CALL: {
				let endstl = stack.length;
				vm.pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[vm.pc-i] + 1;
					let subvm = stack[endstl];
					if (!i) {
						stack.push(...vm.dotdotdot);
					}
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[vm.pc-arg2] + 1;
				let subvm = stack[endstl];
				if (arg == 1) {
					stack.push.apply(...vm.dotdotdot);
				}
				yield*callObj(subvm, stack, endstl);
				while (stack.length < endstl + arg) {
					stack.push(null);
				}
				stack.length = endstl + arg;
				break;
			}
			case opc.FOR_NEXT: {
				let endstl = stack.length - 3;
				let iter = stack[endstl], k = stack[endstl+1], v = stack[endstl+2];
				yield*callObj(iter, stack, endstl);
				if (endstl == stack.length || stack[endstl] === null) {
					vm.pc = arg;
					stack.length = endstl;
				} else {
					while (stack.length < endstl + arg2) {
						stack.push(null);
					}
					stack.length = endstl + arg2;
					stack.splice(endstl, 0, iter, k, stack[endstl]);
				}
				break;
			}
		}
	}
}

function init(func, stack, e = env()) {
	const vm = new Vm(func);
	for (let i=0; i<func.fcount; i++) {
		vm.frees[i] = { value: null };
	}
	let freeid = func.local2free[0];
	if (freeid !== undefined) {
		vm.frees[freeid].value = e;
	} else {
		vm.locals[0] = e;
	}
	return vm;
}

function run(func, e = env()) {
	const stack = [], vm = init(func, stack, e);
	if (!_run(vm, stack).next().done) {
		// TODO need to hit this sooner for coroutine.isyieldable
		throw "coroutine.yield: Attempt to yield from outside a coroutine";
	}
	console.log("vm", vm, stack);
	return stack;
}

exports.Vm = Vm;
exports.callObj = callObj;
exports._run = _run;
exports.run = run;
