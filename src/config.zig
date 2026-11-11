const std = @import("std");
const schedule = @import("schedule.zig");
const log = @import("log.zig");

const Schedule = schedule.Schedule;

pub const Config = struct {
    environment: Environment,
    behaviour: Behaviour,
    schedules: []const Schedule,
};

const Environment = struct {
    app: []const u8,
    device_info: []const u8,
    message_token: []const u8,
};

const Behaviour = struct {
    use_monday_schedule_on_friday: bool,
};

fn parseJson(input: []const u8, allocator: std.mem.Allocator) !Config {
    const parsed_cfg = try std.json.parseFromSlice(Config, allocator, input, .{});
    return parsed_cfg.value;
}

pub fn loadConfig(io: std.Io, arena: std.mem.Allocator) Config {
    // Tries to read "config.json" from the folder the executable is being run inside.
    // Otherwise throws an error.
    const input = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, "config.json", arena, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => log.fatal("Arquivo 'config.json' não existe.", .{}),
        else => log.fatal("Algo deu errado. ({s})", .{@errorName(err)}),
    };
    // Parses the provided "config.json" into a Config (struct), expects it to be
    // correct JSON syntax.
    const parsed_json = parseJson(input, arena) catch |err| {
        log.fatal("O \"config.json\" não é válido. ({s})", .{@errorName(err)});
    };
    return parsed_json;
}
