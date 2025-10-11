const std = @import("std");

const LexerToken = @import("Lexer.zig").Token;
const BinaryOperator = @import("Lexer.zig").BinaryOperator;

pub const ParameterList = std.ArrayList(VariableSignature);
pub const ArgumentList = std.ArrayList(Expression);
pub const RootNode = std.ArrayList(TopLevelNode);
pub const Block = std.ArrayList(Statement);

pub const Expression = union(enum) {
    pub const Binary = struct {
        lhs: *const Expression,
        op: BinaryOperator,
        rhs: *const Expression,
    };

    pub const Member = struct {
        lhs: *const Expression,
        rhs: *const Expression,
    };

    pub const Call = struct {
        callee: *const Expression,
        args: ArgumentList,
    };

    bad_node,

    atom: []const u8,
    call: Call,
    member: Member,
    binary: Binary,
};

pub const TopLevelNode = union(enum) {
    bin_expr: Expression.Binary,
    func_def: FunctionDefinition,
};

pub const FunctionDefinition = struct {
    function_name: []const u8,
    params: ParameterList = .{},
    return_type: Type,
    body: Block,
};

const Statement = union(enum) {
    return_statement: Expression,
};

const VariableSignature = struct {
    param_name: []const u8,
    type: Type,
};

const Type = []const u8;

// const Type = struct {
//     type_atom: TypeAtom,
// };
//
// const TypeAtom = enum {
//     i32,
// };
