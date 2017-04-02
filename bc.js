"use strict";
const lex = require("./lex"), ast = require("./ast");

const NOP = exports.NOP = 0,
	LOAD_NIL = exports.LOAD_NIL = 1,
	LOAD_FALSE = exports.LOAD_FALSE = 2,
	LOAD_TRUE = exports.LOAD_TRUE = 3,
	BIN_PLUS = exports.BIN_PLUS = 4,
	BIN_MINUS = exports.BIN_MINUS = 5,
	BIN_MUL = exports.BIN_MUL = 6,
	BIN_DIV = exports.BIN_DIV = 7,
	BIN_IDIV = exports.BIN_IDIV = 8,
	BIN_POW = exports.BIN_POW = 9,
	BIN_MOD = exports.BIN_MOD = 10,
	BIN_BAND = exports.BIN_BAND = 11,
	BIN_BNOT = exports.BIN_BNOT = 12,
	BIN_BOR = exports.BIN_BOR = 13,
	BIN_RSH = exports.BIN_RSH = 14,
	BIN_LSH = exports.BIN_LSH = 15,
	BIN_DOTDOT = exports.BIN_DOTDOT = 16,
	BIN_LT = exports.BIN_LT = 17,
	BIN_LTE = exports.BIN_LTE = 18,
	BIN_GT = exports.BIN_GT = 19,
	BIN_GTE = exports.BIN_GTE = 20,
	BIN_EQ = exports.BIN_EQ = 21,
	BIN_NEQ = exports.BIN_NEQ = 22,
	UNARY_MINUS = exports.UNARY_MINUS = 23,
	UNARY_NOT = exports.UNARY_NOT = 24,
	UNARY_HASH = exports.UNARY_HASH = 25,
	UNARY_BNOT = exports.UNARY_BNOT = 26,
	MAKE_TABLE = exports.MAKE_TABLE = 27,
	APPEND = exports.APPEND = 28,
	FORTIFY = exports.FORTIFY = 29,
	FOR2 = exports.FOR2 = 30,
	FOR3 = exports.FOR3 = 31,
	POP = exports.POP = 32,
	POP2 = exports.POP2 = 33,
	POP3 = exports.POP3 = 34,
	LOAD_INDEX = exports.LOAD_INDEX = 35,
	STORE_INDEX = exports.STORE_INDEX = 36,
	RETURN = exports.RETURN = 37,
	RETURN_VARG = exports.RETURN_VARG = 38,
	APPEND_VARG = exports.APPEND_VARG = 39,
	LOAD_ENV = exports.LOAD_ENV = 40,
	LOAD_NUM = exports.LOAD_NUM = 64,
	LOAD_STR = exports.LOAD_STR = 65,
	LOAD_IDENT = exports.LOAD_IDENT = 66,
	GOTO = exports.GOTO = 67,
	STORE_IDENT = exports.STORE_IDENT = 68,
	LOAD_VARG = exports.LOAD_VARG = 71,
	TABLE_SET = exports.TABLE_SET = 72,
	JIF = exports.JIF = 73,
	JIFNOT = exports.JIFNOT = 74,
	LOAD_METH = exports.LOAD_METH = 75,
	STORE_METH = exports.STORE_METH = 76,
	JIF_OR_POP = exports.JIF_OR_POP = 77,
	JIFNOT_OR_POP = exports.JIFNOT_OR_POP = 78,
	RETURN_VARG_CALL = exports.RETURN_VARG_CALL = 79,
	APPEND_VARG_CALL = exports.APPEND_VARG_CALL = 80,
	LABEL = exports.LABEL = 127,
	VARG_CALL = exports.VARG_CALL = 129,
	FOR_NEXT = exports.FOR_NEXT = 130,
	RETURN_CALL = exports.RETURN_CALL = 131,
	APPEND_CALL = exports.APPEND_CALL = 132,
	CALL = exports.CALL = 192;

function *selectNodes(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			yield ch;
		}
	}
}

function selectNode(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			return ch;
		}
	}
}

