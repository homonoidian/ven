## Ven

> **Beware!** Despite the serious look (hopefully!), Ven is just
> a hobby project I work on from time to time.

This repository contains a reference interpreter for the Ven
programming language. Ven is lightweight, slick and elegant;
it is inspired mostly by Perl (and Raku), JavaScript, Python
and Lisp (yes, Lisp!)

### Building Ven

1. Clone this repo.

_With Docker:_

A Docker buildimage is shipped with Ven.

2. Run `docker build -t venlang .`;
3. Run `docker run --rm -v $(pwd)/bin:/build/bin venlang`;
4. The executable will be in `bin/`. If you ran Docker as root,
   you might want to `chown` the executable: `sudo chown <your-user> bin/ven`.

_Without Docker:_

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

1. `/path/to/bin/inquirer start -d` starts Inquirer in _detached_
   mode, i.e., as a daemon that will run in the background;
   Omit the `-d` flag if you want to see what the server is
   doing, live.
2. You can see what Inquirer is up to by the means of its
   interactive shell (`/path/to/bin/inquirer shell`), too.
   Type `ping` into the prompt, and you'll hopefully see `pong`;
3. You can quit from the Inquirer shell by pressing _CTRL+D_;
4. **It is not recommended to leave Inquirer running in background
   for too long (who knows what leaks there may be!).** To
   stop Inquirer, you can run `/path/to/bin/inquirer stop`,
   or use the `die` command from the interactive shell.

Second, try to run Ven:

1. Run `/path/to/bin/ven sanity -t`. If it worked with no errors,
   you have successfully built Ven. Moreover, Ven itself had a
   proper interaction with the running instance of Inquirer!
   If there was a boom, though, make sure Inquirer's running and,
   if things still fall apart, file a bug here or in the Inquirer
   repository (choose as you wish).
2. If you want to play with Ven through an interactive prompt,
   run `/path/to/bin/ven`.
3. If you want to see what's going on under the hood, pass
   `-j` (or `--just`) flag (`ven -j <...>`). It halts Ven at
   the specified stage of the interpretation process. Try
   `-j read`, `-j compile` and `-j optimize`. If you don't
   know what to type, type `1 + 1` :slightly_smiling_face:
4. Use `/path/to/bin/ven path/to/file.ven` to run a file. Try
   `ven examples/calculator.ven`. The `-j` flag works here,
   too, and `ven -j optimize examples/calculator.ven` dumps
   on you the optimized bytecode — as expected.

### Contributing

1. Fork it;
2. Create your feature branch (git checkout -b my-new-feature);
3. Commit your changes (git commit -am 'Add some feature');
4. Push to the branch (git push origin my-new-feature);
5. Create a new Pull Request.
