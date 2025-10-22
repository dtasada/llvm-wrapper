const std = @import("std");
const utils = @import("utils.zig");

const Lexer = @import("Lexer.zig");

const ast = @import("ast.zig");

const Self = @This();

const StatementHandler = *const fn (*Self) ParserError!ast.Statement;
const NudHandler = *const fn (*Self) ParserError!ast.Expression;
const LedHandler = *const fn (*Self, ast.Expression, BindingPower) ParserError!ast.Expression;

const StatementLookup = std.AutoHashMap(Lexer.TokenKind, StatementHandler);
const NudLookup = std.AutoHashMap(Lexer.TokenKind, NudHandler);
const LedLookup = std.AutoHashMap(Lexer.TokenKind, LedHandler);
const BpLookup = std.AutoHashMap(Lexer.TokenKind, BindingPower);

/// Binding power. please keep order of enum
const BindingPower = enum {
    default_bp,
    comma,
    assignment,
    logical,
    relational,
    additive,
    multiplicative,
    unary,
    call,
    member,
    primary,
};

const ParserError = error{
    UnexpectedToken,
    NoSpaceLeft,
    HandlerDoesNotExist,
};

pos: usize,
input: *const Lexer,
bp_lookup: BpLookup,
nud_lookup: NudLookup,
led_lookup: LedLookup,
statement_lookup: StatementLookup,
// errors: std.ArrayList(ParserError) = .{},

pub fn init(input: *const Lexer, alloc: std.mem.Allocator) !Self {
    var self = Self{
        .pos = 0,
        .input = input,
        .bp_lookup = .init(alloc),
        .nud_lookup = .init(alloc),
        .led_lookup = .init(alloc),
        .statement_lookup = .init(alloc),
    };

    // logical
    try self.led(Lexer.Token.@"and", .logical, parseBinaryExpression);
    try self.led(Lexer.Token.@"or", .logical, parseBinaryExpression);
    try self.led(Lexer.Token.dot_dot, .logical, parseBinaryExpression);

    // relational
    try self.led(Lexer.Token.less, .relational, parseBinaryExpression);
    try self.led(Lexer.Token.less_equals, .relational, parseBinaryExpression);
    try self.led(Lexer.Token.greater, .relational, parseBinaryExpression);
    try self.led(Lexer.Token.greater_equals, .relational, parseBinaryExpression);
    try self.led(Lexer.Token.equals_equals, .relational, parseBinaryExpression);
    try self.led(Lexer.Token.bang_equals, .relational, parseBinaryExpression);

    // additive & multiplicative
    try self.led(Lexer.Token.plus, .additive, parseBinaryExpression);
    try self.led(Lexer.Token.dash, .additive, parseBinaryExpression);
    try self.led(Lexer.Token.asterisk, .multiplicative, parseBinaryExpression);
    try self.led(Lexer.Token.slash, .multiplicative, parseBinaryExpression);
    try self.led(Lexer.Token.percent, .multiplicative, parseBinaryExpression);

    // literals & symbols
    try self.nud(Lexer.Token.int, parsePrimaryExpression);
    try self.nud(Lexer.Token.float, parsePrimaryExpression);
    try self.nud(Lexer.Token.ident, parsePrimaryExpression);
    try self.nud(Lexer.Token.string, parsePrimaryExpression);

    return self;
}

pub fn deinit(self: *Self) void {
    self.bp_lookup.deinit();
    self.nud_lookup.deinit();
    self.led_lookup.deinit();
    self.statement_lookup.deinit();
}

/// Returns root node of the AST
pub fn getAst(self: *Self, alloc: std.mem.Allocator) !ast.RootNode {
    var root = ast.RootNode{};

    while (std.meta.activeTag(self.currentToken()) != Lexer.Token.eof)
        try root.append(alloc, try self.parseStatement());

    return root;
}

