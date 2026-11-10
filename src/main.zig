const std = @import("std");
const linux = std.os.linux;

const utc_offset_seconds = 3 * 3600;
const base_url = "https://portal.ufsm.br/mobile/webservice/flutter/";

const Config = struct {
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

const Weekday = enum {
    mon,
    tue,
    wed,
    thu,
    fri,
    sat,
    sun,
};
const Restaurant = enum(u8) {
    ru1 = 1,
    ru2 = 2,

    fn apiId(self: Restaurant) u8 {
        return switch (self) {
            .ru1 => 1,
            .ru2 => 41,
        };
    }
};
const Schedule = struct {
    weekday: Weekday,
    restaurant: Restaurant,
    vegetarian: bool = false,
    coffee: bool = false,
    lunch: bool = false,
    dinner: bool = false,
};
const Login = struct {
    student_id: ?[]const u8 = null,
    password: ?[]const u8 = null,
};
const LoginBody = struct {
    appName: []const u8,
    deviceId: []const u8,
    deviceInfo: []const u8,
    messageToken: []const u8,
    login: []const u8,
    senha: []const u8,
};

const LoginResponse = struct {
    @"error": bool = false,
    mensagem: ?[]const u8 = null,
    body: ?struct {
        accessToken: ?[]const u8 = null,
    } = null,
};

const ScheduleResponseItems = struct {
    sucesso: bool = false,
    impedimento: ?[]const u8 = null,
    dataRefAgendada: ?[]const u8 = null,
    tipoRefeicao: ?struct {
        descricao: ?[]const u8 = null,
    } = null,
};

const ScheduleResponse = struct {
    @"error": bool = false,
    mensagem: ?[]const u8 = null,
    body: ?[]const ScheduleResponseItems = null,
};

const ScheduleBody = struct {
    dataInicio: []const u8,
    dataFim: []const u8,
    idRestaurante: u8,
    opcaoVegetariana: bool,
    tiposRefeicoes: []const u4,
};

pub fn main(init: std.process.Init) !void {
    // Initiates the arena allocator
    const arena: std.mem.Allocator = init.arena.allocator();
    // Gets system io
    const io = init.io;

    // Loads student login from args and env, then checks if a password was provided.
    // If it was not, it asks the user to provide one secretly from the terminal.
    const final_student_login: Login = loadLogin(init, io, arena);

    // Parses the provided "config.json" into a Config (struct), expects it to be
    // correct JSON syntax.
    const parsed_json = loadConfig(io, arena);

    // Get current moment since Jan 1, 1970 in nanosseconds,
    // and then convert it to the enum weekday through weekdayFromSeconds.
    const now_posix = std.Io.Clock.real.now(io);
    const enum_weekday: Weekday = weekdayFromSeconds(now_posix.toSeconds());

    const target = targetWeekday(enum_weekday, parsed_json.schedules, parsed_json.behaviour.use_monday_schedule_on_friday);
    const days_ahead = daysUntil(enum_weekday, target);
    const date = try dateString(arena, now_posix.toSeconds(), days_ahead);

    if (!hasScheduleFor(target, parsed_json.schedules)) {
        std.debug.print("[RUTINA] Nenhum agendamento foi encontrado para o dia.\n", .{});
        return;
    }

    var client: std.http.Client = .{ .io = io, .allocator = arena };
    defer client.deinit();
    const token = httpFetchToken(io, &client, arena, parsed_json, final_student_login) catch |err| switch (err) {
        error.NoAccessToken => {
            fatal("Não foi possível obter o token de acesso.", .{});
        },
        error.HttpError, error.LoginRefused => std.process.exit(1),
        else => {
            fatal("Algo deu errado. ({s})", .{@errorName(err)});
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
            doSchedule(&client, arena, s, token, date) catch |err| switch (err) {
                error.FailedSchedule => {
                    logError("Um ou mais agendamentos falharam.", .{});
                    failed = true;
                },
                error.HttpError, error.ScheduleRefused => failed = true,
                error.NoMealList => {
                    logError("RU {d}: a API não retornou a lista de refeições.", .{@backingInt(s.restaurant)});
                    failed = true;
                },
                else => {
                    logError("RU {d}: algo deu errado. ({s})", .{ @backingInt(s.restaurant), @errorName(err) });
                    failed = true;
                },
            };
        }
    }

    if (failed) std.process.exit(1);
}

fn logError(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[ERRO] " ++ fmt ++ "\n", args);
}

fn loadConfig(io: std.Io, arena: std.mem.Allocator) Config {
    // Tries to read "config.json" from the folder the executable is being run inside.
    // Otherwise throws an error.
    const input = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, "config.json", arena, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => fatal("Arquivo 'config.json' não existe.", .{}),
        else => fatal("Algo deu errado. ({s})", .{@errorName(err)}),
    };
    // Parses the provided "config.json" into a Config (struct), expects it to be
    // correct JSON syntax.
    const parsed_json = parseJson(input, arena) catch |err| {
        fatal("O \"config.json\" não é válido. ({s})", .{@errorName(err)});
    };
    return parsed_json;
}

