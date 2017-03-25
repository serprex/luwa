"use strict";
var lex = require("./lex");

// Thanks lua-users.org/lists/lua-l/2010-12/msg00699.html
var Block = 0,
	Stat = 1,
	Retstat = 2,
	Label = 3,
	Funcname = 4,
	Varlist = 5,
	Var = 6,
	Namelist = 7,
	Explist = 8,
	Exp = 9,
	Prefix = 10,
	Functioncall = 11,
	Args = 12,
	Functiondef = 13,
	Funcbody = 14,
	Parlist = 15,
	Tableconstructor = 16,
	Fieldlist = 17,
	Field = 18,
	Fieldsep = 19,
	Binop = 20,
	Unop = 21,
	Value = 22,
	Index = 23,
	Call = 24,
	Suffix = 25;

var name = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() & lex._ident)
		yield t;
};
var number = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() & lex._number)
		yield t;
};
var slit = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() & lex._string)
		yield t;
};
var _s = [], s = r => _s[r] || (_s[r] = function*(x, p) {
	var t = x.next(p);
	if (t && t.val() == r) {
		yield t;
	}
});
var _o = [], o = n => _o[n] || (_o[n] = function*(x, p) {
	yield *rules[n](x, x.spawn(n, p));
});
function seq() {
	var args = [];
	Array.prototype.push.apply(args, arguments);
	function *seqf(x, p, i) {
		if (i == args.length - 1) {
			yield *args[i](x, p);
		} else {
			for (let ax of args[i](x, p)) {
				yield *seqf(ax, p, i+1);
			}
		}
	}
	return (x, p) => seqf(x, x.spawn(-1, p), 0);
}
var many = f => {
	function* manyf(x, p) {
		for (let fx of f(x, p)) {
			yield *manyf(fx, p);
		}
		yield x;
	};
	return (x, p) => manyf(x, x.spawn(-2, p));
}
var maybe = f => function*(x, p) {
	yield *f(x, p);
	yield x;
};
function of() {
	var args = [];
	Array.prototype.push.apply(args, arguments);
	return function*(x, p){
		var i = 32;
		for (let a of args) {
			yield *a(x, x.spawn(i++, p));
		}
	}
}

var rules = [];
rules[Block] = seq(many(o(Stat)), maybe(o(Retstat)));
rules[Stat] = of(
	s(lex._semi),
	seq(o(Varlist), s(lex._set), o(Explist)),
	o(Functioncall),
	o(Label),
	s(lex._break),
	seq(s(lex._goto), name),
	seq(s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._while), o(Exp), s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._repeat), o(Block), s(lex._until), o(Exp)),
	seq(s(lex._if), o(Exp), s(lex._then), o(Block), many(seq(s(lex._elseif), o(Exp), s(lex._then), o(Block))), maybe(seq(s(lex._else), o(Block))), s(lex._end)),
	seq(s(lex._for), name, s(lex._set), o(Exp), s(lex._comma), o(Exp), maybe(seq(s(lex._comma), o(Exp))), s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._for), o(Namelist), s(lex._in), o(Explist), s(lex._do), o(Block), s(lex._end)),
	seq(s(lex._function), o(Funcname), o(Funcbody)),
	seq(s(lex._local), s(lex._function), name, o(Funcbody)),
	seq(s(lex._local), o(Namelist), maybe(seq(s(lex._set), o(Explist))))
);
rules[Retstat] = seq(s(lex._return), maybe(o(Explist)), maybe(s(lex._semi)));
rules[Label] = seq(s(lex._label), name, s(lex._label));
rules[Funcname] = seq(name, many(seq(s(lex._dot), name)), maybe(s(lex._colon), name));
rules[Varlist] = seq(o(Var), many(seq(s(lex._comma), o(Var))));
rules[Var] = of(seq(o(Prefix), maybe(o(Suffix)), o(Index)), name);
rules[Namelist] = seq(name, many(seq(s(lex._comma), name)));
rules[Explist] = seq(o(Exp), many(seq(s(lex._comma), o(Exp))));
rules[Exp] = of(seq(o(Unop), o(Exp)), seq(o(Value), maybe(seq(o(Binop), o(Exp)))));
rules[Prefix] = of(seq(s(lex._pl), o(Exp), s(lex._pr)), name);
rules[Functioncall] = seq(o(Prefix), maybe(o(Suffix)), o(Call));
rules[Args] = of(seq(s(lex._pl), maybe(o(Explist)), s(lex._pr)), o(Tableconstructor), slit)
rules[Functiondef] = seq(s(lex._function), o(Funcbody));
rules[Funcbody] = seq(s(lex._pl), maybe(o(Parlist)), s(lex._pr), o(Block), s(lex._end));
rules[Parlist] = of(
	seq(o(Namelist), maybe(seq(s(lex._comma), s(lex._dotdotdot)))),
	s(lex._dotdotdot));
