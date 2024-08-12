# ZigStation 2

An experimental project for compiling zig for the PlayStation 2, using the [PS2DEV](https://github.com/ps2dev/ps2dev)
toolchain and [PS2SDK](https://github.com/ps2dev/ps2sdk).

## Requirements

- Zig 0.14.0 (tested with `0.14.0-dev.839+a931bfada`)
- PS2SDK and PS2DEV environment variables with a relatively recent build of the toolchain (`mips64r5900el-ps2-elf-gcc` works, `ee-gcc` doesn't)

## Tested on

- compiled EE code has been tested on:
  - pcsx2 2.0
  - SCPH-75004

compiled IOP code has not been tested yet.

Planned testing:

- SCPH-70004, primarily due to the original IOP.

I don't have any non-slim PS2s on hand, but feel free to test the example elf file this repo compiles on your own consoles,
and please report back whether it works on not!

## Limitations

PS2DEV declares a custom target called `mips64r5900el-ps2-elf`, and this cannot be compiled by Zig's LLVM backend.
Due to this, the zig target has been set to `mipsel-freestanding-c`, which translates the zig code to C as if it was
compiling for a plain mipsel cpu without any ABI, and then the buildscript passes this generated C code to ps2dev's gcc.

The main issue with this is that any POSIX functionality in zig's standard library doesn't work (POSIX error type is
`void` on freestanding), this includes most logging utilities, std.Thread (even though pthreads *is* available in PS2DEV).

## Contents

- `build.zig` - Contains an example buildscript that invokes the PS2DEV gcc compiler for compiling and linking
- `src/c.h` - Separate C header file with the imports. The buildscript converts this to zig, and then adds it as an import.
The reason for doing it like this instead of @cImport is that `zls` is unaware of the PS2SDK system imports, and this
also reduces compile times a bit when changing zig code only (cImports don't need to be re-evaluated)
- `src/main.zig` - An example code that can run on the ps2 once compiled. I will frequently modify this file, so it will
do different things depending on which commit you're on.
- `shell.nix` - For NixOS users. A shell with the PS2DEV and PS2SDK env vars, and an FHS with the PS2DEV dependencies.
You probably have your own already if you got this far.
- `zls` - Also for NixOS users. Launches the `zls` executable from PATH inside the `shell.nix` file's FHS.

## Future goals

- Encapsulate the mess in build.zig to a standalone module which can be imported via build.zig.zon
- Create a patchset for the zig standard library for the PS2DEV ABI
- (maybe?) upstream a `ps2dev` OS target/abi to zig. Object file generation still unsupported (it's in LLVM), only C
backend is targeted for now.
- Abstraction layers to hide the raw C code mess
- DMA demo that works with the vector units to make a spinny cube using said abstraction layer

## License
Plain old LGPL3.0 for now, see `COPYING` and `COPYING.LESSER`.

## Contributing
Feel free to contribute any improvements, cleanups, abstraction layers, etc. (really just whatever you want, this project
is still very new and I don't really have a precise goal aside from "zig on PS2")

## Community
At the moment i'm only really active about ps2 zig programming in the [PS2 Scene](https://discord.gg/Uz8p9bJ6za)
discord server's `#other-language-dev` channel. You can hop in there to see my insane ramblings i guess.