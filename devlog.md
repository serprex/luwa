# luwa devlog

Imported from https://www.patreon.com/serprex (deactivated for inactivity).

## Day One

*2017-03-21* · https://www.patreon.com/serprex/posts/day-one-8510733

Yesteday I finally wrote a readme for my Befunge https://github.com/serprex/Befunge repo. It gave me some time to reflect, & based on the past few days beforehand I realized I should take a stab at trying to take my ideas on how to further optimize the WASM JIT to a more practical application: Lua

Lua's going to be a lot more work than Befunge. But maybe the value of this work will be worth it

I'm going to get my feet wet by starting with a parser in JS. I'm thinking I should have a tracing VM in wasm which eventually sends chunks of wasm back to JS land. Lazy compilation will need to stitch modules together. I'm going to have research various code layouts to see what clicks best with Firefox & Chrome. But I'm going to try not get ahead of myself. Parser first

https://github.com/serprex/luwa  [first commit](http:// https://github.com/serprex/luwa/commit/ddbf7c2117afd2105af82e5e990b0bf330ca777e) 

## Day Two

*2017-03-22* · https://www.patreon.com/serprex/posts/day-two-8524353

https://github.com/serprex/luwa/commit/2a182e317f610c93c25c924a546aafcc6631aba2

Started on parser portion. Shortcut taken with not parsing numbers is biting me. Still lots to put together. Still need to figure out how to refit these parser combinators to produce an AST rather than a bool. Not enough time in the day

## Day Three

*2017-03-23* · https://www.patreon.com/serprex/posts/day-three-8536428

https://github.com/serprex/luwa/commit/ec5716857f2d0f9af9cdd0674f06a639d9249b38

'Parser Generator Combinators' seem much less aesthetical than 'Parser Combinators'. Somewhere out there someone worked them out in Java independently & called them AbstractParserFactoryFactory. Damn you Wittgenstein

I found myself rather annoyed writing this bit. Hours spent staring at the number 53 (token: .)

Whenever I search for parser combinator things it seems to pull up Scala questions on stackoverflow. This pushed me in the direction of using Builder immutably. Right now it's really just an int that changes, when it's throwing ASTs around I'll have to think of some way to share data. This doesn't seem most efficient