/// Consumes current token and then increases position.
inline fn advance(self: *Self) Lexer.Token {
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

inline fn currentTokenKind(self: *const Self) Lexer.TokenKind {
    return std.meta.activeTag(self.currentToken());
}

/// Consumes token and returns next one.
inline fn nextToken(self: *Self) Lexer.Token {
    self.pos += 1;
    return self.currentToken();
}

/// Skips a token (self.pos+=2) and returns token at new position.
inline fn skipToken(self: *Self) Lexer.Token {
    self.pos += 2;
    return self.currentToken();
}

/// parses parameters and returns `!Node.ParameterList`. Caller is responsible for cleanup.
fn parseParameters(self: *Self, alloc: std.mem.Allocator) !ast.ParameterList {
    var params = ast.ParameterList{};

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

// fn parseArguments(self: *Self, alloc: std.mem.Allocator) !ast.ArgumentList {
//     var args = ast.ArgumentList{};
//
//     try self.expect(self.nextToken(), .@"(", "argument list", "'('");
//
//     // `self.expectSilent(self.nextToken(), .@",")` consumes a token, so if one
//     // was wasted attempting to parse a comma, keep that in mind when attempting
//     // to parse the closing parenthesis.
//     var compensate_for_comma = false;
//
//     while (true) {
//         const arg = try self.parseExpression(alloc, 0.0);
//         try args.append(alloc, arg);
//
//         // look for a comma, else a closing parenthesis
//         self.expectSilent(self.nextToken(), .@",") catch {
//             compensate_for_comma = true;
//             break;
//         };
//     }
//
//     try self.expect(
//         if (compensate_for_comma)
//             self.currentToken()
//         else
//             self.nextToken(),
//         .@")",
//         "argument list",
//         "')'",
//     );
//
//     return args;
// }
//
// fn parseBlock(self: *Self, alloc: std.mem.Allocator) !ast.Block {
//     var block = ast.Block{};
//
//     try self.expect(self.nextToken(), .@"{", "block", "{");
//     switch (self.nextToken()) {
//         .atom => |atom| {
//             if (std.mem.eql(u8, atom, "return")) {
//                 try block.append(alloc, .{ .return_statement = try self.parseExpression(alloc, 0.0) });
//             }
//         },
//         else => |unexpected| {
//             return self.unexpectedToken("block statement", "other", unexpected);
//         },
//     }
//     try self.expect(self.nextToken(), .@"}", "block", "'}'");
//
//     return block;
// }

fn parseStatement(self: *Self) ParserError!ast.Statement {
    if (self.statement_lookup.get(self.currentTokenKind())) |statement_fn| {
        return statement_fn(self);
    }

    const expression = try self.parseExpression(.default_bp);
    try self.expect(self.currentToken(), Lexer.Token.semicolon, "statement", ";");

    return .{ .expression = expression };
}

fn parsePrimaryExpression(self: *Self) !ast.Expression {
    return switch (self.advance()) {
        .int => |int| .{ .uint = int },
        .float => |float| .{ .float = float },
        .ident => |atom| .{ .ident = atom },
        .string => |string| .{ .string = string },
        else => |other| self.unexpectedToken("primary expression", "int, float, atom", other),
    };
}

fn parseBinaryExpression(self: *Self, lhs: ast.Expression, bp: BindingPower) ParserError!ast.Expression {
    const op = ast.BinaryOperator.fromLexerToken(self.advance());
    const rhs = try self.parseExpression(bp);

    return .{
        .binary = &.{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        },
    };
}

fn parseExpression(self: *Self, bp: BindingPower) ParserError!ast.Expression {
    // first parse the NUD
    var token_kind = self.currentTokenKind();
    const nud_fn = self.nud_lookup.get(token_kind) orelse
        return error.HandlerDoesNotExist;

    var left = try nud_fn(self);

    // while we have a led and (current bp < bp of current token)
    // continue parsing lhs
    if (self.bp_lookup.get(self.currentTokenKind())) |current_bp| {
        while (@intFromEnum(current_bp) > @intFromEnum(bp)) {
            token_kind = self.currentTokenKind();

            const led_fn = self.led_lookup.get(token_kind) orelse
                return error.HandlerDoesNotExist;

            left = try led_fn(self, left, bp);
        }
    } else return error.HandlerDoesNotExist;

    return left;
}

/// A token which has a NUD handler means it expects nothing to its left
/// Common examples of this type of token are prefix & unary expressions.
fn nud(self: *Self, kind: Lexer.TokenKind, nud_fn: NudHandler) !void {
    try self.bp_lookup.put(kind, .primary);
    try self.nud_lookup.put(kind, nud_fn);
}

/// Tokens which have an LED expect to be between or after some other expression
/// to their left. Examples of this type of handler include binary expressions and
/// all infix expressions. Postfix expressions also fall under the LED handler.
fn led(self: *Self, kind: Lexer.TokenKind, bp: BindingPower, led_fn: LedHandler) !void {
    try self.bp_lookup.put(kind, bp);
    try self.led_lookup.put(kind, led_fn);
}

fn statement(self: *Self, kind: Lexer.TokenKind, statment_fn: StatementHandler) !void {
    try self.bp_lookup.put(kind, .default_bp);
    try self.statement_lookup.put(kind, statment_fn);
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
    utils.print(
        "Unexpected token in {s} '{f}' at {}:{}. Expected {s}\n",
        .{
            environment,
            actual,
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
    comptime expected: Lexer.TokenKind,
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
    comptime expected: Lexer.TokenKind,
) !@FieldType(Lexer.Token, @tagName(expected)) {
    return if (std.meta.activeTag(actual) == expected)
        @field(actual, @tagName(expected))
    else
        return error.UnexpectedToken;
}
