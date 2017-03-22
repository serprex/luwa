"use strict";
var lex = require("./lex");

// Thanks lua-users.org/lists/lua-l/2010-12/msg00699.html
var Block = 1,
	Stat = 2,
	Retstat = 3,
	Label = 4,
	Funcname = 5,
	Varlist = 6,
	Var = 7,
	Namelist = 8,
	Explist = 9,
	Exp = 10,
	Prefix = 11,
	Functioncall = 12,
	Args = 13,
	Functiondef = 14,
	Funcbody = 15,
	Parlist = 16,
	Tableconstructor = 17,
	Fieldlist = 18,
	Field = 19,
	Fieldsep = 20,
	Binop = 21,
	Unop = 22,
	Value = 23,
	Index = 24,
	Call = 25,
	Suffix = 26;

var name = x => {
	var t = x.pop();
	if (!lex.rekey.test(t) && /^\w+$/.test(t) && !/^\d/.test(t))
		return true;
	x.push(t);
	return false;
};
var number = x => {
	var t = x.pop();
	// TODO fractional hex
	if (/^(0x[\da-fA-F]+|-?(\d+|\d+\.\d+|\.\d+)(?:[eE][+-]?\d+)?)$/.test(t)) {
		console.log(t, "num");
		return true;
	}
	x.push(t);
	console.log(t, NaN);
	return false;
};
var slit = x => {
	var t = x.pop();
	if (/\0\d+/.test(t))
		return true;
	x.push(t);
	return false;
};
var s = r => x => {
	var t = x.pop();
	if (t == r) {
		console.log(t, r, true);
		return true;
	}
	console.log(t, r, false);
	x.push(t);
	return false;
};
var o = n => x => rules[[console.log(n),n][1]](x);
var seq2 = (a, b) => x => {
	var sc = x.scope();
	if (a(x) && b(x)) {
		console.log(x, "commit");
		x.commit(sc);
		return true;
	}
	x.reset(sc);
	return false;
};
var of2 = (a, b) => x => a(x) || b(x);
var many = f => x => {
	while (f(x));
	return true;
};
var maybe = f => x => {
	f(x);
	return true;
};
function of(a, b) {
	var f = of2(a, b);
	for (var i = 2; i < arguments.length; i++)
		f = of2(f, arguments[i]);
	return f;
}

function seq(a, b) {
	var f = seq2(a, b);
	for (var i = 2; i < arguments.length; i++)
		f = seq2(f, arguments[i]);
	return f;
}

var rules = [];
rules[Block] = seq(many(o(Stat)), maybe(o(Retstat)));
rules[Stat] = of(
	s(';'), seq(o(Varlist), s('='), o(Explist)),
	o(Functioncall), o(Label), s('break'), seq(s('goto'), name),
	seq(s('do'), o(Block), s('end')), seq(s('while'), o(Exp), s('do'), o(Block), s('end')),
	seq(s('repeat'), o(Block), s('until'), o(Exp)),
	seq(s('if'), o(Exp), s('then'), o(Block), many(seq(s('elseif'), o(Exp), s('then'), o(Block))), maybe(seq(s('else'), o(Block))), s('end')),
	seq(s('for'), name, s('='), o(Exp), s(','), o(Exp), maybe(seq(s(','), o(Exp))), s('do'), o(Block), s('end')),
	seq(s('for'), o(Namelist), s('in'), o(Explist), s('do'), o(Block), s('end')),
	seq(s('function'), o(Funcname), o(Funcbody)),
	seq(s('local'), s('function'), name, o(Funcbody)),
	seq(s('local'), o(Namelist), maybe(seq(s('='), o(Explist))))
);
rules[Retstat] = seq(s('return'), maybe(o(Explist)), maybe(s(';')));
rules[Label] = seq(s('::'), name, s('::'));
rules[Funcname] = seq(name, many(seq(s('.'), name)), maybe(s(':'), name));
rules[Varlist] = seq(o(Var), many(seq(s(','), o(Var))));
rules[Var] = of(name, seq(o(Prefix), maybe(o(Suffix)), o(Index)));
rules[Namelist] = seq(name, many(seq(s(','), name)));
rules[Explist] = seq(o(Exp), many(seq(s(','), o(Exp))));
rules[Exp] = of(seq(o(Unop), o(Exp)), seq(o(Value), maybe(seq(o(Binop), o(Exp)))));
rules[Prefix] = of(seq(s('('), o(Exp), s(')')), name);
rules[Functioncall] = seq(o(Prefix), maybe(o(Suffix)), o(Call));
rules[Args] = of(seq(s('('), maybe(o(Explist)), s(')')), o(Tableconstructor), slit)
rules[Functiondef] = seq(s('function'), o(Funcbody));
rules[Funcbody] = seq(s('('), maybe(o(Parlist)), s(')'), o(Block), s('end'));
rules[Parlist] = of(seq(o(Namelist), maybe(seq(s(','), s('...')))), s('...'));
rules[Tableconstructor] = seq(s('{'), maybe(o(Fieldlist)), s('}'));
rules[Fieldlist] = seq(o(Field), maybe(seq(o(Fieldsep), o(Field))), maybe(o(Fieldsep)));
rules[Field] = of(seq(s('['), o(Exp), s(']'), s('='), o(Exp)), seq(name, s('='), o(Exp)), o(Exp));
rules[Fieldsep] = of(s(','), s(';'));
rules[Binop] = of(s('+'), s('-'), s('*'), s('/'), s('//'), s('^'), s('%'), s('&'),
	s('~'), s('|'), s('>>'), s('<<'), s('..'), s('<'), s('<='), s('>'), s('>='), s('=='), s('~='), s('and'), s('or'));
rules[Unop] = of(s('-'), s('not'), s('#'), s('~'));
rules[Value] = of(s('nil'), s('false'), s('true'), number, slit, s('...'), o(Functiondef), o(Tableconstructor), o(Functioncall), o(Var), seq(s('('), o(Exp), s(')')));
rules[Index] = of(seq(s('['), o(Exp), s(']')), seq(s('.'), name));
rules[Call] = of(o(Args), seq(s(':'), name, o(Args)));
rules[Suffix] = of(o(Call), o(Index));

function Builder(lx) {
	this.lx = lx;
	this.li = 0;
	this.ast = new Node(null, ';');
}
Builder.prototype.push = function(tok) {
	this.li--;
}
Builder.prototype.pop = function() {
	var c = this.li >= this.lx.lex.length ? "" : this.lx.lex[this.li];
	this.li++;
	return c;
}
Builder.prototype.scope = function() {
	return this.li;
}
Builder.prototype.reset = function(li) {
	this.li = li;
}
Builder.prototype.commit = function(li) {
}
Builder.prototype.parse = function() {
	rules[Block](this);
	return this.li == this.lx.lex.length;
}

function Node(p, tok) {
	this.tok = tok;
	this.p = p;
	this.chs = [];
}
Node.prototype.spawn = function spawn(tok) {
	return new Node(this, tok);
}

exports.Builder = Builder;
exports.Node = Node;
