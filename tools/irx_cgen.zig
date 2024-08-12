const std = @import("std");
pub fn main() !void {
    {
        var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const args = try std.process.argsAlloc(arena);
        if (args.len < 4) fatal("wrong number of arguments", .{});

        const mode = args[1];
        const input = args[2];
        const output = args[3];

        const is_imports = std.mem.eql(u8, mode, "imports");
        const is_exports = std.mem.eql(u8, mode, "exports");

        if (!is_imports and !is_exports) {
            fatal("unknown mode {s}", .{mode});
        }

        var input_file = std.fs.cwd().openFile(input, .{}) catch |err| {
            fatal("unable to open '{s}': {s}", .{input, @errorName(err)});
        };
        defer input_file.close();
        var br = std.io.bufferedReader(input_file.reader());
        const reader = br.reader();

        var output_file = std.fs.cwd().createFile(output, .{}) catch |err| {
            fatal("unable to create '{s}': {s}", .{output, @errorName(err)});
        };
        defer output_file.close();
        var bw = std.io.bufferedWriter(output_file.writer());
        const writer = bw.writer();

        if (is_imports) {
            if (args.len < 5) {
                fatal("wrong number of arguments for imports", .{});
            }
            try writer.writeAll("#include \"");
            try writer.writeAll(args[4]);
            try writer.writeAll("\"\n");
        } else if (is_exports) {
            try writer.writeAll("#include <irx.h>\n");
        } else unreachable;

        const Fifo = std.fifo.LinearFifo(u8, .{ .Static = 4096 });
        var fifo: Fifo = Fifo.init();
        defer fifo.deinit();
        try fifo.pump(reader, writer);
        try bw.flush();
    }

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}