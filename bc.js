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
	BIN_AND = exports.BIN_AND = -1,
	BIN_OR = exports.BIN_OR = -2,
	UNARY_MINUS = exports.UNARY_MINUS = 23,
	UNARY_NOT = exports.UNARY_NOT = 24,
	UNARY_HASH = exports.UNARY_HASH = 25,
	UNARY_BNOT = exports.UNARY_BNOT = 26,
	MAKE_TABLE = exports.MAKE_TABLE = 27,
	TABLE_ADD = exports.TABLE_ADD = 28,
	LOAD_NUM = exports.LOAD_NUM = 128,
	LOAD_STR = exports.LOAD_STR = 129,
	LOAD_VARARG = exports.LOAD_VARARG = 130,
	LOAD_IDENT = exports.LOAD_IDENT = 131,
	GOTO = exports.GOTO = 132,
	RETURN = exports.GOTO = 133,
	STORE_IDENT = exports.STORE_IDENT = 134,
	LOAD_ATTR = exports.LOAD_ATTR = 135,
	STORE_ATTR = exports.STORE_ATTR = 136,
	CALL = exports.CALL = 137,
	STORE_INDEX_SWAP = 138,
	TABLE_SET = 139,
	JIF = 140,
	JIFNOT = 141,
	LABEL = exports.LABEL = 255;

function *selectNodes(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--)
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			yield ch;
		} else if (ch.type < 0 || ch.type > 31) {
			yield *selectNode(ch, type);
		}
	}
}

function selectNode(node, type) {
	for (let i = node.fathered.length - 1; i >= 0; i--)
		let ch = node.fathered[i];
		if ((ch.type & 31) == type) {
			return ch;
		} else if (ch.type < 0 || ch.type > 31) {
			let n = selectNode(ch, type);
			if (n) return n;
		}
	}
}

Assembler.prototype.hasLiteral = function(node, lit) {
	for (let i=node.fathered.length; i<=node.fathered.length; i++){
		let ch = node.fathered[i];
		if (node.type == -1 && node.val() == lit) return true;
	}
	return false;
}

Assembler.prototype.filterMasks = function*(node, mask) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if (node.type == -1 && node.val(this.lx) & mask) {
			yield node;
		}
	}
}

Assembler.prototype.filterMask = function(node, mask) {
	for (let i = node.fathered.length - 1; i >= 0; i--) {
		let ch = node.fathered[i];
		if (node.type == -1 && node.val(this.lx) & mask) {
			return node;
		}
	}
}