rules[Tableconstructor] = seq(s(lex._cl), maybe(o(Fieldlist)), s(lex._cr));
rules[Fieldlist] = seq(o(Field), maybe(seq(o(Fieldsep), o(Field))), maybe(o(Fieldsep)));
rules[Field] = of(
	seq(s(lex._sl), o(Exp), s(lex._sr), s(lex._set), o(Exp)),
	seq(name, s(lex._set), o(Exp)),
	o(Exp));
rules[Fieldsep] = of(s(lex._comma), s(lex._semi));
rules[Binop] = of(s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod), s(lex._band),
	s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot), s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq), s(lex._and), s(lex._or));
rules[Unop] = of(s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot));
rules[Value] = of(s(lex._nil), s(lex._false), s(lex._true), number, slit, s(lex._dotdotdot), o(Functiondef), o(Tableconstructor), o(Functioncall), o(Var), seq(s(lex._pl), o(Exp), s(lex._pr)));
rules[Index] = of(
	seq(s(lex._sl), o(Exp), s(lex._sr)),
	seq(s(lex._dot), name));
rules[Call] = of(o(Args), seq(s(lex._colon), name, o(Args)));
rules[Suffix] = of(o(Call), o(Index));

function Builder(lx, li, mo, fa, ty) {
	this.lx = lx;
	this.li = li;
	this.mother = mo;
	this.father = fa;
	this.type = ty;
}
Builder.prototype.val = function() {
	return this.lx.lex[this.li];
}
Builder.prototype.next = function(p) {
	return new Builder(this.lx, this.li+1, this, p, -3);
}
Builder.prototype.spawn = function(ty, p) {
	return new Builder(this.lx, this.li, this, p, ty);
}

var _chunk = seq(rules[Block], s(0));
function parse(lx) {
	var root = new Builder(lx, -1, null, null, -4);
	var end = _chunk(root, root).next().value, start = end;
	console.log(window.PARSE = end);
	console.log(window.ROOT = root);
	while (start.mother) start = start.mother;
	makeChildren(end);
	var bc = [];
	astVisit(root, bc);
	console.log(window.BYTES = bc);
}

function *selectNode(node, type) {
	for (let ch of node.fathered) {
		if (ch.type < 0 || ch.type > 31) {
			yield *selectNode(ch, type);
		} else if (ch.type == type) {
			yield ch;
		}
	}
}

function *filterMask(node, mask) {
	for (let ch of node.fathered) {
		yield
	}
}

function Namelist_names(node) {
	if (!node.fathered) {
		if (node.type & lex.ident) {
			yield node;
		}
	} else {
		for (let ch of node.fathered) {
			yield *Namelist_names(ch);
		}
	}
}

function Explist_exps(node) {
	return selectNode(node, Exp);
}

function genValue(node, bc) {
}

