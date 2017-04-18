"use strict";
const opc = require("./bc"),
	env = require("./env"),
	obj = require("./obj"),
	trace = require("./trace"),
	Table = require("./table");

function Vm(func) {
	this.func = func;
	this.locals = [];
	this.frees = [];
	this.dotdotdot = null;
	for (let i=0; i<func.fcount; i++) {
		this.frees[i] = { value: null };
	}
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

function callObj(subvm, stack, base) {
	if (typeof subvm === 'function') {
		return subvm(stack, base);
	} else {
		subvm.readarg(stack, base);
		return _run(subvm, stack);
	}
}

function*_run(vm, stack) {
	let bc = vm.func.bc, lx = vm.func.lx, pc = 0;
	let trset = new trace.TraceSet(), trblk = trset.traces[0];
	while (true){
		let op = bc[pc], arg = bc[pc+1], arg2 = bc[pc+2];
		const oldpc = pc;
		pc += (op >> 6) + 1;
		switch (op) {
			case opc.LOAD_NIL: {
				stack.push(null);
				trblk.incr(oldpc, 0, trace.nil);
				break;
			}
			case opc.LOAD_FALSE: {
				stack.push(false);
				trblk.incr(oldpc, 0, trace.bool);
				break;
			}
			case opc.LOAD_TRUE: {
				stack.push(true);
				trblk.incr(oldpc, 0, trace.bool);
				break;
			}
			case opc.BIN_ADD: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b + a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_SUB: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b - a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_MUL: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b * a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_DIV: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b / a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_IDIV: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b / a | 0);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_POW: {
				let a = stack.pop(), b = stack.pop();
				stack.push(Math.pow(b, a));
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_MOD: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b % a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_BAND: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b & a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_BXOR: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b ^ a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_BOR: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b | a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_SHR: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b >> a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_SHL: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b << a);
				trblk.incr(oldpc, 2, trace.num);
				break;
			}
			case opc.BIN_CONCAT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b.toString() + a.toString());
				trblk.incr(oldpc, 2, trace.str);
				break;
			}
			case opc.BIN_LT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b < a);
				trblk.incr(oldpc, 2, trace.bool);
				break;
			}
			case opc.BIN_LE: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b <= a);
				trblk.incr(oldpc, 2, trace.bool);
				break;
			}
			case opc.BIN_GT: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b > a);
				trblk.incr(oldpc, 2, trace.bool);
				break;
			}
			case opc.BIN_GE: {
				let a = stack.pop(), b = stack.pop();
				stack.push(b >= a);
				trblk.incr(oldpc, 2, trace.bool);
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
				trblk.incr(oldpc, 2, trace.bool);
				break;
			}
			case opc.UNARY_MINUS: {
				let a = stack.pop(), n = obj.numcoerce(a);
				if (n !== null) {
					stack.push(-n);
					trblk.incr(oldpc, 1, trace.num);
				} else if (a instanceof Table) {
					let __unm = obj.metaget(a, "__unm");
					if (__unm) {
						let stl = stack.length;
						stack.push(__unm, a);
						yield*callObj(vm, stack, stl);
						stack.length = stl + 1;
						trblk.incr(oldpc, 1, trace.any);
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
				trblk.incr(oldpc, 1, trace.bool);
				break;
			}
			case opc.UNARY_HASH: {
				let a = stack.pop();
				if (typeof a == 'string') {
					stack.push(a.length);
					trblk.incr(oldpc, 1, trace.int);
				} else if (a instanceof Table) {
					let __len = obj.metaget(a, "__len");
					if (__len) {
						let stl = stack.length;
						stack.push(__len, a);
						yield*callObj(vm, stack, stl);
						stack.length = stl + 1;
						trblk.incr(oldpc, 1, trace.any);
					} else {
						stack.push(a.getlength());
						trblk.incr(oldpc, 1, trace.int);
					}
				} else {
					throw "Attempted to get length of non string, non table";
				}
				break;
			}
			case opc.UNARY_BNOT: {
				let a = stack.pop();
				stack.push(~a);
				trblk.incr(oldpc, 1, trace.int);
				break;
			}
			case opc.MAKE_TABLE: {
				stack.push(new Table());
				trblk.incr(oldpc, 0, trace.table);
				break;
			}
			case opc.FOR2: {
				let a = stack.pop(), b = stack.pop();
				trset.fork(trblk, pc, arg);
				if (b > a) {
					trblk.incr2(oldpc, 2);
					pc = arg;
				}
				else {
					trblk.incr1(oldpc, 2, trace.num, trace.num, trace.num);
					stack.push(b+1, a, b);
				}
				trblk = trset.traces[pc];
				break;
			}
			case opc.FOR3: {
				let a = stack.pop(), b = stack.pop(), c = stack.pop(), ca = c+a;
				trset.fork(trblk, pc, arg);
				if (Math.abs(ca - b) > Math.abs(c - b) && b != c) {
					trblk.incr2(oldpc, 3);
					pc = arg;
				}
				else {
					trblk.incr1(oldpc, 3, trace.num, trace.num, trace.num, trace.num);
					stack.push(ca, b, a, c);
				}
				trblk = trset.traces[pc];
				break;
			}
			case opc.LOAD_FUNC: {
				let f = vm.func.fus[arg];
				let subvm = new Vm(f);
				let freelist = vm.func.freelist[f.id];
				if (freelist) {
					for (let [ff, cf] of freelist) {
						subvm.frees[cf] = vm.frees[ff];
					}
				}
				stack.push(subvm);
				trblk.incr(oldpc, 0, trace.func|trace.jsfunc);
				break;
			}
			case opc.POP: {
				stack.length -= arg;
				trblk.incr(oldpc, arg);
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
				trblk.incr(oldpc, 0, trace.num);
				break;
			}
			case opc.LOAD_STR: {
				stack.push(lx.ssr[arg]);
				trblk.incr(oldpc, 0, trace.str);
				break;
			}
			case opc.LOAD_DEREF: {
				stack.push(vm.frees[arg].value);
				trblk.incr(oldpc, 0, trace.any);
				break;
			}
			case opc.STORE_DEREF: {
				vm.frees[arg].value = stack.pop();
				trblk.incr(oldpc, 1);
				break;
			}
			case opc.GOTO: {
				trset.fork(trblk, arg);
				trblk = trset.traces[arg];
				pc = arg;
				break;
			}
			case opc.LOAD_LOCAL: {
				stack.push(vm.locals[arg]);
				trblk.incr(oldpc, 0, trace.any);
				break;
			}
			case opc.STORE_LOCAL: {
				vm.locals[arg] = stack.pop();
				trblk.incr(oldpc, 1);
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
				let tr = []; // TODO cache
				for (let i=0; i<arg; i++) {
					tr.push(trace.any);
					if (i < vm.dotdotdot.length) {
						stack.push(vm.dotdotdot[i]);
					} else {
						stack.push(null);
					}
				}
				trblk.incr(oldpc, 0, tr);
				break;
			}
			case opc.TABLE_SET: {
				let a = stack.pop(), b = stack.pop(), c = stack.pop();
				c.set(b, a);
				stack.push(c);
				trblk.incr(oldpc, 2);
				break;
			}
			case opc.JIF: {
				let a = stack.pop();
				if (a !== false && a !== null) pc = arg;
				break;
			}
			case opc.JIFNOT: {
				let a = stack.pop();
				if (a === false || a === null) pc = arg;
				break;
			}
			case opc.LOAD_METH: {
				let a = stack.pop();
				stack.push(obj.index(a, lx.ssr[arg]), a);
				// TODO propagate type of a
				trblk.incr(oldpc, 2, trace.func|trace.jsfunc, trace.any);
				break;
			}
			case opc.JIF_OR_POP: {
				let a = stack.pop();
				if (a !== false && a !== null) {
					stack.push(a);
					pc = arg;
				}
				break;
			}
			case opc.JIFNOT_OR_POP: {
				let a = stack.pop();
				if (a === false || a === null) {
					stack.push(a);
					pc = arg;
				}
				break;
			}
			case opc.APPEND: {
				let a = stack.pop(), b = stack.pop();
				b.set(arg, a);
				stack.push(b);
				trblk.incr(oldpc, 1);
				break;
			}
			case opc.APPEND_CALL: {
				let endstl = stack.length;
				pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[pc-i] + 1;
					let subvm = stack[endstl], sret;
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[pc-arg2] + 1;
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
				pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[pc-i] + 1;
					let subvm = stack[endstl];
					if (!i) {
						stack.push(...vm.dotdotdot);
					}
					yield*callObj(subvm, stack, endstl);
					endstl -=  bc[pc-i-1] + 1;
				}
				endstl -=  bc[pc-arg2] + 1;
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
				pc += arg;
				for (var i=1; i<arg; i++) {
					endstl -=  bc[pc-i] + 1;
					let subvm = stack[endstl];
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[pc-arg] + 1;
				let subvm = stack[endstl];
				if (typeof subvm === 'function') {
					return yield*subvm(stack, endstl);
				} else {
					vm = subvm;
					vm.readarg(stack, endstl);
					bc = vm.func.bc;
					lx = vm.func.lx;
					pc = 0;
				}
				break;
			}
			case opc.RETURN_VARG_CALL: {
				let endstl = stack.length;
				pc += arg;
				for (var i=1; i<arg; i++) {
					endstl -=  bc[pc-i] + 1;
					let subvm = stack[endstl];
					if (!i) {
						stack.push(...vm.dotdotdot);
					}
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[pc-arg] + 1;
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
					pc = 0;
				}
				break;
			}
			case opc.CALL: {
				let endstl = stack.length;
				pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[pc-i] + 1;
					let subvm = stack[endstl];
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[pc-arg2] + 1;
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
				pc += arg2;
				for (var i=1; i<arg2; i++) {
					endstl -=  bc[pc-i] + 1;
					let subvm = stack[endstl];
					if (!i) {
						stack.push(...vm.dotdotdot);
					}
					yield*callObj(subvm, stack, endstl);
				}
				endstl -=  bc[pc-arg2] + 1;
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
					pc = arg;
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

function init(func, e = env()) {
	const vm = new Vm(func);
	let freeid = func.local2free[0];
	if (freeid !== undefined) {
		vm.frees[freeid].value = e;
	} else {
		vm.locals[0] = e;
	}
	return vm;
}

function run(func, e = env()) {
	const stack = [], vm = init(func, e);
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
