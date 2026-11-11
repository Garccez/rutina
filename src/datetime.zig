const std = @import("std");

const utc_offset_seconds = 3 * 3600;

pub const Weekday = enum {
    mon,
    tue,
    wed,
    thu,
    fri,
    sat,
    sun,
};

pub fn weekdayFromSeconds(seconds: i64) Weekday {
    const to_local_seconds = seconds - utc_offset_seconds;
    const to_days = @divFloor(to_local_seconds, 86400);
    const to_unsigned_weekday: u3 = @intCast(@mod(to_days + 3, 7));
    const to_enum_weekday: Weekday = @fromBackingInt(to_unsigned_weekday);

    return to_enum_weekday;
}

pub fn tomorrowFromWeekday(weekday: Weekday) Weekday {
    const to_unsigned_weekday: u3 = @backingInt(weekday);
    const tomorrow: u3 = (to_unsigned_weekday + 1) % 7;
    const to_enum_tomorrow: Weekday = @fromBackingInt(tomorrow);

    return to_enum_tomorrow;
}

/// How many days there are from `today` until `target` (always 1 to 6).
pub fn daysUntil(today: Weekday, target: Weekday) u8 {
    const t: u3 = @backingInt(today);
    const g: u3 = @backingInt(target);
    return (@as(u8, g) + 7 - t) % 7;
}

/// Date `days_ahead` days from now (UTC-3 timezone), in the API format.
pub fn dateString(arena: std.mem.Allocator, now_seconds: i64, days_ahead: u8) ![]u8 {
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

fn expectDate(expected: []const u8, now_seconds: i64, days_ahead: u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const date = try dateString(arena_state.allocator(), now_seconds, days_ahead);
    try std.testing.expectEqualStrings(expected, date);
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
