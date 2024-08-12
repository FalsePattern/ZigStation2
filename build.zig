const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_ee = Processor.ee.target();
    const target_iop = Processor.iop.target();
    const optimize_ee = processorOptimizeOptions(b, .ee, .safe);
    const optimize_iop = processorOptimizeOptions(b, .iop, .fast);

    const ps2 = try Toolchain.fromEnv(b);

    const pipeline_iop = ps2.buildIOPBinary(
        b,
        Toolchain.IOPParams.fromDir(b, b.path("src/iop")),
        .{
            .name = "hello",
            .root_source_file = b.path("src/iop/hello.zig"),
            .target = target_iop,
            .optimize = optimize_iop,
            .link_libc = true,
        },
    );

    var pipeline_ee = ps2.buildEEBinary(b, .{
        .name = "example",
        .root_source_file = b.path("src/ee/main.zig"),
        .target = target_ee,
        .optimize = optimize_ee,
        .link_libc = true,
    });

    const translate_c_ee = ps2.createTranslateC(b, .ee, b.path("src/ee/c.h"), optimize_ee);
    translate_c_ee.addIncludeDir(ps2.extras.gsKit.include);

    pipeline_ee.rootModule().addImport("c_ee", translate_c_ee.createModule());

    pipeline_ee.addLibDir(ps2.extras.gsKit.resolve(b, "lib"));
    pipeline_ee.link(&.{ "debug", "atomic", "gskit", "dmakit" });

    const stripped_elf = ps2.stripElf(b, .ee, optimize_ee, pipeline_ee.output_file);

    const install = b.getInstallStep();
    install.dependOn(&b.addInstallFileWithDir(stripped_elf, .bin, "example.elf").step);
    install.dependOn(&b.addInstallFileWithDir(pipeline_iop.output_file, .bin, "hello.irx").step);
}

fn processorOptimizeOptions(b: *std.Build, proc: Processor, default: std.Build.ReleaseMode) std.builtin.OptimizeMode {
    if (b.option(
        std.builtin.OptimizeMode,
        b.fmt("optimize_{s}", .{@tagName(proc)}),
        b.fmt("Prioritize performance, safety, or binary size for the {s}", .{proc.friendlyName()}),
    )) |mode| {
        return mode;
    }

    return switch (default) {
        .fast => .ReleaseFast,
        .safe => .ReleaseSafe,
        .small => .ReleaseSmall,
        else => .Debug,
    };
}