function Assembler(lx) {
	this.lx = lx;
	this.bc = [];
	this.fus = [];
	this.labgen = 0;
	this.scopes = [];
}

Assembler.prototype.hasLiteral = function(node, lit) {
	return node.fathered.exists(ch => ch.type == -1 && ch.val(this.lx) == lit);
}

Assembler.prototype.filterMasks = function*(node, mask) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if (ch.type == -1 && ch.val(this.lx) & mask) {
			yield ch;
		}
	}
}

Assembler.prototype.filterMask = function(node, mask) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if (ch.type == -1 && ch.val(this.lx) & mask) {
			return ch;
		}
	}
}

Assembler.prototype.push = function() {
	return Array.prototype.push.apply(this.bc, arguments);
}

Assembler.prototype.genLabel = function() {
	return this.labgen++;
}

Assembler.prototype.pushScope = function(lab) {
	return this.scopes.push(lab);
}

Assembler.prototype.popScope = function() {
	return this.scopes.pop();
}

Assembler.prototype.getScope = function() {
	return this.scopes.length ? this.scopes[this.scopes.length - 1] : null;
}

Assembler.prototype.gensert = function(node, ty) {
	if ((node.type & 31) != ty) console.log(node, "Invalid type, expected ", ty);
}

Assembler.prototype.genPrefix = function (node) {
	this.gensert(node, ast.Prefix);
	if (node.type >> 5) {
		this.genExpOr(selectNode(node, ast.ExpOr), 1);
	} else {
		this.push(LOAD_IDENT, this.filterMask(node, lex._ident).val(this.lx) & 0xffffff);
	}
}

Assembler.prototype.genSuffix = function (node) {
	this.gensert(node, ast.Suffix);
	if (node.type >> 5) {
		this.genIndex(selectNode(node, ast.Index), false);
	} else {
		this.genCall(selectNode(node, ast.Call));
	}
}

Assembler.prototype.genIndex = function(node, store) {
	// TODO a[b] = c is order of evaluation
	this.gensert(node, ast.Index);
	if (node.type >> 5) {
		this.push(LOAD_STR, this.filterMask(node, lex._ident).val(this.lx) & 0xffffff);
	} else {
		var exp = selectNode(node, ast.ExpOr);
		this.genExpOr(node, exp, 1);
	}
	this.push(store ? STORE_INDEX : LOAD_INDEX);
}

Assembler.prototype.genTable = function(node) {
	this.gensert(node, ast.Tableconstructor);
	this.push(MAKE_TABLE);
	let list = selectNode(node, ast.Fieldlist);
	if (list) {
		let fields = Array.from(selectNodes(list, ast.Field));
		for (let i=0; i<fields.length; i++) {
			let field = fields[i];
			switch (field.type >> 5) {
				case 0:
					for (let exp of selectNodes(field, ast.ExpOr)) {
						this.genExpOr(exp, 1);
					}
					this.push(TABLE_SET);
					break;
				case 1:
					this.push(LOAD_STR, this.filterMask(field, lex._ident).val(this.lx) & 0xffffff);
					this.genExpOr(selectNode(field, ast.ExpOr), 1);
					this.push(TABLE_SET);
					break;
				case 2:
					this.genExpOr(selectNode(field, ast.ExpOr), -1, 2);
					break;
			}
		}
	}
}

Assembler.prototype.genVar = function(node, store) {
	this.gensert(node, ast.Var);
	if (node.type >> 5) {
		let prefix = selectNode(node, ast.Prefix),
			suffix = selectNodes(node, ast.Suffix),
			index = selectNode(node, ast.Index);
		this.genPrefix(prefix);
		for (let suf of suffix) {
			this.genSuffix(suffix);
		}
		this.genIndex(index, store);
	} else {
		this.push(store ? STORE_IDENT : LOAD_IDENT, this.filterMask(node, lex._ident).val(this.lx) & 0xffffff);
	}
}

