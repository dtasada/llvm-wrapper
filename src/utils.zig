const std = @import("std");

pub const Position = struct {
    line: usize,
    col: usize,

    pub fn format(self: Position, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{}:{}", .{ self.line, self.col });
    }
};

const Color = enum { white, red, green, blue, yellow };

pub fn print(
    comptime fmt: []const u8,
    args: anytype,
    comptime color: Color,
) void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &stdout_writer.interface;

    stdout.print(
        switch (color) {
            .white => "",
            .red => "\x1b[0;31m",
            .green => "\x1b[0;34m",
            .blue => "\x1b[0;32m",
            .yellow => "\x1b[0;33m",
        } ++ fmt ++ "\x1b[0m",
        args,
    ) catch |err| std.debug.print("Couldn't stdout.print(): {}\n", .{err});

    stdout.flush() catch |err| std.debug.print("Couldn't stdout.flush(): {}\n", .{err});
}

pub inline fn printErr(
    comptime err: anytype,
    comptime fmt: []const u8,
    args: anytype,
    comptime color: Color,
) @TypeOf(err) {
    print(fmt, args, color);
    return err;
}

pub fn hash(context: anytype, key: anytype, depth: u32) void {
    if (depth > 100) { // arbitrary recursion limit
        print("exceeding hash depth limit of 100.", .{}, .red);
        return;
    }

    const Key = @TypeOf(key);
    switch (@typeInfo(Key)) {
        .noreturn, .type, .undefined, .null, .void => {},
        .comptime_int, .comptime_float => @compileError("unable to hash comptime value"),

        .float => switch (@TypeOf(key)) {
            f32 => { // f32
                const v: u32 = @bitCast(key);
                context.update(std.mem.asBytes(&v));
            },
            f64 => { // f64
                const v: u64 = @bitCast(key);
                context.update(std.mem.asBytes(&v));
            },
            else => context.update(std.mem.asBytes(&key)),
        },

        .int, .bool, .@"enum" => context.update(std.mem.asBytes(&key)),

        .pointer => |info| switch (info.size) {
            .one => {
                const v: usize = @intFromPtr(key);
                context.update(std.mem.asBytes(&v));
            },
            .slice => {
                const len_bytes = std.mem.asBytes(&key.len);
                context.update(len_bytes);
                context.update(std.mem.sliceAsBytes(key));
            },
            else => {
                // Ignore other pointers
            },
        },

        .array => {
            for (key) |item| {
                hash(context, item, depth + 1);
            }
        },

        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (!field.is_comptime) {
                    hash(context, @field(key, field.name), depth + 1);
                }
            }
        },

        .@"union" => |union_info| {
            hash(context, std.meta.activeTag(key), depth + 1);
            inline for (union_info.fields) |field| {
                if (std.mem.eql(u8, field.name, @tagName(std.meta.activeTag(key)))) {
                    if (field.type != void) {
                        const payload = @field(key, field.name);
                        hash(context, payload, depth + 1);
                    }
                    break;
                }
            }
        },

        .optional => {
            if (key) |payload| {
                context.update(&.{1});
                hash(context, payload, depth + 1);
            } else {
                context.update(&.{0});
            }
        },
        .@"opaque", .@"fn" => @compileError("unable to hash type " ++ @typeName(Key)),
        .error_set => {},
        .frame => @compileError("unable to hash type " ++ @typeName(Key)),
        .@"anyframe" => @compileError("unable to hash type " ++ @typeName(Key)),
        .vector => |info| {
            for (0..info.len) |i| {
                hash(context, key[i], depth + 1);
            }
        },
        .error_union => {},
        .enum_literal => {},
    }
}
