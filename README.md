**Ven bytecode compiler & virtual machine are being under active
development on this branch. Ven of this branch is generally faster,
has no stack limit etc., but has a lot less features.**

Ven is a lightweight scripting language and (**beware!**) a
hobby project.

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