Assembler.prototype.genArgs = function(node, ismeth, vals, ret, calls) {
	this.gensert(node, ast.Args);
	calls = calls || [];
	switch (node.type >> 5) {
		case 0:
			let explist = selectNode(node, ast.Explist);
			if (explist) {
				let exps = Array.from(selectNodes(explist, ast.ExpOr));
				calls.push(exps.length + ismeth - 1);
				for (let i=0; i<exps.length; i++) {
					if (i == exps.length - 1) {
						this.genExpOr(exps[i], -1, ret, calls);
					} else {
						this.genExpOr(exps[i], 1);
					}
				}
				return;
			} else {
				calls.push(ismeth);
			}
			break;
		case 1:
			this.genTable(selectNode(node, ast.Tableconstructor));
			calls.push(ismeth + 1);
			break;
		case 2: {
			let str = this.filterMask(node, lex._string);
			this.push(LOAD_STR, str.val(this.lx) & 0xffffff);
			calls.push(ismeth + 1)
			break;
		}
	}
	this.handleRet(-1, vals, ret, calls);
}

Assembler.prototype.genCall = function(node, vals, ret, calls) {
	this.gensert(node, ast.Call);
	if (node.type >> 5) {
		let name = this.filterMask(node, lex._ident);
		this.push(LOAD_METH, name.val(this.lx) & 0xffffff);
	}
	let args = selectNode(node, ast.Args);
	this.genArgs(args, node.type >> 5, vals, ret, calls);
}

Assembler.prototype.genFuncCall = function(node, vals, ret, calls) {
	this.gensert(node, ast.Functioncall);
	let prefix = selectNode(node, ast.Prefix),
		suffix = selectNodes(node, ast.Suffix),
		call = selectNode(node, ast.Call);
	this.genPrefix(prefix);
	for (let suf of suffix) {
		this.genSuffix(suf);
	}
	this.genCall(call, vals, ret, calls);
}

Assembler.prototype.genFuncname = function(node) {
	this.gensert(ast.Funcname);
	let colon = hasLiteral(node, lex._colon);
	let names = Array.from(this.filterMasks(node, lex._ident));
	this.push(LOAD_IDENT, names[0].val(this.lx) & 0xffffff);
	for (var i=1; i<names.length - 1; i++) {
		this.push(LOAD_STR, names[i].val(this.lx) & 0xffffff, LOAD_INDEX);
	}
	this.push(colon ? STORE_METH : STORE_ATTR, names[names.length-1].val(this.lx) & 0xffffff);
}

Assembler.prototype.genFuncbody = function(node) {
	this.gensert(node, ast.Funcbody);
	this.push(LOAD_FUNC, this.fus.length);
	// TODO handle parlist, add to func's locals
	var parlist = selectNode(node, ast.Parlist);
	let dotdotdot = hasLiteral(node, lex._dotdotdot);
	var subasm = new Assembler(this.lx);
	subasm.genBlock(selectNode(node, ast.Block));
	this.fus.push(subasm);
}

Assembler.prototype.genValue = function(node, vals, ret, calls) {
	this.gensert(node, ast.Value);
	switch (node.type >> 5) {
		case 0:
			this.push(LOAD_NIL);
			break;
		case 1:
			this.push(LOAD_FALSE);
			break;
		case 2:
			this.push(LOAD_TRUE);
			break;
		case 3:
			this.push(LOAD_NUM, this.filterMask(node, lex._number).val(this.lx) & 0xffffff);
			break;
		case 4:
			this.push(LOAD_STR, this.filterMask(node, lex._string).val(this.lx) & 0xffffff);
			break;
		case 5:
			if (vals) {
				if (calls) {
					if (!ret) {
						this.push(CALL_VARG, vals);
					} else {
						this.push(ret == 1 ? RETURN_VARG_CALL : APPEND_VARG_CALL);
					}
					this.push(calls.length, ...calls);
				} else if (!ret) {
					this.push(LOAD_VARG, vals);
				} else {
					this.push(ret == 1 ? RETURN_VARG : APPEND_VARG);
				}
			}
			return;
		case 6:
			this.genFuncbody(selectNode(selectNode(node, ast.Functiondef), ast.Funcbody));
			break;
		case 7:
			this.genTable(selectNode(node, ast.Tableconstructor));
			break;
		case 8:
			this.genFuncCall(selectNode(node, ast.Functioncall), vals, ret, calls);
			return;
		case 9:
			this.genVar(selectNode(node, ast.Var));
			break;
		case 10: {
			this.genExpOr(selectNode(node, ast.ExpOr), 1);
			break;
		}
	}
	this.handleRet(1, vals, ret, calls);
}