fn loadLogin(init: std.process.Init, io: std.Io, arena: std.mem.Allocator) Login {
    // Tries to load the commandline arguments into the args slice, otherwise returns a fatal error.
    const args = init.minimal.args.toSlice(arena) catch |err| switch (err) {
        error.OutOfMemory => fatal("O aplicativo ficou sem memória para concluir esta operação.", .{}),
        error.Unexpected => fatal("Algo inesperado ocorreu.", .{}),
    };

    // Then tries to parse the student login information from the arguments with parseStudentFromArgs.
    const student_login = parseStudentFromArgs(args) catch |err| switch (err) {
        error.MissingUsernameValue => fatal("É necessário fornecer um valor para matrícula.", .{}),
        error.MissingPasswordValue => fatal("É necessário fornecer um valor para senha.", .{}),
        error.UnknownArgument => fatal("Argumento ou opção desconhecida.\nUtilize -u/--username e -p/--password para fornecer matrícula e senha.", .{}),
    };
    // Loads login information environment variables
    const student_id_env = init.environ_map.get("RUTINA_USERNAME");
    const password_env = init.environ_map.get("RUTINA_PASSWORD");

    // Then tries to parse those same variables into the final Login (struct), if both the arguments'
    // and environment's username is null, returns an error.
    var final_login: Login = parseEnvWithArgs(student_login, student_id_env, password_env) catch |err| switch (err) {
        error.MissingUsername => fatal("É necessário fornecer uma matrícula.", .{}),
    };

    if (final_login.password == null) {
        final_login.password = promptPassword(arena, io) catch |err| {
            fatal("Algo deu errado. ({s})", .{@errorName(err)});
        };
    }

    return final_login;
}

fn hasScheduleFor(target: Weekday, schedules: []const Schedule) bool {
    for (schedules) |s| {
        if (s.weekday == target) return true;
    }
    return false;
}

fn weekdayFromSeconds(seconds: i64) Weekday {
    const to_local_seconds = seconds - utc_offset_seconds;
    const to_days = @divFloor(to_local_seconds, 86400);
    const to_unsigned_weekday: u3 = @intCast(@mod(to_days + 3, 7));
    const to_enum_weekday: Weekday = @fromBackingInt(to_unsigned_weekday);

    return to_enum_weekday;
}

fn tomorrowFromWeekday(weekday: Weekday) Weekday {
    const to_unsigned_weekday: u3 = @backingInt(weekday);
    const tomorrow: u3 = (to_unsigned_weekday + 1) % 7;
    const to_enum_tomorrow: Weekday = @fromBackingInt(tomorrow);

    return to_enum_tomorrow;
}

fn targetWeekday(today: Weekday, schedules: []const Schedule, rule: bool) Weekday {
    const weekend = hasScheduleFor(.sat, schedules) or hasScheduleFor(.sun, schedules);
    if (today == .fri and rule and !weekend) return .mon;
    return tomorrowFromWeekday(today);
}

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

