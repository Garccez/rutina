const std = @import("std");
const log = @import("log.zig");

const linux = std.os.linux;

pub const Login = struct {
    student_id: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

fn parseStudentFromArgs(args: []const [:0]const u8) !Login {
    var student_login = Login{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--username")) {
            if (i + 2 > args.len) {
                return error.MissingUsernameValue;
            }
            student_login.student_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--password")) {
            if (i + 2 > args.len) {
                return error.MissingPasswordValue;
            }
            student_login.password = args[i + 1];
            i += 1;
        } else {
            return error.UnknownArgument;
        }
    }
    return student_login;
}

fn parseEnvWithArgs(args: Login, student_id: ?[]const u8, password: ?[]const u8) !Login {
    if (args.student_id == null and student_id == null) {
        return error.MissingUsername;
    }
    const final_login = Login{ .student_id = args.student_id orelse student_id, .password = args.password orelse password };
    return final_login;
}

fn setEcho(enabled: bool) !void {
    var term: linux.termios = undefined;
    if (linux.errno(linux.ioctl(0, linux.T.CGETS, @intFromPtr(&term))) != .SUCCESS) return error.NotATerminal;

    term.lflag.ECHO = enabled;

    if (linux.errno(linux.ioctl(0, linux.T.CSETS, @intFromPtr(&term))) != .SUCCESS) return error.TerminalFailed;
}

fn promptPassword(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;

    var hidden = true;
    setEcho(false) catch {
        hidden = false;
    };
    defer {
        if (hidden) setEcho(true) catch {};
    }

    std.debug.print("[RUTINA] Senha UFSM: ", .{});
    const line = try stdin.takeDelimiterExclusive('\n');
    if (hidden) std.debug.print("\n", .{});

    return try allocator.dupe(u8, line);
}

pub fn loadLogin(init: std.process.Init, io: std.Io, arena: std.mem.Allocator) Login {
    // Tries to load the commandline arguments into the args slice, otherwise returns a fatal error.
    const args = init.minimal.args.toSlice(arena) catch |err| switch (err) {
        error.OutOfMemory => log.fatal("O aplicativo ficou sem memória para concluir esta operação.", .{}),
        error.Unexpected => log.fatal("Algo inesperado ocorreu.", .{}),
    };

    // Then tries to parse the student login information from the arguments with parseStudentFromArgs.
    const student_login = parseStudentFromArgs(args) catch |err| switch (err) {
        error.MissingUsernameValue => log.fatal("É necessário fornecer um valor para matrícula.", .{}),
        error.MissingPasswordValue => log.fatal("É necessário fornecer um valor para senha.", .{}),
        error.UnknownArgument => log.fatal("Argumento ou opção desconhecida.\nUtilize -u/--username e -p/--password para fornecer matrícula e senha.", .{}),
    };
    // Loads login information environment variables
    const student_id_env = init.environ_map.get("RUTINA_USERNAME");
    const password_env = init.environ_map.get("RUTINA_PASSWORD");

    // Then tries to parse those same variables into the final Login (struct), if both the arguments'
    // and environment's username is null, returns an error.
    var final_login: Login = parseEnvWithArgs(student_login, student_id_env, password_env) catch |err| switch (err) {
        error.MissingUsername => log.fatal("É necessário fornecer uma matrícula.", .{}),
    };

    if (final_login.password == null) {
        final_login.password = promptPassword(arena, io) catch |err| {
            log.fatal("Algo deu errado. ({s})", .{@errorName(err)});
        };
    }

    return final_login;
}

test "parse student from arguments: username and password" {
    const args = [_][:0]const u8{ "programa", "-u", "123", "-p", "abc" };
    const login = try parseStudentFromArgs(&args);

    try std.testing.expectEqualStrings("123", login.student_id.?);
    try std.testing.expectEqualStrings("abc", login.password.?);
}

test "merge login: password only, no username anywhere" {
    const from_args = Login{ .password = "abc" };
    try std.testing.expectError(error.MissingUsername, parseEnvWithArgs(from_args, null, null));
}
