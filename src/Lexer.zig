const std = @import("std");

const utils = @import("utils.zig");

const Self = @This();

input: []const u8,
tokens: std.ArrayList(Token) = .{},
/// maps each token by index to its corresponding location in the source code
source_map: std.ArrayList(struct { line: usize, col: usize }) = .{},
pos: usize,

const BadToken = error{
    BadNumber,
    UnknownToken,
};

pub const BinaryOperator = enum {
    plus,
    minus,
    asterisk,
    slash,
    percent,

    plus_equals,
    minus_equals,
    times_equals,
    slash_equals,
    mod_equals,

    equals,
    equals_equals,
    bang,
    greater,
    less,
    greater_equals,
    less_equals,
    bang_equals,
};

pub const Token = union(enum) {
    bad_token: BadToken,
    atom: []const u8,
    int: u64,
    float: f64,
    eof,
    @"(",
    @")",
    @"{",
    @"}",
    @";",
    @":",
    @",",
    @".",

    op: BinaryOperator,

    pub fn toString(self: *const Token, buf: []u8) error{NoSpaceLeft}![]const u8 {
        return try switch (self.*) {
            .int => |int| std.fmt.bufPrint(buf, "int({})", .{int}),
            .float => |float| std.fmt.bufPrint(buf, "float({})", .{float}),
            .atom => |atom| std.fmt.bufPrint(buf, "atom({s})", .{atom}),
            .op => |op| std.fmt.bufPrint(buf, "op({s})", .{@tagName(op)}),
            .bad_token => |bad_token| std.fmt.bufPrint(buf, "bad_token({})", .{bad_token}),
            else => |token| std.fmt.bufPrint(buf, "{s}", .{@tagName(token)}),
        };
    }
};

