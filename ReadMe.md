# dub-build-deep

`dub-build-deep` is a simple utility that fetches and builds all dependencies
of a DUB package for a specified compiler, architecture, configuration, etc.

This program is needed because DUB won't do a recursive build when sub-dependencies
are static libraries (virtually 100% of Dub library packages).

This is mainly useful for D projects working with Meson, which expects all the needed
DUB dependencies and sub-dependencies to be already available during the `meson setup` phase.

## Manual

```txt
$ dub-build-deep -h
dub-build-deep v1.0.0 - An utility to build DUB sub-dependencies

Usage:
    dub-build-deep [options] (package name)[@version]

Most options are the same than expected by DUB describe.

            --config Specificy a DUB configuration
   --override-config Specify a DUB configuration for a sub-dependency
               --dub Specify a DUB executable
          --compiler D compiler to be used
              --arch Architecture to target
             --build The build type (debug, release, ...)
-h            --help This help information.
```

## Usage example

- Build `vibe-d:http@0.9.4` and all sub-dependencies
- For compiler `dmd`, architecture `x86_64` and build type `release`
- Dub configuration `notls` is specified for the subpackage `vibe-d:tls`

```txt
$ dub run dub-build-deep -- --override-config vibe-d:tls/notls --compiler dmd --arch x86_64 --build release vibe-d:http@0.9.4`
[...]
running "dub" describe ^"vibe-d:http@0.9.4^" --override-config vibe-d:tls/notls --compiler dmd --arch ^"x86_64^" --build release
Warning: vibe-d:http@0.9.4 does not appear to be present locally. Will try to fetch and repeat...
running "dub" fetch ^"vibe-d:http@0.9.4^"
running "dub" describe ^"vibe-d:http@0.9.4^" --override-config vibe-d:tls/notls --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:http@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:inet@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:data@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:utils@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"stdx-allocator@2.77.5^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:textfilter@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-core@1.22.0^" --config winapi --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"eventcore@0.9.20^" --config winapi --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"taggedalgebraic@0.11.22^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:stream@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:tls@0.9.4^" --config notls --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"vibe-d:crypto@0.9.4^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"mir-linux-kernel@1.0.1^" --config library --compiler dmd --arch ^"x86_64^" --build release
running "dub" build ^"diet-ng@1.8.0^" --config library --compiler dmd --arch ^"x86_64^" --build release
```
