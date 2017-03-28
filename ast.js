"use strict";
const lex = require("./lex");

// Thanks lua-users.org/lists/lua-l/2010-12/msg00699.html
const Block = exports.Block = 0,
	Stat = exports.Stat = 1,
	Retstat = exports.Retstat = 2,
	Label = exports.Label = 3,
	Funcname = exports.Funcname = 4,
	Varlist = exports.Varlist = 5,
	Var = exports.Var = 6,
	Namelist = exports.Namelist = 7,
	Explist = exports.Explist = 8,
	Exp = exports.Exp = 9,
	Prefix = exports.Prefix = 10,
	Functioncall = exports.Functioncall = 11,
	Args = exports.Args = 12,
	Functiondef = exports.Functiondef = 13,
	Funcbody = exports.Funcbody = 14,
	Parlist = exports.Parlist = 15,
	Tableconstructor = exports.Tableconstructor = 16,
	Fieldlist = exports.Fieldlist = 17,
	Field = exports.Field = 18,
	Fieldsep = exports.Fieldsep = 19,
	Binop = exports.Binop = 20,
	Unop = exports.Unop = 21,
	Value = exports.Value = 22,
	Index = exports.Index = 23,
	Call = exports.Call = 24,
	Suffix = exports.Suffix = 25;

function*name(lx, x, p) {
	var t = x.next(p);
	if (t.val(lx) & lex._ident)
		yield t;
};
function*number(lx, x, p) {
	var t = x.next(p);
	if (t.val(lx) & lex._number)
		yield t;
};
function*slit(lx, x, p) {
	var t = x.next(p);
	if (t.val(lx) & lex._string)
		yield t;
};
const _s = [], s = r => _s[r] || (_s[r] = function*(lx, x, p) {
	var t = x.next(p);
	if (t.val(lx) == r) {
		yield t;
	}
});
const _o = [], o = n => _o[n] || (_o[n] = function*(lx, x, p) {
	yield *rules[n](lx, x, p);
});
function seqcore(args) {
	function *seqf(lx, x, p, i) {
		if (i == args.length - 1) {
			yield *args[i](lx, x, p);
		} else {
			for (let ax of args[i](lx, x, p)) {
				yield *seqf(lx, ax, p, i+1);
			}
		}
	}
	return seqf;
}
function seq() {
	const args = [];
	for (var i=0; i<arguments.length; i++) args[i] = arguments[i];
	const seqf = seqcore(args);
	return (lx, x, p) => seqf(lx, x, p, 0);
}
function sf(o) {
	const args = [];
	for (var i=1; i<arguments.length; i++) args[i-1] = arguments[i];
	const seqf = seqcore(args);
	rules[o] = (lx, x, p) => seqf(lx, x, x.spawn(o, p), 0);
}
var many = f => function*manyf(lx, x, p) {
	for (let fx of f(lx, x, p)) {
		yield *manyf(lx, fx, p);
	}
	yield x;
};
var maybe = f => function*(lx, x, p) {
	yield *f(lx, x, p);
	yield x;
};
function of(o) {
	const args = [];
	for (var i=1; i<arguments.length; i++) args[i-1] = arguments[i];
	rules[o] = function*(lx, x, p){
		let i = o;
		for (let a of args) {
			yield *a(lx, x, x.spawn(i, p));
			i += 32;
		}
	}
}

const rules = [];
sf(Block, many(o(Stat)), maybe(o(Retstat)));
of(Stat,
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
sf(Retstat, s(lex._return), maybe(o(Explist)), maybe(s(lex._semi)));
sf(Label, s(lex._label), name, s(lex._label));
sf(Funcname, name, many(seq(s(lex._dot), name)), maybe(s(lex._colon), name));
sf(Varlist, o(Var), many(seq(s(lex._comma), o(Var))));
of(Var, name, seq(o(Prefix), many(o(Suffix)), o(Index)));
sf(Namelist, name, many(seq(s(lex._comma), name)));
sf(Explist, o(Exp), many(seq(s(lex._comma), o(Exp))));
of(Exp, seq(o(Unop), o(Exp)), seq(o(Value), maybe(seq(o(Binop), o(Exp)))));
of(Prefix, name, seq(s(lex._pl), o(Exp), s(lex._pr)));
sf(Functioncall, o(Prefix), many(o(Suffix)), o(Call));
of(Args,
	seq(s(lex._pl), maybe(o(Explist)), s(lex._pr)),
	o(Tableconstructor),
	slit);
sf(Functiondef, s(lex._function), o(Funcbody));
sf(Funcbody, s(lex._pl), maybe(o(Parlist)), s(lex._pr), o(Block), s(lex._end));
of(Parlist,
	seq(o(Namelist), maybe(seq(s(lex._comma), s(lex._dotdotdot)))),
	s(lex._dotdotdot));
sf(Tableconstructor, s(lex._cl), maybe(o(Fieldlist)), s(lex._cr));
sf(Fieldlist, o(Field), many(seq(o(Fieldsep), o(Field))), maybe(o(Fieldsep)));
of(Field,
	seq(s(lex._sl), o(Exp), s(lex._sr), s(lex._set), o(Exp)),
	seq(name, s(lex._set), o(Exp)),
	o(Exp));
of(Fieldsep, s(lex._comma), s(lex._semi));
of(Binop,
	s(lex._plus), s(lex._minus), s(lex._mul), s(lex._div), s(lex._idiv), s(lex._pow), s(lex._mod),
	s(lex._band), s(lex._bnot), s(lex._bor), s(lex._rsh), s(lex._lsh), s(lex._dotdot),
	s(lex._lt), s(lex._lte), s(lex._gt), s(lex._gte), s(lex._eq), s(lex._neq), s(lex._and), s(lex._or));
of(Unop, s(lex._minus), s(lex._not), s(lex._hash), s(lex._bnot));
of(Value,
	s(lex._nil), s(lex._false), s(lex._true), number, slit, s(lex._dotdotdot),
	o(Functiondef), o(Tableconstructor), o(Functioncall), o(Var),
	seq(s(lex._pl), o(Exp), s(lex._pr)));
of(Index,
	seq(s(lex._sl), o(Exp), s(lex._sr)),
	seq(s(lex._dot), name));
of(Call,
	o(Args),
	seq(s(lex._colon), name, o(Args)));
of(Suffix, o(Call), o(Index));
const _chunk = seq(rules[Block], s(0));

function Builder(li, mo, fa, ty) {
	this.li = li;
	this.type = ty;
	this.mother = mo;
	this.father = fa;
	this.fathered = [];
}
Builder.prototype.val = function(lx) {
	return lx.lex[this.li];
}
Builder.prototype.next = function(p) {
	return new Builder(this.li+1, this, p, -1);
}
Builder.prototype.spawn = function(ty, p) {
	return new Builder(this.li, this, p, ty);
}

function parse(lx) {
	const root = new Builder(-1, null, null, -2);
	for (let child of rules[Block](lx, root, root)) {
		if (child.li == lx.lex.length - 2) {
			do {
				var father = child.father, prev_father = child;
				while (father) {
					father.fathered.push(prev_father);
					if (father.fathered.length > 1) break;
					prev_father = father;
					father = father.father;
				}
			} while (child = child.mother);
			const b0 = root.fathered[0];
			b0.father = b0.mother = null;
			return b0;
		}
	}
}

exports.parse = parse;