function genExp(node, bc) {
	if (node.type != Exp) console.log(node, "Not an Exp");
	if (node.fathered.length != 1) console.log(node, "Fathered.length <> 1");
	let ofc = node.fathered[0];
	if (ofc.type == 32) {
		let unop = selectNode(ofc, Unop);
		let exp = selectNode(ofc, Exp);
		genExp(exp, bc);
		switch (unop.type) {
			case 32: // minus
				bc.push(UNARY_MINUS);
				break;
			case 33: // not
				bc.push(UNARY_NOT);
				break;
			case 34: // hash
				bc.push(UNARY_HASH);
				break;
			case 35: // bnot
				bc.push(UNARY_BNOT);
				break;
		}
	} else {
		let value = selectNode(ofc, Value).next().value;
		let binop = selectNode(ofc, Binop).next().value;
		if (binop) {
			let rexp = selectNode(ofc, Exp);
			genValue(value, bc);
			genExp(rexp, bc);
		} else {
			getValue(value, bc);
		}
	}
}

function genStoreLocal(node, bc) {
	if (!(node.val() & name) || node.type != -3) console.log(node, "Not a name");
	var val = node.val();
	bc.push(LOAD_IDENT, node.val());
}

function astVisit(node, bc) {
	switch (node.type) {
	case -4:
		for (let child of node.fathered) {
			astVisit(node);
		}
		break;
	case -3:
		console.log(node, "Unexpected terminal");
		break;
	case -2:
		console.log(node, "Unexpected many");
		break;
	case -1:
		console.log(node, "Unexpected seq");
		break;
	case 0: // Block
		for (let child of node.fathered) {
			astVisit(node);
		}
		break;
	case 1: { // Stat
		if (child.fathered.length != 1) console.log("Stat has fathered more than 1 node", child.fathered);
		let ofc = child.fathered[0];
		switch (ofc.type&0x31) {
			case 0:
				break;
			case 1:
				break;
			case 2:
				break;
			case 3:
				break;
			case 4:
				break;
			case 5:
				break;
			case 6:
				break;
			case 7:
				break;
			case 8:
				break;
			case 9:
				break;
			case 10:
				break;
			case 11:
				break;
			case 12:
				break;
			case 13:
				break;
			case 14: {
				let names = Array.from(Namelist_names(selectNode(Namelist).next().value)), exps = Explist_exps(selectNode(Explist).next().value);
				for (let exp of exps) {
					genExp(exp);
				}
				for (let i=names.length-1; i>=0; i--) {
					genStoreLocal(names[i]);
				}
				break;
			}
		}
		break;
	}
	case 2: // Retstat
		break;
	case 3: // Label
		break;
	case 4: // Funcname
		break;
	case 5: // Varlist
		break;
	case 6: // Var
		break;
	case 7: // Namelist
		break;
	case 8: // Explist
		break;
	case 9: // Exp
		break;
	case 10: // Prefix
		break;
	case 11: // Functioncall
		break;
	case 12: // Args
		break;
	case 13: // Functiondef
		break;
	case 14: // Funcbody
		break;
	case 15: // Parlist
		break;
	case 16: // Tableconstructor
		break;
	case 17: // Fieldlist
		break;
	case 18: // Field
		break;
	case 19: // Fieldsep
		break;
	case 20: // Binop
		break;
	case 21: // Unop
		break;
	case 22: // Value
		break;
	case 23: // Index
		break;
	case 24: // Call
		break;
	case 25: // Suffix
		break;
	default:
		console.log(node, "Unexpected of");
		break;
	}
}

function makeChildren(child) {
	if (!child) return;
	if (child.mother){
		if (!child.mother.mothered) {
			child.mother.mothered = [child];
			makeChildren(child.mother);
		}
		else child.mother.mothered.push(child);
	}
	if (child.father){
		if (!child.father.fathered) {
			child.father.fathered = [child];
			makeChildren(child.father);
		}
		else child.father.fathered.push(child);
	}
}


exports.parse = parse;