fn parseJson(input: []const u8, allocator: std.mem.Allocator) !Config {
    const parsed_json = try std.json.parseFromSlice(Config, allocator, input, .{});
    return parsed_json.value;
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

fn checkStatus(status: std.http.Status) !void {
    const code = @backingInt(status);
    if (code >= 400) {
        logError("O Portal UFSM respondeu com status {d}.", .{code});
        return error.HttpError;
    }
}

fn setEcho(enabled: bool) !void {
    var term: linux.termios = undefined;
    if (linux.errno(linux.ioctl(0, linux.T.CGETS, @intFromPtr(&term))) != .SUCCESS) return error.NotATerminal;

    term.lflag.ECHO = enabled;

    if (linux.errno(linux.ioctl(0, linux.T.CSETS, @intFromPtr(&term))) != .SUCCESS) return error.TerminalFailed;
}

fn postJson(
    comptime Response: type,
    client: *std.http.Client,
    arena: std.mem.Allocator,
    url: []const u8,
    request: anytype,
    extra_headers: []const std.http.Header,
) !Response {
    var body: std.Io.Writer.Allocating = .init(arena);
    const payload = try std.json.Stringify.valueAlloc(arena, request, .{});

    const result = try client.fetch(.{
        .method = .POST,
        .location = .{ .url = url },
        .payload = payload,
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .extra_headers = extra_headers,
        .response_writer = &body.writer,
    });
    try checkStatus(result.status);
    const parsed = try std.json.parseFromSlice(Response, arena, body.written(), .{ .ignore_unknown_fields = true });

    return parsed.value;
}

fn httpFetchToken(
    io: std.Io,
    client: *std.http.Client,
    arena: std.mem.Allocator,
    config: Config,
    login: Login,
) ![]const u8 {
    var raw: [16]u8 = undefined;
    io.random(&raw);
    const device_id = try formatUuid(arena, raw);

    const body_struct = LoginBody{ .appName = config.environment.app, .deviceId = device_id, .deviceInfo = config.environment.device_info, .messageToken = config.environment.message_token, .login = login.student_id.?, .senha = login.password.? };
    const login_url: []const u8 = base_url ++ "generateTokenJwt";

    const response = try postJson(LoginResponse, client, arena, login_url, body_struct, &.{});

    if (response.@"error") {
        logError("{s}", .{response.mensagem orelse "A API recusou o login."});
        return error.LoginRefused;
    }
    const response_body = response.body orelse return error.NoAccessToken;
    const token = response_body.accessToken orelse return error.NoAccessToken;
    return token;
}

fn formatUuid(arena: std.mem.Allocator, raw: [16]u8) ![]u8 {
    var bytes = raw;
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    const hex = std.fmt.bytesToHex(bytes, .lower);
    return std.fmt.allocPrint(arena, "{s}-{s}-{s}-{s}-{s}", .{
        hex[0..8],
        hex[8..12],
        hex[12..16],
        hex[16..20],
        hex[20..32],
    });
}

fn foodType(arena: std.mem.Allocator, schedule: Schedule) ![]u4 {
    const n = @as(usize, @intFromBool(schedule.coffee)) +
        @as(usize, @intFromBool(schedule.lunch)) +
        @as(usize, @intFromBool(schedule.dinner));

    const list = try arena.alloc(u4, n);
    var i: usize = 0;

    if (schedule.coffee) {
        list[i] = 1;
        i += 1;
    }
    if (schedule.lunch) {
        list[i] = 2;
        i += 1;
    }
    if (schedule.dinner) {
        list[i] = 3;
        i += 1;
    }

    return list;
}

/// How many days there are from `today` until `target` (always 1 to 6).
fn daysUntil(today: Weekday, target: Weekday) u8 {
    const t: u3 = @backingInt(today);
    const g: u3 = @backingInt(target);
    return (@as(u8, g) + 7 - t) % 7;
}

/// Date `days_ahead` days from now (UTC-3 timezone), in the API format.
fn dateString(arena: std.mem.Allocator, now_seconds: i64, days_ahead: u8) ![]u8 {
    const local = now_seconds - utc_offset_seconds + @as(i64, days_ahead) * 86400;

    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return std.fmt.allocPrint(arena, "{d}-{d:0>2}-{d:0>2} 00:00:00", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
    });
}