function Assembler(lx) {
	this.lx = lx;
	this.bc = [];
	this.fus = [];
	this.fui = 0;
	this.labgen = 0;
	this.scopes = [];
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

Assembler.prototype.gensert(node, ty) {
	if ((node & 31) != ty) console.log(node, "Invalid type, expected ", ty);
}

Assembler.prototype.genPrefix = function (node) {
	this.gensert(node, ast.Prefix);
	if (node.type >> 5) {
		this.genExp(selectNode(node, ast.Exp));
	} else {
		this.push(LOAD_IDENT, this.filterMask(node, lex._ident).val());
	}
}

Assembler.prototype.genIndex = function(node, store) {
	// TODO a[b] = c is order of evaluation
	this.gensert(node, ast.Index);
	if (node.type >> 5) {
		// TODO convert this to LOAD_STR STORE_INDEX / LOAD_INDEX
		this.push(store ? STORE_ATTR : LOAD_ATTR, this.filterMask(node, lex._ident))
	} else {
		var exp = selectNode(node, ast.Exp);
		this.genExp(node, exp);
		this.push(store ? STORE_INDEX : LOAD_INDEX);
	}
}

Assembler.prototype.genTable = function(node) {
	this.gensert(node, ast.Tableconstructor);
	this.push(MAKE_TABLE);
	for (let field of selectNodes(selectNode(node, ast.Fieldlist), ast.Field)) {
		switch (field.type >> 5) {
			case 0:
				for (let exp of selectNodes(field, ast.Exp)) {
					this.genExp(exp);
				}
				this.push(STORE_INDEX_SWAP);
				break;
			case 1:
				this.genExp(selectNode(field, ast.Exp));
				this.push(TABLE_SET, this.filterMask(field, lex._ident));
				break;
			case 2:
				this.genExp(selectNode(field, ast.Exp));
				this.push(TABLE_ADD);
				break;
		}
	}
}

Assembler.prototype.genVar = function(node, store) {
	this.gensert(node, ast.Var);
	if (node.type >> 5) {
		this.push(store ? STORE_IDENT : LOAD_IDENT, this.filterMask(node, lex._ident).val(this.lx));
	} else {
		let prefix = selectNode(node, ast.Prefix),
			suffix = selectNodes(node, ast.Suffix),
			index = selectNode(node, ast.Index);
		this.genPrefix(prefix);
		for (let suf of suffix) {
			this.genPrefix(suffix);
		}
		this.genIndex(index, store);
	}
}

Assembler.prototype.genArgs = function(node) {
	this.gensert(node, ast.Args);
	switch (this.type >> 5) {
		case 0:
			let explist = selectNode(node, ast.Explist);
			if (explist) {
				let exps = Array.from(selectNodes(explist, ast.Exp));
				for (let i=0; i<exps.length; i++) {
					this.genExp(node, i == exps.length - 1);
				}
				this.push(CALL, exps.length);
			} else {
				this.push(CALL, 0);
			}
			break;
		case 1:
			this.genTable(selectNode(node, ast.Tableconstructor));
			this.push(CALL, 1);
			break;
		case 2: {
			let str = this.filterMask(node, lex._string);
			this.push(LOAD_STR, str.val(this.lx), CALL, 1);
			break;
		}
	}
}

Assembler.protototype.genCall = function(node) {
	this.gensert(node, ast.Call);
	if (this.type >> 5) {
		let name = this.filterMask(node, lex._ident);
		this.push(LOAD_METH, name.val(this.lx));
	}
	let args = selectNode(node, Args);
	this.genArgs(args);
}

Assembler.prototype.genFuncCall = function(node) {
	this.gensert(node, ast.Functioncall);
	let prefix = selectNode(node, ast.Prefix),
		suffix = selectNodes(node, ast.Suffix),
		call = selectNode(node, ast.Call);
	this.genPrefix(prefix);
	for (let suf of suffix) {
		this.genPrefix(suffix);
	}
	this.genCall(call);
}

Assembler.prototype.genFuncname = function(node) {
	this.gensert(ast.Funcname);
	let colon = hasLiteral(node, lex._colon);
	let names = Array.from(this.filterMasks(node, lex._ident));
	this.push(LOAD_IDENT, names[0].val());
	for (var i=1; i<names.length - 1; i++) {
		this.push(LOAD_ATTR, names[i].val());
	}
	this.push(colon ? STORE_METH : STORE_ATTR, names[names.length-1].val());
}

Assembler.prototype.genFuncbody = function(node) {
	this.gensert(node, ast.Funcbody);
}

Assembler.prototype.genValue = function(node) {
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
			this.push(LOAD_NUM, this.filterMask(node, lex._number).val(this.lx));
			break;
		case 4:
			this.push(LOAD_STR, this.filterMask(node, lex._string).val(this.lx));
			break;
		case 5:
			// TODO not sure how to handle multival
			// maybe compute what we expect? Use 0 or -1 for when it's going to return
			this.push(LOAD_VARARG);
			break;
		case 6:
			this.genFuncbody(selectNode(selectNode(node, ast.Functiondef), ast.Funcbody));
			break;
		case 7:
			this.genTable(selectNode(node, ast.Tableconstructor));
			break;
		case 8:
			this.genFuncCall(selectNode(node, ast.Functioncall));
			break;
		case 9:
			this.genVar(selectNode(node, ast.Var));
			break;
		case 10: {
			var exp = selectNode(node, ast.Exp);
			this.genExp(exp);
			break;
		}
	}
}