const _precedence = [7, 7, 8, 8, 8, 9, 8, 5, 4, 3, 6, 6, 2, 1, 1, 1, 1, 1, 1],
	precedence = x => (x.type & 31) == ast.Binop ? _precedence[x.type>>5] : 0;

Assembler.prototype.handleRet = function(made, vals, ret, calls) {
	if (~made && ~vals) {
		if (calls) calls[calls.length - 1] += made;
		while (made > vals) {
			this.push(POP);
			made--;
		}
		while (made < vals) {
			this.push(LOAD_NIL);
			made++;
		}
	}
	if (ret) {
		if (calls) {
			this.push(ret == 1 ? RETURN_CALL : APPEND_CALL, calls.length, ...calls);
		} else {
			this.push(ret == 1 ? RETURN : APPEND);
		}
	} else if (calls) {
		this.push(CALL, vals, calls.length, ...calls)
	}
}

Assembler.prototype.genExpOr = function(node, vals, ret = 0, calls = null) {
	this.gensert(node, ast.ExpOr);
	if (vals === undefined) console.log("genExpOr: vals undefined");
	let exps = Array.from(selectNodes(node, ast.ExpAnd));
	if (exps.length == 1) {
		this.genExpAnd(exps[0], vals, ret, calls);
	} else {
		let lab = this.genLabel();
		for (let i=0; i<exps.length - 1; i++) {
			this.genExpAnd(exps[i], 1, 0, null);
			this.push(JIF_OR_POP, lab);
		}
		this.genExpAnd(exps[exps.length - 1], 1, 0);
		this.push(LABEL, lab);
		this.handleRet(1, vals, ret, calls);
	}
}

Assembler.prototype.genExpAnd = function(node, vals, ret, calls) {
	this.gensert(node, ast.ExpAnd);
	let exps = Array.from(selectNodes(node, ast.Exp));
	if (exps.length == 1) {
		this.genExp(exps[0], vals, ret, calls);
	} else {
		let lab = this.genLabel();
		for (let i=0; i<exps.length - 1; i++) {
			this.genExp(exps[i], 1, 0);
			this.push(JIFNOT_OR_POP, lab);
		}
		this.genExp(exps[exps.length - 1], 1, 0);
		this.push(LABEL, lab);
		this.handleRet(1, vals, ret, calls);
	}
}

const Exp32 = ast.Exp|32;
function*shunt(lx, node) {
	var ops = [];
	while (node.type == Exp32 && node.fathered.length == 3) {
		let [rson, op, lson] = node.fathered;
		yield lson;
		while (ops.length && precedence(ops[ops.length-1]) >= precedence(op) && precedence(op) != 9) {
			yield ops.pop();
		}
		ops.push(op);
		node = rson;
	}
	yield node.type == Exp32 ? selectNode(node, ast.Value) : node;
	for (let i=ops.length-1; i>=0; i--) {
		yield ops[i];
	}
}