const Processor = enum {
    ee,
    iop,

    pub fn ext(self: Processor) []const u8 {
        return switch (self) {
            .ee => "elf",
            .iop => "irx",
        };
    }

    pub fn friendlyName(self: Processor) []const u8 {
        return switch (self) {
            .ee => "Emotion Engine",
            .iop => "I/O processor",
        };
    }

    pub fn macro(self: Processor) []const u8 {
        return switch (self) {
            .ee => "_EE",
            .iop => "_IOP",
        };
    }

    pub fn toolPrefix(self: Processor) []const u8 {
        return switch (self) {
            .ee => "mips64r5900el-ps2-elf",
            .iop => "mipsel-ps2-irx",
        };
    }

    pub fn suffix(self: Processor) []const u8 {
        return @tagName(self);
    }

    pub fn target(self: Processor) std.Build.ResolvedTarget {
        return switch (self) {
            .ee => ee_target.get(),
            .iop => iop_target.get(),
        };
    }

    pub fn defaultCompileArgs(self: Processor, optimize: std.builtin.OptimizeMode) []const []const u8 {
        return switch (self) {
            .ee => blk: {
                const base = [_][]const u8{ "-D_EE", "-fno-builtin", "-gdwarf-2", "-gz", "-Wno-incompatible-pointer-types", "-Wno-address-of-packed-member" };
                break :blk switch (optimize) {
                    .Debug => &(base ++ [0][]const u8{}),
                    .ReleaseSafe => &(base ++ [_][]const u8{ "-O2", "-G0" }),
                    .ReleaseFast => &(base ++ [_][]const u8{ "-O2", "-G0", "-s" }),
                    .ReleaseSmall => &(base ++ [_][]const u8{ "-Os", "-G0", "-s" }),
                };
            },
            .iop => blk: {
                const base = [_][]const u8{ "-D_IOP", "-fno-builtin", "-msoft-float", "-mno-explicit-relocs", "-gdwarf-2", "-gz", "-Wno-incompatible-pointer-types", "-Wno-address-of-packed-member" };
                break :blk switch (optimize) {
                    .Debug => &(base ++ [0][]const u8{}),
                    .ReleaseSafe => &(base ++ [_][]const u8{ "-O2", "-G0" }),
                    .ReleaseFast => &(base ++ [_][]const u8{ "-O2", "-G0", "-s" }),
                    .ReleaseSmall => &(base ++ [_][]const u8{ "-Os", "-G0", "-s" }),
                };
            },
        };
    }

    pub fn defaultLinkArgs(self: Processor, optimize: std.builtin.OptimizeMode) []const []const u8 {
        return switch (self) {
            .ee => blk: {
                const base = [_][]const u8{ "-Wl,-zmax-page-size=128", "-lm", "-lcdvd", "-lpthread", "-lpthreadglue", "-lcglue", "-lkernel" };
                break :blk switch (optimize) {
                    .Debug => &(base ++ [_][]const u8{"-lg"}),
                    .ReleaseSafe, .ReleaseFast => &(base ++ [_][]const u8{ "-O2", "-G0", "-lc" }),
                    .ReleaseSmall => &(base ++ [_][]const u8{ "-Os", "-G0", "-lc" }),
                };
            },
            .iop => blk: {
                const base = [_][]const u8{ "-D_IOP", "-fno-builtin", "-gdwarf-2", "-gz", "-msoft-float", "-mno-explicit-relocs", "-nostdlib", "-s" };
                break :blk switch (optimize) {
                    .Debug => &(base ++ [0][]const u8{}),
                    .ReleaseSafe, .ReleaseFast => &(base ++ [_][]const u8{ "-O2", "-G0" }),
                    .ReleaseSmall => &(base ++ [_][]const u8{ "-Os", "-G0" }),
                };
            },
        };
    }

    fn knownTarget(query: std.Target.Query) std.Build.ResolvedTarget {
        return .{
            .query = query,
            .result = std.zig.system.resolveTargetQuery(query) catch
                @panic("unable to resolve target query"),
        };
    }

    var ee_target = LazyTarget.of(init: {
        var tgt: std.Target.Query = .{};
        tgt.cpu_arch = .mipsel;
        tgt.os_tag = .freestanding;
        tgt.ofmt = .c;
        tgt.cpu_model = .{ .explicit = &std.Target.mips.cpu.mips2 };
        tgt.cpu_features_add.addFeature(@intFromEnum(std.Target.mips.Feature.mips2));
        break :init tgt;
    });

    var iop_target = LazyTarget.of(init: {
        var tgt: std.Target.Query = .{};
        tgt.cpu_arch = .mipsel;
        tgt.os_tag = .freestanding;
        tgt.ofmt = .c;
        tgt.cpu_model = .{ .explicit = &std.Target.mips.cpu.mips2 };
        tgt.cpu_features_add.addFeature(@intFromEnum(std.Target.mips.Feature.mips2));
        break :init tgt;
    });

    const LazyTarget = struct {
        q: std.Target.Query,
        value: ?std.Build.ResolvedTarget = null,

        const Self = @This();

        pub fn get(self: *Self) std.Build.ResolvedTarget {
            if (self.value) |v| {
                return v;
            } else {
                const v = knownTarget(self.q);
                self.value = v;
                return v;
            }
        }

        pub fn of(q: std.Target.Query) LazyTarget {
            return .{ .q = q };
        }
    };
};