fn doSchedule(client: *std.http.Client, arena: std.mem.Allocator, schedule: Schedule, token: []const u8, date: []const u8) !void {
    const schedule_body_struct = ScheduleBody{ .dataInicio = date, .dataFim = date, .idRestaurante = schedule.restaurant.apiId(), .opcaoVegetariana = schedule.vegetarian, .tiposRefeicoes = try foodType(arena, schedule) };
    const auth_value = try std.fmt.allocPrint(arena, "Bearer {s}", .{token});
    const schedule_url: []const u8 = base_url ++ "ru/agendaRefeicoes";

    const schedule_response = try postJson(ScheduleResponse, client, arena, schedule_url, schedule_body_struct, &.{
        .{ .name = "Authorization", .value = auth_value },
    });

    if (schedule_response.@"error") {
        logError("RU {d}: {s}", .{ schedule.restaurant, schedule_response.mensagem orelse "A API recusou o agendamento." });
        return error.ScheduleRefused;
    }

    const items = schedule_response.body orelse return error.NoMealList;

    var failed = false;
    for (items) |item| {
        const meal = if (item.tipoRefeicao) |t| t.descricao orelse "refeição" else "refeição";
        const data = item.dataRefAgendada orelse "data desconhecida";

        if (item.sucesso) {
            std.debug.print("{s} ({s}): Agendado com sucesso.\n", .{ data, meal });
        } else {
            logError("{s} ({s}): {s}", .{ data, meal, item.impedimento orelse "resposta sem motivo" });
            failed = true;
        }
    }

    if (failed) return error.FailedSchedule;
}

// ---------- helpers para os testes ----------

fn expectDate(expected: []const u8, now_seconds: i64, days_ahead: u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const date = try dateString(arena_state.allocator(), now_seconds, days_ahead);
    try std.testing.expectEqualStrings(expected, date);
}

fn expectFoodType(expected: []const u4, schedule: Schedule) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const result = try foodType(arena_state.allocator(), schedule);
    try std.testing.expectEqualSlices(u4, expected, result);
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("[ERRO] " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

// ---------- foodType ----------

test "food type: only coffee" {
    try expectFoodType(&.{1}, .{ .weekday = .mon, .restaurant = .ru1, .coffee = true });
}

test "food type: only lunch" {
    try expectFoodType(&.{2}, .{ .weekday = .mon, .restaurant = .ru1, .lunch = true });
}

test "food type: only dinner" {
    try expectFoodType(&.{3}, .{ .weekday = .mon, .restaurant = .ru1, .dinner = true });
}

test "food type: coffee and dinner" {
    try expectFoodType(&.{ 1, 3 }, .{ .weekday = .mon, .restaurant = .ru1, .coffee = true, .dinner = true });
}

test "food type: coffee and lunch" {
    try expectFoodType(&.{ 1, 2 }, .{ .weekday = .mon, .restaurant = .ru1, .coffee = true, .lunch = true });
}

test "food type: all three" {
    try expectFoodType(&.{ 1, 2, 3 }, .{ .weekday = .mon, .restaurant = .ru1, .coffee = true, .lunch = true, .dinner = true });
}

test "food type: none" {
    try expectFoodType(&.{}, .{ .weekday = .mon, .restaurant = .ru1 });
}

// ---------- daysUntil ----------

test "days until: friday -> monday" {
    try std.testing.expectEqual(3, daysUntil(.fri, .mon));
}

test "days until: friday -> saturday" {
    try std.testing.expectEqual(1, daysUntil(.fri, .sat));
}

test "days until: thursday -> friday" {
    try std.testing.expectEqual(1, daysUntil(.thu, .fri));
}

test "days until: sunday -> monday (wraps the week)" {
    try std.testing.expectEqual(1, daysUntil(.sun, .mon));
}

test "days until: monday -> sunday" {
    try std.testing.expectEqual(6, daysUntil(.mon, .sun));
}

// ---------- dateString ----------
// 1794112542 + utc_offset_seconds = domingo, 8 de novembro de 2026, 04:35 em UTC-3

test "date string: today" {
    try expectDate("2026-11-08 00:00:00", utc_offset_seconds + 1794112542, 0);
}

test "date string: tomorrow" {
    try expectDate("2026-11-09 00:00:00", utc_offset_seconds + 1794112542, 1);
}

test "date string: three days ahead" {
    try expectDate("2026-11-11 00:00:00", utc_offset_seconds + 1794112542, 3);
}

test "date string: month rollover" {
    // 30 de novembro de 2026, 00:00 em UTC-3
    try expectDate("2026-12-01 00:00:00", utc_offset_seconds + 1795996800, 1);
}

test "date string: year rollover" {
    // 31 de dezembro de 2026, 12:00 em UTC-3
    try expectDate("2027-01-01 00:00:00", 1798729200, 1);
}

test "date string: leap year" {
    // 28 de fevereiro de 2028, 12:00 em UTC-3
    try expectDate("2028-02-29 00:00:00", 1835362800, 1);
}

test "date string: UTC already tomorrow, Brazil still today" {
    // 8 de novembro, 23:30 em UTC-3 (já é 9 de novembro, 02:30 em UTC)
    try expectDate("2026-11-08 00:00:00", 1794191400, 0);
}

// ---------- hasScheduleFor ----------

test "has schedule for: day present" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .wed, .restaurant = .ru2, .coffee = true },
    };
    try std.testing.expect(hasScheduleFor(.wed, &schedules));
}