Assembler.prototype.genExp = function(node, vals, ret, calls) {
	this.gensert(node, ast.Exp);
	if (node.fathered.length == 1) {
		return this.genValue(node.fathered[0], vals, ret, calls);
	} else if (node.type >> 5) {
		for (let op of shunt(this.lx, node)) {
			switch (op.type & 31) {
				case ast.Binop:
					switch (op.type >> 5) {
						case 0: this.push(BIN_PLUS); break; // plus
						case 1: this.push(BIN_MINUS); break; // minus
						case 2: this.push(BIN_MUL); break; // mul
						case 3: this.push(BIN_DIV); break; // div
						case 4: this.push(BIN_IDIV); break; // idiv
						case 5: this.push(BIN_POW); break; // pow
						case 6: this.push(BIN_MOD); break; // mod
						case 7: this.push(BIN_BAND); break; // band
						case 8: this.push(BIN_BNOT); break; // bnot
						case 9: this.push(BIN_BOR); break; // bor
						case 10: this.push(BIN_RSH); break; // rsh
						case 11: this.push(BIN_LSH); break; // lsh
						case 12: this.push(BIN_DOTDOT); break; // dotdot
						case 13: this.push(BIN_LT); break; // lt
						case 14: this.push(BIN_LTE); break; // lte
						case 15: this.push(BIN_GT); break; // gt
						case 16: this.push(BIN_GTE); break; // gte
						case 17: this.push(BIN_EQ); break; // eq
						case 18: this.push(BIN_NEQ); break; // neq
					}
					break;
				case ast.Value:
					this.genValue(op, 1, 0);
					break;
				case ast.Exp:
					if (op.type >> 5) {
						console.log("shunt error: returned binop exp");
					} else this.genExp(op, 1, 0);
					break;
			}
		}
	} else {
		let unop = selectNode(node, ast.Unop);
		let exp = selectNode(node, ast.Exp);
		this.genExp(exp, 1, 0);
		switch (unop.type >> 5) {
			case 0: // minus
				this.push(UNARY_MINUS);
				break;
			case 1: // not
				this.push(UNARY_NOT);
				break;
			case 2: // hash
				this.push(UNARY_HASH);
				break;
			case 3: // bnot
				this.push(UNARY_BNOT);
				break;
		}
	}
	this.handleRet(1, vals, ret, calls);
}