[Also I rewrote the lexer to be a giant loop switch rather than that regex split hack.](https://github.com/serprex/luwa/commit/e8397621b366f3dc42e80b2810773bc9db2e4ca0)  Moves all the strings/identifiers/numbers into tables & puts them behind bitflags. Much faster getting away from strings asap. A lot of tokenizers seem to like to create a bunch of objects with span info etc, but can't resist integer blobs

Wish I could've gotten an AST today but covering up gaps will have to do

## Day Four, belated

*2017-03-24* · https://www.patreon.com/serprex/posts/day-four-belated-8551066

[This AST is one messed up family tree.](https://github.com/serprex/luwa/commit/03c6c569149a7f603a75f7bc832d3635a2db2239) Have been trying to iterate ideas on how to effectively group. Concept was forming yesterday but wanted a sober mind to verify & clean up in the morning. Simplified, the idea is that

local x = 5 + 6 + 2

Has an AST built up immutably by returning the root pointing at 2. 2's mother is +, +'s mother is 6, 6's mother is +, etc. Meanwhile fathering is a bit complicated: 2 & + share a father whoes father is shared with 6 (may have a bug right now where the father of 2 & + is 6)

\[local x = (5 \[+ (6 \[+ 2\])\])\]

The bracketing shows the father grouping. Going to have to figure out how to then extract the useful information based on block type next. [I recently helped refactor a shunting yard algorithm,](https://github.com/squiidz/yard/pull/2)  so hopefully I'll be freshened up enough to apply that to this messed up family tree

## Day Six

*2017-03-26* · https://www.patreon.com/serprex/posts/day-six-8570105

[I came up with a better parenting structure,](https://github.com/serprex/luwa/commit/8d2fea741b261c751c43b54e706acbd53f6acc7c)[then I refactored seq2/seq3/seq4/seq5/seq6/seq7/seq8/seq9/seq10 into one function,](https://github.com/serprex/luwa/commit/ac81173cd204cc5f5fac9b0a716efe6944339b27)[then I went to mentor at HTML150,](https://twitter.com/theo_mart9/status/845765465209257986)[got to program Luwa some while there,](https://github.com/serprex/luwa/commit/3c06ee4c1b48275eca8376db2adb74dbded9b010)[then I created brainfuckwebassembly,](https://github.com/serprex/brainwebfuckassembly)[before finally getting back on task & grinding away at AST processing & AST size reduction](https://github.com/serprex/luwa/commit/e521f3958b001e075fc1d38c87d73260222596e6) \#nohangover    

## Day Seven

*2017-03-27* · https://www.patreon.com/serprex/posts/day-seven-8579491

[Obligatory](https://www.youtube.com/watch?v=pyz6MnWFAIg)

[Moved bytecode gen out of ast.js](https://github.com/serprex/luwa/commit/e07c61aae1389498cf7a8650666a06960b55d9f6) as codegen is pretty encapsulated from treegen & has grown to be more lines

[Refactor fathered & remove mothered while continuing to implement misc codegen](https://github.com/serprex/luwa/commit/27ba7fdd426c203ae4bb9eb543041537dfa757ba), [whoops I broke makeChildren there](https://github.com/serprex/luwa/commit/828163fe3ed2032b26bc413803ab90effe3afa0b) (so many fathereds..)

[Tried to optimize ast.Builder memory layout](https://github.com/serprex/luwa/commit/b56bcc2938dcddbbadf837b5ff171bddaa45ba59), Chrome didn't like it, Firefox didn't seem to care. I think it had negligible impact because it the redundancy of the Lexer reference has just been shifted to the generators' state. Really want a shared closure namespace somehow.. This is probably a bad change, will need to revisit at a later point

[More codegen, no more BREAK.](https://github.com/serprex/luwa/commit/a515969633787caaf83d188a782fff815791d897) Plan is that functions will get their own Assembler contexts. Then it'll be trying to match Lua evaluation order (apparently that's unspecified, but de facto..), matching scope, adding in a manner to convert identifiers into strings to unify indexing, which'll remove TABLE\_SET. Oh & wrapping my head around multiple returns..

Feels like not much progress but this is a period of having to put in the grunt work to flesh out visitors, will probably have to rewrite it after too. Haven't tested bytecode gen at all

## Day Eight

*2017-03-28* · https://www.patreon.com/serprex/posts/day-eight-8593339

[Implemented for loops & genFuncname in half hour morning before work](https://github.com/serprex/luwa/commit/40a4bed16d84598a932d111c1f806d88adcd9adf), [got bc to build afterwards](https://github.com/serprex/luwa/commit/8f4b7ef64313d873fa1cd788cd383e263bd59c0f), [spent a couple hours trying to micro optimize-- at least I implemented and/or](https://github.com/serprex/luwa/commit/86a1497265d02b82f8e952ffa6731eebb38148df), [then cut to the chase & implemented a broken eval alongside function defining & tail call opcode gen](https://github.com/serprex/luwa/commit/2c1ef6be42b804144340a2e8fb79cbfeb4bc9e8a)

I was pretty disappointed that moving Builder to be defined in the parse closure in order to get an upval to lx proved a negative impact. I also tried rewriting Binop to use a hand rolled switch, negative impact there too. Probably because I didn't constant propagate the case values. Compile time is 90% ast.js

Operator precedence is nowhere to be seen. Probably best off working the rules into the grammar like the C standard listed out

Nothing to say about runbc. I feel getting bits onto the screen is an important step to any project, & I wasn't feeling it reading intermediate data structures off the console

A lot of this code is written knowing it's planned to be thrown away. I want the Lua stuff moving towards a point that it can be tested so that when I get to writing raw wast I can test for regressions

So my short term goals are: begin unit testing in node, operator precedence, continue working on implementing a more accurate vm class, which'll probably dig up bugs in bc. I might start on basic [metatable](https://www.lua.org/manual/5.3/manual.html#2.4) stuff, just to make sure the architecture fits it in. Rewriting ast.js can wait for when it won't be written in js; perhaps I'll look to create a wasm generator just for it. Again getting away from the short term..

## Day Nine

*2017-03-29* · https://www.patreon.com/serprex/posts/day-nine-8605641

[I couldn't build up the courage to take on operator precedence so I just implemented simple loop optimization in brainwebfuckassembly](https://github.com/serprex/brainwebfuckassembly/commit/62b7e2a6fe8e079eab50490397a7d8f831aa0cfd)

Did some reading on operator precedence. I was coming up with tree rewriting on paper, while leaning towards restructuring grammar to explicitly define precedence, but [precedence climbing](https://en.wikipedia.org/wiki/Operator-precedence_parser#Precedence_climbing_method)  just comes off as the *right way*. Meanwhile there's so much else to do. But I'd like to start by having arithmetic expressions working

I didn't expect to spend so long on the brainwebfuckassembly optimization. Unfortunately I also decided to finish off some vodka so I'll blame that for why it took me a couple hours to realize the mandelbrot program was having memory access errors because of \[\<\<+\>\>-\] *needing* one to only execute the move when the current cell is nonzero *(nb I went with bounds checking rather than zero checking. Maybe a mistake if caching the load)*. Oh well, it got Chrome to go from 2.5s to 2s for Mandel, so pretty good

## Day Ten

*2017-03-30* · https://www.patreon.com/serprex/posts/day-ten-8618790

Of course since I'm using generator combinators instead of recursive descent the pseudocode needs to be inverted into recursion as every yield needs to produce a different return. Wishing I had call/cc to invert this flow control

Lots of time taken up today with chopping wood & controller head aches

[So back to the inverted flow of control.](https://en.wikipedia.org/wiki/Operator-precedence_parser#Pseudo-code) It's the two assignments to rhs from calls to parse\_primary & parse\_expression\_1 which produce multiple results. I'm trying to sketch out how to reflow this on paper, whenever I go to paper I start wishing I had better hand writing, but idea is that the algorithm's idea is to somewhat delimit drops in operator precedence. So..

3 \* 5 + 2 -\> 3 \* 5 | + 2

Or,

3 \* 5 + 2 \* 7 -\> 3 \* 5 | + 2 \* 7

 Or,

3 \* 5 \* 2 + 7 -\> 3 \* 5 \* 2 | + 7

Or,

2 + 3 \* 4 \* 5 + 6 + 7 \* 8 + 9 -\> 2 + 3 \* 4 \* 5 | + 6 + 7 \* 8 | + 9

The issue is that by the time we reach a delimiting point (we'll use the first example for conciseness) we've constructed the tree to have 3 \* 5 already pointing to the main parent, yet to appease tree traversal we need 3 \* 5 to point to a shared father with + 2 which itself points to the top level Exp node

So right now 3 \* 5 + 2 produces (Where a: b means 'a fathers b')

Exp: 3 \* X

X: 5 + 2

& I want

Exp: X + 2

X: 3 \* 5

Which means tree rewriting. Either I break the rules carefully (I've already been considering how to reduce allocations since the lifetime of a node should end upon return of a yield), or I delay this until codegen. The nice thing about codegen is that that'd avoid this logic being done & then backtracked. As it's growing to be that this isn't going to be a most straight forward computation. The other idea rolling around is to try encode the grammar idea (as shown just atop the pseudo code I've already linked to on Wikipedia) into the combinator, seeking to skip the layers by specially encoding rules on the operator (ie if we hit an '&' then tunnel past operators such as \*) but I get the idea that that'll boil down to being one of these operator precedence algorithms all the same

If I defer this to codegen then I'll have to work out that these invalid trees are unique. ie that the computational order they designate is distinct from parenthesized expressions. I'm pretty sure that's the case since parentheses produce Value nodes where they'd otherwise not exist, eg

3 \* 5 + 2 -\> 3 \* X, X is Exp: 5 + 2 whereas 3 \* (5 + 2) -\> 3 \* X, X is Value: Y, Y is Exp: 5 + 2. Thus if I look explicitly for A op1 X, X is Exp: B op2 C, where op2 has lower precedence than op1, rewrite. Sounds simple yet here I am taking three days to get around to even trying it

## Day Eleven

*2017-03-31* · https://www.patreon.com/serprex/posts/day-eleven-8632947

[Code refactoring while implementing tree rewriting which doesn't work](https://github.com/serprex/luwa/commit/ea17054439b0f6c04e678c7aee26b7de3a990855)

Issue is that 3 \* 2 + 4 + 5 is first rewritten to 3 \* (2 + 4) + 5 before rewriting multiplication. The addition rewriting on account of making operators left associative. Easiest fix is to run rewriting in order of precedence, but then I'm no better than encoding the precedence in the grammar. Better will be working out how to steal children since rewrites should never actually move Exp node, only Value nodes. Only hassle there is the complexity of drilling into Exp trees repeatedly to steal all their children. Really should just fit shunting yard into the tree rewriting. Blahh oh well there's progress it handles '3 \* 5 + 2' being 17 not 21

Fun line rewrite: 'let \[rson, op, lson\] = node.fathered;' on account of 3 \* 2 being stored in the order 2 \* 3 in fathered

## Day Twelve

*2017-04-01* · https://www.patreon.com/serprex/posts/day-twelve-8646752

https://github.com/serprex/luwa/commit/e30fffbf61a9817da26de51c282c8802c09e5c33

Huge weight off my chest

shunt should probably push directly to the bytecode rather than be a generator

woo

## Day Thirteen

*2017-04-02* · https://www.patreon.com/serprex/posts/day-thirteen-8660532

Decided to work out multiple valued returns

Which meant learning how those work

So, as code:

function f() return 7, 6 end

local a, b, c, d = 5, f()

{4, 3, f()}

return 5, 6, f()

Also ... produces multiple values

Idea: multiple returns should be consumed once produced before executing more bytecode

So {f()} needs to be MAKE\_TABLE, LOAD f, APPEND\_CALL 0

Similarly introduce RETURN\_CALL. Then add VARG variants APPEND\_VARG, CALL\_VARG, RETURN\_VARG, LOAD\_VARG

So little point here: LOAD\_VARG needs to take a parameter as to how many values it will return. So a, b = ... produces LOAD\_VARG 2, STORE a, STORE b

The issue is that you can have f(1, f()) which means we need an opcode that pipes its multiple return into a function call. So I decided to create CALL\_CALL & friends

An hour later I thought about f(f(f())). CALL\_CALL\_CALL? This caused me to deeply consider allowing multiple return values to exist on the stack for a bit, introducing a LOAD\_MULTI\_SENTINEL to delimit their stack space

I ended up deciding I'd rather have a few variable length instructions. So now CALL & friends take a parameter which states how many chained calls they produce

Currently in the middle of implementing codegen for this

## Day Fourteen

*2017-04-03* · https://www.patreon.com/serprex/posts/day-fourteen-8672471

[Pretty quickly implemented multivalue stuff before evening.](https://github.com/serprex/luwa/commit/1c04c9c7f82abe425f2e1ef8bcdef019b2e1e670)  Getting a pretty clear picture of how stack gets passed around, reviewed Lua's coroutine docs, have a clear idea how that'll work out with the current implementation. Decided to try work out something with simple for loops since they seemed simple, came across how for variables are implicitly scoped to the for loop. Going to have to get back to that since I only really thought about special casing block scope rules for repeat-until including until's expression. Of course multivalue is well coupled to functions so began getting that, got it as far as

x = 2

function f() return x end

return f()

Outputting '2'. Started skimming over thoughts on how to best implement parameters, caller needs to either pass a stack offset to where to start reading locals in from or else caller has to setup locals array & dump rest into ... or the aether

Of course that means the bytecode will need a concept of locals, in which case I should implement locals, but at that point I should implement block scoping, & while I'm in there I should figure out how to have upvals without having a closure keep the entire stack frame around. This is all mostly still being pieced together in my head, which shows by the fact that the [latest commit on the topic](https://github.com/serprex/luwa/commit/7fa0e9f5ad357edc0ffb0201d1ba8b80244a1d94) adds a lot of code, rewrites little, & doesn't really accomplish anything. Also in that puzzle is \_ENV, which I've determined shouldn't need an opcode so much as desugaring. I was thinking there was some magic when in the REPL I found

\> \_ENV

{table}

\> \_G.\_ENV

nil

\> \_G.\_ENV = 3

\> \_ENV

{table}

But it all makes sense now: \_ENV is block scoped to the REPL. So I really can desugar unbound variable accesses to seeking \_ENV from whichever local variable slot scoping assigns it, 'LOAD\_LOCAL envid LOAD\_STR ident LOAD\_INDEX' rather than 'LOAD\_LOCAL identid'. The only challenge is figuring out how to create implicit local declarations, but I can probably get away putting that in the top level parse function

## Day Fifteen

*2017-04-04* · https://www.patreon.com/serprex/posts/day-fifteen-8686818

Sketched out how I want to implement scoping this morning. Have started working out how to translate from paper to code

Cases:

local x,x = 3,4 return x -\> 4

I generate code as

LOAD 3, LOAD 4, STORE x, STORE x

So going to have to implement subscope renaming to make the 2nd store essentially get shadowed out

Of course if this was all about local renaming that'd be possible to implement in the codegen pass. It's also important to maintain uniqueness given

local x = 1 function f1() x =  x + 1 print(x) end local x = 10 function f2() x = x + 1 print(x) end function f3() x = x + 2 print(x) end f1() f2() f1() f3() f2() f3() -\> 2, 11, 3, 13, 14, 16

& the issue in codgen is that given 'local x = 2 x = x + 2 function f() x = x + 2 end' requires the earlier stuff to know that f is going to capture that variable. So originally I was thinking of gathering any locals referenced in closures into context arrays & then having those be bound together with linked lists. Then LOAD\_DEREF can take 2 args: how many scopes up, variable id. But then I figured no need to make deeply nested scopes introduce overhead, store references to each context. This also means that 'function f1(x) (function f2() x = x + 1 return function f3() return x end end)()  end' will allow f2 to be garbage collected. But then I thought about it & decided why go through all this scope counting, since this is pretty static, instead upvals should exist in isolation, so... 'function f1(b, x, y) function f1() return x end function f2() return y end if b return f1 else return f2 end' the closures of f1 & f2 will reference x & y directly, allowing that x or y be collected independently

So the idea I'm settling on is to trace the AST twice: once with scopeX visitors & again with genX visitors. scopeX will generate some array of scopes which genX will id their scopes as they go through to know how to index. Essentially

(f f1 (f2 f3) (f4 f5)) while the stack during visiting has a history of 

f, f f1, f f2, f f2 f3, f f4, f f4 f5

A complete history can be kept more or less losslessly by having any scope pop push into the array, so f f1 f3 f2 f5 f4. This doesn't contain the nesting information but that'll be recovered by the 2nd pass since it'll be iterating in the exact same order. I should probably abstract the visiting logic to insure that but I'd rather see how it develops

That push-to-array-on-pop stuff looks wrong, might be best to push-to-array-on-push, giving f, f1, f2, f3, f4, f5. This way the order is determined by pushes, which we know are active, as opposed to pops, which occurs at the moment we no longer really care about that scope.. switched it for now

I've also updated the lexer to always have \_ENV with stringId 0. When a scope reachs the end, it's going to have to get itself to generate as LOAD\_IDENT '\_ENV' LOAD\_STR real-ident LOAD\_INDEX & similarly for store. Note that LOAD\_IDENT is a pseudoop; it's LOAD\_LOCAL when the variable isn't free & LOAD\_DEREF when the variable is free. 'free variable' being a variable who's captured by a closure

This adds having Assembler now take a parent. In reality what I've described is handled by each Assembler doing various scope stack juggling & falling back on getting its parent to try scope stack juggle when it runs into an identifier it doesn't have scoped. Whichever parent gets it marks that variable as being free & returns some free variable id to the child. Falling back on \_ENV when the root fails to match

## Day Sixteen

*2017-04-05* · https://www.patreon.com/serprex/posts/day-sixteen-8699705

Spent the evening drinking in the corner of a networking event

## Day Seventeen

*2017-04-06* · https://www.patreon.com/serprex/posts/day-seventeen-8713964

[+388 -106, this is getting messy.](https://github.com/serprex/luwa/commit/e411da85997067815cc4a9b8022b16f45958f029)  I dropped the idea last night of trying to have codegen retrace the steps of the scope pass. Instead any given invocation of a variable will be tied to a specific token index, & any given token index has only one interpretation of whether it is local/global/nonlocal. Key of the concept is all in the getScope/nameScope functions, the rest is all trace logic & block scoping. Moved subfunction compilation to occur within scoping phase, tho that's commented until I get around to it. Getting busy with a work project so that'll hamper this project

getScope's designed to have any upvar also mark the variable as being upvar'd by the between functions. This is because 'function f1(x) function f2() return function f3() return x end end return f2 end' needs g = f1(5) h = f1(8) to be able to pass the upvar ref to f3 on any arbitrary call to g or h

As an aside it turns out Functiondef was a totally useless rule to have so I killed it. I'd like to clean up the grammar code a bit, stuff like Namelist doesn't need to propagate to the AST

## Day Eighteen

*2017-04-07* · https://www.patreon.com/serprex/posts/day-eighteen-8726935

Time was short since I worked 10½ hours today, but was pleased with results. [Changes were more precise today.](https://github.com/serprex/luwa/commit/53706365559a53a949495cd43d6d706639aec0b6)  Got codegen of scoping working, then set to work getting this to run:

x = 2

local x = 4

function f() return x end

x = 6

return f()

This was suppose to use all the variable access methods but it actually skips out on LOAD\_LOCAL/STORE\_LOCAL. Oh well those ones are trivial. Got pretty stuck on LOAD\_INDEX's broken opcode definition (& was generating with undefined arg afterwards to boot)

Infinite recursion was ran into with getScope, ended up splitting up logic & landing on that nice locals\[0\]\[0\] shortcut

Of course the puzzle of the whole thing was free variables. Have to remap local variable IDs to free IDs which I then map which free IDs get put into a child function's other free IDs in order to have the upvals flow down the call chain

With switching to a Func object rather than reusing Assembler, I needed to add in idgen to avoid using Assembler objects as map keys

Bonus elegance: no more \_G in vm. Bonus semantic check: Detect invalid use of ...

## Day Nineteen

*2017-04-08* · https://www.patreon.com/serprex/posts/day-nineteen-8739422

Since function scoping seems to be working, [it only made sense that I should start on function calling this morning.](https://github.com/serprex/luwa/commit/e2e2cb72934cbbf9cec09e37a33504d7b610eb14) Which meant getting parameters into locals/frees. Lots of diffnoise from deciding to keep the stack out of the context. Had to change run to have vm be a paramter so that vm can be changed during call for tail calls

[Evening](https://github.com/serprex/luwa/commit/cce72f046417f73987fd70fd65cff2bd4141950f) was spent getting function calls further worked out, getting stdlib started on now that an ABI of sorts is known. Also needing to get scoping tested, as it currently fails to scope mandelbrot renderer. But things are getting close to having mandel rendering: print works

## Day Twenty

*2017-04-08* · https://www.patreon.com/serprex/posts/day-twenty-8749215

One of those days where I can't focus, & that'll only be more true in an hour

[How I skipped for/if/for](https://github.com/serprex/luwa/commit/bf9373a0a8f5c2d238670df6d8c63e2ede2be4a8)

[Aliased call chains' produced values with their requested output, whoops](https://github.com/serprex/luwa/commit/24f6e998344abfa5017055e0e520faae59e7bf85) 

[Perhaps a readme will make this project accessible](https://github.com/serprex/luwa/commit/0a5ac1b47b4a2654bc40aa528a6aecbfe9e2bb1d)

[Passed up fixing codegen of for loops when implementing their scoping](https://github.com/serprex/luwa/commit/76bed10ff3df45595358e7d49d0c204cbf50d883) 

[Ye ol math](https://github.com/serprex/luwa/commit/f8f371804882504c81a2d39bc0c5ef3183bfb978)

[Both pair & ipair; only ipair works](https://github.com/serprex/luwa/commit/0028971207fee39b63b178b9e63a4a72d23f5b3e)

[Definition issues in for loops, missed endval refactor & more on APPEND logic](https://github.com/serprex/luwa/commit/6c2522f224dbc0ed1ed325734f6a7f3055166a84)

[Again I missed the endval refactor, this time for RETURN logic](https://github.com/serprex/luwa/commit/e16eed48b87b286232d807f6e77b975e988399f8)

Yelling out from this pit within pits within

## Day Twenty One

*2017-04-10* · https://www.patreon.com/serprex/posts/day-twenty-one-8763117

Felt like making two-line commits today

[Fleshing out env](https://github.com/serprex/luwa/commit/06c522c2e46fd8914c1d71b80674695573c0ef8d)

[Nitpicking readme](https://github.com/serprex/luwa/commit/508f37ab74e8a62e34479ad186dbc4e2d74c173a)

[RETURN\_VARG, APPEND\_VARG, pushing for generic-for,](https://github.com/serprex/luwa/commit/351e2d14f69e7292923153c244ee20c0dd3c7dca)  turns out I was failing hard on codegen there & was getting pc to become NaN. Also found out that I'm not so sure about how to do coroutines. Not currently storing the callstack, vm isn't reentrant, will have to figure out some ABI with the return value of functions. & log/log10

[Remove LABEL instruction.](https://github.com/serprex/luwa/commit/81df97e1c2587e46e3243be159b85e32b092c4bf) 3 words explain so much that was going wrong there, was pretty straight forward, I procrastinated on that too long

Experiment: looked like [Fieldlist could be inlined](https://github.com/serprex/luwa/commit/33d67a2f5982115c96abc816faa688fb84118975)  to flatten the AST a bit. Soon followed with [Explist/Namelist/Varlist](https://github.com/serprex/luwa/commit/c5396195ddc4df089d7e22156c1af7ed332ba392). I had to stash/pop that change as the initial take caused weird regressions, all sorted out tho, wasn't getting fields from parlist, instead selecting off node

[Got through nested calls.](https://github.com/serprex/luwa/commit/e061c8ed988b04e94412b757777151caf26cc012)  I procrastinated on that front for awhile since I wanted to try avoid duplicating code. I ended up copying/pasting quite a bit

[Forgot to 'git add thread.js'](https://github.com/serprex/luwa/commit/fb1d767844f8155167986bedd03671c3761df61d)

Played around in the REPL to figure out STORE\_METH semantics. Turns out 'function f:a() end' is equivalent to 'function f.a(self) end' so added self to always being in the lex table & implemented that sugar. Upside: [STORE\_METH is not an opcode](https://github.com/serprex/luwa/commit/cd80d395d893197f04e2821e499cd6a055a1a353)

Back to flattening the AST, [removed Parlist & Fieldsep](https://github.com/serprex/luwa/commit/5a2dd2051fb16d332313250a8c100097cf6d322a). This required creating an of which doesn't track which variant it resolves into. Kind of neat how the syntactic distinction exists where there's no semantic difference. Guess that happens with most sugar, this is just a very primitive sugar, being able to say {1;2} instead of {1,2}

[tonumber, tostring, pairs](https://github.com/serprex/luwa/commit/bc805ab607c54aaf767a3a879e33faa745e48bb5). tostring is my first take on interacting with metamethods. I'm a bit tempted to move the metatable reference into the Table object. The keyidx/keys/rm fields are pretty cringeworthy. I've some thoughts on lazilly initializing those fields, maybe even having the heavy lifting delayed until next is next called

## Day Twenty Two

*2017-04-11* · https://www.patreon.com/serprex/posts/day-twenty-two-8776504

Got some refactoring out of the way to try move towards default modules being their own cjs modules. This made it easy to then hook up getmetatable to return {\_\_index=require("./string")} in order to let ("asdf"):len() to work out. [So now \_\_index is implemented](https://github.com/serprex/luwa/commit/a3a61f3807916e4ebb561d4559953a7edb117767)

Finally decided to dig into why mandel was causing unbound growth of stack while infinitely looping. Issue was that for-loops keep their intermediate values on the stack for the duration of the loop, so break was skipping FOR2/FOR3/FOR\_NEXT popping those values off when loop was over. This required adding some depth tracking to Assembler, made POP take a parameter to keep the size constant, could still avoid generating POPs as I currently do for break-inside-while-inside-for

Then nested calls weren't working which I flip flopped between a few different ways around these off-by-one/wrong-direction bugs, ended up coming out with it fixed, resulted in dropping parameter count of call functions, no longer have any 3-parameter instructions as a result. [Meanwhile continued on stdlib while that refactoring was going on](https://github.com/serprex/luwa/commit/4e178da6692b384a9d09699a6f778fa2ece27565) 

## Day Twenty Three

*2017-04-12* · https://www.patreon.com/serprex/posts/day-twenty-three-8790398

Fix typo in parsing [local function f()](https://github.com/serprex/luwa/commit/6163be89c36c2cf3b49d6f87d057a0b72583c660)

Coroutines work. Decided to continue abusing javascript generators & instead of having some mechanism where functions return null on success & an array to store a callstack which stores enough information so to return tho whichever spot in the code was calling on success, I just made coroutine\_yield be implemented as '[yield](https://github.com/serprex/luwa/commit/6163be89c36c2cf3b49d6f87d057a0b72583c660#diff-5825dc4c5082751b8301bec50a02bc0dR499)' yep had to link to that commit twice. Fun bit: turns out we don't need to pass the caller in the ABI

So whenever JS engines get around to optimizing generators this'll prove a wise choice. Until then w/e w/e, I do what I want

## Day Twenty Four

*2017-04-13* · https://www.patreon.com/serprex/posts/day-twenty-four-8802596

Rose at 0430. [Continued fleshing out coroutines](https://github.com/serprex/luwa/commit/536676dc82d81d410f84f0e5bb84e2bce1e149b3). Reviewing string api, reviewing patterns. [Wrote a repl](https://github.com/serprex/luwa/commit/f803d6f64d36ca28ee472d40869cc24d4f3f4c01). try-catch is because immediate readline call was causing EAGAIN. [Fixed string escapes to be decimal, not octal](https://github.com/serprex/luwa/commit/167853cccdf30c7c83332a5646cd8107fe5400cf). Noticed this misunderstanding on my part while reading about string.pack. [String.reverse](https://github.com/serprex/luwa/commit/4298dc762fc47e50213c290819bf0a1559d1727a) & ran into issues while trying to call string functions so fixed. Went after that one since it looked obvious enough, don't know how I missed it first time around. Referenced jsperf for string reverse. I reference jsperf quite a bit. Hence not using Number.isNan. [I'd been getting annoyed seeing print output always being an array](https://github.com/serprex/luwa/commit/a3dacdcd3c043a73bcdd06f70f44e2266ea1ab50)

At this point my mind was fluttering, no thought could persist without forming a mantra, So sought rest. Realized that I'm going to have to drop using string & use Uint8Array as my string type. It'll be easier for wasm port, so that's a plus. Slowly going to start implementing objects to be wrappers around indices into a WebAssembly.Memory buffer

Then I found out that 'a=\[1,2,3\];delete a\[2\]' results in a.length still being 3, not 2. So figuratively rolled up my sleeves & [reworked Table](https://github.com/serprex/luwa/commit/213459f17af4fbe36b851546c5b43d66f9b3bf80) to now exist completely in the hash Map, tracking borders in a sorted array & deciding to raze any code which wasn't trivial to switch from fiddling with the array field. Turns out scopeVar was broken in calling scopeIndex. Trying to input table test cases into the REPL & getting syntaxes errors, joy. Got cute with appendix both in name & mixing postfix/prefix increment. Append opcodes now all take an index at which to start appending values

Fragment of mutter, don't know where to stash these things: A table is a map, a mapping, not a map, but a mathematical map.. at least imagine a table, not a table

Oh I get it, it's been an hour, now it all makes sense it makes sense

## Day Twenty Five

*2017-04-14* · https://www.patreon.com/serprex/posts/day-twenty-five-8815549

Quiet day[...](https://github.com/serprex/luwa/commit/9ca96ffc2d7ad49054d4c7c146f82ce738f5acd6)

[Metamethods are inherently tied to the stack machine](https://github.com/serprex/luwa/commit/1644c900a6d5d596e70ced9c0597d246be48c3e0). This seems like a problem, essentially making that I can't create a generic 'add two lua objects' function that doesn't devolve into creating an intermediate stack to run metamethods on. So I'm going to set this thought down & focus on the WASM goals. I've been trying to decide whether to write in the S-expr wast of binaryen, the stack code as shown by Chrome's debugger, or to begin on writing my own Forth. Clearly I'm procrastinating as a process of convincing myself of the last option. But maybe that's wrong & I should go after something like how the Mill's assembler is C++ which happens to output the binary machine code. Bleh, too much pondering, not enough empirical input to make a decision, can't let that persist

## Day Twenty Six

*2017-04-17* · https://www.patreon.com/serprex/posts/day-twenty-six-8850794

Belated post. [2 microoptimizations](https://github.com/serprex/luwa/commit/a2f290370e277afb0007c4cda31d5f27064c9b49). It then struck me how to implement some minor form of tracing into WASM codegen without first having to do the hard work of implementing Lua datastuctures in terms of offsets into WebAssembly.Memory: trace in this JS interpreter, if code is entirely numerical generate WASM for that. This seems like a good prototype step

The matter becomes representation. A traceset should follow the stack's types, splitting when types differ, & then joining back together when values are being popped. ie a DAG

I was going to flesh out how to implement this today, but instead [I read Gulliver's Travels](https://www.goodreads.com/review/show/1973626981)

## Day Twenty Eight

*2017-04-18* · https://www.patreon.com/serprex/posts/day-twenty-eight-8865099

Counting days by twos has days happening too fast

[Did some renaming to match Lua's metamethod naming convention more](https://github.com/serprex/luwa/commit/1ca5480394fd1a74f05f42cc37f38d11ac668821) , decided to trim opcode space in favor of outputting more ops, includes refactoring to store metatable reference in Table object, & making callObj a tail call. Little bug in this commit that'll get fixed in one of the following commits. I'm going to vomit them all since they're mostly me poking around trying to get things working nicely on [travis-ci](https://travis-ci.org/serprex/luwa) & [npm](https://www.npmjs.com/package/luwa):

https://github.com/serprex/luwa/commit/ac47611af1a59c5662210723db64b7f3a746b90d

https://github.com/serprex/luwa/commit/3f55158cc86cf33fb60fdd4d141bdaf10837264c

https://github.com/serprex/luwa/commit/8729cd1e1ae3c8c481495823dbed2a01db3173ac

https://github.com/serprex/luwa/commit/5ad03b2bbcdcbfcad422c3832c88ec663a8eeff9

https://github.com/serprex/luwa/commit/4f3faf63afbe259e759dc1776a77453b3608c110

https://github.com/serprex/luwa/commit/09e41269c4a2492ad438d9899c16fefe10a5e15e

[& fix NaN regression](https://github.com/serprex/luwa/commit/02df915ea3fb518a27bb24e3903de3bfb423ac88). [Finally checking in trace.js](https://github.com/serprex/luwa/commit/099120ea402c5e77485262b1d81f631f4b573b9a). Bit late so didn't do the hard word of actually fully integrating it into the bytecode VM. & while the API seems about what I want, it fails to properly encode itself: pops don't collapse together once their stacks' types match. Yesterday I mentioned it being a DAG, that only goes for basic blocks, it's a graph of DAGs, which is kind of mincing words. Going to want to persist the set of indices which are labels in order to encode forks at points where control flow by barge in. Basically

if (b) goto a

\[asdf\]

a: \[stuff\]

..should be transformed into

if (b) goto a

\[asdf\]

goto a

a: \[stuff\]

Except without actually putting it into the bytecode. Somewhat tempting to break up the bytecode into an actual array of basic blocks, tossing around in my head how things are going to compile & how i'll probably be doing a loop-switch with basic blocks. Having to wonder whether it makes sense to have the IR be SSA & convert SSA back to stack code when compiling. Hoping to stay stack oriented the whole way

## Day Twenty Nine

*2017-04-19* · https://www.patreon.com/serprex/posts/day-twenty-nine-8877763

[I lied](https://github.com/serprex/luwa/commit/b5e15ef394fae0936f17d7db01f959b9e3b6cf9b)

Decided that this whole TraceSet -\> TraceBlock -\> TracePop -\> TracePush hierarchy was too much. Instead of focusing on nodes I switched the focus to edges, where an edge is defined by 2 nodes & a count. A node is referred to as an "id" because they represent a code offset alongside the type info at that point (push/pop). I filled in most of the remaining opcodes' trace code

Did quite a bit of skimming over trace jit literature today. Mostly too abstract. At least I got to reread [this classic](http://article.gmane.org/gmane.comp.lang.lua.general/58908)

SO anyways, returns aren't being traced properly. I either need to start caching contexts based on function id & swapping out traces (but with some kind of interprocedural edge?) or I need to have bytecode exist as a giant chunk which gets into dynamically linking new code so then offsets are position independent

Of course this means I've thrown out the whole basic block thing out the window. Traces don't care about your flow control; that's for the trace compiler to worry about. That mythological beast that has yet to manifest here

Also thinking of unifying the code paths for func/jsfunc by creating a set of 'real mode' bytecodes which I can then use to encode the stdlib in as bytecode. This would also want to create opcodes for stuff like coroutine methods & metatable tinkering & string util & table util. So clearly that's a slippery slope that I'll take care to sidestep for now. Focus is to get tracing to a point that it can detect a hotpath of numerical code & generate a little wasm stub which'll have more overhead being called into then it'll save since it'll only JIT like an opcode or something

## Day Thirty Four

*2017-04-24* · https://www.patreon.com/serprex/posts/day-thirty-four-9147007

[Got distracted](https://www.codewars.com/users/serprex)

Also busy doing stuff. Trying to sketch out how to trace the call stack. [I did the preliminary stuff](https://github.com/serprex/luwa/commit/a6bd6cf6a9245c94a880ae730acd5288b3d1e65f). Thinking of making context be part of Id. Then cursor can trace through calls. Right now cursors are somewhat per-context. Part of me wants to ignore that and just get a basic script working like

i = 0 while i \< 10000 do i = i + 1 end

Which might be a good pick-me-up milestone-thing goal

## Day Thirty Eight

*2017-04-28* · https://www.patreon.com/serprex/posts/day-thirty-eight-9414204

Busy week at work

Been getting some code written up during morning

Need to track labels in order to put together basic blocks. Did that this evening

Codegen right now is being written assuming ints, guards will have to come later, the loop is pretty straight forward so only having to setup tracing logic for less than a dozen opcodes

LOAD\_NUM 0, STORE\_LOCAL 1, $l, LOAD\_LOCAL 1, LOAD\_NUM 1, BIN\_LT, JIF\_NOT $e, LOAD\_LOCAL 1, LOAD\_NUM 2, BIN\_ADD, STORE\_LOCAL 1, GOTO $l, $e, RETURN

Where RETURN can exercise jitcode-to-bytecode fallback

Key right now is to sit down & rework my Befunge jit logic to this. But not today

## Day Forty

*2017-05-01* · https://www.patreon.com/serprex/posts/day-forty-9626311

Time to pivot. I wrote up a [jit.js](https://github.com/serprex/luwa/commit/d162094acf6d65f854c6c4f561a06899254fe507) which starts on trying to generate a non zero amount of wasm which is massively incomplete & incorrect. I've also started on a meta language to write the wasm runtime in. I'm realizing how much I need to shed the javascript ties. I've talked before about writing the objects to be implemented in terms of a pointer into a Memory blob. I could try to gradually transition like that.. or I could start anew

So I took to benchmarking [LuaDate](https://github.com/LuaDist/luadate) to guide some changes to the lexer. Specifically [merging the sn/ss mappings into a Map](https://github.com/serprex/luwa/commit/f2c116a76355bfc8ee587b123928d7bcb5399b3c) & [compressing it into a Uint8Array](https://github.com/serprex/luwa/commit/77575987e252c3809b31431ceb673a3dd654a15f) where \_string/\_ident/\_number are variable width tokens. Also [making sure the token stream can be garbage collected](https://github.com/serprex/luwa/commit/af5bc38c1b9a56c6571aa542618d81e4bc4910ae). Cue [regressions](https://github.com/serprex/luwa/commit/6c4f485cb82a96edbdb939900169b42500f1a4bb) & [last minute refactoring](https://github.com/serprex/luwa/commit/1236e858216f983340399fa47fd9387291df427f)

So next step is replacing ast.js/bc.js with a wasm implementation. I'm considering if I suck it up & use C/emscripten for this. Nahhh

## Day Forty Two

*2017-05-04* · https://www.patreon.com/serprex/posts/day-forty-two-10183020

 Since I'm jacking out for the next four days I decided to post about this wip wasm work which is currently at the level of [electric doodles](https://github.com/serprex/luwa/commit/b5c244728cb7898c9a9020abfe2a7c9f8742dfba)

I have a sketched mod of mkcjs in *scripts/mkwasm.js* whose purpose is to compile whatever dialect I settle on for writing wasm into an actual wasm module. Going to need to come up with exporting to a javascript require-js which'll be the entry point

Of course before I write an assembler I'll be needing to settle on wasm. So *rt/* is acting as a directory for writing up the runtime. Currently trying to poke at how to implement tables as a basic hash table in raw wasm seems like a good starting problem (also I've never written my own hashtable before so time to get wet), but that's quite unrelated to the deliverable of getting the parser implemented in wasm. On that end there's alloc.wasm which is going to act as interface to grow\_memory for managing the heap. I'm intending to go with reference counting over implementing a gc for now since there's the [GC feature proposal](https://github.com/WebAssembly/design/blob/master/GC.md) which I figure I should wait on

## Day Forty Seven

*2017-05-09* · https://www.patreon.com/serprex/posts/day-forty-seven-10746509

[Still in this wip mess](https://github.com/serprex/luwa/commit/af976584385d4a45591a6a9372a8e3639abbe67d)

Copied out ops, included some aliases, going to need to encode type signature of instruction, might decide to drop aread32/aread16 aliases for some other mechanism

## Day Forty Eight

*2017-05-10* · https://www.patreon.com/serprex/posts/day-forty-eight-11023180

Considered conceding to wast à la [wasm-games-by-hand](https://github.com/abagames/wasm-game-by-hand/blob/master/src/game.wat), considered rewriting everything to follow a lexer/parser/compiler chain similar to luwa's JS implementation, but kept too, futher deferring name-to-number binding, focusing on [generating what bytecode I can](https://github.com/serprex/luwa/commit/0da0419a47e84678b815e4c5313c4e4767d92b74) in order to get an idea of how I'm going to generate the module as a whole

## Day Forty Nine

*2017-05-11* · https://www.patreon.com/serprex/posts/day-forty-nine-11124503

Been tossing around the idea of implementing this wasm assembler stuff as a guile script, try tap into that for macros, was pretty lost, decided I'd rather port to that than pivot, deal with the hard things with what I've got, so kept on there, going between implementing specific handlers & wanting to implement a similar parser combinator method of parsing lines. It'd be implemented in such a way that the lexer is just line.split(/\\s+/) with tokens being strings. Going to let this series of hacks continue while I think of how I'll rewrite it after. Kind of nice being able to know that a rewrite will happen, too use to 'rewrite it after' being 'it'll never get rewritten', thus forcing 'rewrite it now, before it's too late' development

## Day Fifty

*2017-05-12* · https://www.patreon.com/serprex/posts/day-fifty-11138380

[Getting there](https://github.com/serprex/luwa/commit/0f875a8ee80dae8fae4b049e84bfb49a4e2fdfaa). [Made a commit before getting compilation working in fear that I'd overwrite some key file by accident](https://github.com/serprex/luwa/commit/4d447f85e42ce18a1cb3a9d9f3a7ff0d8dae3251). Been in a hazy state for programming as of late, thinking through insurance processing, the solutions are going through me as a piling on of code that'll hopefully spit out the right answer, rather than mapping it to a graph of data flow, modular, pieces small enough to roll around with the tip of my index finger, only to drop them back into the soupy mess of text which they've been encoded within

Output of std.wawa is off due to lack of implicit parameters. Going to do the polish work of implicit params & maybe get into type inference after that (ie 'add' should resolve to the correct add instruction. Realizing now that I'm not sure if i32.add can consume 64 bit values, or mixed type values.. that would explain why the explicit opcodes rather than making instructions polymorphic, as the type prefix is really specifying only the output of the instruction in that case.. may have to experiment)

Somewhat tempted to clean up std.wawa to have it compile properly, falling back on wagu (wasm-guile) as the savior beacon from this assembly twiddling dev environment

## Day Fifty One

*2017-05-13* · https://www.patreon.com/serprex/posts/day-fifty-one-11155675

[Got it to the WASM validator's door](https://github.com/serprex/luwa/commit/389c86a8ba023a6a75a4e1e9cb98ee439ebdf50c). Noticed tests were failing by the little red exs in commits, [so fixed](https://github.com/serprex/luwa/commit/a6fe261bdbfc07761ec7fc0bb4abae693e1b92d9). Afterwards I got back to trying to [simultaenously get further with valid wasm whilst shoving even more invalid wasm in](https://github.com/serprex/luwa/commit/935479e81f7f4dc0dc2149c5283e804131a67d96)

## Day Fifty Two

*2017-05-14* · https://www.patreon.com/serprex/posts/day-fifty-two-11172641

[Thought out how to do immediate encoding](https://github.com/serprex/luwa/commit/23ffdc5d7d7f64c42c5212cb29be5dbe3d643e4f)

## Day Fifty Three

*2017-05-15* · https://www.patreon.com/serprex/posts/day-fifty-three-11202310

Got [std.wawa to validate](https://github.com/serprex/luwa/commit/ae7d5056f0ba7f483bc75fcccfdd40225ea96a6c). Then the [whole bundle](https://github.com/serprex/luwa/commit/26a4cf3eebb9b31ccea8334f80c6a33789770483). Turned attention to [hashtable building blocks](https://github.com/serprex/luwa/commit/0e05ec4bfecd566e0a4d674f95c1d6d4319fab2a)

I've never had to really consider how to create a manageable assembly application. Especially with some of the decisions I'm making where I'll have to learn how to refactor this kind of thing. Probably'll be a lot easier once I convert over to making guile be the macro assembler

I didn't know the ABI of grow\_memory at all. Going to want to rework malloc to batch the grow\_memory request to a single execution

## Day Fifty Four

*2017-05-16* · https://www.patreon.com/serprex/posts/day-fifty-four-11219823

Doing something really helps understand it. I've always been a little confused by linear probing & it's ilk, but now it's all so clear. Because I wrote [tabget](https://github.com/serprex/luwa/commit/d44c240f6376a93ee88c759346fbae67339e40d9). Well, I'm still a bit confused: If I insert A into 3, then probesert B into 4, then delete A, now B is unreachable.. I guess that's what tombstones are all about

Currently I'm pulling a PHP & having hash(str) == strlen(str). I'll get to that when I actually get to string stuff. Still need to write tabset

Bug: tabget doesn't wrap around, instead returning nil if it reaches the end. Will rectify that tomorrow

## Day Fifty Five

*2017-05-17* · https://www.patreon.com/serprex/posts/day-fifty-five-11233549

In a haze of hashtables 101, [working out tabset](https://github.com/serprex/luwa/commit/91bda8ca9dd2c5feb71b4266977a09c63fea2732) , which happens to be tabdel since I'm implementing Lua's semantics in the primitives, need to sketch out the refcounting story, will look into breaking up tabset tomorrow so that I can reuse the logic for when the backing array is not inside the struct. Or maybe I should setup the loop that struct's length is set to 0, proceed to call tabset while iterating old backing array, which is no longer referenced by struct.. yeah that seems about right

## Day Fifty Six

*2017-05-18* · https://www.patreon.com/serprex/posts/day-fifty-six-11248042

[Going to have to get around to testing this stuff eventually](https://github.com/serprex/luwa/commit/3c907f9bff1cfc756084f5f3a2637c4edb9ad070). mktable giving a good example of code that yearns to be macrocompressed

After I figure out how to test this hashtable I'll move on to implementing the lexer. Will have to decide whether it's going to use tables or some specialized hashtable (ie not carry around a nil metatable & an array component)

Should probably create a datastructure for resizable arrays. Mostly ticking off what's necessary to mostly port lex.js in a straight forward manner

## Day Fifty Seven

*2017-05-20* · https://www.patreon.com/serprex/posts/day-fifty-seven-11285809

Get it [validating again](https://github.com/serprex/luwa/commit/9fdcb06de170f611b1d49d0eef6655e4c9f250f8). Then get it [working](https://github.com/serprex/luwa/commit/664a0f23c433cb127f1ffde16ec900b24a53cfea). Have been able to test that t=mktable();\[tabget(t,5),tabset(t,5,5),tabget(t,5)\] == \[0, undefined, 5\], where 0 is nil & 5 is false

Issue: nil is currently being initialized at 0x0. So my use of 0 as an empty slot & nil as tombstone didn't work. Then I realized that I don't need explicit tombstones: don't clear key on assigning nil, allows reassigning nil'd slots, vacuum out nil values & nil keys on rehash. nil keys are now always unassigned

Bonus: [fix up malloc](https://github.com/serprex/luwa/commit/32b831ecf42a77402199ceddb536631a43f2b48c)

## Day Fifty Eight

*2017-05-22* · https://www.patreon.com/serprex/posts/day-fifty-eight-11299990

I spent over an hour stuck because I didn't realize br 0 in a loop doesn't break out of the loop. Anyways I've decided to go with [the heap being 100% GC'd](https://github.com/serprex/luwa/commit/84d3cd2461e1bc64b014448418858074d322a879). To start I've settled on making every allocation typed, this includes the internal buffers of tables. This'll apply to the callstack too. There's an oroot global now I haven't gotten to: it'll be a vec of roots. The GC will be compacting. Right now I'm thinking 2-state mark-and-sweep Lisp2 because I understand how to implement it off reading the description

Mark/Sweep bits will be stored in lower bits of relocation pointers. Going with all allocations being 8-byte aligned so that the GC's copying can assume it's safe to memcpy with 64bit instructions. No 'next' pointers because given an object one can deduce its size, so next is self+sizeof(self)

Had to jiggle with table code since I'm no longer storing capacity inside the table struct, as that's stored in the vec instance. vec initializes filled with nils, this way I don't have to store a len/cap pair in vecs. Code had to rethink a bit since various values were being stored as element count rather than byte count, but vec stores its size as byte code, even though it must be a multiple of 4, as vec represents a collection of objects, ended up mostly simplifying the code

## Day Fifty Nine

*2017-05-23* · https://www.patreon.com/serprex/posts/day-fifty-nine-11313088

[My first GC](https://github.com/serprex/luwa/commit/84a4c9ae439f1a41bfd7b6b7463b2f29a2fb0513). Will leave testing it for later. String's hash is some rotate/xor numbers I pulled out of my ass, code includes padding the end of a string's allocation with nuls in order to not have to bounds check. Unfortunately that's wrong since looking at it now I forgot about the 13 byte header. Will fix it up after posting this to have specialized code for first 3 bytes

*edit: **[done](https://github.com/serprex/luwa/commit/66b89100e7b6d870b904c5e2aa77afe44ea83f6e)*

## Day Sixty

*2017-05-24* · https://www.patreon.com/serprex/posts/day-sixty-11335964

Writing this with connection issues

Decided to finally experiment with breaking-to-end-of-function, found that it can act as another form of if, opens up potential with br\_table & br\_if, also means I should prune trailing rets in my code. Then was having an issue with loop fallthru. All this time I've avoided this behavior. Probably worked around it in debugging sessions. Documentation on webassembly.org was pretty sparse, clearest mentioning I could find was [this blog post](https://binji.github.io/2017/03/05/webassembly-type-checking.html). Some hinting with a '[remove bottom label](https://reviews.llvm.org/D25118) ' commit to llvm. I had previously ran into this when an attempt to break from a label acted as a continue, at the time I thought that meant br/br\_if/br\_table all jumped before the previous end, hence fallthru for blocks, continue for loops. Brings me back to finally learning in college that continue evaluates the condition when I had a do-while(0) with a continue to act as a reloop. Thought it was a Java idiosyncrasy at first. Anyways I got out of bed realizing [an error](https://github.com/serprex/luwa/commit/429427f7e8d49cb2dd8a3294e85151df3c69963b) last night, had to fix it then because either I'd have trouble sleeping or I'd forget by today. Then back to [constant fixes](https://github.com/serprex/luwa/commit/1774df1f6679f6f8e86ce6455027df504a66a66c) before getting to next on the list: [gc integration](https://github.com/serprex/luwa/commit/cf0cfd7ea3ca4cc494fe4162e1210bff8b48ee71). Which then leads to this whole paragraph's start where I got into deeper debugging, thinking of making a test script in index.html, kind of waiting on node 8 to release with wasm1, found out the Firefox I'm using now exposes wasm debugger, was neat seeing it shows local values, still neither Chrome nor Firefox showing stack slots tho

## Day Sixty Four

*2017-05-28* · https://www.patreon.com/serprex/posts/day-sixty-four-11404965

[I feel like I should be writing a lex generator](https://github.com/serprex/luwa/commit/7a889697db67cf933dded4ca6cc0d55fae874228). But hand writing it is helping place me in a first person perspective of dealing with all pointers in local variables being invalidated by any allocations. So coming up with a stack to track objects. Will probably eventually involve into the callstack, but callstack has to be somewhat flexible given coroutines

## Day Sixty Five

*2017-05-29* · https://www.patreon.com/serprex/posts/day-sixty-five-11424007

[Two character operators](https://github.com/serprex/luwa/commit/9069e3f18a2cc6dea2252db8cde11413b9b2ce6b). [In two parts](https://github.com/serprex/luwa/commit/1fb0ff75f24386e2263889fa702bbcde9bcb2631)

## Day Sixty Six

*2017-05-30* · https://www.patreon.com/serprex/posts/day-sixty-six-11449547

[Cleaned up 94 deep blocks with named scopes,](https://github.com/serprex/luwa/commit/7ad4b9379249f33191791a4efcec7d76e452d1d8) helping to make managing depth straight forward. Also makes it clear that the only things the lexer really needs now are identifiers, strings, numbers, comments

Mostly distracted this evening running Act III with a javazon

## Day Sixty Seven

*2017-05-31* · https://www.patreon.com/serprex/posts/day-sixty-seven-11472785

Decided to start with the easiest of the remaining lexemes, [comments](https://github.com/serprex/luwa/commit/f6a75f69d60567edf6aa133a071a6cac49c2f8f2). Spotted a bug with the js lexer's handing of -- at the end of a line. Didn't finish the logic as I still need to add the scan for multiline comments. Kinda sublime that multiline comments are also used for subline comments

## Day Sixty Eight

*2017-06-01* · https://www.patreon.com/serprex/posts/day-sixty-eight-11500154

Lex [dots](https://github.com/serprex/luwa/commit/bdaeca0678c226e2e22f67c60d50215e858ce9b4) & [comments](https://github.com/serprex/luwa/commit/bddb2838982013f85870d93f3b40f72239486675). Figuring on waiting for nodejs 8 to hit extra, should be able to then write up some CI to demonstrate how broken all this code is

In the meantime I'll navel gaze about WebAssembly & integrated GC

So effective GC should be precise. Feel like each object should be it's own miniheap. Or object we'll say. 'allocate X Y' returns an object of size X with Y object references. Default them to some 'null' value. One can then use obj.i32.load or obj.i32.store or obj.i32.load8\_u or etc which would take an additional 'object' off the stack & execute those instructions on the memory segment of it. Include an obj.load & obj.store to read the nth object. Include a load.nullobj instruction

Expansion is to include the ability to allocate a variable number of bytes or object slots. Also to have an instruction which'll read from the Nth object slot where N is some runtime value. This would facilitate having a vector of objects as opposed to having to create some cons cell soup

Important effect here is that we never expose the pointer locations of objects. & it's impossible to create invalid object references. null is just a singleton 0-byte 0-slots object. This makes it that the GC can be compacting if it so chooses. It would be nice to be able to ID objects for easy hashing & equality through i64.eq, but that's easy enough to roll on one's own if really necessary

Ideally from there objects should be able to refer to each other across wasm module boundaries. Probably a minefield to come up with clean semantics on that though in a multithreaded world

Another key property here is that it does not expose JS semantics to WebAssembly. Which I feel is important, but that's probably tied to my desire to create a WASM kernel which executes all programs in kernelspace except inside a JIT'd WASM sandbox

Weak references could be marked as an 'last Z of the Y object references are weak, ie, may randomly become null if the only references to that object are weak'

## Day Sixty Nine

*2017-06-02* · https://www.patreon.com/serprex/posts/day-sixty-nine-11529597

Stayed a couple hours late today preparing for [the open house](https://www.eventbrite.ca/e/mld-anniversary-open-house-tickets-34623382469), so only got around to [getting the code to actually be valid wasm](https://github.com/serprex/luwa/commit/ac7bb9aa56a8177ddb8c498ad1780dbf3094f931) again

## Day Seventy Two

*2017-06-05* · https://www.patreon.com/serprex/posts/day-seventy-two-11572950

Saw a write up on a [Racket based 6502 assembler](http://pinksquirrellabs.com/blog/2017/05/30/asi64). Which pretty much reflects what I've been dreaming to do with Guile. So I've started on that. Which means learning Guile.. and Scheme. So I've got something, currently working to get wawa files to compile with a few brackets thrown in

## Day Seventy Four

*2017-06-07* · https://www.patreon.com/serprex/posts/day-seventy-four-11606631

Trying to figure out how to implement parser combinators in Guile

Got a copy of node 8. My befunge implementation worked out of the box, competes with bejit pretty well. However it's failing to validate luwa's rt.wasm despite Chrome & Firefox being able to compile & test

## Day Seventy Five

*2017-06-08* · https://www.patreon.com/serprex/posts/day-seventy-five-11622203

So decided to start writing the Guile code backwards. It seems scheme doesn't even have a good builtin syntax for destructuring cons cells so my ideas that this might draw on my Haskell experience is seeming wrong. So func is..

(define func (r-seq (rule params) (rule locals) (rule code)))

code's definition is a plain (r-many (rule instruction)) while instruction carries all the meat. This reminds me that I'll have to include in the context depth/locals & function-index parsing will need to draw on a symbol table if I don't defer making sure the name is valid

So in all this I'm of course wondering when do I raise the flag & get back to writing wasm in the raw wawa dialect I've thrown together. Maybe looking to use a templating engine with lua or javascript. I can't stand templating. I often seek to avoid aspx files for html which start with a JSON ajax handshake to load the dynamic portion of the data. Which has some pretty good properties when that initial html can then be cached. Which of course isn't relevant here

Watched 'hammock driven development', convinced me to go to sleep sober tonight to think over this stuff

## Day Seventy Seven

*2017-06-10* · https://www.patreon.com/serprex/posts/day-seventy-11660353

Committed [wagu](https://github.com/serprex/luwa/commit/38dd6c3f01b4e53bdc0dd1d9cfe50b564158a377). Might as well get it into source control. I'm getting to the point that I've got basic functions to produce an AST of the code & from there I just need to add in codegen. Could probably skip needing a parse phase if I made the code less flat & input a bunch of parentheses

Somewhat tempted to roll my own lisp for this, then yield & destructuring could just be there. But this tangent has already gone on too long. I'm also checking in wagu at this stage because I'd like to set it down & get back to Luwa itself. Was a nice vacation in Schemeland. Mostly learnt that I don't really like Scheme. Parantheses weren't the problem. It's that everything looks like it might be a feature but then it turns out it's a primitive that you have to turn into that feature. & documentation is hard to find because mostly you run into Racket's docs. (help let) didn't give anything. I really wanted to be writing Scheme with Haskell syntax... and semantics

Too bad GHC is huge so I had to uninstall it

## Day Seventy Nine

*2017-06-12* · https://www.patreon.com/serprex/posts/day-seventy-nine-11688867

Decided to get back into the swing of thing with actual development by getting in-browser testing, [fixed up GC](https://github.com/serprex/luwa/commit/275722e5f37deae879a7dbef96249f50de429da2) & now know that it actually works. Real shame node8's wasm validation is broken

Left the 'echo' function in there as it was very useful in doing printf debugging. Which is how things'll have to be while browser's struggle to support wasm in their debuggers. Would really like to have the stack being inspected. Was able to actually reduce size of wasm blob by optimizing jump tables & inlining

Bugs that were fixed in the GC: incorrect order of arguments to memcpy8, util.readuint32 ignored index param, name typos were making calls to gcfix a 'call 0', wasn't checking mark bits in move phase, was returning rather than breaking in pointer fixup phase

## Day Eighty

*2017-06-13* · https://www.patreon.com/serprex/posts/day-eighty-11708388

10 hour shift cut in on doing as much as I'd've liked

Mistyping shift as shfit caused me to notice the odd rendering of this font where it drops the dot of the i after an f

[Morning got rmroot fixed](https://github.com/serprex/luwa/commit/45321d181297eeb2461a53caea84510be513b333). Also added in reading Lua strings back into JS strings, but didn't commit. That got bundled with [the evening bunt](https://github.com/serprex/luwa/commit/3a52000f19f117ca16713b4ebb9a1c19da362857) of encoding local entries with RLE, shaving off about 40 bytes

Patreon's text editor is getting even worse. Now it's consistently breaking when I add links. I've had to create-link, save, edit, create-link, save, edit. After being unable to create-link during the initial write up. Previously I'v had it mess up the cursor, after create-link any attempt to type has the cursor move before the link. Wish I could just write this up in markdown

## Day Eighty Two

*2017-06-15* · https://www.patreon.com/serprex/posts/day-eighty-two-11743594

Fixed some [little bugs](https://github.com/serprex/luwa/commit/4aede5e38b3d0b688667c2553298e157e8af13eb) last night, getting lex to terminate with an empty array

Fixed some [little bugs](https://github.com/serprex/luwa/commit/23de957155309bcc4509ff827d7eb9a1645c60fd) this morning, getting lex to terminate with basic tokens

Then fit in implementing [identifier lexing](https://github.com/serprex/luwa/commit/ba981f321b178ba38d2dae9668b8ec622cb1d459) before/after making an after-hours hour drive by at the office

Included is a commented out idea of what kind of macro facility I'd like. Pretty tempted to take a dive into implementing a wasm forth *warth* once I finish the lexer

Other direction is to sketch out a bytecode VM, leaving parse/compile to JS for now. Lexer was a bit of an experiment in what it's like to program in this WASM environment I've made (both tool-wise & rt-wise), ideally I'd like to go the PyPy/Rubinus route of trying to implement most of Luwa in Lua

PS I think the identifier's character scan is a little cute, despite it checking character classes in the order opposite of their likelihood

PPS new Patreon theme is a bit is a bit too CAPS LOCK & light-themed for my tastes, but the UI isn't bugging up on me, so that's cool

## Day Eighty Four

*2017-06-17* · https://www.patreon.com/serprex/posts/day-eighty-four-11776095

Fixed some issues in pushvec, made a pushstr, use that for [quoted string lexing](https://github.com/serprex/luwa/commit/722c7b4cc226c6b1fa89e20ac9469e780165c8ca) & convert the token stream to using it, ran into some lexer issues with the string table, need to investigate more (adding 'local y = 2' to the ui.js tests cause it to loop infinitely)

Looked to see if there was much existing work in WASM Forths, didn't seem like it

## Day Eighty Six

*2017-06-19* · https://www.patreon.com/serprex/posts/day-eighty-six-11811089

Spent yesterday & this morning in a [deep dive debugging session](https://github.com/serprex/luwa/commit/ff6d83de5c11c9f0a4ed3e38264b0252ef9f61b6). Was getting suspicious of bugs as deep as hash or eq. Mostly found out tables were totally broken & fixed that. Few hours later got back to [fix up a couple faux pas](https://github.com/serprex/luwa/commit/415d414ebeed9d34d82acd2fb69b49ce1336f0de) in the lexer & memcpy1rl

Still to do: string escapes, square bracket strings, & the most difficult thing to parse: numbers

## Day Eighty Seven

*2017-06-20* · https://www.patreon.com/serprex/posts/day-eighty-seven-11840327

[Lex multiline strings](https://github.com/serprex/luwa/commit/e838986206ee146c5e6f2ef048fb87e466765308). First it was invalid because I didn't propagate types to all the ifs/loops which never return. Sketched out 2 example strings on paper to keep track of variables. My initial sketch thought i was anchored on the first '\[' but it was being incremented. For now that's still having i be incremented when a \[ is hit, then decrementing it if we get into multiline strings. I was computing the src parameter of memcpy before the call to newstr, but whoops, life's tough when every call to malloc invalidates all your local pointers. I forgot to remove the src calc so I ended up adding src to the pointer twice. The whole br\_if-drop pattern showed up quite a bit, should review how that can be applied to the rest of the codebase. I copied 91 for scanning for the end-of-string marker, needed to change that to 93

## Day Ninety

*2017-06-23* · https://www.patreon.com/serprex/posts/day-ninety-11962765

String escapes were [relatively straight forward](https://github.com/serprex/luwa/commit/77215b880d469f019f3b3c5c371bc8d58546fed0). [\\x](https://github.com/serprex/luwa/commit/77fd32ee4f9a228eb3be91f8be74a56a0eaa75eb) included creating a helper function which'll be useful for parsing hex numbers. What was missing were tests & \\u, decided to [start with tests](https://github.com/serprex/luwa/commit/1f79cceef4f6f0bc3d339a7103a7342316f0fbed) for once. Which found a bug in tmppop

otmpstack is looking like it's going to become the callstack. Just need to add a method to pop it to a specific length etc in order to handle multiple return value opcodes. Which is getting to the desire to replace lex.js with this lexer (after doing perf comparison), update ast with new token format (switched to 4 byte ints over LEB128), & dive into a WASM interpreter for the bytecode. Which'll also require making the bytecode an actual bytecode, since I currently cheat a bit with putting larger-than-byte values into the array

Still need to implement \\u. Should work out how the ABI will deal with exceptions & coroutines

## Day Ninety Three

*2017-06-26* · https://www.patreon.com/serprex/posts/day-ninety-three-12095052

Wrote [\\u](https://github.com/serprex/luwa/commit/5bdc8e30836fdd8f98f9232b52c1317239105d40) over a quarter hour, referencing libcore's [encode\_utf8](https://github.com/rust-lang/rust/blob/fd9d7aa2cf76c949633cb4156642654238c03921/src/libcore/char.rs#L482). Then this morning I was reading Lua's lexer's source & noticed a \\z, so [I did that](https://github.com/serprex/luwa/commit/4ad2ccb198cd1e7c5b907a1d786599352f3c1ac8). Kinda neet that one can test isspace with 9 \<= x \<= 13 || x == 32. Onwards to having the lexer able to lex something useful, [integers](https://github.com/serprex/luwa/commit/b8a7f3c6d15d45ac6e6c6d58fc2156a65440afec). Decided to take the opportunity to finally optimize string equality to compare in [8 byte chunks](https://github.com/serprex/luwa/commit/7f3ab48062783d05f29814b1b1daf4dc658add1a), splitting up [cleanup](https://github.com/serprex/luwa/commit/ef240a47ef3313e2f6b3906433a591c67e991239) from that portion

At this point I'd like to touch vm.wawa, I'm thinking the first stage JIT could actually be producing a hardcoded sequence of call instructions, don't know if the WASM JIT'll inline the calls whenever that happens to become hot. Wanting to keep the output compact. Calling convention of opcode should use tmpstack as the lua stack. My JS Lua toy used generators as API, tmpstack won't be sufficient for coroutines. So I have to have a function take its stack & base as per toy. But this feels like coroutines might end up eating up indeterminate call stack. & this doesn't allow pausing the interpreter in order to let the page refresh. So I can't use the WASM callstack

It's important to get this at the ABI because if I decide that only the VM stack is resumable then I'll get into not being able to properly call into RT code that calls into VM code. That might be alright if I implement all that functionality as VM code. Might end up adding a VM bytecode assembler. Depends if I can get a sufficiently good bytecode optimizer implemented

Opcode returns 0 for next op, 1 for yield, 2 for throw, 3 for call. This is seeming like Python. Perhaps create singleton objects to direct this which get pushed to the callstack, making it a manually managed callstack rather than a pure paramter/return data stack

Ugh. Maybe I should focus on tagged integers first

## Day Ninety Five

*2017-06-28* · https://www.patreon.com/serprex/posts/day-ninety-five-12203928

Implementing [decimals](https://github.com/serprex/luwa/commit/da5453b6dcadef1a36529edc6ea1121604c91ccb) got some test coverage into wawa's untested float handing. This left hex & exponent bits, had a clearer idea of how to [tie hex into things](https://github.com/serprex/luwa/commit/aaa545298bd72f86eaaf9b15c9e68719444ed790), so did that, mostly tweaking decimal code to use chex instead of converting ascii digits to integers inline. Took a break to try tune a Werewolf strugging to finish Act2NM which previously had all negative res, Dark Clan Crusher is not a good weapon for the build either despite the +2 to all skills. Afterwards implemented [e/p](https://github.com/serprex/luwa/commit/3144048d2b8b5ba897d9753a31a5f0a6c8ede622)

The implementation is pretty forgiving. If one ends code with '0x' it'll lex it as '0 x', additionally it allows such numbers as 21.5p3, 0x.ae, probably 0x. too. Made sure to include .23 in there but I should test that

Fun bug during dev: 0x2.1 produced a token stream of '0x2.1 1' which had to do with me having a 'br @fltloop' whereas the br was inside @xfltloop. I keep wanting to scope labels. Should disallow invalid labels while I'm at it

ALSO, I'm thinking I should investigate the use of indirect table calling to enter into the VM environment, at that point things'll get really messy as I work out how to stitch the runtime into dynamically generated code, but only alternative seems to be reproducing the whole RT for every VM gen

## Day Ninety Eight

*2017-07-02* · https://www.patreon.com/serprex/posts/day-ninety-eight-12423754

Shower thoughts reminded me to implement [+/- for e/p](https://github.com/serprex/luwa/commit/6a1ad24c80e33c2d31b8ecc3f1a1c64e293d405c). Have started sketching vm on paper. Started a [Lua prelude](https://github.com/serprex/luwa/commit/1288b310d98c7f71db0561775ea3b14db39cfd06). Removed [labels from func](https://github.com/serprex/luwa/commit/1befb0f7640b83d3b19662574ae699e177fa189e), I think I can essentially implement it as a vec. So many offsets. Also my hashing is broken: it uses identity as a hash value, but identity changes in compaction. So either rehash on compaction or have a global id counter. I could defer rehash. If I have a counter I need to store hash values in vecs & tables. Potentially not vecs if I don't allow vecs to be hashed. Brings in the concept of having a with-hash/without-hash monomorphisation process. Which gets into more codegen which means taking a dive into trying out Forth. Would also be useful to come up with a method to name field offsets because too many bugs happened when table's layout changed to have capacity stored with the buffer

## Day Hundred One

*2017-07-06* · https://www.patreon.com/serprex/posts/day-hundred-one-12516452

Decided new assembler will be a [Lua DSL](https://github.com/serprex/luwa/commit/ff5f3fe9240cf2d7ff30b0d0c0c2ae63a40103f7). Evolved that over this evening. Amusingly there are [no string literals in the generator code for std](https://github.com/serprex/luwa/commit/784151466ddae2fa8a5e25dcb4cb408925bd56e9), so so much for f 'x' application syntax. Would prefer the DSL in Haskell. This is looking alright tho, have some ideas to execute function blocks with an \_ENV set to get the method from the function so one doesn't have to spam 'f:' prefixes, would require binding methods inside the func closure in order to make self an upval

So going to focus on getting this new DSL both working & ported to. Then I'll update the code to not use hard coded offsets for fields. Also included is some basic type inference so that the assembler can both type check & use that info for good & evil

## Day Hundred Five

*2017-07-10* · https://www.patreon.com/serprex/posts/day-hundred-five-12803940

[Development](https://github.com/serprex/luwa/commit/1ee728f4d9b3252ff264e63e20956ec37368086a)[of](https://github.com/serprex/luwa/commit/468049a4d361ce23f85d9ec1d041ed07eb5e0e25)[the](https://github.com/serprex/luwa/commit/2601633fdd9b4a555adf60a7b695bbb0702110ce)[lua](https://github.com/serprex/luwa/commit/262ddc9d014d6f0f1165bb4f590dda9bf9daca8a)-[as](https://github.com/serprex/luwa/commit/dc2e6140d4de902441936084ef6eff7cfa48a352)-[macro](https://github.com/serprex/luwa/commit/4d95190fcaea3ee672c528bc6ffef2edf2f80fa4)-[lang](https://github.com/serprex/luwa/commit/b3f7a86ffc849cf79ffb15c4e197cf77e2aff39a)[assembler](https://github.com/serprex/luwa/commit/093198782f08122e69df1af1ad0f36616292abe8)[is](https://github.com/serprex/luwa/commit/c7a343c7c2ea510afa74b32019ea2d8d557fa147)[almost](https://github.com/serprex/luwa/commit/68db9baee9f761d3e6cafdc224a494421d43c880)[working](https://github.com/serprex/luwa/commit/b22ca7906c06f78e2ffe1b30c8bbb79a0bb0cf1b)[.](https://github.com/serprex/luwa/commit/adb8ee41aec6a21c5f1105015f4315623b16aeae)[.](https://github.com/serprex/luwa/commit/6cc1a3a1e200e19f0e1e8603038d0441752bed3e)[.](https://github.com/serprex/luwa/commit/4f7f69eab9bd26064f388f8632fbeac091613397)

Sprinked in there is implementing table.insert/table.remove/table.move/table.sort in prelude.lua. Tested prelude some too, got to fix up print

## Day Hundred Six

*2017-07-11* · https://www.patreon.com/serprex/posts/day-hundred-six-12873492

[It works](https://github.com/serprex/luwa/commit/14fd8d906212950a044ab95378284b9b5fc43056)

[Cleared out the old](https://github.com/serprex/luwa/commit/54893a8444844d991558964ab292e8b8516dfa66) 

Now to transition to field access by macro. Was planning to do that today but then I ended up on enigma-dev's IRC & got chatting with Josh whom I haven't chatted with for a couple years. I really need to learn not to discard these human connections I make, seldom as they are

## Hundred Seven

*2017-07-12* · https://www.patreon.com/serprex/posts/hundred-seven-12902600

[Simplified local declarations](https://github.com/serprex/luwa/commit/3f6aff77ab3a8d691ca778f25c974b1a179e1171). Having the API match the WASM format ends up making the code simpler too

[Field offset stuff](https://github.com/serprex/luwa/commit/badac4db21d24b4f8d0a63076b270df82c81727e) turned out to be really easy, this is kind of doing it in an easy way tho. Ideally I'd like to capture information about objects in the type inference, have a whole subclassing thing going on, but we'll see if things are well enough without. Unsure how to make a clean type-dispatch macro too

[Data](https://github.com/serprex/luwa/commit/a63ea7bb37c8db11bfcbe5ef3d5a65b8f98cefd4) for simplifying init. Kind of neat that 'eqz eqz' gets to be a byte shorter than 'i32 0 eq'. Don't really like the choice to have both a static index & computed offset for data. Should've had i32.add included in init\_expr spec originally & dropped the index field

## Hundred Eleven

*2017-07-16* · https://www.patreon.com/serprex/posts/hundred-eleven-13021030

[Development on hold while my spare development time is invested elsewhere](https://github.com/serprex/backend-coding-challenge)

All I've done is [pairs/ipairs](https://github.com/serprex/luwa/commit/7d8705c7a173b32dc3b9c8005d0177ac246f047a) while reviewing how I'm going to go about attempting rt/vm.lua while remembering that I need to update ast.js to use the wasm lexer

Also found a [bug report](https://bugs.chromium.org/p/v8/issues/detail?id=6204) for the wasm validation issue in node

## Hundred Nineteen

*2017-07-24* · https://www.patreon.com/serprex/posts/hundred-nineteen-13254527

Did a bit of cleanup over past week still

[The commented out lxaddnum macro is no longer a dream](https://github.com/serprex/luwa/commit/3cd3d1e30c9a554f27110c325fe4588d3ddbfb9d)

[While attempting to drop in the wasm lexer I realized I'd forgotten to tokenize keywords. oops](https://github.com/serprex/luwa/commit/995dbaa5331daa14aaae1a3db56d2a1666c4510d)

[Came up with a suffix sharing pattern in kw parsing](https://github.com/serprex/luwa/commit/e33e2f821010311188b622dc5e8bb4e3547ccfd7)

[Turns out that pattern applies all over lex](https://github.com/serprex/luwa/commit/6441544cef0af0f605a842519b9b6ba4e3d34b4b)

[Table sections](https://github.com/serprex/luwa/commit/56e7e3c7a2bd405895f6ff3a3b6955acd54d3b35). [Continued](https://github.com/serprex/luwa/commit/56e7e3c7a2bd405895f6ff3a3b6955acd54d3b35). So in trying to figure out how I'm going to do dynamic code loading & builtin functions, I've kept coming across Tables being the 'how to do dynamic linking' thing. Finally starting to click: Tables allow for boxed functions through their integer representation. Alternative would be making a hard coded br\_table 'syscall' function. Now that I think about it I kind of like the syscall approach. Thinking generated wasm can be appended to the table (or replace indices), but that'd have to be worked out with CALL\_FUNCTION needing to not push the wasm callstack depth, only the reified stack depth, in order to have straight forward YIELD & other goodies

[frexp](https://github.com/serprex/luwa/commit/7cd6774ec38ded35ea9a86008f80424fc17780e4). Thanks musl. Some really gross frexp implementations in the binaryen test suite, giant br\_table over if x == 0 else if x == 0x7ff. Going to want to revisit this after having added a datastack in order to have a str variant of the vec tmpstack. Will also have to really figure out how the whole builtin ABI works for math\_frexp

[lx.length was undefined](https://github.com/serprex/luwa/commit/f0aff4400f7cc63398b9d29dfb540c7cbe1b551c). Lex2 now gets as far as runbc, where it explodes with some ridiculous arg value. Kind of surprised it gets through codegen at all

[Previously mentioned datastack](https://github.com/serprex/luwa/commit/76a6a502adf7b3c64ca29737e7059fb2b8ed52a4)

[I-have-no-clue-what-I'm-doing wordcode sketch](https://github.com/serprex/luwa/commit/ed3717b717b5ed8283dead053ec26241adf40453). Just need something tangible to bounce ideas off. Kind of weird to talk about something as abstract as code as being tangible

## Hundred Twenty Six

*2017-07-31* · https://www.patreon.com/serprex/posts/hundred-twenty-13538197

[This kind of commit feels good](https://github.com/serprex/luwa/commit/73f131c349ca8cf404dfaee9d0a7e952f61df732). Don't even care that it's moot when that bit of code never worked to begin with

Completed a goal: [Be able to run with either js-lexer or wasm-lexer](https://github.com/serprex/luwa/commit/a9020daa8281385b3b1c6f032eb370d9de8440d9). Being able to compare outputs is really helpful. Funny bug fixed in that commit: identifier parse would exit if an identifier ended at the end of the string, so was able to get test to work by appending a space to the end of it. Went with fixing the issue rather than coding in an always-append-whitespace-to-code hack

[Punted float-int equality edgecase](https://github.com/serprex/luwa/commit/adf5969a041b2e74a8c97aa83160ae6c13273636). Iterated quite a bit on how best to check the float xor int check. Also learnt that C likes to have integer/double comparisons not care so much about whether the integer is actually equal to the double, only the integer as-a-double. Feel like that kind of looseness permiates through languages, up to even the likes of Python where bignums make one feel like it should become all the more strict about equality being equality. Oh well

Oh also ended up learning that memory index for a data section isn't the index in memory, but the actual memory instance. Easy to forget there's future-plans of multiple memories & tables

Suppose that was after having gone to continue fleshing out rt/vm. Found that it'd be nice if pushvec was a buffer object rather than some weird index-on-tmpstack with some-length-from-somewhere. Been thinking of making specialized type for growable strings/vecs. Ended up being one type, just a length & pointer. May want to eventually specialize vec to not scan past length in mark phase. This put the repo in a bit of an everything-is-broken state because I decided to drop the previous pushvec code in favor of this new buf type. Which meant refactoring the lexer

Refactoring was getting past rt/make's validation, but was failing to pass browser validation. In the past it was easy to go through the print out of wawa.js. rt/make instead spits out decimal bytecode for each function. I end up going with Firefox's offset errors & looking up the issue in hexdump. Clearly non ideal UX. So implemented stricter stack depth validation for blocks. Turns out I was leaving a bunch of stuff on the stack with various instructions so that broke a lot. & then call was broken because translation was happening in the same phase as type resolution since params only executes in translation. So refactor params to go before return type, passing params as params to lua func. Can probably cleanup section output now that I don't need to run func's codegen before type section is output

Overall binary size has increased from [this change](https://github.com/serprex/luwa/commit/a1c1e84394d5719aa0ed820e7c321a3d98146a9f). But I think there's more room for compression & long term I expect the abstraction of buf will allow less code duplication. Monomorphization be damned

## 80

*2017-08-02* · https://www.patreon.com/serprex/posts/80-13601752

Yesterday [basic refactoring & stack push ops](https://github.com/serprex/luwa/commit/70bcae679eb608b7f33964347a04cffa0d3ba516)

Today [return & pcall](https://github.com/serprex/luwa/commit/a269410967a89a523fd09decb9dcdd12a0977a36)

Tomorrow.. we'll see

ofc this is all very broken progress. The core ideas being pushed so far are summarized in [the comment atop vm/rt](https://github.com/serprex/luwa/commit/a269410967a89a523fd09decb9dcdd12a0977a36#diff-bd31a30295ec7240668c6fe2279b2a3eR1). Tempting to shortcut stuff like BIN\_ADD like I did in the js implementation, ignoring metatables, but I think it's really important to address the fact that all ops can get into our callstack mess

## 85

*2017-08-07* · https://www.patreon.com/serprex/posts/85-13712200

So pcall needs to be rewritten

[Decided I should avoid repeating info between stack frames](https://github.com/serprex/luwa/commit/fe371851ecfd68d53d232ff24d44a2217caa678c) & stash coroutine specific information at the beginning of the buffer's vec. Also realized that I can't use tmpstack because a coroutine's caller needs to be able to return before the coroutine is off the stack

This came off to me as slacking from the real task at hand: [implementing opcodes](https://github.com/serprex/luwa/commit/9e74559903c2d9c736a7b782e3b95d38c287745a). Those two are straight forward as they're only used with table construction & can therefore avoid any metatable semantics

[Don't break the build they say](https://github.com/serprex/luwa/commit/ebc88f3e97533029df5294b2956601468d62b307). You'll break your nose they say. Chattering by windows, pitch ascending until I shatter

Really need to address the monster in the basement: [metamethods](https://github.com/serprex/luwa/commit/790e0a2d6bbb829f33ea851dc1c78954186a29bf). Having any opcode potentially getting into having to push a stack frame means I really need to come up with a concise macro system to handle stack frame juggling. So far am working out the [stack push](https://github.com/serprex/luwa/commit/5bdf285ae4baa86317da915aab9249c6b2b89a90). Also included some rt/make clean up I've been itching for ever since I fixed parameter types to resolve at func's declaration site. Codegen can wait until code sections are actually being emitted. But anyways back to [stack push](https://github.com/serprex/luwa/commit/d1286ace9f162404b262ac9426d2e0291ea2cd77) & [not double dipping otmp](https://github.com/serprex/luwa/commit/48dd56f189e7b8bf59d4b44574e10ce498aa1480) while trying to not [break the build](https://github.com/serprex/luwa/commit/b1b590eeef41b2a8fc17b3155f98721fb8516d2d)... [Rerevise the lua stack to be a coroutine object](https://github.com/serprex/luwa/commit/228ab780bc8cd99306b1d4967bc772cffc6cf7c5), not a buffer. Coroutines aren't allowed to recursively resume themselves so at any given time a coroutine can only have one caller to yield to. It was getting kind of painful having to reload the equality metamethod through oluastack -\> 1st slot of stack frame object pointers -\> add length of buffer & pointer to dereference table -\> dereference to metatable -\> dereference \_\_eq. I should really just declare one of the unused flagbits a pinbit. OTOH I should leave the gc alone when there's an in progress RFC for wasm that's going to flip my garbage world

Once I work out a clean way to handle returning I'll be ready to start preliminary testing of rt/vm

Meanwhile added some stuff to prelude: [xpcall](https://github.com/serprex/luwa/commit/1669d2173c2a8ba744d975c59ed02500818197c8), [coroutine.wrap](https://github.com/serprex/luwa/commit/f1db1c08f8339580cbd10e9298eed19ccc210dec), [etc](https://github.com/serprex/luwa/commit/dcdb41cdaab191eea41b31d551b35df03825f6a4). Important to work those out to verify they shouldn't impact the core ABI

## 87

*2017-08-09* · https://www.patreon.com/serprex/posts/87-13756920

Started falling back into smaller commits

[rt/vm churn continues](https://github.com/serprex/luwa/commit/910d0a5d7d1ffcd4af8c65ac23c740bfe362e32e). But it's coming together, I've got a new version of [pcall](https://github.com/serprex/luwa/commit/cac8808981ba5876df73f55ef3ffd7c93b84dcbe) thrown together, the code's been moving towards [variables over comments](https://github.com/serprex/luwa/commit/c94f88772a89b53f957d5610b3dae5f5bf7a899e) (need to fit that into an interview: "I don't think comments are necessary, just less than 6 letter variable names"). Code's nearing a point where my goal of cleaning up the code & hand writing some bytecode for it to execute is becoming clearer. So focus turns to [fixes](https://github.com/serprex/luwa/commit/a83ee01470eafdd05961488ac339d1088695ab35). Implement logic that copies a [coroutine's stack to its caller's stack](https://github.com/serprex/luwa/commit/7c1aa6bf326ceb1414216b5e6efdef82a6d967e2) upon completion (going to want to figure out how to try reuse logic between that & coroutine.yield). Got around to some [backlog items like whitespace cleanup & having hash(1.0) == hash(1)](https://github.com/serprex/luwa/commit/934fbcb077ce556f438277bc04c4c7b32941281a). Was really hoping there was some magical f64 hash function that would just happen to map integer equivalents to their integer values, but nope, surveying other language implementations failed to unearth such a beast. Also added the id field there. Went with a single id global since it's a bit of a misnomer: it's a persistent hash value. It isn't an id. Didn't actually add in machinery for that idhash stuff until [afterwards](https://github.com/serprex/luwa/commit/9c9f0b8ee1c5636eba55f7c0366a05b41aae351c). Included there is my finally dealing with having to execute 'rm rt.wasm' whenever an error is thrown during codegen. Don't know why I let stuff like that hang for weeks. So all this vm/rt churn had rt.wasm up to like 8100 bytes so I decided to shave the yak & [remove odatastack](https://github.com/serprex/luwa/commit/cc5d7af4a7c5232a745441fe85c0c2a1ddb5deb0), [remove otmpstack](https://github.com/serprex/luwa/commit/2427147b807dfa2f17ef5fa2f40537df03d92e7f), down to 8004.. & add in some [static data](https://github.com/serprex/luwa/commit/003e13de1ba674b635af850b0a07ff024d921507) to get it back 9662

String data is pretty sparse. All those 4-5 length strings end up needing 6-7 bytes of padding. Type value breaks up runs of zeroes so that one can't straightforwardly break the section into multiple data segments. Could sort all the strings by length, implement loops in an init function to write in type/length. Alternatively implement a basic bytecode to compress to & interpret it. Don't think wasm bytecode is dense enough as an encoding format. All of which should take into account how it interacts with the gzipped size. Executable compression is a whole other topic I'm not going to get into further

Now that I fixed hashing I need to fix the lexer to not map 1 & 1.0 to the same constant. Thinking integer hash should not xor higher 32 bits

zzz

## 8d

*2017-08-15* · https://www.patreon.com/serprex/posts/8d-13864320

Feels good to get [coroutine.status](https://github.com/serprex/luwa/commit/3d9449fc83526cdfd80fa8ae1a13835f48980ba4) out of my head. One of those trivial things that kept intruding my consciousness. Also stack machines are hard, was visualizing AST, so figured tee load i32load i32load would be fine.. whoops, i32load doesn't go to a different stack

[coroutine.running](https://github.com/serprex/luwa/commit/2e328b76b684d0a238bc4fb1ebbf3ad3cd2932f5) [coroutine.isyieldable math.abs](https://github.com/serprex/luwa/commit/20aa6fc5d729df786f8c23055e3f451b8828b785) [whoops](https://github.com/serprex/luwa/commit/a42e1ab0e4a93aafb53f9c6644e6a72251209dd9) [whoops](https://github.com/serprex/luwa/commit/2dc542e73ecd025241993f57652221843a32a129) [loadfile](https://github.com/serprex/luwa/commit/d6108cf03b1139e85bc5016212e934d56a25c836) [whoops](https://github.com/serprex/luwa/commit/b5aa073225c4a3931bfbc33d6d0d6580b97c5b7a) [math](https://github.com/serprex/luwa/commit/8972ec0f583c0d6b202a649df0f01b87cce588d0) [whoops](https://github.com/serprex/luwa/commit/ba6ad065c84f8ac3b988e40ee0bcfa848ffa9143). It's important to get all sketchs out so that when I change the ABI yet again I'll have that much more to rewrite

[select](https://github.com/serprex/luwa/commit/526748acef108487988270183479187dea5d3987). Didn't realize select returns multiple results, complicates things a bit. Also have to get into select('3.0', ...). Realizing the abundance of coercions leads to fleshing out tonum/toint. Perhaps toint should return an i64. tonum a bit torn given it's polymorphic return type. Easy to tweak that later

tonum/toint gets into the idea that I need to start breaking up rt/vm with [various small functions](https://github.com/serprex/luwa/commit/77cdb8f76ed7414d7ea5d4285bb0124c16c3c809) which will then be composable. Because this inline stack frame management isn't working

[init](https://github.com/serprex/luwa/commit/2c1dfb3243945a16ca009c452cc15e6a2315f231). Kind of complicated having to allocate multiple objects, which means making them reachable from root set, while in the midst of creating what's essentially the root set. This also makes it that init will probably get mostly copied for coroutine.create, where the previous oluastack will have to be set as the caller of the new oluastack. Dunno. Maybe I can have init set caller to the old oluastack & then nil it out if we're the real deal

I was going to do [UNARY\_LENGTH](https://github.com/serprex/luwa/commit/2216c2eb6409cb4cba68bc5797afdfc9ecd92636) but then I decided I didn't want to write out the whole metacall ceremony again. It's probably a better choice of metamethod to implement than equality since it's an unary op, doesn't have that boolify behavior..

Became ill. Drank too much tea over past couple days. Was able to pierce the veil of delirium enough to get ['return nil'](https://github.com/serprex/luwa/commit/5bf92c961d092cbee2a0c18037a903156b436be5) working. Also side tracked in collaborating with antiaverage to get openEtG working on https. Got that finally working seamlessly at 5 in the morning..

## 94

*2017-08-22* · https://www.patreon.com/serprex/posts/94-13986819

[memcpy4, broken switch, drop underscore](https://github.com/serprex/luwa/commit/9b4c2f40c078377aac0c03b1bd7b7d4bfb99d5ab)

Proceed into much switch refactoring: [rt/obj](https://github.com/serprex/luwa/commit/ee105530c5c1b459a81566cc4dfbca3e46765c70) [rt/vm](https://github.com/serprex/luwa/commit/7782de6a770eb4e12d2269640ed5466a9b1c9a0a) [coroutine.status](https://github.com/serprex/luwa/commit/d15c7df759c987a755aca2cf5609fd1292bf0a14) [rt/obj](https://github.com/serprex/luwa/commit/9540bbea60f40ef8f07b6ebf1e08748340887f1e) [whoops](https://github.com/serprex/luwa/commit/2e519ec0732adf7fc1a61b3f3fef0b856953b4e9) [newstr](https://github.com/serprex/luwa/commit/e522a7a26ed9e801921f263505dd8bd951025574) [rt/gc&rt/lex](https://github.com/serprex/luwa/commit/68e77cbee32b6a600c7ae0e79fc0188bf6424207) [refactor](https://github.com/serprex/luwa/commit/7dda14194db83376fca4ce161be5311e443c99ed) [whoops](https://github.com/serprex/luwa/commit/4b3e617cc3d829eff4e2b0bd94b3f90a8613c9d3) [whoops](https://github.com/serprex/luwa/commit/8af150936f6a093f8cc1029787fdd58b2f3d5b77) [theory-of-everything-typeck](https://github.com/serprex/luwa/commit/907097ddc99f467d26976790acde7db9cb5c82fb) [branchless-allocsize](https://github.com/serprex/luwa/commit/efe59578adf33f2372383549695c66be07d3ae55) [whoops](https://github.com/serprex/luwa/commit/db20f4de69c74d9c736685d5a04e822d565ad444) [rt/lex-for-real](https://github.com/serprex/luwa/commit/4149084f64616aceb74fea4b3d959f8da4c3f1fe) [refactor](https://github.com/serprex/luwa/commit/6b2d54e174434dbbfb246473765cc7f72fd04970) [branch-ops](https://github.com/serprex/luwa/commit/5f9b8d58a950584d599c5f8daea4a7a49398f38b) [prelude](https://github.com/serprex/luwa/commit/93cb19d1b6f809ca54663fca8bb9b3f75ac2f421) & finally the thing I've been aiming towards: [metacalls](https://github.com/serprex/luwa/commit/17e22ade3ec0e2efb2eb58911eb47c01db9d6d25) 

switch makes this all pretty clean. Took longer than expected to get it all working correctly, could use more error handling. Main goal is the stack frame stuff, pretty simple start, but the first step always takes longer than it should. Considering opcodes for 'reset stack to retb' which can be used to prefix return-push code to avoid a copy there. Also need to write up the store-stack-slots-to-locals prelude logic. Intend to have builtins have wrapper local functions for signatures which then contain some straight up return-syscall instruction. Tempted to have that logic in some kind of near-lua-language that can be precompiled in order to not need the error handling in the wasm definitions. Main focus is getting a comlete call-called-return-returned workflow working so that basic testing can work. Kind of fun working out the calling convention without getting to the actual call instructions

## 99

*2017-08-27* · https://www.patreon.com/serprex/posts/99-14069497

Turns out [unary](https://github.com/serprex/luwa/commit/e6b0aeab70a3486441c96c05f7b8edb0cc14984d) operators are pretty easy. [Coalescing](https://github.com/serprex/luwa/commit/905dbac8f1bd483494e94fd8062ce7db50d20abf) is a slow path. [getmetatable/setmetatable+syscall](https://github.com/serprex/luwa/commit/436c7271120fcd116af30e906919afe7a7e55254). Kind of feeling like syscall could be split up into an opcode for reach syscall. Will come back to that later when I have an idea of opspace usage. May specialize the readarg there to only be 1 byte. In the end syscall is meant for handwritten bytecode. [Split out stdmath from rt/std](https://github.com/serprex/luwa/commit/ec7b851563c9c77aa4df9816afd64085cb6cb560). Includes capturing globals to avoid global rewrite messing up internal implementations in prelude. Not sure how I'll deal with my use of internal methods. ie io.input():read(x) is how io.read is implemented, but I don't have access to file object's metatable in prelude without instantiation. Don't know, haven't thought too much about files, there kind of out of place in this environment to begin with. [Indexing](https://github.com/serprex/luwa/commit/c2afd9a117193dbe0e76f071ac0f3112d7568e08) is a binary operator. Whole file for [strcmp](https://github.com/serprex/luwa/commit/052ad82539cc60e05d3ba86168b9f1f60a4f452f). strcmp is a fun case of where big endian wins over little endian. [lt/le/gt/ge](https://github.com/serprex/luwa/commit/dcaed9407cff5a41fe23075a630514a9dfdd980c). [Whoops](https://github.com/serprex/luwa/commit/bc0ac71bd71b85a90663abf09b3c2d42b64a1a21). All this metatable stuff prompts [yet another ABI revamp](https://github.com/serprex/luwa/commit/240e6a9c5ccabf7710bd20fec708bb4410be540b). At first it starts with deciding to fold coro.obj into coro.stack, the idea being that I should work so hard to optimize out copying in return logic if it's going to bring about copying in call logic, & I can make calls be zero copy. Also [revise init](https://github.com/serprex/luwa/commit/c59d113953ad1cc41ec672f761f984959d38df48) to reuse the oluastack being passed in, program arguments already on stack we were zeroing the length of previously. Then the ABI went full [base+offsets](https://github.com/serprex/luwa/commit/11b0edc74d038af6ffe43a9a5f9c088e7cb80d73), params/locals are separated now, since ... has to exist between params & locals. [First stab at reworking rt/vm with these changes](https://github.com/serprex/luwa/commit/94507ac5f9ca6b82b919dbca381dd29fad7afdae), mind's been adrift on this, can't find a hook to grind, adrift in the shallows, face up, sun down, visitors from abstract space, need to close eyes & resume tunnel vision, world's passing me by, I'm not interested in that trolley ride, just need to focus on the little things, things that matter to me

## 9c

*2017-08-30* · https://www.patreon.com/serprex/posts/9c-14116947

[Static handrolled functions](https://github.com/serprex/luwa/commit/13fbb6d6543a323c3bbab9cbaf86717e417bf76d)

[select with new ABI progress](https://github.com/serprex/luwa/commit/c60c04e0589c9a23465b81eb808e31f55a96593f)

[stdlib with new ABI progress](https://github.com/serprex/luwa/commit/20de420ebb07e083acb1200288c16f04db0e57a8)

[\_ENV init](https://github.com/serprex/luwa/commit/069f72a8f031ecfe26c20905e1c5f90cd2af3b4d)

debug.getmetatable/debug.setmetatable really shook the boat. Going to have to switch to a vec of metatables indexed by type for non-table metatables. Have been rolling around in my mind the next ABI revamp: in place locals. The idea is that instead of computing an intermediate & storing it to a stack slot, I can statically map local variables to stack slots. Skips a store instruction. Would want to modify return to take an argument saying where it's return values begin. Currently thinking I'll pop for-loop variables from stack at beginning of this-statement-returns computation. Other part was thinking it'd be nice if for loop variables were stored in local slots because then the stack would always be empty at the end of a statement. But locals-as-stack-slots seems more interesting. It kind of blurs the line between registers & stack. Small step from that to marking functions with a stack-size & having instructions be told which stack slot to get their values from rather than off the top. Difference with registers is the shedding of nested lifetimes, stack top tracking, & on & on

## a2

*2017-09-05* · https://www.patreon.com/serprex/posts/a2-14229136

[Look ma software architecture](https://github.com/serprex/luwa/commit/20fb7c6edf4fe3998aff9addd65dcf92e896dd54). [Coroutine return](https://github.com/serprex/luwa/commit/79bd214682271605dfd93cb67b0ef7259889cbbf). Will have to reuse most of that for yield syscall. Remember that I'm dealing with [shorts & bools](https://github.com/serprex/luwa/commit/0736d67414a03962c2f681d8fed24fd64ab4748f)

It's frustrating to've left return logic at that cusp, I recall writing it, thinking 'I need to sit down & just bang this out' & yet nothing of the sort. Late days, leaking into labour day weekend. Off the Luwa path: [Learning preact](https://github.com/serprex/openEtG/pull/36). Eventually realized that the PR had reached a point of being able to seamlessly begin transistion from my hand rolled & thin abstraction layer of the dom to preact. Posting live really helped shake out the kinks. The hard work's left on that project. Good point to get back to Luwa, can't lose touch, it all balances, who am I kidding it doesn't balance, lopsided wreck, but the destination, it's coming together, the idea at least

## ab

*2017-09-14* · https://www.patreon.com/serprex/posts/ab-14370219

It seems I won't have to translate musl to wasm for [basic math functions](https://github.com/serprex/luwa/commit/4ca0aa22d5e80b9b5b61f244228669987dcd0e22). I wasn't sure I'd be able to use Math.sin et al without boxing them, & digging into things it seems Chrome at least may've implemented specialized JIT logic for these functions. So it seems that importing Math from JS is both correct & easy

Yesterday I was able to get away from preact drudgery to implement [2-param log/tan](https://github.com/serprex/luwa/commit/05086b225c55b09acdd42190be1e008be701d49c). Been adjusting to a new sleep schedule as I'm transitioning to a support/dev hybrid role which involves being available to answer a phone by 0800. Still need to pull my punch out time an hour back

Today I ended up spending my after hours time finishing reading 'Surely You're Joking, Mr Feynman!' & looking to scratch my own itch on [recursive queries in knex](https://github.com/serprex/knex). Issue there roots in an ecs-in-sql schema where entities have types & entity types are entities. It's not turning out too well because there's issues making it that one has to do two self joins in order to also make sure that the type of the entity's type is the type 'type'. Have some plans to get that simplified

Meanwhile I do not want to lose touch so I got the new ABI's code [working again](https://github.com/serprex/luwa/commit/b2a469a6c801acee99b25fbac89fca7b3d365801) since that had regressed

& off to some wedding for a week

## bb

*2017-09-30* · https://www.patreon.com/serprex/posts/bb-14619321

[Shed the past](https://github.com/serprex/luwa/commit/2611e88841b795e7b9894d6edbecf70a4080f3b7)

[Try to meet up with the new](https://github.com/serprex/luwa/commit/f698a5f8647e09087aa69ef2d307e545c3016d85)

Nope. 1100 lines of bytecode rolling probably isn't worth salvaging to teach how the new bytecode. Rather than build up intermediate representations I'd prefer to generate straight into an rt.mod.newfunc()

If the for loop variables aren't kept on stack, instead moved into some implicit locals, then there's no need to generate pops before returns, as every statement will begin with an empty stack. I'd like to come up with an efficient representation of scopes, one that doesn't involve so many linear scans. Will probably need to still do two pass for free variables. Learn these lessons a second time

openEtG's preact branch has been pushed live; going to let it settle for bugs before rewriting the in-match ui. So this weekend seems the weekend to rewrite bc.js

Considered going straight for bootstrapping by implementing bc.js rewrite in Lua. Unfortuanately to the generated bytecode into the wasm binary would involves pushing the text into JS to lex, ideally passing tokens to an ast.lua. It's tempting, the tooling effort to get it into the build system is probably miniscule to the effort of everything else involved

## c7

*2017-10-12* · https://www.patreon.com/serprex/posts/c7-14840675

So my lexer [failed on newlines](https://github.com/serprex/luwa/commit/c11cc6e6cdc74c32a56a2475cdc71efad4821b76)

Thankfully node can now run [tests](https://github.com/serprex/luwa/commit/632f9462e1a3d358aec846fdeb1d726879fc8970)

Tests failing on travis-ci because I haven't had the motivation to figure out how to teach travis to download lua5.3 in order to build rt.wasm

So got [main.js](https://github.com/serprex/luwa/commit/8bfb888b8c277948ef7885cf4c6ff0af9458b64a) working too. Also started on trying to add travis fixes but never checked to see how to progress further

I sketched ast.lua awhile back but it's totally broken so it wasn't checked in. But since [rt/lex is now referencing the lexer portion of luart](https://github.com/serprex/luwa/commit/069a123ea17bc45cd3fa0a59e9fca44c87c86eca) might as well show what's behind the curtain (actual referencing happened in [a second commit](https://github.com/serprex/luwa/commit/da9c53826e31a2188d03c5be773c3289c86b8d41))

So these changes got me to testing rt/lex a bit more.. [& fixing the inevitable issues](https://github.com/serprex/luwa/commit/6e58e5a5bb65e584865a977837a9e61293d4ee47)

escpaed

[This commit message really expresses myself](https://github.com/serprex/luwa/commit/7c5beb3373258d4263f616dfc1d316f6fd43a650)

[Oops](https://github.com/serprex/luwa/commit/5fe580e4b98f38a2e8c73c3a251a7e2ac0408c8f)

So started on that whole [bootstrapping pipeline](https://github.com/serprex/luwa/commit/ba4832bc00b18cf05b4d5709dd9c866d05572249) I outlined previously

I spent hours reading in disbelief about Lua's require being relative to the working directory rather than the file being executed. Also [translated ast.js into ast.lua](https://github.com/serprex/luwa/commit/fd834a73aa396304530e32028494027f2b83aabc) because I'ven't an issue with the AST structure. Considered taking a dive into earley parsing since a friend recently showed me some [toy early parser he wrote in python](https://github.com/natebuhar/earley.py)

ast.lua wasn't working so I started [optimizing it](https://github.com/serprex/luwa/commit/fd0a5b2ef259c04c14bd99d93354ad66c56c0e45) because make it fast & then make it work

[Turns out ast.lua was fine, the issue was rt/lex. It's always rt/lex](https://github.com/serprex/luwa/commit/1c9e3deabbbb7b338c2f9ccf94b1f9595c93a4b6)

[Identifier lookup](https://github.com/serprex/luwa/commit/41fdab1931212ee695e379bf45601bce70eca93d) wasn't working right so I started optimizing that too

Then I actually f[ixed identifier lookup](https://github.com/serprex/luwa/commit/3c2981ca21d6a83bcf9083a91d388f3028f66ed3)

[References to \_ENV & self were being nulled](https://github.com/serprex/luwa/commit/95abb579bcb1da9d96e1703d0196f1488bb5f748) when lexing api.lua

[Improve rt/make](https://github.com/serprex/luwa/commit/848867822a3418cb1d1b3ae0f6da31659fda4ff0) in regards to features of wasm I don't use

[utf8 validate wasm strings](https://github.com/serprex/luwa/commit/63f6fcc0fad6732c57e12c9484873c217a61f5ca)

& finally start on [luart/bcgen](https://github.com/serprex/luwa/commit/e30732c8911a8cf6564cb9b18e8c856a57fa3788)

I'd like to avoid repeating mistakes of bc.js. Specifically the whole name scoping is a mess there. Ideally I'd have some straight forward constant-time lookup datastructure to handle scope assignments & goto scoping conflict error checking would just fall out in a snap. I probably need to devise that mechanism on paper first. Unfortunately I'm again ill, alcoholism takes its toll, & winter depression has me feeling drained of energy, as demonstrated by how long I've taken to write up this summary of development over the past couple weeks

To oblivion & back, as they say

## e0

*2017-11-06* · https://www.patreon.com/serprex/posts/e0-15234780

Finished conversion of oetg to preact this weekend. So that can't help me procrastinate so much now

Frustrated because I sought to bring about a better design but I'm ending up with a mostly 1:1 js:lua translation. Some differences where I thought I could escape, but the way forward dwindled & now it's just a wart

I don't want a cfg

Scoping gets screwed up because it's referencing token indices despite self & \_ENV not having an index. I should drop this wannabe zero copy AST silliness, the index doesn't beat a tokenid+optionalint by much. Index does help for if I wanted to produce error messages by tracking them back to a line/col

Also considering if I should be reviewing how I'm generating the AST. It's structure could be fine tuned some, if I applied a bit more control over it. Not like the combinators have the desired long term perf characteristics. Maybe I should push for a serialized ast, implement in in wasm

Lua's syntax comes off as straight forward so it's tempting to skip desugaring. But-- so patreon's editor gets messed up by tildes. Anyways 'function x:f(y) return self end' -\> 'function x.f(self, y) return self end' -\> 'x.f = function(self, y) return self end'. Ideally codegen would only have to handle the last case

On the other end I'm weighing if I really want to push for an SSA bytecode. But that's out of my depth, floundering on a shillelagh sought to be a raft. Maybe. Keep that out of mind, empty head floating amongst the waves

## f3

*2017-11-25* · https://www.patreon.com/serprex/posts/f3-15538357

So I think the last time I posted we were about [here](https://github.com/serprex/luwa/commit/07b43696c7453cae2acd27078c5950dec7ba4b70) 

The commits that follow dig into codegen. Eventually deciding to test this code. Proceed to produce fixes rather than just throwing more logs on the fire. Includes some ast issues

Been a bit lethargic while going through a break up. So that happened

Only fell into a [drawling commit message](https://github.com/serprex/luwa/commit/879a4c925ea189230db7b8db641491885a6068bc) once

I'm liking how names are being resolved. It's the one thing I did get to actually improve upon relative to bc.js. Still need to work out how I'm going to take the free variable dependency graph & produce code that passes such into closures, even when the intermediate function doesn't reference the free variable. Implicit usage, maybe invoke usename on all the free variables after scoping a funcbody. Main pain point is also going to be generation of hidden variables for for loops. bc.js got away with leaving that info on the stack, but I want every statement to end with an empty stack

Scoping system made labelck pretty straight forward, so that was nice

Codegen also needs to implement return-- have to push that down the tree so that tailcalls happen

Finally [indexing-from-1 is terrible](https://github.com/serprex/luwa/commit/a426afe2da719d45380bba465f84cd0edee5fabb). Great having to sprinkle random +1-1s everywhere

## fc

*2017-12-04* · https://www.patreon.com/serprex/posts/fc-15696095

[Multiple return values](https://github.com/serprex/luwa/commit/244220b5afa047bb5e2b8ebe20cc0165e62d3edd) from a tail call bit me, don't know how that random yield-nil got there, could git blame for it, there's enough blame in the world, more off-by-1, multiple return was producing nil pushes

Getting ready to [drain the swamp](https://github.com/serprex/luwa/commit/dbd4556d10dd7a0ddc37ce4e56de1278a11a11ff) 

Got a little scared that my scoping was hitting some wrinkle that'd turn out to be a fundamental flaw, [but nope](https://github.com/serprex/luwa/commit/f264dbe1669ae03273a86779c83644cd10a705f2) 

Had to play around with some pretty silly lines of code in the REPL to figure out Lua's [table semantics](https://github.com/serprex/luwa/commit/dec4c070b6dd392e0308402248f015185aedfb6a) ({1,2,\[3\]=4,5,6} == {1,2,5,6}) but it all kind of makes sense when you start to consider the expressions listed along with a function call to occur together. I should check the order of evaluation tho

Finally sat down & accepted that I am indeed going to repeat the [large set of many different kinds of call & multival opcodes](https://github.com/serprex/luwa/commit/61c17a1ba4d0209bf0a5b41d43793bb951c3bf3e). It's just necessary if I want the interpreter to ellide a copy to the stack while being resumable. So I [flailed about](https://github.com/serprex/luwa/commit/ef92fa336dcd5bb64c525f53b8782583fc8c43bb) trying to [flesh](https://github.com/serprex/luwa/commit/6204d3fc5fef00334c826a9786eff0af6a6fa48f) those out

Realized I'd hit that point. The point where I turn back towards actually [bootstrapping](https://github.com/serprex/luwa/commit/c8bfafb34130ab178cadc80350363559a9a0de28) the output of this all. Which pretty quickly started getting [snagged](https://github.com/serprex/luwa/commit/65ebce4479dcaab37ce0ae597b6277d9fec1d715) on my various mistakes from having spent the past long while not really testing anything. Also it seems Lua doesn't like code to have [more than 255 arguments in a function call](https://github.com/serprex/luwa/commit/ca442db2de7ab2aadcac21f77f250d43794a552f). I took especially long finding the [GmpGt typo](https://github.com/serprex/luwa/commit/64817e5bc1b8c0cf2e028beac4860464c92f6a3a)

I was pretty excited about getting bootstrapping working. Almost made a post, something simple, like 'it works'. Decide to treat myself to [obliterating the old JS code](https://github.com/serprex/luwa/commit/bc93b363c6208b3e2db9d1b244377865b36cd142)

Realized that the bootstrapping [required rt.wasm to build rt.wasm](https://github.com/serprex/luwa/commit/d5f91790bb7d1ee01beb52dc9a95b92291992305), which is conveniently in .gitignore. Follow up sought to [reduce recompiling](https://github.com/serprex/luwa/commit/f0744f12e49e875e33b94cc4c26994c19742ac00) bootstrap

Replace shell portion of bootstrap to happen in Lua through [popen](https://github.com/serprex/luwa/commit/05cfb0b50945ff4e2d3ebfc0e5bd5d1d327345cf). Less piping makes for easier print-debugging

Implemented the [simpler instructions](https://github.com/serprex/luwa/commit/786fefb4d5aded103e43cab14c32a0a48f31b155). Hard to decide between hardcoding pointer-size in bytecode [versus](https://github.com/serprex/luwa/commit/d96ba8fc478813a0a65a65c6346d8ee646e5035c) having to multiply by 4 so often. Finally put together some [code to call this prelude](https://github.com/serprex/luwa/commit/9e3d7eee0837f15cfe4df3a0c3725f37830249f9) I'd only glimpsed as being generated through hexdump. Having done that in a rush I later on returned to [get it to go](https://github.com/serprex/luwa/commit/ebc2b89861840e1fdbb305dec3cc8e74864645d7) so far as eval

[Proceed](https://github.com/serprex/luwa/commit/1303c185afb9303200bc8df1645bb49fb4ebccbb) to [spend](https://github.com/serprex/luwa/commit/4e6afeb21fd92bdecf7acbcb33fa582e2fc5189c) a few [days](https://github.com/serprex/luwa/commit/635ded0e8202d4fe9710f1224cd0e8a2a95377e6) getting the [prelude](https://github.com/serprex/luwa/commit/0443bd68c4063fc523a77c0d77aae94c6c70ea84) to [execute](https://github.com/serprex/luwa/commit/ef9cb457e792947000aa4d64b3ebde7a9383262d) up to [trying](https://github.com/serprex/luwa/commit/60ffb67919d3fc1dbe0a7f691dcaf529698dd06c) to [call](https://github.com/serprex/luwa/commit/f5092bbd5de3420fce4b2f17d234757f4da8400c) a [function](https://github.com/serprex/luwa/commit/fd4b8e79ea95f28e9edd0f158506f34cbe3b34ba). Also read [Do Androids Dream of Electric Sheep?](https://www.goodreads.com/review/show/2202556368) 

## 109

*2017-12-17* · https://www.patreon.com/serprex/posts/109-15921493

So I started on implementing [Call](https://github.com/serprex/luwa/commit/4980114a64a5b91c9e30f6bc86912deb4e26a797). Skipped handling chained call at first, but that soon [followed](https://github.com/serprex/luwa/commit/af722127e92f7a9125ab09bcb5387bac11bcb29f). Bit by bit I'd keep rereading this instruction, [fixing little things](https://github.com/serprex/luwa/commit/810c99adf97a5a425a997d3b6cdc6ce9e4bc7603). Only writing locals/frame offsets for [first call of chain](https://github.com/serprex/luwa/commit/c1122aed0d19cf1fae41a3efdbb88dcd667d2b10) as the remaining will have to be resolved in Return. Took this long to notice I wasn't having calls [start with pc at 0](https://github.com/serprex/luwa/commit/ca7c42262f8e5ece47e964846498938fd79bd433), also made sure that this particular call should be implemented: we're calling [debug\_setmetatable('', { \_\_index = string})](https://github.com/serprex/luwa/commit/b1c484fcca2c934a67784a88968dbc7166fe6da3). Took a break from Call to implement [AppendVarg](https://github.com/serprex/luwa/commit/4ebaf78bc0a5c122997622b974702d012ab2802d). Finally got around to [writing objframe](https://github.com/serprex/luwa/commit/d512ea8a3f2765140c5c93c04e66e646bc640eab) since it's kind of important

[Removed NIL == 0 asserts](https://github.com/serprex/luwa/commit/1907e5bdc6b03e8e4cb2a03a8d213f7148a2bd04). This one I'm kind of worried about wrt GC RFC. Hopefully I get to keep nil at 0 & false at 8 so that truthiness can just compare if address is greater than false. Need to have the ability for static objects to exist alongside the GCed objects. Not sure if my input on WASM would be wanted. On the one hand I'm writing a significant amount of WASM, on the other hand I'm writing some crazy hand written WASM target which isn't the intended use case compared to LLVM/emscripten. & my thoughts all unstructured, I don't know, I probably wouldn't know how to express these things. At work we're trying to have specs for product features, I tried writing a spec of what I'm working on, but it just came out as some stream of consciousness about implementation possibilities & then randomly ended at some point where I got bored enough to go back to programming

[This commit](https://github.com/serprex/luwa/commit/4164d5313d34b160b65c4f5668ef0ec5e0874d88) was made in a flurry. Noticed some non free variables as unused locals. echoptr became useful in printing out just about anything, has been pretty useful, a whole new printf debugging experience. Included in there is stuff like \_\_index only being called if the field doesn't exist & store instructions not popping the stack

Whereas [this small commit](https://github.com/serprex/luwa/commit/29d75898aae38549f21bfff1be946da240082231) was prepared to be surgical: write out on paper what I need, review how I'm not doing that, then do that

So I turn my gaze to [Return](https://github.com/serprex/luwa/commit/02bfc3e9dd97c7d8564434bfebce7a44212a5b1d). But first [stdmath wasn't being included](https://github.com/serprex/luwa/commit/b4ed7be484888349a1c5a62d6a1524b4eb0628ed) by accident so of course it was totally broken. [& secondly](https://github.com/serprex/luwa/commit/3f0b9fa8be2537c387e680db641b5240a319b335) I've been itching to fix up this scope resolution nit. & thirdly the call kept going to coroutine.create rather than debug\_setmetatable & it took me a couple days to finally figure out that [I wasn't boxing locals](https://github.com/serprex/luwa/commit/8f284a72c375bc0cb37cb2cac86082c9dac9d9be) so the boxing instructions were being applied to nil, but of course it's no big deal to write randomly in the memory of false/true since nobody really reads that memory anyways. So I tried to [unify this boxing logic & it was broken](https://github.com/serprex/luwa/commit/909d22d9f02cf72254ef75daa349ead2005da05d). Because I was generating boxing instructions based on namety which creates entries for every use of a name, not just its declaration, causing \_ENV to be boxed multiple times, but came up with a nice [fix that's just linear scans](https://github.com/serprex/luwa/commit/2694824eaaae02ba0771d929dd7596be1cce9fa4). Part of what was making debugging this difficult was that [rebuilding bootrt wasn't triggering a rebuild of rt.wasm](https://github.com/serprex/luwa/commit/a452fab488879e0d648baeb62dd8995c4bed7946)

So I can get back to implementing Return now. Also read [On Unnatural Authority](https://www.goodreads.com/review/show/2196141549)

## 119

*2018-01-02* · https://www.patreon.com/serprex/posts/119-16172602

Been reading quite a bit, [The Man Who Japed](https://www.goodreads.com/review/show/2217261863), [Gone with the Wind](https://www.goodreads.com/review/show/2219832153), came out of reading *Choke* not knowing what to think, soon to be done *Confessions of a Crap Artist*, I took to trying to bring the parser/codegen into the bootstrap process in order to be able to have a working REPL, but upon hitting a memory corruption bug the lexer hits when a GC cycle triggers, I decided to focus on removing the huge reliance on global state in the assembler. I'd like to merge rt & luart so that the assembler might be fitted to be the mechanism to produce WASM at runtime. Currently is generating code for lex.wasm that produces a memory fault when creating rt.wasm. So that's been cause for the commit silence, not entirely due to [holidays](http://fiction.wikia.com/wiki/2018_walking_back_into_the_present) & bookishness

## 120

*2018-01-09* · https://www.patreon.com/serprex/posts/120-16302204

Going to start from before the last, since I skipped going over past commits last time, all strung out to dry

[Looking back now](https://github.com/serprex/luwa/commit/200cdbea175b06dda0d011ea5261375f9e90feab), seeing how I just call it silly, the message rings true, but I'm looking it at it now without context. Been away from vm code for awhile now. But I recall this being a classic case of just having to sit down & do the hard word of step-by-step reasoning

Trivial [optimizations](https://github.com/serprex/luwa/commit/c5acec27f9eed917619785a674c18907823fb3b7) are always a good way to kill time. Started digging into the [edge cases of assert](https://github.com/serprex/luwa/commit/aea168e386d0fe8a865bedd5fe55094de5aa3c8c), not sure what got me reading over coroutine stuff, I was kind of tinkering with going the implement pcall on coroutines idea. [LOAD\_FUNC](https://github.com/serprex/luwa/commit/45a23067545dd4be67f701d9d1e7c38fbc9c356d) & decided to not put math.deg/math.rad constants as free variables, ideally the implementation can do constant propagation

[This bug](https://github.com/serprex/luwa/commit/3fff30af3a9dedc8ed623b816f79b802488dff52) was fun. I had to work backwards, from the lexer, trying to determine why there'd be some massive constant appearing, noticing the uncanny constants being ASCIIish. Went as far as printing stuff to see that I most certainly was pushing what I thought. Ah well, need to learn bugs can appear anywhere when one decides to shave the yak

So I've got ideas on how to [implement loadstring](https://github.com/serprex/luwa/commit/450f379320a66b8966917bc57f4fc0eca2670492). It involves shoving most of luart into prelude, thinking of making the \_luwa thing more pervasive in order to reduce the size of the wasm runtime, ie use that to expose buffer objects to implement stuff like utf8 or string functions with

[Moving bootstrapping into the compile step](https://github.com/serprex/luwa/commit/b084f3f785e88cd4ecc5228d9032e698224936b7) makes me want to make the parser not be super slow. Maybe I'll go back to the separate compilation of bootrt

So I started to work out how to [put the rest of luart into prelude](https://github.com/serprex/luwa/commit/293dccc51b5a73c232d751eff70b5ecfaf960321) without having a single file prelude, making \_luwa a special object passed to prelude as opposed to globally available

[By now README was stale](https://github.com/serprex/luwa/commit/67f90a6b362a5035edf78eb4e8e6b18034300d1d)

[Parallel lexers](https://github.com/serprex/luwa/commit/531d5fa475d3703a886f466acf4cfd8ca9f211db) & more cleanup. Bit moot since the lexer's plenty fast

[New lua files for bootstrap](https://github.com/serprex/luwa/commit/9cff6021f27ea4a887abddf12c6bd1e38fbfe6b9) exposes edgecases, & a file with some rightward drift exposes how shallow Lua's internal limits are

& here we have [what I set to do](https://github.com/serprex/luwa/commit/c2e119dfaa703cda64df9df12a42452d16b11882) in [the last post](https://github.com/serprex/luwa/commit/8b42a248b72aed0b9eca0ce4b515adf11b73902d). Still poluting some stuff into global scope because I'm lazy. For a couple days I couldn't figure out what was the last thing wrong, turns out export ids were all off, so I was calling random functions, causing random errors

Sometimes I forget about [util.js](https://github.com/serprex/luwa/commit/e9c9a34c65e996ad106946a16d8b3959b6cc569b). If I merged util.js & rt.js I could drop the dependency on mkcjs

[This bug](https://github.com/serprex/luwa/commit/0306f81caaf9dabd4aaba2e82c621d7ffbc8a867) took a week. Would hit it on the second gc cycle. Was combing through pushstr, doped addlxval to not touch table code, finally ended up commenting out some unbuf logic, fixed issue. Now the bug is astgen claiming a parse error

So I distract myself with [some optimization](https://github.com/serprex/luwa/commit/83b305da7ca5b4d49ff69a30fbbcb1e745412ef9) & [fixing my optimization](https://github.com/serprex/luwa/commit/431cae62e48fab228cf1520338f295b853d0f427)

Which brings us to me deciding to share the current issue before it's been solved. I can get through astgen if I [comment the following 3 lines](https://github.com/serprex/luwa/blob/431cae62e48fab228cf1520338f295b853d0f427/luart/bcgen.lua#L239). Turns out replacing the ellipsis in emitNode with a local variable allows the code to terminate without a peep. The thing which bothers me the most is... I didn't have to comment out emitNodes, which is syntactically the same code. So I'm pretty stumped. Kind of tempted to go off & erradicate coroutines from astgen by working out closure iterators for many & seq

Anyways read [The World Jones Made](https://www.goodreads.com/review/show/2246313839) over the weekend. Feel like I could've enjoyed this good story more if I didn't get hung up on logical realism

## 121

*2018-01-10* · https://www.patreon.com/serprex/posts/121-16322450

Did some recording while [programming](https://github.com/serprex/luwa/commit/996dcd2769ccda6f838a25e9c57d017980e2812a) today

[Reflected on Reflektor](https://soundcloud.com/serprex/excerptsof996dcd2769ccda6f838a25e9c57d017980e2812a) in description

Fruits of this labor: https://github.com/serprex/luwa/commit/996dcd2769ccda6f838a25e9c57d017980e2812a Listening to Reflektor on loop while debugging a lexer bug with --\[\[comments\]\] instead of digging into why bcgen won't parse, noticed since it failed if I used --\[\[comments\]\] instead of --comments while playing around with the error case, decided to pause music & record noises

![attachment](16322450.png)

## 133

*2018-01-28* · https://www.patreon.com/serprex/posts/133-16661243

Made a [program](https://github.com/serprex/luwa/commit/cdfc1ffc7bbc842968d68f89e1ea2b6a1ed8a362) to dump lexer output. I had some inspiration to create a webui which could be used to introspect the heap, inspecting bytecode with opcodes spilling out everywhere, but I decided to stick with the echo spam I've been getting along with. Eventually

Fixed up some bugs while [optimizing](https://github.com/serprex/luwa/commit/a3aa23324d7987d0e59fd6008202e52b2eefeafa) astgen's allocations & rule complexity

If you don't want to say factory just say [higher ordered](https://github.com/serprex/luwa/commit/d535baf63f9572dcc398a4057999f95783b75e1e)

So rt.wasm build was a [simple fix](https://github.com/serprex/luwa/commit/adaaddc4f39206e9815c05f2a12eeb19c9fa5094), once rt.lua was succeeding I had to fix up the rest of the no-globals idea outside of bootstrap. The actual bug was needing to remove lines 74/75 in rt/util.lua

& then imports were wrong & I forgot about [Math.tan](https://github.com/serprex/luwa/commit/c7145abcf47a3d58ff136e607b87b8fb842c6a12)

Got to thinking about [io & debug.debug](https://github.com/serprex/luwa/commit/b7f5d41357945757401b58bce017d8135e8b356b). Increase memory to be 1MB by default since the initial heap is now larger than 64KB with how inefficient my lua bytecode encoding is. Need to weigh between gz encoding being for HTTP to encode & just going ahead with an lz4 decompressor in the start function

More [prelude nitpicking](https://github.com/serprex/luwa/commit/8f86bcd3899ad537d275f83d6f987f11ef4dfbdf). Metatables can't be trusted because I have to defend against a mutable \_ENV. Also I have no idea what I'm doing with quotes. I need a Prettier-for-Lua so I can stop thinking about that kind of stuff

More [thinking about io](https://github.com/serprex/luwa/commit/e20b08b62d39be59443c4e4b781bd2a25c828d50) means more thinking about userdata. Especially since io will behave differently based on whether it's node or browser, so it needs to be very much hooking into the JS runtime. Found out that metatables for userdata is per instance. Probably make userdata something like a table without the array part, maybe let the array part be for hidden data, or force that to be handled by the JS runtime, creating a syscall to call some table index

[debug.getregistry](https://github.com/serprex/luwa/commit/0e6728d5c80611b4d252930d45113b87e21fdab2)'s pretty funny. [Genesis](https://github.com/serprex/luwa/commit/f0a740ade7d8a555cdbeded87f1e4e33adfcb427): Get back to running prelude, messing around with how to drive the lua vm from js, moving startup code out of the start section so that the vm can be rebooted

Naming clashes & that I know I'm going to be requiring the assembler eventually for jit prompts [merging rt & luart](https://github.com/serprex/luwa/commit/2f5d917b4122904b851806dc2c8a9a38a62bdd47)

More typeck [&](https://github.com/serprex/luwa/commit/64742f82c71785e88ceae7ab5acbc35feb23264d) reentrant iterative iterator code is so much more readable than recursive coroutines

[Get the little things right](https://github.com/serprex/luwa/commit/93617ddc0a3f1a48429096bfcf971a8bc7d77767). Really wish Lua was like use-strict, accessing a nil from \_ENV should throw. I know this can all be done with metatable stuff so I'm just whining

Accessing locals which are suppose to be boxed but aren't sure does cause [issues](https://github.com/serprex/luwa/commit/8ec032f19dac3e45998612dae75742bd5e83b7bd). TblNew code is kind of funny, from before I moved temp stack to be the same as the lua stack, right now the pains I go through with the opcodes to not spill multivals onto the stack aren't being reaped, only sown, but long term I can have functions allocate a constant sized stack frame, then reduce reloading pointer values, reduce juggling a stack pointer, move everything to explicit stack slots, register slots, it'll be a scream, for now it's a dream

Anyways from loadstring & io [come loadfile come require](https://github.com/serprex/luwa/commit/dc5294c08a2b513c623b14e57893364d7dd88fde)

Reading over reference, seems my sanitize function is a [string.format option](https://github.com/serprex/luwa/commit/b9bc7306861ddc44207c909bac5e2897d08fb96f)..

[Never trust \_ENV](https://github.com/serprex/luwa/commit/a7f5a5de5d22ef17a63e812560ad3ff190650686). LoadFunc was getting all messed up by having duplicate frees all thrown on the stack, delete the old loadfile I'd written longer ago, io.type had a syscall clash, need to move syscall mapping to a module, I was copying from nil to where the frees were supposed to be on the stack, real fun

if codegen was [totally broken](https://github.com/serprex/luwa/commit/c6a1978a3e4f210f52a3a7c3d626af74d9c5b28d). If I'd've used strings for types instead of having that mapping in ast.lua I could just do visitEmit.Block instead  of visitEmit\[ast.Block\] but even then with how often the structure is static I should do visitEmitBlock, really just yearning for sum types

Some day my [off-by-1 bug](https://github.com/serprex/luwa/commit/4dedb20d4aa8c0d4c008d61db77897059f1b3dec)'ll turn out to be an off-by-2 bug

Luwa has now been [run by someone besides myself](https://github.com/serprex/luwa/commit/78b1a3bb06d0158cd201c62f945a899612447d6d), so hardcoded paths in the name of Arch don't fly. It took me a [few days](https://github.com/serprex/luwa/commit/f00ce70108b39ca2bd8e1a1722e5faa9d2fb19c2) to merge, 13 hour shift to start the week just kept rolling, my week pretty booked, so I had to actually be told by a friend over pizza that someone had opened an issue on github

Readme still [thought make.lua was the entrypoint](https://github.com/serprex/luwa/commit/c9568708f2cb53907b211ffb70c7bde8967aad51). & of course I've never had to pull from the remote so I had to [merge again](https://github.com/serprex/luwa/commit/f00ce70108b39ca2bd8e1a1722e5faa9d2fb19c2)

Was wondering why JifNot was hitting unreachable when it clearly doesn't unreachable.. but oh [fallthrough](https://github.com/serprex/luwa/commit/b088e616e7dc5f0ce831b910612353c242b30337). Settled down to continue going over call logic, spotting that comments lie, & shifts are important. Part of what makes me usually avoid comments, I've worked in code bases where one essentially is playing a game of knights & knaves

Turns out [tostring](https://github.com/serprex/luwa/commit/a833827764fe6b719a7df0b04932fd3bc9b2bb04) can be almost entirely defined by prelude. Feel a bit guilty using +'' to stringify

Anonymous locals [remove GetMeth](https://github.com/serprex/luwa/commit/65d64942243e1749df7000bfbe5d1e26956ae25a), want a tight instruction set, it's bad enough having bcgen dealing with syntactic sugar which astgen doesn't strip out, but by time that hits vm it should be gone. Good [blog post by wingo](https://wingolog.org/archives/2018/01/17/instruction-explosion-in-guile) got me thinking about [choosing both](https://news.ycombinator.com/item?id=16171106) where I'd essentially create templates of the HIR with MIR, then GetMeth would perhaps make sense, it kind of leans on thoughts about nanopass compilers, where you slowly JIT your way through these passes, since any pass you can attach an interpreter can start there instead of doing the remaining passes, only need to keep passing on hot code, had started on thinking on what instructions I'd want for Luwa, most complicated bit is metatable logic, type dispatch of operators, callstack juggling. How does microcode deal with multiple values? Ended up setting the idea down

So there I was stuck staring at call being kind-of broken until I finally noticed it was only breaking down once we got to the stackframe thinking there were locals & not just frees or params, so [fixed](https://github.com/serprex/luwa/commit/59fd9e057afbd79e7a4e09fe4464bfe06fd538a9). Now we get as far as making a call, but it crashes, because at that point we've actually gone as far as doing a return, so must be smashing the stack somehow

The fact that emscripten too is having to put the C stack in WASM memory has me a little worried. Sure, you don't have ROP, but we're going to see what happens when C undefined behavior has sensitive data get left in the heap or someplace & some clientside thing gets a read on that data. We'll see how far people go with trusting clientside, with having it do heavylifting, data manipulation. In the end it can never be trusted

Read [The Penultimate Truth](https://www.goodreads.com/review/show/2252613546) pretty quickly, then spent a whole ten days to get through [The End of The World News](https://www.goodreads.com/review/show/2259619753), mix of maybe phasing out of intent reading, the prose didn't make for light reading, & being busy. Now have a pad of paper to write down words I don't know so that I might expand my vocabulary. Includes words I recognize, might even understand in the context of the sentence, but which I wouldn't be able to pull out & use in a new context. Like candor. I know what it is to speak with candor, but what does it mean to walk into a room with candor?

## 149

*2018-02-19* · https://www.patreon.com/serprex/posts/149-17078805

tmw you fix bugs, but [nothing changed](https://github.com/serprex/luwa/commit/e1c2811d95fa080ddfcefe3b31e9a6a5f7fdd738) 

Improve printing, use memcpy, so many [things to fix](https://github.com/serprex/luwa/commit/57e151dc28204629ab22ee7a2ca54eba3c62d455) 

Keep trying to [dig deeper](https://github.com/serprex/luwa/commit/2689e8f80d7d2cbba18b3f478ca92e935132fc04), trying to figure out what's happening

[Here](https://github.com/serprex/luwa/commit/45ed9c80349e69724fa9543d408a7137bd58d87a) we break through to pairs. No longer does the stack pointer exponentially run off

Fix [codegen & prelude](https://github.com/serprex/luwa/commit/a94087997b18674d66cd7a7a1e90375ca8f35547). Issues pop out from anywhere

[rawget/rawset](https://github.com/serprex/luwa/commit/7792e6aede33b54081a2d808389de84bf592c82d) are pretty straightforward. As are some other [syscalls](https://github.com/serprex/luwa/commit/07aa1784c50e49f0e40c968bbb66b84765f492ef)

Fix an [astgen regression](https://github.com/serprex/luwa/commit/4c4ba73ef8d7aeafcbd4403fca0fd55a198f0cc2) 

So was wondering why code that shouldn't be executing was executing, was digging into the instructions, but nope, silly me, [I mixed up the definition of TRUE & FALSE](https://github.com/serprex/luwa/commit/27c2e87877d34862739209422754e072758639d0). Just don't expect things to get this far with such a fundamental misconception

Turns out nodejs has [readline](https://github.com/serprex/luwa/commit/42c3405cfcca05432c004d85a8e89ac09e78b2d1) in stdlib

[std.next](https://github.com/serprex/luwa/commit/49f8d5c691126187242e94716ccd8b5d23f724b5). I was wondering how REPL was being reached when it should be complaining about next being nil, but since I got to the REPL I started fixing up [the REPL code](https://github.com/serprex/luwa/commit/f01cf680f6db5a8a70fc9044465e03d2e31a2093), having prelude deal with [2-parameter tonumber](https://github.com/serprex/luwa/commit/3127533bd1db136115ad4af27c10b069b6ca6415), oh next being nil was fine because [for-loop codegen was totally bonkers](https://github.com/serprex/luwa/commit/ef3654bda354b2024bf62e160125e27382a88f4d). [Oops](https://github.com/serprex/luwa/commit/1afacd0ae4a58fabaec480c340b54eda379082b1). It's amusing how much more complicated counting-fors are than generic-fors. Could definitely use specialized codegen for constant steps. So anyways [+ & don't copy out of bounds stack](https://github.com/serprex/luwa/commit/c87b51e2d4e2ebf7d0b5f3b319466caa59654ebc). Sometimes I [mess up my left & right](https://github.com/serprex/luwa/commit/68ed99f3529b6f6a801a45cccb0c1cfda93adbe2)

[\_VERSION depends on package.json](https://github.com/serprex/luwa/commit/0d67fe76752a59d5c07d677cb3d71ad63cd848d6)

For some reason tblget is failing to work on \_ENV for load, echoing seems to show it's there, testing tblset/tblget is working alright when reusing a string, so something's pretty wrong with hashing & string identity stuff. Need to look into that. Was hoping to this weekend, but instead of doing that & reading *Left Hand of Darkness*, I spent 35 hours at the office this weekend & am going in tomorrow despite it being a statutory holiday

## 156

*2018-03-04* · https://www.patreon.com/serprex/posts/156-17361417

So [equality was broken](https://github.com/serprex/luwa/commit/57590106f92559898935993003303867eec4f490). First I thought it was hashing different strings differently because maybe I wasn't properly zero padding. Then I thought the equality was broken. Finally I found that switch needed to fill in the gaps. Essentially the issue is the switch table will have 1, 2, 5 & then \#scopes is 2 so it compiles but we ignore the 5

[nil is a boolean](https://github.com/serprex/luwa/commit/99a995d47ec6d900b60205a5b4d1944b657a8dfa). Trits are for kids

[tmpclear](https://github.com/serprex/luwa/commit/bb34f46c8ac5d53dc0acfdf14cf03508973b8161) so that WebAssembly instances aren't one-shot

prelude stdin/stdout [juggling fixes](https://github.com/serprex/luwa/commit/11c8b213cfc0818fcc0e829424a6dec50f97ed67)

This [should](https://github.com/serprex/luwa/commit/293f15b8c4d22a1d5042e79670d8070cf8d203e6), but it doesn't. Just making (function(a) end)() put nil in a. Wrote a note at midnight reminding myself to [fix](https://github.com/serprex/luwa/commit/6df7ba3fbad30e7ba67330cdcbe98e43ed0a8f07) after realizing before bed

& [little rt.js check](https://github.com/serprex/luwa/commit/a8ecfcf6b3fced57bedeee16cef3fd6da657ac4a) let's us see that we're getting as far as returning from loadstring, though it's returning too soon

What I'm really wanting to write about is currently some code that's not quite ready to commit: rewrite of astgen.lua

So currently it works by being a bunch of nested iterators. & this is slow. Especially for parsing astgen for some reason. I feel I've hit a perf wall for this approach. But I do like how astgen specifies Lua's grammar. So I've been thinking of how to make things faster with tables, because apparently fast parsers use tables, & it seems that when one is able to break a problem down to a series of table lookups they'll be at a pretty ideal performance situation

So I started thinking I want to get rid of backtracking by parsing all the options at the same time. Because that's how regex DFAs are cool. But then I began to get an intuition for this pumping lemma thing, & so even if I make my tables recursive I'd still need an infinitely large graph. Oh right, also, there's semantic discord where instead of having one big 2D table I'm actually encoding a graph with Lua tables. What I really want is to be able to have each step be a single table lookup per token, because if you dig down into any of the parser combinators they all boil down to wanting a specific token to continue

So now I'm visualizing this infinitely large graph & I'm wishing I was in Haskell, where the lines between datastructure & control flow blur. But I'mn't, but lazy evaluation is just a lazy man's implicit thunk. So I spent a few hours randomly messing around with where to thunk things in order to stop stack overflows from happening. & it seems to be working now. Perf is only slightly better than iterators. It was a lot slower before I added a bit of memoization. But I'm okay with minor perf, it's terser code, no more closure iterators, has room to grow. Didn't have to touch the grammar specification besides deciding to revert ofs back to of. Need to update it to actually generate an AST since right now it's just returning yes/no on whether the tokens parse

Anyways one thing I did was print out at each step how many possible parses there are. Usually it doesn't often get much past a dozen, but in the AST grammar section where I've got a bunch of long function calls to function calls, it ends up in the thousands. So that's why astgen takes half a minute to parse. I should go see how fast some LPEG Lua parser is on astgen

If I was less stubborn I'd just make parsing the bootstrap happen as a separate build artifact, but parsing 5 files shouldn't be slow, & I want to keep things well designed for bootstrap code being in the runtime

## 161

*2018-03-13* · https://www.patreon.com/serprex/posts/161-17524824

So lazily generating a graph which represents in spirit every possible lua ast doesn't work out so well. Did post a [draft](https://github.com/serprex/luwa/blob/master/rt/astgen2.lua) after pivoting on AST gen & having to dig into vim undo more than I like. Massive slow downs from generating AST nodes, since we're generating the AST for every potential branch, while also allocating lots for the slice of the graph that's being considered

So instead the focus is to come up with a finite pushdown automata. Kind of twiddling around with how to deal with of having to tag \_which\_ type it is, so like (token)\>-\>(STACKOP, tag, graph)

I need to keep the token as the sole key in order to keep merging these lookups into a single table sane. STACKOP is a predicate which is either true, POPx, or PUSHx. POPx requires the top of stack be x, otherwise it doesn't match. PUSHx sets top of stack

See how it goes

## \`\`-\`\`\`

*2018-03-23* · https://www.patreon.com/serprex/posts/17724710

Realized my idea would be labelled 'Deterministic Infinite Automata'

Been trying to think in terms of pushdown automata. Trying to think. Mind's vaporous

Don't know if title will be broken, apparently Patreon doesn't like tildes

The exponential possible states is because it's impossible to tell a function call from a variable assignment without infinite lookahead. f(x) vs f(x)\[1\] = 2

Citation: http://lua-users.org/lists/lua-l/2011-10/msg00426.html

So everytime a funccall is parsed currently it first thinks it might be a variable but then it isn't

Need to consider how one might pivot without reparsing prefix/suffix/call portion. Feels like something mutable, which doesn't play nice with my grow-an-immutable-ast techniques

## 1d0

*2018-04-09* · https://www.patreon.com/serprex/posts/1d0-18064139

So LR really looked like what I was thinking of. Building up what might be a function call or a variable, & only attaching it at the end. Which would mean the children can exist before the parents, so the immutable inversion would follow the natural hierarchy

So I started trying to work that out before deciding to suck it up & not yak shave. I pulled down [LuLPeg](https://github.com/pygy/LuLPeg) & started experimenting

Happened to commit some transient files, like [astgen2](https://github.com/serprex/luwa/commit/471fdf0a4f05195d2a805072811858218c13f776) which was my infinite automaton idea

LPEG stuff ended up under [astgen3](https://github.com/serprex/luwa/commit/0c62b1a1fbe8db7c40199e992985e9a1a411aad4) while changing astgen2 to generate an AST AST which I was thinking how to compile into a pushdown automaton. Was dragging my feet on LR because that means making things be left recursive rather than right recursive, & I wasn't sure how to toggle around on unary parsing there

Then I found out [LPeg doesn't do backtracking](https://github.com/serprex/luwa/commit/6f7d293c6f5bbf582ed722cccc9a2a08eb47e72b). Thought all I'd need to do was [this](https://github.com/serprex/luwa/commit/1955c2ebb4828527829f55c01a60a46b4af89e4b), where I make sure only-name doesn't prefix-intercept indexing, & suffix rules are split into Call-ending & Index-ending variants. The last one impacts codegen quite a bit since it makes Suffix in the AST a linked list rather than a flat array

So figuring that was settled I settled in on updating [bcgen](https://github.com/serprex/luwa/commit/5db48f7a434350a8ff899c0ac4444ca2fc6daa27). Only place parent references are used in bcgen is for [checking if a label is at the end of a block](https://github.com/serprex/luwa/commit/f85b4b01fbb62274b6cf36a3eda61339f032a32e). Nice extra: no longer generate AST nodes for semicolons. LPeg's no-capture-means-match-text was annoying, wish I could have two combinators to decide that, '/ 0' didn't even fix, had to resort to Cc()

[Suffix handling was really broken](https://github.com/serprex/luwa/commit/4557457273fe9c459e699125d85814bc428e848e). So at this point astgen could compile but prelude couldn't, nor could lulpeg. Fixing prelude was pretty quick but [lulpeg made for a good test case](https://github.com/serprex/luwa/commit/7fe2b8b2b17143a22fe3ad86db077817cc8a07df), finding a bcgen bug that existed from before this astgen revamp

I was somewhat interested in how my astgen would perform if I updated it to meet LPeg's greedy ways, but didn't. Build now takes 10s on my system

Time's been additionally taken up learning Latin, reading the bible, finished Psalms, 88 was my favorite, & learning bass. My left index finger has a pain now, might be from gripping neck too tightly while also trying to teach it to reach. Finished my personal project to reach soundcloud's 3 hour limit with *[Entropy](https://soundcloud.com/serprex/entropy)*

## 1d4

*2018-04-13* · https://www.patreon.com/serprex/posts/1d4-18149720

So LuLPeg outputs

Lua code to parse grammar

Infinite bootstrap

Need to either precompile

Or LPEG in WASM

## 1e5

*2018-04-30* · https://www.patreon.com/serprex/posts/1e5-18490937

So my off hours time has become pretty invested in [openEtG](https://github.com/serprex/openEtG/commits/master?before=45e3a8e474fce54882c8a299a9244861788d6e53+35). Reviving communities is work

Spent this evening looking at what it takes to have LuLPeg print out codegen. Less work is converting the code to not generate lua code, instead use loops in closures. So started doing that but 'lua ../scripts/pack.lua \> ../lulpeg.lua' is throwing "lua: ./compiler.lua:36: pattern expected" so I'll have to keep slogging away

## 1f2

*2018-05-12* · https://www.patreon.com/serprex/posts/1f2-18761427

[Dropped LuLPeg](https://github.com/serprex/luwa/commit/6d8b7f6fcdbee536ee5310570c599288ddf61a0c). Spent 4 hours debugging past midnight because at the top of o's closure definition I had 'local res = {}' causing the parsing to pretty much be working except that there were somehow a bunch of nils in the result

So I think this marks completion of the Lua Lua parser subproject. Can get back to debugging the vm

In actuality this new parser comes off as really simple computationally. Tempting to move it into wasm like the lexer. Will resist the urge for now

## 207

*2018-06-02* · https://www.patreon.com/serprex/posts/207-19190383

Started back on specifying opcodes with microcode. WASM isn't a suitable IR: it doesn't abstract the object model, the heap constraints of the GC. Most complicated instruction sketched so far is LoadFunc, need to dig into the metatable opcodes, & ofc that smorgasbord that's call/append/return ops

## 3 tracks in 2 minutes

*2018-08-18* · https://www.patreon.com/serprex/posts/3-tracks-in-2-20838420

Feel like a snail protruding its eyes out, breaking out of that shell I'd been hiding in programming all day, like this space I consume can be explored now. The unobserved life is not worth living? No, the unobserved life is living

Attachment: [3track.ogg](20838420.ogg)

## 5ffc3678e8fd9cf8b4570120cee7c212b0848c0e

*2018-09-25* · https://www.patreon.com/serprex/posts/5ffc3678e8fd9cf8-21624035

Been awhile since reviewing commits, been awhile since really working on things, doing the former should help with the latter, oetg dev is winding down since it seems there isn't tangible interest in polishing the UI, so maybe this winter seeping in will bring me to program Luwa rather than play Starcraft. Very low energy day at work today, slept for an hour & a half, weird half dreams of half dreams

Anyways, [cleaned up](https://github.com/serprex/luwa/commit/3177bd6730a36cc7c5753829a6902415b99217cc) after LuLpeg's dependency creep

[Nitpicking callee/caller stuff](https://github.com/serprex/luwa/commit/9db5fa9df84251c28f47fb948be046eba4f22113), doesn't look that good looking back now, was probably thinking I could avoid pushing top of stack to top of stack, but nope

[Commit microbc](https://github.com/serprex/luwa/commit/d20c9fe0ff788de4eafee3b60157119035cb8236), scrappiest code around. This shows attempting to write out the ASTs as a call tree, unfortunately code builders really prefer to be CFGs, I really need to think this out, part of why I'm writing this, I'm starting to think over computing reserve slots for opcodes in order to avoid allocations mid instruction. Nature of thing makes it that one can't have two objects in wasm variables & tmppush them beforehand, need to reserve before calculating those pointers

So played around with [how to handle Varg](https://github.com/serprex/luwa/commit/a3a10ee1bc7136cee280376e953d39238e6a8240), there's an unknown here in how much I want to bake in VM semantics beyond get-the-thing ops

Some days I can only get out of bed enough to [punt](https://github.com/serprex/luwa/commit/84ea1527b47fe77af8e56ecfe46b04a1170fc7ca) myself back to sleep

Trying to play with an [unary metamethod opcode](https://github.com/serprex/luwa/commit/96615587defb7af92ac246ea0e8327b27449196d)

Huh, was all the way back in June that I made [this transition](https://github.com/serprex/luwa/commit/9723e62db59d936167be85068721f8d7a7e3c2eb). Commit message says most of what I'm trying to think through still. Pretty much realized that I should try to get a similar API to my wasm code builder. Today I wrote out an observation that there's lua-bc & micro-bc & wasm-bc. micro-bc is really weird because it's the layer where Lua objects interact with wasm types, whereas wasm-bc is oblivious about Lua & lua-bc is obvlious about wasm. Hence the need to think how to represent pointer lifetimes only really becoming a programming problem with micro-bc, since lua-bc doesn't know about pointers being integers & wasm-bc has pointer correctness being a programmer problem rather than a programming problem

Took a [swing at comparions](https://github.com/serprex/luwa/commit/d6695a5a9166a844642b2e62e21f5a54eb49a901) as an attempt to experiment with metaprogramming these microbc metaprograms

[Language lawyering is fun](https://github.com/serprex/luwa/commit/bdba641acc925c49428258565e9787c59e795dea)

[List out unsketched opcodes](https://github.com/serprex/luwa/commit/4abef504b9aed595bfe580d2d242d05b8c1b0ae4)

[Sketching Neg](https://github.com/serprex/luwa/commit/f722edb0e799b79f6dc486beb68c79c55f5ac856) with thoughts on how best to express type guards. Can't think about dynamic language JITs without randomly referring to if statements as guards

Got restless with just navel gazing microcode, so started [trying to work out what microcode codegen looks like](https://github.com/serprex/luwa/commit/63cea1bededc595b6fed30c0c17153c2deb358f9). Luda prodded me to explain my mind [drifting into that Church tarpit](https://github.com/serprex/luwa/commit/7f399f675d3d81ee1b7696b488268355e9ce5b1c)

I don't [really like](https://github.com/serprex/luwa/commit/c9c3d85279f127444aa6eaea118191859a4eaa3f) where this codebuilder is going

When in doubt, [start reifying](https://github.com/serprex/luwa/commit/3b51681a4f88e83f42979fb87f2cb62f89714858) more things

Ideally the layout spec wouldn't be [duplicated](https://github.com/serprex/luwa/commit/ef0ab596acf87286ac1f5517373fc340c6469f46) between microbc & alloc

[Lua 5.4](https://github.com/serprex/luwa/commit/75e91bc2bd41adb6b9b80330251268074da7a714)'s a thing, only looks like the real change is 'undef'

[smtfb is based on the Lua sources](https://github.com/serprex/luwa/commit/5ffc3678e8fd9cf8b4570120cee7c212b0848c0e), missed a detail, I think they're bugged, not checking for {} + "3" & using their binary helper function on unary minus

## caee4099511b135b40129ee949c518aa977d2666

*2018-12-03* · https://www.patreon.com/serprex/posts/caee4099511b135b-23083679

Making a post because I'd like to devlog my latest befunge jit, but first I'll review the sluggish past couple months. Took awhile to figure out how to post, seems Patreon's changing things again

[Binary operators](https://github.com/serprex/luwa/commit/24affef37bed089f7f866428cb42644010e0e35a). Pretty straight forward

[Typo fix & trying to outline more microops](https://github.com/serprex/luwa/commit/d832a89da143a32d1c895d0eb0b20aa11831414a). I'm really lost on how to best reify instruction type signatures

[Microops continue, & why are loops so hard](https://github.com/serprex/luwa/commit/ff57e5cbf2898ce9dca1a391e398cdf7868666e5) 

[BNot sketch](https://github.com/serprex/luwa/commit/9884f9b88da55614a447703340a0df2ca2b587d5) 

[This one](https://github.com/serprex/luwa/commit/caee4099511b135b40129ee949c518aa977d2666)'s commit message is a pretty good explanation of what's causing things to circle back to being an AST. Unfortunately my motivation has tapered off to continue the push on this. Thankfully people have stopped donating to this project; I'm really just using this as a place to sometimes make devlogs. This project really lost steam over the past year

Part of that has to do with me realizing that I need to reorient myself to not tie personal worth to side projects. I shouldn't feel like succeeding in a side project validates my value. I also got to focussing on leetcode.com in the latter part of November, practicing the awfully named pattern called dynamic programming

Then a couple days ago I saw *[Toy language JIT using Cranelift](https://www.reddit.com/r/rust/comments/a1aa8i/toy_language_jit_using_cranelift/)*, so I'm throwing together a Befunge JIT '[barfs](https://github.com/serprex/Befunge/tree/master/barfs)' using Cranelift now. Fun to get back to my roots. Had to dig around for awhile to find an [outline of Cranelift's instructions](https://github.com/CraneStation/cranelift/blob/077f0e4794ea115341fce052713a6fc61ed7a474/lib/codegen/meta-python/base/instructions.py)
