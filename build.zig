const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = Processor.ee.target();
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addObject(.{
        .name = "example",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .single_threaded = false,
        .strip = false,
    });

    const ps2 = try Toolchain.fromEnv(b);

    const ee_tool = ps2.dev.ee.tool();

    const ctx: Ctx = .{
        .b = b,
        .ps2 = ps2,
        .artifact = exe,
        .optimize = optimize,
        .processor = .ee,
    };

    _ = ctx.addCpuImport("c", b.path("src/c.h"));

    var compile_obj = b.addSystemCommand(&.{ ee_tool.gcc, "-D_EE", "-nostdlib", "-D_SIGNAL_H_", "-gdwarf-2", "-gz", "-Wno-incompatible-pointer-types", "-Wno-address-of-packed-member" });
    compile_obj.setName("[EE] Compile example.o");
    switch (optimize) {
        .Debug => {},
        .ReleaseSafe => {
            compile_obj.addArg("-O2");
            compile_obj.addArg("-G0");
        },
        .ReleaseFast => {
            compile_obj.addArg("-O2");
            compile_obj.addArg("-G0");
            compile_obj.addArg("-s");
        },
        .ReleaseSmall => {
            compile_obj.addArg("-Os");
            compile_obj.addArg("-G0");
            compile_obj.addArg("-s");
        },
    }
    compile_obj.addArgs(&.{ "-I", b.graph.zig_lib_directory.path.? });
    compile_obj.addArg("-c");
    compile_obj.addFileArg(exe.getEmittedBin());
    compile_obj.addArg("-o");
    const compiled_obj = compile_obj.addOutputFileArg("example.o");

    var compile_elf = b.addSystemCommand(&.{ ee_tool.gcc, "-flto" });
    compile_elf.setName("[EE] Link example.elf");
    switch (optimize) {
        .Debug => {},
        .ReleaseSafe, .ReleaseFast => {
            compile_elf.addArg("-O2");
            compile_elf.addArg("-G0");
        },
        .ReleaseSmall => {
            compile_elf.addArg("-Os");
            compile_elf.addArg("-G0");
        },
    }
    compile_elf.addArgs(&.{ "-T", ps2.sdk.ee.resolve("startup/linkfile") });
    compile_elf.addArg("-o");
    const compiled_elf = compile_elf.addOutputFileArg("example.elf");
    compile_elf.addFileArg(compiled_obj);
    compile_elf.addArgs(&.{ "-L", ps2.sdk.ee.resolve("lib") });
    compile_elf.addArgs(&.{ "-L", ps2.sdk.gsKit.resolve("lib") });
    compile_elf.addArgs(&.{ "-Wl,-zmax-page-size=128", "-ldebug", "-lc", "-lpthread", "-latomic", "-lgskit", "-ldmakit" });

    _, const final_file: std.Build.LazyPath = switch (optimize) {
        .Debug, .ReleaseSafe => .{ &compile_elf.step, compiled_elf },
        .ReleaseSmall, .ReleaseFast => blk: {
            const strip_elf = b.addSystemCommand(&.{ ee_tool.strip, "-s" });
            strip_elf.setName("[EE] Strip example.elf");
            strip_elf.addFileArg(compiled_elf);
            strip_elf.addArg("-o");
            const stripped_elf = strip_elf.addOutputFileArg("example.elf");
            break :blk .{ &strip_elf.step, stripped_elf };
        },
    };

    const install_file = b.addInstallFileWithDir(final_file, .bin, "example.elf");
    b.getInstallStep().dependOn(&install_file.step);
}

const Ctx = struct {
    b: *std.Build,
    ps2: Toolchain,
    artifact: *std.Build.Step.Compile,
    optimize: std.builtin.OptimizeMode,
    processor: Processor,

    fn addCpuImportSysHeader(
        self: Ctx,
        name: []const u8,
    ) *std.Build.Step.TranslateC {
        const fname = self.b.fmt("{s}.h", .{name});
        const import_name = self.b.fmt("<{s}>", .{fname});
        const wf = self.b.addWriteFiles();
        const the_file = wf.add(fname, self.b.fmt("#import {s}", .{import_name}));
        return self.addCpuImport(
            import_name,
            the_file,
        );
    }

    fn addCpuImport(
        self: Ctx,
        name: []const u8,
        root_source_file: std.Build.LazyPath,
    ) *std.Build.Step.TranslateC {
        const translate_c = self.b.addTranslateC(.{
            .root_source_file = root_source_file,
            .optimize = self.optimize,
            .target = self.processor.target(),
        });
        translate_c.defineCMacro(self.processor.macro(), null);
        translate_c.addIncludeDir(self.ps2.dev.get(self.processor).tool().include.?);
        translate_c.addIncludeDir(self.ps2.sdk.get(self.processor).include);
        translate_c.addIncludeDir(self.ps2.sdk.common.include);
        translate_c.addIncludeDir(self.ps2.sdk.gsKit.include);

        self.artifact.root_module.addImport(name, translate_c.createModule());
        return translate_c;
    }
};

