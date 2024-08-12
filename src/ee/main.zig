const std = @import("std");
const c = @import("c_ee");
pub fn _main(argc: c_int, argv: [*c][*c]u8) callconv(.C) c_int {
    _ = argc;
    _ = argv;
    return main() catch |err| {
        @panic(@errorName(err));
    };
}

comptime {
    @export(_main, .{
        .name = "main",
    });
}

var done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn thread_main(_: ?*anyopaque) u32 {
    screen_writer.print("Thread 2!\n", .{}) catch {};
    _ = c.sleep(2);
    done.store(true, .release);
    return 1;
}

fn gskitDemo() void {
    const Black = c.GS_SETREG_RGBAQ(0x00, 0x00, 0x00, 0x00, 0x00);

    const gsGlobal: *c.gsGlobal = @ptrCast(c.gsKit_init_global_custom(c.GS_RENDER_QUEUE_OS_POOLSIZE, c.GS_RENDER_QUEUE_PER_POOLSIZE));
    defer c.gsKit_deinit_global(gsGlobal);

    gsGlobal.PSM = c.GS_PSM_CT24;
    gsGlobal.PSMZ = c.GS_PSMZ_16S;

    gsGlobal.Mode = c.gsKit_check_rom();
    if (gsGlobal.Mode == c.GS_MODE_PAL) {
        gsGlobal.Height = 512;
    } else {
        gsGlobal.Height = 448;
    }

    c.gsKit_init_screen(gsGlobal);

    c.gsKit_mode_switch(gsGlobal, c.GS_PERSISTENT);

    const quad = [_:.{}]c.gsPrimPoint{
        .{
            .rgbaq = c.color_to_RGBAQ(0xFF, 0x00, 0x00, 0xFF, 0),
            .xyz2 = c.vertex_to_XYZ2(gsGlobal, 200, 200, 0),
        },
        .{
            .rgbaq = c.color_to_RGBAQ(0x00, 0xFF, 0x00, 0xFF, 0),
            .xyz2 = c.vertex_to_XYZ2(gsGlobal, 300, 200, 0),
        },
        .{
            .rgbaq = c.color_to_RGBAQ(0x00, 0x00, 0xFF, 0xFF, 0),
            .xyz2 = c.vertex_to_XYZ2(gsGlobal, 300, 100, 0),
        },
        .{
            .rgbaq = c.color_to_RGBAQ(0x00, 0x00, 0xFF, 0xFF, 0),
            .xyz2 = c.vertex_to_XYZ2(gsGlobal, 300, 100, 0),
        },
        .{
            .rgbaq = c.color_to_RGBAQ(0xFF, 0xFF, 0x00, 0xFF, 0),
            .xyz2 = c.vertex_to_XYZ2(gsGlobal, 200, 100, 0),
        },
        .{
            .rgbaq = c.color_to_RGBAQ(0xFF, 0x00, 0x00, 0xFF, 0),
            .xyz2 = c.vertex_to_XYZ2(gsGlobal, 200, 200, 0),
        },
    };
    c.gsKit_clear(gsGlobal, Black);
    c.gsKit_prim_list_triangle_gouraud_3d(gsGlobal, quad.len, &quad);

    var start: c.time_t = undefined;
    var now: c.time_t = undefined;
    _ = c.time(&start);
    now = start;
    while (c.difftime(c.time(&now), start) < 5) {
        c.gsKit_queue_exec(gsGlobal);
        c.gsKit_sync_flip(gsGlobal);
    }
}

fn main() !i32 {
    // gskitDemo();
    c.init_scr();
    c.scr_clear();
    c.scr_setCursor(0);
    var ret: c_int = undefined;
    ret = c.SifLoadModule("host:hello.irx", 0, null);
    if (ret < 0) {
        try screen_writer.print("Failed to load host:hello.irx ({})\n", .{ret});
        _ = c.SleepThread();
    }
    _ = c.printf("Hello from zig EE!\n");
    try screen_writer.print("Hello from zig EE! (on your screen!)\n", .{});
    _ = c.SleepThread();
    return 0;
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    c.init_scr();
    c.scr_clear();
    c.scr_setCursor(0);
    c.scr_setXY(0, 0);
    c.scr_setfontcolor(0x000000);
    c.scr_setbgcolor(0x0000FF);
    c.scr_printf("PANIC");
    c.scr_setfontcolor(0xFFFFFF);
    c.scr_setbgcolor(0x000000);
    c.scr_printf("\n");
    var buf: [1:0]u8 = undefined;
    buf[1] = 0;
    for (msg) |char| {
        buf[0] = char;
        c.scr_printf(&buf);
    }
    _ = c.SleepThread();
    unreachable;
}
const ScreenCtx = struct {
    pub fn write(_: *ScreenCtx, bytes: []const u8) ScreenError!usize {
        const buf_size = 16;
        var print_buf: [buf_size:0]u8 = undefined;
        @memset(&print_buf, 0);
        var i: usize = 0;
        while (i < bytes.len) : (i += buf_size) {
            const count = @min(buf_size, bytes.len - i);
            @memcpy(print_buf[0..count], bytes[i..][0..count]);
            print_buf[count] = 0;
            c.scr_printf(print_buf[0..count :0]);
        }
        return bytes.len;
    }
};

const ScreenError = error{
    Overflow,
};

var global_screen = ScreenCtx{};

var screen_writer = std.io.Writer(*ScreenCtx, ScreenError, ScreenCtx.write){ .context = &global_screen };
