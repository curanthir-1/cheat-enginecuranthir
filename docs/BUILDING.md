# Building

## On Linux (cross-build to Windows) - what this fork's releases use

Tested on Ubuntu 24.04, which ships FPC 3.2.2 and Lazarus 3.0.

```bash
sudo build/setup-toolchain.sh
```

```bash
build/build.sh
```

The first command installs the packages and builds the Windows cross toolchain (about five minutes). The second
builds everything (about ten minutes) into `Cheat Engine/bin` and zips that folder to
`dist/CheatEngine-community.zip`. Unzip it on Windows and run `Cheat Engine.exe` (a launcher that starts the 64-bit
or 32-bit build), or `cheatengine-x86_64.exe` directly.

### What the toolchain script does

Ubuntu only ships the native Linux compiler and units, and its `fpc-source` package has the generated makefiles
removed. `setup-toolchain.sh` therefore, using only distribution packages:

1. regenerates the makefiles with `fpcmake` and recreates the two tiny `makefile.cpu` files,
2. builds the win64 RTL and FPC packages with the native `ppcx64` (it can target win64 by itself),
3. regenerates the compiler message includes with `msg2inc` and builds an i386 cross compiler (`ppcross386`),
4. builds the win32 RTL and FPC packages,
5. copies the units to `/usr/lib/x86_64-linux-gnu/fpc/3.2.2/units/<target>`, where the stock `fpc.cfg` finds them.

No external binutils are needed: FPC has an internal assembler and linker for Windows targets. Lazarus builds the LCL
for the win32 widget set by itself the first time `lazbuild` runs.

### What gets built

| Output in `Cheat Engine/bin` | Project |
|---|---|
| `cheatengine-x86_64.exe`, `cheatengine-i386.exe` | `cheatengine.lpi` |
| `Cheat Engine.exe` | `launcher/cheatengine.lpi` |
| `speedhack-*.dll`, `vehdebug-*.dll`, `luaclient-*.dll`, `allochook-*.dll`, `winhook-*.dll` | the folders of the same name |
| `Tutorial-x86_64.exe`, `Tutorial-i386.exe` | `Tutorial/tutorial.lpi` |
| `ceregreset.exe`, `xmplayer.exe`, `windowsrepair.exe`, `cepack.exe` | the folders of the same name |

### Things to know

* After changing the interface of a unit, FPC 3.2.2 can stop with "Compilation raised exception internally" or
  "Internal error 200611031" on an incremental build. Delete `Cheat Engine/lib` and build again; `build.sh` always
  starts clean for this reason.
* `lazbuild` rewrites the `.lpi` project files on every build. `build.sh` restores them with `git checkout`.
* The Visual Studio projects (`*.sln`: kernel driver, tcc, Mono/.NET/Java collectors, Direct3D hooks) are not
  built by these scripts. See the upstream instructions in the README if you need them.

## On Windows with the Lazarus IDE

1. Install Lazarus 3.0 (or 2.2.x) 64-bit, plus the `cross-i386-win32` add-on if you want the 32-bit build.
2. Open `Cheat Engine/cheatengine.lpi`, pick the build mode `Release 64-Bit`, and build (Shift+F9).
3. Build the secondary projects in the table above the same way.

## GitHub Actions

`.github/workflows/build.yml` runs the two scripts on every push and pull request, and uploads
`CheatEngine-community.zip` as a workflow artifact (Actions tab -> the run -> Artifacts).