const Toolchain = struct {
    const DevSet = struct {
        ee: Dev,
        iop: Dev,

        const Self = @This();

        pub fn get(self: Self, p: Processor) Dev {
            return switch (p) {
                .ee => self.ee,
                .iop => self.iop,
            };
        }
    };

    const ExtraSdks = struct {
        common: Sdk,
        gsKit: Sdk,
    };

    extras: ExtraSdks,
    dev: DevSet,

    pub fn fromEnv(b: *std.Build) !Toolchain {
        const dev_root = std.posix.getenv("PS2DEV") orelse {
            std.log.err("PS2DEV environment variable missing!", .{});
            return error.EnvMissing;
        };
        const sdk_root = std.posix.getenv("PS2SDK") orelse {
            std.log.err("PS2SDK environment variable missing!", .{});
            return error.EnvMissing;
        };
        const sdk_ee = Sdk.from(b, sdk_root, Processor.ee.suffix());
        const sdk_iop = Sdk.from(b, sdk_root, Processor.iop.suffix());
        const extras = ExtraSdks{
            .common = Sdk.from(b, sdk_root, "common"),
            .gsKit = Sdk.from(b, dev_root, "gsKit"),
        };
        const dev = DevSet{
            .ee = Dev.from(b, dev_root, .ee, sdk_ee),
            .iop = Dev.from(b, dev_root, .iop, sdk_iop),
        };
        return .{
            .extras = extras,
            .dev = dev,
        };
    }

    pub fn createTranslateC(self: Toolchain, b: *std.Build, processor: Processor, root_source_file: std.Build.LazyPath, optimize: std.builtin.OptimizeMode) *std.Build.Step.TranslateC {
        const dev = self.dev.get(processor);
        const translate_c = b.addTranslateC(.{
            .root_source_file = root_source_file,
            .optimize = optimize,
            .target = processor.target(),
        });
        translate_c.defineCMacro(processor.macro(), null);
        if (dev.stdlibIncludePath(b)) |include| {
            translate_c.addIncludeDir(include);
        }
        translate_c.addIncludeDir(dev.sdk.include);
        translate_c.addIncludeDir(self.extras.common.include);
        return translate_c;
    }
    pub fn createPureCCompileStep(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode) *std.Build.Step.Run {
        const dev = self.dev.get(processor);
        var cmd = b.addSystemCommand(&.{
            dev.tool(b, "gcc"),
        });
        cmd.addArgs(processor.defaultCompileArgs(optimize));
        cmd.addArgs(&.{ "-I", b.graph.zig_lib_directory.path.? });
        cmd.addArgs(&.{ "-I", dev.sdk.include });
        cmd.addArgs(&.{ "-I", self.extras.common.include });
        return cmd;
    }

    pub fn compilePureCFile(self: Toolchain, b: *std.Build, input: std.Build.LazyPath, processor: Processor, optimize: std.builtin.OptimizeMode) struct { *std.Build.Step.Run, std.Build.LazyPath } {
        var step = self.createPureCCompileStep(b, processor, optimize);
        step.addArg("-c");
        step.addFileArg(input);
        step.addArg("-o");
        const output = step.addOutputFileArg("output.o");
        return .{ step, output };
    }


    pub fn createTranslatedCompileStep(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode) *std.Build.Step.Run {
        const dev = self.dev.get(processor);
        var cmd = b.addSystemCommand(&.{
            dev.tool(b, "gcc"),
        });
        cmd.addArgs(processor.defaultCompileArgs(optimize));
        cmd.addArgs(&.{ "-I", b.graph.zig_lib_directory.path.? });
        if (processor == .iop) {
            var d = b.addWriteFile("signal.h", "\n");
            cmd.addArg("-I");
            cmd.addDirectoryArg(d.getDirectory());
        }
        return cmd;
    }

    pub fn compileTranslatedCFile(self: Toolchain, b: *std.Build, input: std.Build.LazyPath, processor: Processor, optimize: std.builtin.OptimizeMode) struct { *std.Build.Step.Run, std.Build.LazyPath } {
        var step = self.createTranslatedCompileStep(b, processor, optimize);
        step.addArg("-c");
        step.addFileArg(input);
        step.addArg("-o");
        const output = step.addOutputFileArg("output.o");
        return .{ step, output };
    }

    pub fn createLinkStep(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode) *std.Build.Step.Run {
        const dev = self.dev.get(processor);
        var cmd = switch (processor) {
            .ee => b.addSystemCommand(&.{
                dev.tool(b, "gcc"),
                "-T",
                dev.sdk.resolve(b, "startup/linkfile"),
                "-L",
                dev.sdk.resolve(b, "lib"),
            }),
            .iop => b.addSystemCommand(&.{dev.tool(b, "gcc")}),
        };
        cmd.addArgs(processor.defaultLinkArgs(optimize));
        return cmd;
    }

    pub fn linkObjects(self: Toolchain, b: *std.Build, inputs: []const std.Build.LazyPath, processor: Processor, optimize: std.builtin.OptimizeMode) struct { *std.Build.Step.Run, std.Build.LazyPath } {
        var step = self.createLinkStep(b, processor, optimize);
        step.addArg("-o");
        const output = step.addOutputFileArg(b.fmt("output.{s}", .{processor.ext()}));
        for (inputs) |input| {
            step.addFileArg(input);
        }
        return .{ step, output };
    }

    pub fn stripElf(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode, file: std.Build.LazyPath) std.Build.LazyPath {
        const dev = self.dev.get(processor);
        return switch (optimize) {
            .Debug, .ReleaseSafe => file,
            .ReleaseSmall, .ReleaseFast => blk: {
                const strip_elf = b.addSystemCommand(&.{ dev.tool(b, "strip"), "-s" });
                strip_elf.addFileArg(file);
                strip_elf.addArg("-o");
                const stripped_elf = strip_elf.addOutputFileArg(b.fmt("stripped.{s}", .{processor.ext()}));
                break :blk stripped_elf;
            },
        };
    }

    pub const IOPParams = struct {
        imports: std.Build.LazyPath,
        exports: std.Build.LazyPath,
        imports_header: std.Build.LazyPath,

        pub fn fromDir(b: *std.Build, dir: std.Build.LazyPath) IOPParams {
            const imports = dir.path(b, "imports.lst");
            const exports = dir.path(b, "exports.tab");
            const imports_header = dir.path(b, "irx_imports.h");
            return .{
                .imports = imports,
                .exports = exports,
                .imports_header = imports_header,
            };
        }
    };

    pub fn buildIOPBinary(self: Toolchain, b: *std.Build, params: IOPParams, options: std.Build.ObjectOptions) BuildPipelineIOP {
        const irx_imports = self.createTranslateC(b, .iop, params.imports_header, options.optimize);

        const zig_to_c = b.addObject(options);

        zig_to_c.root_module.addImport("irx_imports", irx_imports.createModule());

        const object_step, const compiled_obj = self.compileTranslatedCFile(b, zig_to_c.getEmittedBin(), .iop, options.optimize);

        //intermediate
        const irx_cgen = b.addExecutable(.{
            .name = "irx_cgen",
            .root_source_file = b.path("tools/irx_cgen.zig"),
            .target = b.graph.host,
        });

        const imports_gen = b.addRunArtifact(irx_cgen);
        imports_gen.addArg("imports");
        imports_gen.addFileArg(params.imports);
        const build_imports = imports_gen.addOutputFileArg("build-imports.c");
        imports_gen.addFileArg(params.imports_header);

        const exports_gen = b.addRunArtifact(irx_cgen);
        exports_gen.addArg("exports");
        exports_gen.addFileArg(params.exports);
        const build_exports = exports_gen.addOutputFileArg("build-exports.c");

        const imports_step, const imports_obj = self.compilePureCFile(b, build_imports, .iop, options.optimize);
        const exports_step, const exports_obj = self.compilePureCFile(b, build_exports, .iop, options.optimize);

        imports_step.addArg("-fno-toplevel-reorder");
        exports_step.addArg("-fno-toplevel-reorder");

        const link_step, const linked_obj = self.linkObjects(b, &.{ compiled_obj, imports_obj, exports_obj }, .iop, options.optimize);

        return .{
            .zig_to_c_step = zig_to_c,
            .object_step = object_step,
            .link_step = link_step,
            .output_file = linked_obj,
        };
    }
    pub const BuildPipelineIOP = struct {
        zig_to_c_step: *std.Build.Step.Compile,
        object_step: *std.Build.Step.Run,
        link_step: *std.Build.Step.Run,
        output_file: std.Build.LazyPath,

        pub fn rootModule(self: BuildPipelineIOP) *std.Build.Module {
            return &self.zig_to_c_step.root_module;
        }

        pub fn addLibDir(self: BuildPipelineIOP, dir: []const u8) void {
            self.link_step.addArgs(&.{ "-L", dir });
        }

        pub fn link(self: BuildPipelineIOP, libraries: []const []const u8) void {
            for (libraries) |library| {
                self.link_step.addArgs(&.{ "-l", library });
            }
        }
    };

    pub fn buildEEBinary(self: Toolchain, b: *std.Build, options: std.Build.ObjectOptions) BuildPipelineEE {
        const zig_to_c = b.addObject(options);

        const object_step, const compiled_obj = self.compileTranslatedCFile(b, zig_to_c.getEmittedBin(), .ee, options.optimize);

        const link_step, const linked_obj = self.linkObjects(b, &.{compiled_obj}, .ee, options.optimize);

        return .{ .zig_to_c_step = zig_to_c, .object_step = object_step, .link_step = link_step, .output_file = linked_obj };
    }

    pub const BuildPipelineEE = struct {
        zig_to_c_step: *std.Build.Step.Compile,
        object_step: *std.Build.Step.Run,
        link_step: *std.Build.Step.Run,
        output_file: std.Build.LazyPath,

        pub fn rootModule(self: BuildPipelineEE) *std.Build.Module {
            return &self.zig_to_c_step.root_module;
        }

        pub fn addLibDir(self: BuildPipelineEE, dir: []const u8) void {
            self.link_step.addArgs(&.{ "-L", dir });
        }

        pub fn link(self: BuildPipelineEE, libraries: []const []const u8) void {
            for (libraries) |library| {
                self.link_step.addArgs(&.{ "-l", library });
            }
        }
    };
};

