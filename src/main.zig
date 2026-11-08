const std = @import("std");

const utc_offset_seconds = 3 * 3600;

const Weekday = enum {
    mon,
    tue,
    wed,
    thu,
    fri,
    sat,
    sun,
};
const Schedule = struct {
    weekday: Weekday,
    restaurant: u8,
    vegetarian: bool = false,
    coffee: bool = false,
    lunch: bool = false,
    dinner: bool = false,
};

pub fn main(init: std.process.Init) void {
    // Experiment with the struct.
    const monday = Schedule{ .weekday = .mon, .restaurant = 1, .vegetarian = false, .coffee = true, .lunch = true, .dinner = true };
    const tuesday = Schedule{ .weekday = .tue, .restaurant = 2, .vegetarian = true, .coffee = false, .lunch = true, .dinner = false };
    // Get system io?
    const io = init.io;

    // Get current moment since Jan 1, 1970 in nanosseconds,
    // and then convert it to the enum weekday through weekdayFromSeconds.
    const now_posix = std.Io.Clock.real.now(io);
    const enum_weekday: Weekday = weekdayFromSeconds(now_posix.toSeconds());

    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = 1, .lunch = true },
        .{ .weekday = .thu, .restaurant = 2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = 1, .coffee = true, .dinner = true },
        .{ .weekday = .mon, .restaurant = 2, .coffee = true, .dinner = true },
    };
    const target = targetWeekday(enum_weekday, &schedules);
    printSchedulesFor(target, &schedules);

    // Print our debug info.
    std.debug.print("Horário POSIX desde 1970 em nanossegundos: {}\n", .{now_posix.toNanoseconds()});
    std.debug.print("Horário POSIX desde 1970 em segundos: {}\n", .{now_posix.toSeconds()});
    std.debug.print("Horário POSIX desde 1970 em segundos ajustado para UTC-3: {}\n", .{now_posix.toSeconds() - utc_offset_seconds});
    std.debug.print("Dia da Semana Enumerado (Mon-Sun): {}\n", .{enum_weekday});

    std.debug.print("{}\n", .{monday});
    std.debug.print("{}\n", .{tuesday});
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

fn printSchedulesFor(target: Weekday, schedules: []const Schedule) void {
    for (schedules) |s| {
        if (s.weekday == target) {
            std.debug.print("Correspondência encontrada: {}\n", .{s});
        }
    }
}

fn targetWeekday(today: Weekday, schedules: []const Schedule) Weekday {
    var has_weekend = false;
    if (today == Weekday.fri) {
        for (schedules) |s| {
            if (s.weekday == Weekday.sat or s.weekday == Weekday.sun) {
                has_weekend = true;
            }
        }
        if (has_weekend) {
            return Weekday.sat;
        }
        return Weekday.mon;
    }
    return tomorrowFromWeekday(today);
}

fn restaurantRealNumber(restaurant: u8) u8 {
    return switch (restaurant) {
        2 => 41,
        else => 1,
    };
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
        .{ .weekday = .mon, .restaurant = 1, .lunch = true },
        .{ .weekday = .thu, .restaurant = 2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = 1, .coffee = true, .dinner = true },
        .{ .weekday = .mon, .restaurant = 2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.mon, targetWeekday(Weekday.fri, &schedules));
}

test "friday check: schedule contains saturday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = 1, .lunch = true },
        .{ .weekday = .thu, .restaurant = 2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = 1, .coffee = true, .dinner = true },
        .{ .weekday = .sat, .restaurant = 2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.sat, targetWeekday(Weekday.fri, &schedules));
}

test "friday check: schedule contains sunday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = 1, .lunch = true },
        .{ .weekday = .thu, .restaurant = 2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = 1, .coffee = true, .dinner = true },
        .{ .weekday = .sun, .restaurant = 2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.sat, targetWeekday(Weekday.fri, &schedules));
}

test "friday check: schedule contains both saturday and sunday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = 1, .lunch = true },
        .{ .weekday = .sat, .restaurant = 2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = 1, .coffee = true, .dinner = true },
        .{ .weekday = .sun, .restaurant = 2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.sat, targetWeekday(Weekday.fri, &schedules));
}

test "friday check: not friday" {
    const schedules = [_]Schedule{
        .{ .weekday = .mon, .restaurant = 1, .lunch = true },
        .{ .weekday = .thu, .restaurant = 2, .coffee = true, .lunch = true },
        .{ .weekday = .fri, .restaurant = 1, .coffee = true, .dinner = true },
        .{ .weekday = .sun, .restaurant = 2, .coffee = true, .dinner = true },
    };

    try std.testing.expectEqual(Weekday.fri, targetWeekday(Weekday.thu, &schedules));
}

test "restaurant real number: one" {
    try std.testing.expectEqual(1, restaurantRealNumber(1));
}

test "restaurant real number: two" {
    try std.testing.expectEqual(41, restaurantRealNumber(2));
}

test "restaurant real number: any other" {
    try std.testing.expectEqual(1, restaurantRealNumber(44));
}
