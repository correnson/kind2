# Kind 2

A multi-engine, parallel, SMT-based automatic model checker for safety properties of Lustre programs.

Kind 2 takes as input a Lustre file annotated with properties to be proven
invariant (see [Lustre syntax](./2_input/1_lustre.md#lustre-input)), and
outputs which of the properties are true for all inputs, as well as an input
sequence for those properties that are falsified. To ease processing by front-
end tools, Kind 2 can output its results in [XML format](./3_output/2_xml.md#xml-output).

By default Kind 2 runs a process for bounded model checking (BMC), a process
for k-induction, two processes for invariant generation, and a process for IC3
in parallel on all properties simultaneously. It incrementally outputs
counterexamples to properties as well as properties proved invariant.

The following command-line options control its operation (run `kind2 --help` for a full list). See also [the description of the techniques](./1_techniques/1_techniques.md#techniques) for configuration examples and more details on each technique.

`--enable {BMC|IND|INVGEN|INVGENOS|IC3}` Select model checking engines
   
By default, all three model checking engines are run in parallel. Give any combination of `--enable BMC`, `--enable IND` and `--enable IC3` to select which engines to run. The option `--enable BMC` alone will not be able to prove properties valid, choosing `--enable IND` only will not produce any results. Any other combination is sound (properties claimed to be invariant are indeed invariant) and counterexample-complete (a counterexample will be produced for each property that is not invariant, given enough time and resources).

`--timeout_wall <int>` (default `0` = none) -- Run for the given number of seconds of wall clock time

`--timeout_virtual <int>` (default `0` = none) -- Run for the given number of seconds of CPU time
 
`--smtsolver {CVC4|Yices|Z3} ` (default `Z3`) -- Select SMT solver

The default is `Z3`, but see options of the `./build.sh` script to override at compile time
  
`--cvc4_bin <file>` -- Executable for CVC4

`--yices_bin <file>` -- Executable for Yices

`--z3_bin <file>` -- Executable for Z3

`-v` Output informational messages

`-xml` Output in XML format


## Requirements

- Linux or Mac OS X,
- OCaml 4.03 or later,
- [Menhir](http://gallium.inria.fr/~fpottier/menhir/) parser generator, and
- a supported SMT solver
    - [CVC4](http://cvc4.cs.nyu.edu),
    - [Yices 2](http://yices.csl.sri.com/), or
    - [Yices 1](http://yices.csl.sri.com/old/download-yices1-full.shtml)
    - [Z3](http://z3.codeplex.com) (presently recommended), 

## Building and installing

Move to the top-level directory of the Kind 2 distribution, and make sure the path to that directory does not contain any white spaces (i.e., do not use something like /Users/Smith/Kind 2/). Then, run

    ./autogen.sh

By default, `kind2` will be installed into `/usr/local/bin`, an operation for which you usually need to be root. Call 

    ./build.sh --prefix=<path>
    
to install the Kind 2 binary into `<path>/bin`. You can omit the option to accept the default path of `/usr/local/bin`. 

The ZeroMQ and CZMQ libraries, and OCaml bindings to CZMQ are distributed with Kind 2. The build script will compile and link to those, ignoring any versions that are installed on your system. 

If it has been successful, call 

    make install

to install the Kind 2 binary into the chosen location. If you need to pass options to the configure scripts of any of ZeroMQ, CZMQ, the OCaml bindings or Kind 2, add these to the `build.sh` call. Use `./configure --help` after `autogen.sh` to see all available options.

You need a supported SMT solver on your path when running `kind2`.

You can run tests to see if Kind 2 has been built correctly. To do so run

    make test

You can pass arguments to Kind 2 with the `ARGS="..."` syntax. For instance

    make ARGS="--enable IC3" test


## Documentation

You can generate the user documentation by running `make doc`. This will generate a `pdf` document in `doc/` corresponding to the markdown documentation
available [on the GitHub page](https://github.com/kind2-mc/kind2/blob/develop/doc/usr/content/Home.md#kind-2).

To generate the documentation, you need

* a GNU version of `sed` (`gsed` on OSX), and
* [Pandoc](http://pandoc.org/).



## Docker

Kind 2 is available on [docker](https://hub.docker.com/r/kind2/kind2/).

### Retrieving / updating the image

[Install docker](https://www.docker.com/products/docker) and then run

```
docker pull kind2/kind2:dev
```

Docker will retrieve the *layers* corresponding to the latest version of the
Kind 2 repository, `develop` version. If you are interested in the latest
release, run

```
docker pull kind2/kind2
```

instead.

If you want to update your Kind 2 image to latest one, simply re-run the
`docker pull` command.

### Running Kind 2 through docker

To run Kind 2 on a file on your system, it is recommended to mount the folder in which this file is as a [volume](https://docs.docker.com/engine/tutorials/dockervolumes/#/mount-a-host-directory-as-a-data-volume).
In practice, run

```
docker run -v <absolute_path_to_folder>:/lus kind2/kind2:dev <options> /lus/<your_file>
```

where

- `<absolute_path_to_folder>` is the absolute path to the folder your file is
  in,
- `<your_file>` is the lustre file you want to run Kind 2 on, and
- `<options>` are some Kind 2 options of your choice.

**N.B.**

- the fact that the path to your folder must be absolute is [a docker constraint](https://docs.docker.com/engine/tutorials/dockervolumes/#/mount-a-host-directory-as-a-data-volume);
- mount point `/lus` is arbitrary and does not matter as long as it is
  consistent with the last argument `/lus/<your_file>`. To avoid name clashes
  with folders already present in the container however, it is recommended to
  use `/lus`;
- replace `kind2:dev` by `kind2` if you want to run the latest release of Kind2
  instead of the `develop` version;
- `docker run` does **not** update your local Kind 2 image to the latest one:
  the appropriate `docker pull` command does.

### Packaging your local version of Kind 2

At the top level of the Kind 2 repository is a `Dockerfile` you can use to
build your own Kind 2 image. To do so, just run

```
docker build -t kind2-local .
```

at the root of the repository. `kind2-local` is given here as an example, feel
free to call it whatever you want.

Note that building your own local Kind 2 image **does require access to the
Internet**. This is because of the packages the build process needs to
retrieve, as well as for downloading the z3 and cvc4 solvers.
