const std = @import("std");
const utils = @import("utils.zig");

const Lexer = @import("Lexer.zig");
const BinaryOperator = Lexer.BinaryOperator;

const Node = @import("ParserNode.zig");

const Self = @This();

pos: usize,
input: *Lexer,

const BindingPower = struct {
    const bp_t = struct { f32, f32 };

    const cmp = bp_t{ 1.0, 1.1 };
    const add = bp_t{ 2.0, 2.1 };
    const mul = bp_t{ 3.0, 3.1 };

    pub inline fn fromOperator(op: BinaryOperator) bp_t {
        return switch (op) {
            .plus, .minus => add,
            .asterisk, .slash => mul,
            else => cmp,
        };
    }
};

pub fn init(input: *Lexer) Self {
    return .{
        .pos = 0,
        .input = input,
    };
}

/// Returns root node of the AST
pub fn getAst(self: *Self, alloc: std.mem.Allocator) !Node.RootNode {
    var root = Node.RootNode{};

    while (true) switch (self.currentToken()) {
        .atom => |atom| {
            if (std.mem.eql(u8, atom, "fn")) {
                var function_definition: Node.FunctionDefinition = undefined;

                function_definition.function_name = try self.expect(
                    self.nextToken(),
                    .atom,
                    "function definition",
                    "function name",
                );
                function_definition.params = try self.parseParameters(alloc);
                function_definition.return_type = try self.expect(self.nextToken(), .atom, "function definition", "return type");
                function_definition.body = try self.parseBlock(alloc);

                try root.append(alloc, .{ .func_def = function_definition });
            }
        },
        else => |actual| {
            var buf: [128]u8 = undefined;
            utils.print("Unexpected token: {s}\n", .{try actual.toString(&buf)}, .red);
            return error.UnexpectedToken;
        },
    };

    return root;
}

/// Consumes current token and then increases position.
inline fn consumeToken(self: *Self) Lexer.Token {
    const current_token = self.input.tokens.items[self.pos];
    self.pos += 1;
    return current_token;
}

/// Doesn't change position and returns next token.
inline fn peek(self: *const Self) Lexer.Token {
    return self.input.tokens.items[self.pos + 1];
}

inline fn currentToken(self: *const Self) Lexer.Token {
    return self.input.tokens.items[self.pos];
}

/// Consumes token and returns next one.
inline fn nextToken(self: *Self) Lexer.Token {
    self.pos += 1;
    return self.currentToken();
}

/// Skips a token (self.pos+=2) and returns token new position.
inline fn skipToken(self: *Self) Lexer.Token {
    self.pos += 2;
    return self.currentToken();
}

/// parses parameters and returns `!Node.ParameterList`. Caller is responsible for cleanup.
fn parseParameters(self: *Self, alloc: std.mem.Allocator) !Node.ParameterList {
    var params = Node.ParameterList{};

    try self.expect(self.nextToken(), .@"(", "parameter list", "'('");

    // `self.expectSilent(self.nextToken(), .@",")` consumes a token, so if one
    // was wasted attempting to parse a comma, keep that in mind when attempting
    // to parse the closing parenthesis.
    var compensate_for_comma = false;

    while (true) {
        const param_name = try self.expect(self.nextToken(), .atom, "parameter list", "parameter name");
        try self.expect(self.nextToken(), .@":", "parameter list", "':'");
        const param_type = try self.expect(self.nextToken(), .atom, "parameter list", "parameter type");

        try params.append(alloc, .{ .param_name = param_name, .type = param_type });

        // look for a comma, else a closing parenthesis
        self.expectSilent(self.nextToken(), .@",") catch {
            compensate_for_comma = true;
            break;
        };
    }

    try self.expect(
        if (compensate_for_comma)
            self.currentToken()
        else
            self.nextToken(),
        .@")",
        "parameter list",
        "')'",
    );

    return params;
}

fn parseArguments(self: *Self, alloc: std.mem.Allocator) !Node.ArgumentList {
    var args = Node.ArgumentList{};

    try self.expect(self.nextToken(), .@"(", "argument list", "'('");

    // `self.expectSilent(self.nextToken(), .@",")` consumes a token, so if one
    // was wasted attempting to parse a comma, keep that in mind when attempting
    // to parse the closing parenthesis.
    var compensate_for_comma = false;

    while (true) {
        const arg = try self.parseExpression(alloc, 0.0);
        try args.append(alloc, arg);

        // look for a comma, else a closing parenthesis
        self.expectSilent(self.nextToken(), .@",") catch {
            compensate_for_comma = true;
            break;
        };
    }

    try self.expect(
        if (compensate_for_comma)
            self.currentToken()
        else
            self.nextToken(),
        .@")",
        "argument list",
        "')'",
    );

    return args;
}

fn parseBlock(self: *Self, alloc: std.mem.Allocator) !Node.Block {
    var block = Node.Block{};

    try self.expect(self.nextToken(), .@"{", "block", "{");
    switch (self.nextToken()) {
        .atom => |atom| {
            if (std.mem.eql(u8, atom, "return")) {
                try block.append(alloc, .{ .return_statement = try self.parseExpression(alloc, 0.0) });
            }
        },
        else => |unexpected| {
            return self.unexpectedToken("block statement", "other", unexpected);
        },
    }
    try self.expect(self.nextToken(), .@"}", "block", "'}'");

    return block;
}

fn parseExpression(self: *Self, alloc: std.mem.Allocator, precedence: f32) anyerror!Node.Expression {
    var expr: Node.Expression = undefined;

    // write parse expression here.

    return expr;
}

/// Prints error message and always returns an error.
/// `environment` and `expected_token` are strings for the error message.
/// example: "function definition" and "function name" respectively yields:
/// "Unexpected token in function definition '<actual>' at <line>:<col>. Expected 'function_name'",
fn unexpectedToken(
    self: *const Self,
    environment: []const u8,
    expected_token: []const u8,
    actual: Lexer.Token,
) error{ NoSpaceLeft, UnexpectedToken } {
    var t_buf: [128]u8 = undefined;
    utils.print(
        "Unexpected token in {s} '{s}' at {}:{}. Expected {s}\n",
        .{
            environment,
            try actual.toString(&t_buf),
            self.input.source_map.items[self.pos].line,
            self.input.source_map.items[self.pos].col,
            expected_token,
        },
        .red,
    );
    return error.UnexpectedToken;
}

/// Returns active tag if active type of `actual` is the same as `expected`. Errors otherwise.
/// `environment` and `expected_token` are strings for the error message.
/// example: "function definition" and "function name" respectively yields
/// "Unexpected token in function definition '<bad_token>' at <line>:<col>. Expected 'function_name'",
fn expect(
    self: *const Self,
    actual: Lexer.Token,
    comptime expected: std.meta.Tag(Lexer.Token),
    comptime environment: []const u8,
    comptime expected_token: []const u8,
) !@FieldType(Lexer.Token, @tagName(expected)) {
    return if (std.meta.activeTag(actual) == expected)
        @field(actual, @tagName(expected))
    else
        self.unexpectedToken(environment, expected_token, actual);
}

/// Identical to `expect` but doesn't print error message.
fn expectSilent(
    _: *const Self,
    actual: Lexer.Token,
    comptime expected: std.meta.Tag(Lexer.Token),
) !@FieldType(Lexer.Token, @tagName(expected)) {
    return if (std.meta.activeTag(actual) == expected)
        @field(actual, @tagName(expected))
    else
        return error.UnexpectedToken;
}
