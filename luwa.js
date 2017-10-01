"use strict";
const lex = require("./lex"),
	ast = require("./ast"),
	bc = require("./bc"),
	runbc = require("./runbc");

exports.eval = function(rt, line, e = require("./env")()) {
	const l = new lex.Lex2(rt, line);
	console.log(rt.obj2js(l.lex));
	const a = ast.parse(l);
	const b = bc.assemble(l, a);
	const r = runbc.run(b, e);
	l.free();
	return r;
}

exports.runSource = function(source, imp){
	var l, a, b;
	console.time("lua");
	console.log(l = new lex.Lex(source), a = ast.parse(l), b = bc.assemble(l, a), runbc.run(b));
	console.timeEnd("lua");
}
