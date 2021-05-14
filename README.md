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

### Contributing

1. Fork it;
2. Create your feature branch (git checkout -b my-new-feature);
3. Commit your changes (git commit -am 'Add some feature');
4. Push to the branch (git push origin my-new-feature);
5. Create a new Pull Request.
