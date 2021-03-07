Ven is a lightweight scripting language and (**beware!**) a
hobby project. It provides a few curious features:

- [x] Extremal cooperation between the parts of the implementation;
- [x] Context and constant guesswork (compile-time and runtime alike);
- [x] Brevity and clarity (disputable, of course);
- [ ] Unity of interpretation and compilation;
- [ ] Unrestricted access to the language's internals anywhere and at any point in time.

### Building Ven

*On \*nix*:

1. Install [Crystal, shards](https://crystal-lang.org/install/) and *libgmp*.
2. Download this repository (via `git clone` or GitHub's *Download ZIP*).
3. Unzip if necessary. `cd` into the downloaded repository.
4. Run `shards install` to install the libraries Ven depends on.
5. Run `shards build --release`. You can optionally provide the
`--no-debug` flag, which will omit all debug information and
greatly decrease the executable's size.
6. The executable will be in `bin/`.

**(NOTE)**: if there's a `boot error`, redo step 5 with the
`BOOT` environment variable set to an absolute path to the
`std/` directory. E.g., in BASH, `BOOT=/absolute/path/to/ven/std shards build --release`.

*On Windows*:

:no_good: Try WSL.

### The Ven Pipeline

Right now, Ven code is interpreted using a simple (and slow,
for what it does) node visitor.

+ Core parsing (called *reading* in Ven) happens in *src/ven/read.cr*;
parselets (units that read a definite entity, *quote*) are
located in *src/ven/parselet/*. They make the core reader
actually read something (see `prepare` in *src/ven/read.cr*)

+ The visiting (evaluation) happens in *src/ven/eval.cr*.
Evaluation is done statement-by-statement to support the
tight integration between the reader and the evaluator:
a statement is evaluated right after the reader reads it.

+ *src/ven/world.cr* is the negotiation buffer between the
reader and the interpreter. The reader and the interpreter
both have access to World, and World has access to the reader
and the interpreter. World also holds the Context
(*src/ven/suite/context*). This means, for example, that the
reader could create a runtime variable.

There is a huge problem with recursion depth. With speed. With
brevity and clarity, which are promised and declared but not
really proven by action.

### Contributing

Thanks for your interest!

As I have stated, though, this is a hobby project. There are
no guidelines, no roadmaps, and everything I add comes off my
ever-recent ideas.

What I really want to say is this: it is *very* hard to contribute
something *new* to a project whose goals and aims you don't
even know.

Have a look at the code, though. You can search for spelling,
grammar et al. mistakes. For inefficiencies. For eye-disintegration
entities. For saboteurs.

If you want your changes in the project,

1. Fork;
2. Commit;
3. PR when ready & (maybe) have the approval.
