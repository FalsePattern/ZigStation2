const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_ee = Processor.ee.target();
    const optimize_ee = processorOptimizeOptions(b, .ee, .safe);

    const exe = b.addObject(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = target_ee,
        .optimize = optimize_ee,
        .link_libc = true,
        .single_threaded = false,
        .strip = false,
    });

    const ps2 = try Toolchain.fromEnv(b);

    const translate_c = ps2.createTranslateC(b, .ee, b.path("src/c.h"), optimize_ee);
    translate_c.addIncludeDir(ps2.extras.gsKit.include);

    exe.root_module.addImport("c", translate_c.createModule());

    _, const compiled_obj = ps2.compileCFile(b, exe.getEmittedBin(), .ee, optimize_ee);

    var compile_elf, const compiled_elf = ps2.linkObjects(b, &.{compiled_obj}, .ee, optimize_ee);
    compile_elf.addArgs(&.{ "-L", ps2.extras.gsKit.resolve(b, "lib") });
    compile_elf.addArgs(&.{ "-ldebug", "-latomic", "-lgskit", "-ldmakit" });

    const stripped_elf = ps2.stripElf(b, .ee, optimize_ee, compiled_elf);

    const install_file = b.addInstallFileWithDir(stripped_elf, .bin, "example.elf");
    b.getInstallStep().dependOn(&install_file.step);
}

fn processorOptimizeOptions(b: *std.Build, proc: Processor, default: std.Build.ReleaseMode) std.builtin.OptimizeMode {
    if (b.option(
        std.builtin.OptimizeMode,
        b.fmt("optimize_{}", .{@tagName(proc)}),
        b.fmt("Prioritize performance, safety, or binary size for the {}", .{proc.friendlyName()}),
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

    pub fn friendlyName(self: Processor) []const u8 {
        return switch(self) {
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
                const base = [_][]const u8{ "-D_EE", "-gdwarf-2", "-gz", "-Wno-incompatible-pointer-types", "-Wno-address-of-packed-member" };
                break :blk switch (optimize) {
                    .Debug => &(base ++ [0][]const u8{}),
                    .ReleaseSafe => &(base ++ [_][]const u8{ "-O2", "-G0" }),
                    .ReleaseFast => &(base ++ [_][]const u8{ "-O2", "-G0", "-s" }),
                    .ReleaseSmall => &(base ++ [_][]const u8{ "-Os", "-G0", "-s" }),
                };
            },
            .iop => blk: {
                const base = [_][]const u8{ "-D_IOP", "-fno-builtin", "-msoft-float", "-mno-explicit-relocs", "-gdwarf-2", "-gz", "-Wno-incompatible-pointer-types", "-Wno-address-of-packed-member"};
                break :blk switch (optimize) {
                    .Debug => &(base ++ [0][]const u8{}),
                    .ReleaseSafe => &(base ++ [_][]const u8{ "-O2", "-G0" }),
                    .ReleaseFast => &(base ++ [_][]const u8{ "-O2", "-G0", "-s" }),
                    .ReleaseSmall => &(base ++ [_][]const u8{ "-Os", "-G0", "-s" }),
                };
            }
        };
    }

    pub fn defaultLinkArgs(self: Processor, optimize: std.builtin.OptimizeMode) []const []const u8 {
        return switch (self) {
            .ee => blk: {
                const base = [_][]const u8{"-Wl,-zmax-page-size=128", "-lm", "-lcdvd", "-lpthread", "-lpthreadglue", "-lcglue", "-lkernel"};
                break :blk switch (optimize) {
                    .Debug => &(base ++ [_][]const u8{"-lg"}),
                    .ReleaseSafe, .ReleaseFast => &(base ++ [_][]const u8{"-O2", "-G0", "-lc"}),
                    .ReleaseSmall => &(base ++ [_][]const u8{"-Os", "-G0", "-lc"}),
                };
            },
            .iop => blk: {
                const base = [_][]const u8{"-D_IOP", "-fno-builtin", "-gdwarf-2", "-gz", "-msoft-float", "-mno-explicit-relocs", "-nostdlib"};
                break :blk switch(optimize) {
                    .Debug => &(base ++ [0][]const u8{}),
                    .ReleaseSafe, .ReleaseFast => &(base ++ [_][]const u8{"-O2", "-G0"}),
                    .ReleaseSmall => &(base ++ [_][]const u8{"-Os", "-G0"}),
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
        translate_c.addIncludeDir(dev.stdlibIncludePath(b).?);
        translate_c.addIncludeDir(dev.sdk.include);
        translate_c.addIncludeDir(self.extras.common.include);
        return translate_c;
    }

    pub fn createCompileStep(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode) *std.Build.Step.Run {
        const dev = self.dev.get(processor);
        var cmd = b.addSystemCommand(&.{
            dev.tool(b, "gcc"),
        });
        cmd.addArgs(processor.defaultCompileArgs(optimize));
        cmd.addArgs(&.{"-I", b.graph.zig_lib_directory.path.?});
        return cmd;
    }

    pub fn compileCFile(self: Toolchain, b: *std.Build, input: std.Build.LazyPath, processor: Processor, optimize: std.builtin.OptimizeMode) struct{*std.Build.Step.Run, *std.Build.LazyPath} {
        var step = self.createCompileStep(b, processor, optimize);
        step.addArg("-c");
        step.addFileArg(input);
        step.addArg("-o");
        const output = step.addOutputFileArg("output.o");
        return .{.step = step, .output = output};
    }

    pub fn createLinkStep(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode) *std.Build.Step.Run {
        const dev = self.dev.get(processor);
        var cmd = b.addSystemCommand(&.{
            dev.tool(b, "gcc"),
            "-T",
            dev.sdk.resolve(b, "startup/linkfile"),
            "-L",
            dev.sdk.resolve(b, "lib"),
        });
        cmd.addArgs(processor.defaultLinkArgs(optimize));
        return cmd;
    }

    pub fn linkObjects(self: Toolchain, b: *std.Build, inputs: []const std.Build.LazyPath, processor: Processor, optimize: std.builtin.OptimizeMode) struct{*std.Build.Step.Run, *std.Build.LazyPath} {
        var step = self.createLinkStep(b, processor, optimize);
        step.addArg("-o");
        const ext = switch (processor) {
            .ee => "elf",
            .iop => "irx",
        };
        const output = step.addOutputFileArg(b.fmt("output.{}", .{ext}));
        for (inputs) |input| {
            step.addFileInput(input);
        }
        return .{.step = step, .output = output};
    }

    pub fn stripElf(self: Toolchain, b: *std.Build, processor: Processor, optimize: std.builtin.OptimizeMode, file: std.Build.LazyPath) std.Build.LazyPath {
        const dev = self.dev.get(processor);
        return switch (optimize) {
            .Debug, .ReleaseSafe => file,
            .ReleaseSmall, .ReleaseFast => blk: {
                const strip_elf = b.addSystemCommand(&.{ dev.tool(b, "strip"), "-s" });
                strip_elf.addFileArg(file);
                strip_elf.addArg("-o");
                const stripped_elf = strip_elf.addOutputFileArg("stripped.elf");
                break :blk stripped_elf;
            },
        };
    }
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
        return b.pathJoin(&.{self.root, "bin", b.fmt("{s}-{s}", .{self.processor.toolPrefix(), tool_name},)});
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