test "has schedule for: day absent" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .wed, .restaurant = .ru2, .coffee = true },
    };
    try std.testing.expect(!hasScheduleFor(.tue, &schedules));
}

test "has schedule for: empty list" {
    const schedules = [_]Schedule{};
    try std.testing.expect(!hasScheduleFor(.mon, &schedules));
}

test "time conversion, current: Thursday Jan 1, 1970 00:00" {
    try std.testing.expectEqual(Weekday.thu, weekdayFromSeconds(utc_offset_seconds));
}

test "time conversion, current: Monday Jan 5, 1970 00:00" {
    try std.testing.expectEqual(Weekday.mon, weekdayFromSeconds(utc_offset_seconds + (4 * 86400)));
}

test "time conversion, current: Friday Jan 2, 1970 00:00:00 -> Thursday Jan 1, 1970 23:59:59" {
    var timestamp: i64 = 3 * 3600;
    try std.testing.expectEqual(Weekday.fri, weekdayFromSeconds(timestamp + (24 * 3600)));
    timestamp -= 1;
    try std.testing.expectEqual(Weekday.thu, weekdayFromSeconds(timestamp + (24 * 3600)));
}

test "time conversion, current: Sunday November 8, 2026 04:35" {
    try std.testing.expectEqual(Weekday.sun, weekdayFromSeconds(utc_offset_seconds + 1794112542));
}

test "time conversion, tomorrow: Sunday -> Monday" {
    try std.testing.expectEqual(Weekday.mon, tomorrowFromWeekday(Weekday.sun));
}

test "time conversion, tomorrow: Saturday -> Sunday" {
    try std.testing.expectEqual(Weekday.sun, tomorrowFromWeekday(Weekday.sat));
}

test "friday check: no weekend" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .thu, .restaurant = .ru2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = .ru1, .coffee = true, .dinner = true },
        .{ .weekday = .mon, .restaurant = .ru2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.mon, targetWeekday(Weekday.fri, &schedules, true));
}

test "friday check: schedule contains saturday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .thu, .restaurant = .ru2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = .ru1, .coffee = true, .dinner = true },
        .{ .weekday = .sat, .restaurant = .ru2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.sat, targetWeekday(Weekday.fri, &schedules, true));
}

test "friday check: schedule contains sunday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .thu, .restaurant = .ru2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = .ru1, .coffee = true, .dinner = true },
        .{ .weekday = .sun, .restaurant = .ru2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.sat, targetWeekday(Weekday.fri, &schedules, true));
}

test "friday check: schedule contains both saturday and sunday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .sat, .restaurant = .ru2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = .ru1, .coffee = true, .dinner = true },
        .{ .weekday = .sun, .restaurant = .ru2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.sat, targetWeekday(Weekday.fri, &schedules, true));
}

test "friday check: not friday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = .ru1, .lunch = true },
        .{ .weekday = .thu, .restaurant = .ru2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = .ru1, .coffee = true, .dinner = true },
        .{ .weekday = .sun, .restaurant = .ru2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.fri, targetWeekday(Weekday.thu, &schedules, true));
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

test "restaurant api id: ru1" {
    try std.testing.expectEqual(1, Restaurant.ru1.apiId());
}

test "restaurant api id: ru2" {
    try std.testing.expectEqual(41, Restaurant.ru2.apiId());
}
