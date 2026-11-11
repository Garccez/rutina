const std = @import("std");

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("[ERRO] " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn logError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[ERRO] " ++ fmt ++ "\n", args);
}
