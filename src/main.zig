// ---------- default imports ----------
const std = @import("std");
const datetime = @import("datetime.zig");
const schedule = @import("schedule.zig");
const config = @import("config.zig");
const log = @import("log.zig");
const cli = @import("cli.zig");
const api = @import("api.zig");

// ---------- external structs loading ----------

const Login = cli.Login;

pub fn main(init: std.process.Init) !void {
    // Initiates the arena allocator
    const arena: std.mem.Allocator = init.arena.allocator();
    // Gets system io
    const io = init.io;

    // Loads student login from args and env, then checks if a password was provided.
    // If it was not, it asks the user to provide one secretly from the terminal.
    const final_student_login = cli.loadLogin(init, io, arena);

    // Parses the provided "config.json" into a Config (struct), expects it to be
    // correct JSON syntax.
    const parsed_json = config.loadConfig(io, arena);

    // Get current moment since Jan 1, 1970 in nanosseconds,
    // and then convert it to the enum weekday through weekdayFromSeconds.
    const now_posix = std.Io.Clock.real.now(io);
    const enum_weekday = datetime.weekdayFromSeconds(now_posix.toSeconds());

    const target = schedule.targetWeekday(enum_weekday, parsed_json.schedules, parsed_json.behaviour.use_monday_schedule_on_friday);
    const days_ahead = datetime.daysUntil(enum_weekday, target);
    const date = try datetime.dateString(arena, now_posix.toSeconds(), days_ahead);

    if (!schedule.hasScheduleFor(target, parsed_json.schedules)) {
        std.debug.print("[RUTINA] Nenhum agendamento foi encontrado para o dia.\n", .{});
        return;
    }

    var client: std.http.Client = .{ .io = io, .allocator = arena };
    defer client.deinit();
    const token = api.httpFetchToken(io, &client, arena, parsed_json, final_student_login) catch |err| switch (err) {
        error.NoAccessToken => {
            log.fatal("Não foi possível obter o token de acesso.", .{});
        },
        error.HttpError, error.LoginRefused => std.process.exit(1),
        else => {
            log.fatal("Algo deu errado. ({s})", .{@errorName(err)});
        },
    };

    var failed = false;
    var tried_schedule: usize = 0;
    for (parsed_json.schedules) |s| {
        if (s.weekday == target) {
            if (tried_schedule > 0) {
                try io.sleep(.fromSeconds(3), .awake);
            }

            tried_schedule += 1;
            api.doSchedule(&client, arena, s, token, date) catch |err| switch (err) {
                error.FailedSchedule => {
                    log.logError("Um ou mais agendamentos falharam.", .{});
                    failed = true;
                },
                error.HttpError, error.ScheduleRefused => failed = true,
                error.NoMealList => {
                    log.logError("RU {d}: a API não retornou a lista de refeições.", .{@backingInt(s.restaurant)});
                    failed = true;
                },
                else => {
                    log.logError("RU {d}: algo deu errado. ({s})", .{ @backingInt(s.restaurant), @errorName(err) });
                    failed = true;
                },
            };
        }
    }

    if (failed) std.process.exit(1);
}

test {
    _ = datetime;
    _ = schedule;
    _ = cli;
}