const Processor = enum {
    ee,
    iop,

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
            .iop => @panic("IOP target not yet implemented!"),
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
    dev: struct {
        ee: DevDir,
        iop: DevDir,

        const Self = @This();

        pub fn get(self: Self, p: Processor) DevDir {
            return switch (p) {
                .ee => self.ee,
                .iop => self.iop,
            };
        }
    },
    sdk: struct {
        ee: SdkDir,
        iop: SdkDir,
        common: SdkDir,
        gsKit: SdkDir,

        const Self = @This();
        pub fn get(self: Self, p: Processor) SdkDir {
            return switch (p) {
                .ee => self.ee,
                .iop => self.iop,
            };
        }
    },

    pub fn fromEnv(b: *std.Build) !Toolchain {
        const dev_root = std.posix.getenv("PS2DEV") orelse {
            std.log.err("PS2DEV environment variable missing!", .{});
            return error.EnvMissing;
        };
        const sdk_root = std.posix.getenv("PS2SDK") orelse {
            std.log.err("PS2SDK environment variable missing!", .{});
            return error.EnvMissing;
        };
        return .{
            .dev = .{
                .ee = DevDir.from(b, dev_root, .ee),
                .iop = DevDir.from(b, dev_root, .iop),
            },
            .sdk = .{
                .ee = SdkDir.from(b, sdk_root, Processor.ee.suffix()),
                .iop = SdkDir.from(b, sdk_root, Processor.iop.suffix()),
                .common = SdkDir.from(b, sdk_root, "common"),
                .gsKit = SdkDir.from(b, dev_root, "gsKit"),
            },
        };
    }
};

const Tool = struct {
    b: *std.Build,
    gcc: []const u8,
    strip: []const u8,
    include: ?[]const u8,
};

const DevDir = struct {
    b: *std.Build,
    root: []const u8,
    tool_prefix: []const u8,

    pub fn from(b: *std.Build, base: []const u8, p: Processor) DevDir {
        return .{
            .b = b,
            .root = b.fmt("{s}/{s}", .{ base, p.suffix() }),
            .tool_prefix = p.toolPrefix(),
        };
    }

    pub fn tool(self: DevDir) Tool {
        const include_path = self.resolve(self.b.fmt("{s}/{s}", .{ self.tool_prefix, "include" }));

        const exists: bool = if (std.fs.openDirAbsolute(include_path, .{})) |dir| blk: {
            var d = dir;
            d.close();
            break :blk true;
        } else |_| false;
        return .{
            .b = self.b,
            .gcc = self.b.fmt("{s}/bin/{s}-gcc", .{ self.root, self.tool_prefix }),
            .strip = self.b.fmt("{s}/bin/{s}-strip", .{ self.root, self.tool_prefix }),
            .include = if (exists) include_path else null,
        };
    }

    pub fn resolve(self: DevDir, rel_path: []const u8) []u8 {
        return self.b.fmt("{s}/{s}", .{ self.root, rel_path });
    }

    pub fn resolveSubTool(self: DevDir, rel_path: []const u8) []u8 {
        return self.b.fmt("{s}/{s}/{s}", .{ self.root, self.tool_prefix, rel_path });
    }
};

const SdkDir = struct {
    b: *std.Build,
    root: []const u8,
    include: []const u8,

    pub fn from(b: *std.Build, base: []const u8, suffix: []const u8) SdkDir {
        const root = b.fmt("{s}/{s}", .{ base, suffix });
        return .{
            .b = b,
            .root = root,
            .include = b.fmt("{s}/include", .{root}),
        };
    }

    pub fn resolve(self: SdkDir, rel_path: []const u8) []u8 {
        return self.b.fmt("{s}/{s}", .{ self.root, rel_path });
    }
};
