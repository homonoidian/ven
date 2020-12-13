# Ven

> And God said: `ensure "hello" + "world" is 10`

# Possible questions

* **What is Ven?**
  Ven is yet another toy programming language project of mine.

* **How do I run the thing?**
  *Do you really want to?*
  If you do, run `shards install` and `shards build`. It may say
  you don't have the development version of *libgmp*, so install
  that in some way or another. And blame Crystal & Shards for the
  rest of the errors that may arise during the build :)

* **Can I help?**
  I don't know. Right now Ven is more of a personal project.
  Also, I barely know how to use git, let alone manage the
  thing with GitHub. If you really want to help though, check
  for spelling mistakes etc. -- I am not a native so I do a
  lot of these.

* **Why perf. is bad / code looks bad?**
  + It's a *prototype* implementation of an *experimental*,
    *toy*, *fun-to-play-with* and, most importantly, *heavily
    runtime-dispatched* programming language. Which was never
    intended for serious use.
  + Node visitor is the quickest way to get the thing working.
    And performance doesn't really matter right now.
  + Code looks as good as I could make it, for now at least.

* **I. Need. Performance!**
  OK! How about 100x slower than Python? I'll repeat: this implementation
  isn't geared towards performance at all.