pub fn init(input: []const u8) Self {
    return .{
        .input = input,
        .pos = 0,
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.tokens.deinit(alloc);
    self.source_map.deinit(alloc);
}

inline fn currentChar(self: *const Self) u8 {
    return self.input[self.pos];
}

inline fn consumeChar(self: *Self) u8 {
    const char = self.input[self.pos];
    self.pos += 1;
    return char;
}

inline fn peek(self: *const Self) ?u8 {
    if (self.input.len > self.pos + 1) {
        return self.input[self.pos + 1];
    } else {
        return null;
    }
}

pub fn tokenize(self: *Self, alloc: std.mem.Allocator) !void {
    errdefer self.tokens.deinit(alloc);

    while (self.pos < self.input.len) {
        if (std.ascii.isAlphabetic(self.currentChar()) or self.currentChar() == '_') {
            var atom: [128]u8 = undefined;
            atom[0] = self.consumeChar();

            var i: usize = 1;
            while (std.ascii.isAlphanumeric(self.currentChar()) or self.currentChar() == '_') : (i += 1) {
                atom[i] = self.consumeChar();
            }

            const token = Token{ .atom = try alloc.dupe(u8, atom[0..i]) };
            errdefer alloc.free(token.atom);
            try self.appendToken(alloc, token);
        } else if (std.ascii.isDigit(self.currentChar()))
            try self.parseNumber(alloc)
        else {
            const char = self.currentChar();
            const non_alphanumeric = "+-*/(){};:,=!><";
            // if is an operator
            if (std.mem.containsAtLeastScalar(u8, non_alphanumeric, 1, char)) {
                switch (char) {
                    '+', '-', '*', '/', '%', '=', '!', '>', '<' => try self.parseBinaryOperator(alloc),
                    '(' => try self.appendAndNext(alloc, .@"("),
                    ')' => try self.appendAndNext(alloc, .@")"),
                    '{' => try self.appendAndNext(alloc, .@"{"),
                    '}' => try self.appendAndNext(alloc, .@"}"),
                    ';' => try self.appendAndNext(alloc, .@";"),
                    ':' => try self.appendAndNext(alloc, .@":"),
                    ',' => try self.appendAndNext(alloc, .@","),
                    '.' => try self.appendAndNext(alloc, .@"."),
                    else => unreachable,
                }
            } else {
                if (std.ascii.isWhitespace(char)) {
                    self.pos += 1;
                    continue;
                }
                if (std.ascii.isAlphanumeric(char))
                    unreachable
                else
                    try self.appendAndNext(alloc, .{ .bad_token = BadToken.UnknownToken });
            }
        }
    }
}

fn parseBinaryOperator(self: *Self, alloc: std.mem.Allocator) !void {
    const first_token = self.currentChar();
    if (!std.mem.containsAtLeastScalar(u8, "+-*/%=!><", 1, first_token)) unreachable;

    self.pos += 1;
    const double_token: Token = switch (self.currentChar()) {
        '=' => blk: {
            self.pos += 1;
            break :blk switch (first_token) {
                '=' => .{ .op = .equals_equals },
                '!' => .{ .op = .bang_equals },
                '>' => .{ .op = .greater_equals },
                '<' => .{ .op = .less_equals },
                '+' => .{ .op = .plus_equals },
                '-' => .{ .op = .minus_equals },
                '*' => .{ .op = .times_equals },
                '/' => .{ .op = .slash_equals },
                '%' => .{ .op = .mod_equals },
                else => unreachable,
            };
        },
        else => switch (first_token) {
            '=' => .{ .op = .equals },
            '!' => .{ .op = .bang },
            '>' => .{ .op = .greater },
            '<' => .{ .op = .less },
            '+' => .{ .op = .plus },
            '-' => .{ .op = .minus },
            '*' => .{ .op = .asterisk },
            '/' => .{ .op = .slash },
            '%' => .{ .op = .percent },
            else => unreachable,
        },
    };

    try self.appendToken(alloc, double_token);
}

inline fn appendAndNext(self: *Self, alloc: std.mem.Allocator, token: Token) !void {
    try self.appendToken(alloc, token);
    self.pos += 1;
}

fn parseNumber(self: *Self, alloc: std.mem.Allocator) !void {
    var passed_decimal = false;
    const number_start = self.pos;

    while (std.ascii.isDigit(self.currentChar()) or self.currentChar() == '.') {
        if (self.currentChar() == '.') {
            if (passed_decimal) {
                try self.appendToken(alloc, .{ .bad_token = BadToken.BadNumber });
                return;
            }
            passed_decimal = true;
        }
        self.pos += 1;
    }

    if (std.ascii.isAlphabetic(self.input[self.pos])) {
        while (std.ascii.isAlphanumeric(self.currentChar())) {
            self.pos += 1;
        }
        try self.appendToken(alloc, Token{ .bad_token = BadToken.BadNumber });
        return;
    }

    if (passed_decimal) {
        const token = blk: {
            const num = std.fmt.parseFloat(f64, self.input[number_start..self.pos]) catch |err| {
                utils.print("Couldn't parse float: {}\n", .{err}, .red);
                break :blk Token{ .bad_token = BadToken.BadNumber };
            };
            break :blk Token{ .float = num };
        };
        try self.appendToken(alloc, token);
    } else {
        const token = blk: {
            const num = std.fmt.parseInt(u64, self.input[number_start..self.pos], 10) catch |err| {
                utils.print("Couldn't parse integer: {}\n", .{err}, .red);
                break :blk Token{ .bad_token = BadToken.BadNumber };
            };
            break :blk Token{ .int = num };
        };
        try self.appendToken(alloc, token);
    }

    try self.appendToken(alloc, .eof);
}

fn appendToken(self: *Self, alloc: std.mem.Allocator, token: Token) !void {
    try self.tokens.append(alloc, token);

    var amount_of_lines: usize = 1;
    for (0..self.pos) |i| {
        if (self.input[i] == '\n') amount_of_lines += 1;
    }

    const col = 1 + self.pos - (std.mem.lastIndexOf(u8, self.input[0..self.pos], "\r\n") orelse 0);
    try self.source_map.append(alloc, .{ .line = amount_of_lines, .col = col });
}