Assembler.prototype.genExp = function(node) {
	this.gensert(node, ast.Exp);
	if (node.type >> 5) {
		let value = selectNode(node, ast.Value);
		let binop = selectNode(node, ast.Binop);
		if (binop) {
			let rexp = selectNode(node, ast.Exp);
			this.genValue(value);
			this.genExp(rexp);
			switch (binop.type >> 5) {
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
					// TODO and/or need to be short circuiting
				case 19: this.push(BIN_AND); break; // and
				case 20: this.push(BIN_OR); break // or
			}
		} else {
			this.genValue(value);
		}
	} else {
		let unop = selectNode(node, ast.Unop);
		let exp = selectNode(node, ast.Exp);
		this.genExp(exp);
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
}

Assembler.prototype.genStat = function(node) {
	this.gensert(node, ast.Stat);
	switch (node.type >> 5) {
		case 0: // ;
			break;
		case 1: { // varlist = explist
			let vars = Array.from(selectNodes(selectNode(ast.Varlist), ast.Var)),
				exps = selectNodes(selectNode(ast.Explist), ast.Exp);
			for (let exp of exps) {
				genExp(exp);
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
			this.push(LABEL, name.val(this.lx));
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
			this.push(GOTO, name.val(this.lx));
			break;
		}
		case 6:
			this.genBlock(selectNode(node, ast.Block));
			break;
		case 7: { // while
			let lab0 = this.genLabel(), lab1 = this.genLabel();
			this.pushScope(lab1);
			this.push(LABEL, lab0);
			this.genExp(selectNode(node, ast.Exp));
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
			this.genExp(selectNode(node, ast.Exp));
			this.push(JIFNOT, lab0);
			this.push(LABEL, lab1);
			this.popScope();
			break;
		}
		case 9: {
			/* If there's an else then exps.length != blocks.length
			*/
			let exps = Array.from(selectNodes(node, ast.Exp));
			let blocks = Array.from(selectNodes(node, ast.Block));
			let endlab = this.genLabel();
			for (var i=0; i<exps.length; i++) {
				let lab = this.genLabel();
				this.genExp(exps[i]);
				block.push(JIFNOT, lab);
				this.genBlock(blocks[i]);
				if (i+1 < blocks.length) block.push(GOTO, endlab);
				block.push(LABEL, lab);
			}
			if (i < blocks.length) {
				this.genBlock(b, blocks[i]);
			}
			this.push(LABEL, endlab);
			break;
		}
		case 10:
			let lab0 = this.genLabel(), endlab = this.genLabel();
			this.pushScope(endlab);
			let exps = Array.from(selectNodes(node, ast.Exp));
			this.genExp(exps[0]);
			this.genExp(exps[1]);
			if (exps.length > 2) {
				this.genExp(exps[2]);
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
		case 11:
			let lab0 = this.genLabel(), endlab = this.genLabel();
			this.pushScope(endlab);
			let exps = selectNodes(selectNode(node, ast.Explist), ast.Exp);
			let names = filterMasks(selectNode(node, ast.Namelist), lex._ident);
			for (let exp of exps) {
				this.genExp(exp);
			}
			this.push(FORTIFY, LABEL, lab0);
			this.push(FOR_NEXT, endlab);
			for (let name of names) {
				this.push(STORE_IDENT, name.val());
			}
			this.genBlock(selectNode(node, ast.Block));
			this.push(GOTO, lab0);
			this.popScope();
			break;
		case 12: {
			this.genFuncbody(selectNode(node, ast.Funcbody));
			this.genFuncname(selectNode(node, ast.Funcname), false);
			break;
		}
		case 13: {
			this.genFuncbody(selectNode(node, ast.Funcbody));
			this.push(STORE_IDENT, this.filterMask(node, lex._ident).val(this.lx));
			break;
		}
		case 14: {
			let names = Array.from(this.filterMask(selectNode(ast.Namelist), lex._ident)),
				exps = selectNodes(selectNode(ast.Explist), ast.Exp);
			for (let exp of exps) {
				genExp(exp);
			}
			for (let i=names.length-1; i>=0; i--) {
				this.push(STORE_IDENT, names[i].val(this.lx));
			}
			break;
		}
	}
}

Assembler.prototype.genRet = function(node) {
	// TODO tail calls
	this.gensert(node, ast.Retstat);
	let exps = selectNodes(selectNode(ast.Explist), ast.Exp), i = 0;
	for (let exp of exps) {
		this.genExp(exp);
		i++;
	}	
	this.push(RETURN, i);
}

Assembler.prototype.genBlock = function(node) {
	this.gensert(node, ast.Block);
	for (let stat of selectNodes(node, ast.Stat)) {
		this.genStat(stat);
	}
	for (let ret of selectNode(node, ast.Retstat)) {
		this.genRet(ret);
	}
}

Assembler.prototype.genChunk = function(node) {
	this.gensert(node, -2 & 31);
	let block = selectNode(node, ast.Block);
	if (block) return this.genBlock(block);
}

function assemble(lx, ast) {
	var asm = new Assembler(lx);
	asm.genChunk(ast);
	return asm;
}

exports.assemble = assemble;
