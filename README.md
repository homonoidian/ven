## Ven

> **Beware!** Ven is just a hobby project I work on from time to time.

This repository contains a reference interpreter for the Ven
programming language. Ven is lightweight, slick and elegant;
it is inspired mostly by Perl (and Raku), JavaScript, Python
and Lisp (yes, Lisp!)

### Building Ven

1. Clone this repo.

*With Docker:*

A Docker buildimage is shipped with Ven.

2. Run `docker build -t venlang .`;
3. Run `docker run --rm -v $(pwd)/bin:/build/bin venlang`;
4. The executable will be in `bin/`. If you ran Docker as root,
   you might want to `chown` the executable: `sudo chown <your-user> bin/ven`.

*Without Docker:*

2. Run `shards install --ignore-crystal-version`;
3. Run `shards build --release --no-debug --production`.

Also, make sure to install [Inquirer](https://github.com/homonoidian/inquirer).
Otherwise, `distinct` and `expose` statements won't work.

You can `strip` the executable to reduce its size (goes down to about 5M).

### Using Ven

Note that:

1. Ven is not ready enough for experimental use.
2. Ven is never going to be ready for production.

First, you have to start Inquirer:

1. `/path/to/bin/inquirer start -d` starts Inquirer in *detached*
   mode, i.e., as a daemon that will run in the background;
   Omit the `-d` flag if you want to see what the server is
   up to, live.
2. You can see whether Inquirer is running by asking it:
   `/path/to/bin/inquirer shell`. Type `ping` into the prompt,
   and you'll hopefully see `pong`;
3. You can quit from the Inquirer shell by pressing *CTRL+D*;
4. **It is recommended to stop Inquirer after you've fiddled
   with it: it's `/path/to/bin/inquirer stop`, or `die` from
   the interactive shell.**

Second, try to run Ven:

1. Run `ven sanity`. If it worked with no errors, you have
   built Ven & friends successfully and know how to run it
   all now. If it didn't, make sure Inquirer's running and,
   if it is and things still fall apart, file an issue here
   or in the Inquirer repository.
2. Run `ven` for an interactive prompt. Play with it?
3. If you want to see what's going under the hood, pass `-j`
   (or `--just`) flag (`ven -j <...>`). It exposes different
   stages of Ven interpretation. Try `-j read`, `-j compile`
   and `-j optimize` to see what happens. If you don't know
   what to type, type `1 + 1` :slightly_smiling_face:
4. You can run files by just passing them to `ven`: e.g., try
   try `ven examples/calculator.ven`. The `-j` flag works here,
   too, so `ven -j optimize examples/calculator.ven` will dump
   the optimized bytecode for that file.

### Contributing

1. Fork it;
2. Create your feature branch (git checkout -b my-new-feature);
3. Commit your changes (git commit -am 'Add some feature');
4. Push to the branch (git push origin my-new-feature);
5. Create a new Pull Request.
