# Ven

In short, Ven is a playground for trying out my (and your!)
ideas in programming language implementation and design. Right now,

* Ven is highly dynamic (like: `ensure "hello" + "world" is 10`).
* Ven is highly unstable.
* Ven is mostly unusable (what I want to say is this: Ven is
  not meant to be used at this particular stage of development)
* Ven has no tests, and that's a *very* big problem.
* Ven has no roadmap (but see issue #2).
* Ven is very slow (approx. 100-500x CPython, exponential at times).

### Trying Ven

Ven is written in Crystal, a language itself not yet ready. Beware!

To compile Ven, you will need (as far as I know):

+ `crystal` and `shards` (see [Crystal installation instructions](https://crystal-lang.org/install/))
+ `libgmp` (math)

Clone this repository, `cd` into the clone, run `shards install` to
install Ven's dependencies and `shards build --release` to build
Ven. The executable will be in `bin`.

### Contributing

Fork, branch, change and pull request. Beware! `eval.cr`, `ven.cr`
and others will be subject to major changes and deletions.
Stable files (no major changes planned) are `read.cr`,
`parselet/*` and `component/quote.cr`.
