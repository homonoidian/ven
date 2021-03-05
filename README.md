Ven is a programming language that aims to be a flexible medium for thought.
Because of this, it has many curious features:

* Extremal cooperation between the parts of the implementation.
* Unrestricted access to the language's internals anywhere and at any point in time.
* Context and constant guesswork (compile-time and runtime alike).
* Interpretation and compilation, together (TODO).

### Building Ven

*On \*nix*:

1. Install [Crystal, shards](https://crystal-lang.org/install/) and *libgmp*.
2. Download this repository (via `git clone` or GitHub's *Download ZIP*).
3. Unzip if necessary. `cd` into the downloaded repository.
4. Run `shards install` to install the libraries Ven depends on.
5. Run `shards build --release`. **IMPORTANT**: it is obligatory
   to have the *BOOT* environment variable set; it should contain
   an absolute path to *std/* (e.g., `/home/user/Downloads/ven/std`),
   orelse building will fail. E.g., if you are using BASH:
   `BOOT=/absolute/path/to/std shards build --release`.
6. The executable will be in `bin/`.

*On Windows*:

:no_good: Try WSL.

### The Ven Pipeline

Imagine a cooperative committee where every member fulfills
some job and, at the same time, can ask the other members for
help.

+ *src/ven/world* manages the relationships between the committee
  members; i.e., it is the committee itself.
+ *src/ven/read* is the reader. It processes a file into a series
  AST nodes (called quotes in Ven), advancing one at a time.
+ *src/ven/eval* is, right now, the only evaluation machinery Ven has.
  After the reader produces a statement quote, *eval* evaluates it.
+ *src/ven/suite/context* is, roughly speaking, the context all
  of this happens in.

### Contributing

1. Fork.
2. Commit.
3. PR when ready.