const Dev = struct {
    processor: Processor,
    sdk: Sdk,
    root: []const u8,

    pub fn from(b: *std.Build, base: []const u8, p: Processor, sdk: Sdk) Dev {
        return .{
            .processor = p,
            .sdk = sdk,
            .root = b.fmt("{s}/{s}", .{ base, p.suffix() }),
        };
    }

    pub fn tool(self: Dev, b: *std.Build, tool_name: []const u8) []u8 {
        return b.pathJoin(&.{ self.root, "bin", b.fmt(
            "{s}-{s}",
            .{ self.processor.toolPrefix(), tool_name },
        ) });
    }

    pub fn stdlibIncludePath(self: Dev, b: *std.Build) ?[]const u8 {
        const include_path = self.resolve(b, b.fmt("{s}/{s}", .{ self.processor.toolPrefix(), "include" }));
        if (std.fs.openDirAbsolute(include_path, .{})) |dir| {
            var d = dir;
            d.close();
            return include_path;
        } else |_| {
            return null;
        }
    }

    pub fn resolve(self: Dev, b: *std.Build, rel_path: []const u8) []u8 {
        return b.fmt("{s}/{s}", .{ self.root, rel_path });
    }
};

const Sdk = struct {
    root: []const u8,
    include: []const u8,

    pub fn from(b: *std.Build, base: []const u8, suffix: []const u8) Sdk {
        const root = b.fmt("{s}/{s}", .{ base, suffix });
        return .{
            .root = root,
            .include = b.fmt("{s}/include", .{root}),
        };
    }

    pub fn resolve(self: Sdk, b: *std.Build, rel_path: []const u8) []u8 {
        return b.fmt("{s}/{s}", .{ self.root, rel_path });
    }
};
