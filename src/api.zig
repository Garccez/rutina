const std = @import("std");
const config = @import("config.zig");
const log = @import("log.zig");
const cli = @import("cli.zig");
const schedule = @import("schedule.zig");

const base_url = "https://portal.ufsm.br/mobile/webservice/flutter/";

const Config = config.Config;
const Login = cli.Login;
const Schedule = schedule.Schedule;

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

fn checkStatus(status: std.http.Status) !void {
    const code = @backingInt(status);
    if (code >= 400) {
        log.logError("O Portal UFSM respondeu com status {d}.", .{code});
        return error.HttpError;
    }
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

pub fn httpFetchToken(
    io: std.Io,
    client: *std.http.Client,
    arena: std.mem.Allocator,
    conf: Config,
    login: Login,
) ![]const u8 {
    var raw: [16]u8 = undefined;
    io.random(&raw);
    const device_id = try formatUuid(arena, raw);

    const body_struct = LoginBody{ .appName = conf.environment.app, .deviceId = device_id, .deviceInfo = conf.environment.device_info, .messageToken = conf.environment.message_token, .login = login.student_id.?, .senha = login.password.? };
    const login_url: []const u8 = base_url ++ "generateTokenJwt";

    const response = try postJson(LoginResponse, client, arena, login_url, body_struct, &.{});

    if (response.@"error") {
        log.logError("{s}", .{response.mensagem orelse "A API recusou o login."});
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

pub fn doSchedule(client: *std.http.Client, arena: std.mem.Allocator, sched: Schedule, token: []const u8, date: []const u8) !void {
    const schedule_body_struct = ScheduleBody{ .dataInicio = date, .dataFim = date, .idRestaurante = sched.restaurant.apiId(), .opcaoVegetariana = sched.vegetarian, .tiposRefeicoes = try schedule.foodType(arena, sched) };
    const auth_value = try std.fmt.allocPrint(arena, "Bearer {s}", .{token});
    const schedule_url: []const u8 = base_url ++ "ru/agendaRefeicoes";

    const schedule_response = try postJson(ScheduleResponse, client, arena, schedule_url, schedule_body_struct, &.{
        .{ .name = "Authorization", .value = auth_value },
    });

    if (schedule_response.@"error") {
        log.logError("RU {d}: {s}", .{ @backingInt(sched.restaurant), schedule_response.mensagem orelse "A API recusou o agendamento." });
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
            log.logError("{s} ({s}): {s}", .{ data, meal, item.impedimento orelse "resposta sem motivo" });
            failed = true;
        }
    }

    if (failed) return error.FailedSchedule;
}
