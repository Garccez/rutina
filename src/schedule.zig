const std = @import("std");
const datetime = @import("datetime.zig");

const Weekday = datetime.Weekday;

pub const Restaurant = enum(u8) {
    ru1 = 1,
    ru2 = 2,

    pub fn apiId(self: Restaurant) u8 {
        return switch (self) {
            .ru1 => 1,
            .ru2 => 41,
        };
    }
};

pub const Schedule = struct {
    weekday: Weekday,
    restaurant: Restaurant,
    vegetarian: bool = false,
    coffee: bool = false,
    lunch: bool = false,
    dinner: bool = false,
};

pub fn hasScheduleFor(target: Weekday, schedules: []const Schedule) bool {
    for (schedules) |s| {
        if (s.weekday == target) return true;
    }
    return false;
}

pub fn targetWeekday(today: Weekday, schedules: []const Schedule, rule: bool) Weekday {
    const weekend = hasScheduleFor(.sat, schedules) or hasScheduleFor(.sun, schedules);
    if (today == .fri and rule and !weekend) return .mon;
    return datetime.tomorrowFromWeekday(today);
}

pub fn foodType(arena: std.mem.Allocator, schedule: Schedule) ![]u4 {
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

// ---------- helper function ----------

fn expectFoodType(expected: []const u4, schedule: Schedule) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const result = try foodType(arena_state.allocator(), schedule);
    try std.testing.expectEqualSlices(u4, expected, result);
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

// ---------- friday check ----------

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

// ---------- restaurant id function check ----------

test "restaurant api id: ru1" {
    try std.testing.expectEqual(1, Restaurant.ru1.apiId());
}

test "restaurant api id: ru2" {
    try std.testing.expectEqual(41, Restaurant.ru2.apiId());
}
