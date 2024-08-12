const irx = @import("irx_imports");

pub export const _irx_id: irx.irx_id = .{
  .n = "hello",
  .v = irx.IRX_VER(1, 0),
};
pub extern var _exp_hello: irx.irx_export_table;

pub export fn _start(argc: c_int, argv: [*c]c_char) c_int {
  _ = argc;
  _ = argv;
  if (irx.RegisterLibraryEntries(&_exp_hello) != 0) {
    return irx.MODULE_NO_RESIDENT_END;
  }
  hello();
  return irx.MODULE_RESIDENT_END;
}

pub export fn hello() void {
  _ = irx.printf("Hello from zig IOP!\n");
}