Assembler.prototype.genStat = function(node) {
	this.gensert(node, ast.Stat);
	switch (node.type >> 5) {
		case 0: // ;
			break;
		case 1: { // varlist = explist
			let vars = Array.from(selectNodes(selectNode(node, ast.Varlist), ast.Var)),
				exps = Array.from(selectNodes(selectNode(node, ast.Explist), ast.ExpOr));
			for (let i=0; i<exps.length; i++) {
				this.genExpOr(exps[i], i >= vars.length ? 0 : i == exps.length-1 ? vars.length-exps.length+1 : 1);
			}
			for (let i=vars.length-1; i>=0; i--) {
				this.genVar(vars[i], true);
			}
			break;
		}
		case 2:
			this.genFuncCall(selectNode(node, ast.Functioncall));
			break;
		case 3: {
			let name = this.filterMask(node, lex._ident);
			this.push(LABEL, name.val(this.lx) & 0xffffff);
			break;
		}
		case 4: {
			let scope = this.getScope();
			if (!scope) console.log("Break out of scope");
			else this.push(GOTO, scope);
			break;
		}
		case 5: { // TODO transform into jump offset
			let name = this.filterMask(node, lex._ident);
			this.push(GOTO, name.val(this.lx) & 0xffffff);
			break;
		}
		case 6:
			this.genBlock(selectNode(node, ast.Block));
			break;
		case 7: { // while
			let lab0 = this.genLabel(), lab1 = this.genLabel();
			this.pushScope(lab1);
			this.push(LABEL, lab0);
			this.genExpOr(selectNode(node, ast.ExpOr), 1);
			this.push(JIFNOT, lab1);
			this.genBlock(selectNode(node, ast.Block));
			this.push(GOTO, lab0);
			this.push(LABEL, lab1);
			this.popScope();
			break;
		}
		case 8: { // repeat
			let lab0 = this.genLabel(), lab1 = this.genLabel();
			this.pushScope(lab1);
			this.push(LABEL, lab0);
			this.genBlock(selectNode(node, ast.Block));
			this.genExpOr(selectNode(node, ast.ExpOr), 1);
			this.push(JIFNOT, lab0);
			this.push(LABEL, lab1);
			this.popScope();
			break;
		}
		case 9: {
			/* If there's an else then exps.length != blocks.length
			*/
			let exps = Array.from(selectNodes(node, ast.ExpOr));
			let blocks = Array.from(selectNodes(node, ast.Block));
			let endlab = this.genLabel();
			for (var i=0; i<exps.length; i++) {
				let lab = this.genLabel();
				this.genExpOr(exps[i], 1);
				this.push(JIFNOT, lab);
				this.genBlock(blocks[i]);
				if (i+1 < blocks.length) this.push(GOTO, endlab);
				this.push(LABEL, lab);
			}
			if (i < blocks.length) {
				this.genBlock(blocks[i]);
			}
			this.push(LABEL, endlab);
			break;
		}
		case 10: {
			let lab0 = this.genLabel(), endlab = this.genLabel();
			this.pushScope(endlab);
			let exps = Array.from(selectNodes(node, ast.ExpOr));
			this.genExpOr(exps[0], 1);
			this.genExpOr(exps[1], 1);
			if (exps.length > 2) {
				this.genExpOr(exps[2], 1);
				this.push(LABEL, lab0, FOR3);
			} else {
				this.push(LABEL, lab0, FOR2);
			}
			this.genBlock(selectNode(node, ast.Block));
			this.push(GOTO, lab0);
			this.push(LABEL, endlab);
			this.push(exps.length > 2 ? POP3 : POP2);
			this.popScope();
			break;
		}
		case 11: {
			let lab0 = this.genLabel(), endlab = this.genLabel();
			this.pushScope(endlab);
			let exps = Array.from(selectNodes(selectNode(node, ast.Explist), ast.ExpOr));
			for (let i=0; i<exps.length; i++) {
				this.genExpOr(exps[i], i > 2 ? 0 : i == exps.length - 1 ? 3 - i : 1);
			}
			this.push(FORTIFY, LABEL, lab0);
			let names = Array.from(filterMasks(selectNode(node, ast.Namelist), lex._ident));
			this.push(FOR_NEXT, endlab, names.length);
			for (let name of names) {
				this.push(STORE_IDENT, name.val(this.lx) & 0xffffff);
			}
			this.genBlock(selectNode(node, ast.Block));
			this.push(GOTO, lab0);
			this.popScope();
			break;
		}
		case 12: {
			this.genFuncbody(selectNode(node, ast.Funcbody));
			this.genFuncname(selectNode(node, ast.Funcname), false);
			break;
		}
		case 13: {
			this.genFuncbody(selectNode(node, ast.Funcbody));
			this.push(STORE_IDENT, this.filterMask(node, lex._ident).val(this.lx) & 0xffffff);
			break;
		}
		case 14: {
			let explist = selectNode(node, ast.Explist);
			if (explist) {
				let names = Array.from(this.filterMask(selectNode(node, ast.Namelist), lex._ident)),
					exps = Array.from(selectNodes(explist, ast.ExpOr));
				for (let i=0; i<exps.length; i++) {
					this.genExpOr(exps[i], i >= names.length ? 0 : i == exps.length-1 ? names.length-exps.length+1 : 1);
				}
				for (let i=names.length-1; i>=0; i--) {
					this.push(STORE_IDENT, names[i].val(this.lx) & 0xffffff);
				}
			}
			break;
		}
	}
}

Assembler.prototype.genRet = function(node) {
	this.gensert(node, ast.Retstat);
	let exps = Array.from(selectNodes(selectNode(node, ast.Explist), ast.ExpOr)), i = 0;
	if (exps.length == 0) {
		this.push(RETURN);
	} else {
		for (let i = 0; i<exps.length; i++) {
			this.genExpOr(exps[i], i == exps.length-1 ? -1 : 1, i == exps.length-1 ? 1 : 0);
		}
	}
}

Assembler.prototype.genBlock = function(node) {
	this.gensert(node, ast.Block);
	for (let stat of selectNodes(node, ast.Stat)) {
		this.genStat(stat);
	}
	let ret = selectNode(node, ast.Retstat);
	if (ret) this.genRet(ret);
}

function assemble(lx, root) {
	var asm = new Assembler(lx);
	asm.genBlock(root);
	return asm;
}

exports.assemble = assemble;
