const std = @import("std");

pub const Type = union(enum) {
    pub const Function = struct {
        params: std.ArrayList(*const Type),
        return_type: *const Type,
    };

    fn CompoundType(T: enum { @"struct", @"enum", @"union" }) type {
        return struct {
            pub const MemberType = switch (T) {
                .@"struct", .@"union" => *const Type,
                .@"enum" => ?usize,
            };

            const Method = struct {
                inner_name: []const u8,
                params: std.ArrayList(*const Type),
                return_type: *const Type,
            };

            name: []const u8,
            members: *std.StringHashMap(MemberType),
            methods: *std.StringHashMap(Method),

            /// get member or method. returns `null` if no member or method is found with `name`.
            pub fn getProperty(self: *const CompoundType(T), name: []const u8) ?union(enum) {
                member: MemberType,
                method: Method,
            } {
                const member = self.members.get(name);
                const method = self.methods.get(name);

                return if (member) |m|
                    .{ .member = m }
                else if (method) |m|
                    .{ .method = m }
                else
                    null;
            }

            pub fn init(alloc: std.mem.Allocator, name: []const u8) !CompoundType(T) {
                const members = try alloc.create(std.StringHashMap(MemberType));
                members.* = .init(alloc);
                const methods = try alloc.create(std.StringHashMap(Method));
                methods.* = .init(alloc);
                return .{
                    .name = name,
                    .members = members,
                    .methods = methods,
                };
            }
        };
    }

    pub const Struct = CompoundType(.@"struct");
    pub const Union = CompoundType(.@"union");
    pub const Enum = CompoundType(.@"enum");

    pub const Reference = struct {
        inner: *const Type,
        is_mut: bool,
    };

    pub const Array = struct {
        inner: *const Type,
        /// if size is `null` type is an arraylist, else it's an array.
        /// if size is `_`, type is an array of inferred size.
        /// if size is a valid expression, type is an array of specified size.
        size: ?usize = null,
    };

    pub const ErrorUnion = struct {
        success: *const Type,
        @"error": ?*const Type = null,
    };

    i8,
    i16,
    i32,
    i64,

    u8,
    u16,
    u32,
    u64,

    f32,
    f64,

    bool,

    void,

    @"struct": Struct,
    @"enum": Enum,
    @"union": Union,
    optional: *const Type,
    reference: Reference,
    array: Array,
    error_union: ErrorUnion,
    function: Function,

    pub fn fromSymbol(symbol: []const u8) !Type {
        return if (std.mem.eql(u8, symbol, "i8"))
            .i8
        else if (std.mem.eql(u8, symbol, "i16"))
            .i16
        else if (std.mem.eql(u8, symbol, "i32"))
            .i32
        else if (std.mem.eql(u8, symbol, "i64"))
            .i64
        else if (std.mem.eql(u8, symbol, "u8"))
            .u8
        else if (std.mem.eql(u8, symbol, "u16"))
            .u16
        else if (std.mem.eql(u8, symbol, "u32"))
            .u32
        else if (std.mem.eql(u8, symbol, "u64"))
            .u64
        else if (std.mem.eql(u8, symbol, "f32"))
            .f32
        else if (std.mem.eql(u8, symbol, "f64"))
            .f64
        else if (std.mem.eql(u8, symbol, "void"))
            .void
        else if (std.mem.eql(u8, symbol, "bool"))
            .bool
        else
            error.TypeNotPrimitive;
    }
};
