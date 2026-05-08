const std = @import("std");
const utils = @import("utils");
const ast = @import("ast");

const compiler = @import("compiler.zig");
const errors = @import("errors.zig");
const Type = @import("type.zig").Type;
const Value = @import("value.zig").Value;
const Symbol = compiler.Symbol;
const Compiler = compiler.Compiler;

const Module = @This();

const Scope = struct {
    symbols: std.StringHashMap(*Symbol),
    defers: std.ArrayList(ast.Statement),
};

name: []const u8,
source_map: []const utils.Position,
scopes: std.ArrayList(*Scope) = .empty,
instantiations: std.StringHashMap(Type),

fn registerBuiltin(
    self: *Module,
    alloc: std.mem.Allocator,
    comptime name: []const u8,
    comptime inner_name: []const u8,
    value: Value,
) !void {
    _ = try self.register(alloc, .{
        .name = name,
        .inner_name = inner_name,
        .type = .type,
        .binding = .@"const",
        .value = value,
        .free_name = false,
        .free_inner_name = false,
        .free_type = true,
    });
}

/// Caller owns returned pointer
pub fn init(alloc: std.mem.Allocator, name: []const u8, source_map: []const utils.Position) !*Module {
    const self = try alloc.create(Module);
    errdefer alloc.destroy(self);

    self.* = .{
        .name = try alloc.dupe(u8, name),
        .source_map = source_map,
        .instantiations = .init(alloc),
        .scopes = .empty,
    };
    errdefer {
        alloc.free(self.name);
        self.instantiations.deinit();
    }

    try self.pushScope(alloc);
    errdefer self.deinit(alloc);

    try self.registerBuiltin(alloc, "i8", "int8_t", .{ .type = .i8 });
    try self.registerBuiltin(alloc, "i16", "int16_t", .{ .type = .i16 });
    try self.registerBuiltin(alloc, "i32", "int32_t", .{ .type = .i32 });
    try self.registerBuiltin(alloc, "i64", "int64_t", .{ .type = .i64 });
    try self.registerBuiltin(alloc, "isize", "ptrdiff_t", .{ .type = .isize });

    try self.registerBuiltin(alloc, "u8", "uint8_t", .{ .type = .u8 });
    try self.registerBuiltin(alloc, "u16", "uint16_t", .{ .type = .u16 });
    try self.registerBuiltin(alloc, "u32", "uint32_t", .{ .type = .u32 });
    try self.registerBuiltin(alloc, "u64", "uint64_t", .{ .type = .u64 });
    try self.registerBuiltin(alloc, "usize", "size_t", .{ .type = .usize });

    try self.registerBuiltin(alloc, "f32", "float", .{ .type = .f32 });
    try self.registerBuiltin(alloc, "f64", "double", .{ .type = .f64 });

    try self.registerBuiltin(alloc, "void", "void", .{ .type = .void });
    try self.registerBuiltin(alloc, "bool", "bool", .{ .type = .bool });
    try self.registerBuiltin(alloc, "type", "type_type", .{ .type = .type });

    try self.registerBuiltin(alloc, "c_char", "char", .{ .type = .c_char });
    try self.registerBuiltin(alloc, "c_short", "short", .{ .type = .c_short });
    try self.registerBuiltin(alloc, "c_int", "int", .{ .type = .c_int });
    try self.registerBuiltin(alloc, "c_long", "long", .{ .type = .c_long });

    try self.registerBuiltin(alloc, "c_uchar", "unsigned char", .{ .type = .c_uchar });
    try self.registerBuiltin(alloc, "c_ushort", "unsigned short", .{ .type = .c_ushort });
    try self.registerBuiltin(alloc, "c_uint", "unsigned int", .{ .type = .c_uint });
    try self.registerBuiltin(alloc, "c_ulong", "unsigned long", .{ .type = .c_ulong });

    try self.registerBuiltin(alloc, "c_float", "float", .{ .type = .c_float });
    try self.registerBuiltin(alloc, "c_double", "double", .{ .type = .c_double });

    try self.registerBuiltin(alloc, "c_null", "NULL", .{
        .type = .{
            .reference = .{
                .is_mut = false,
                .inner = try .clonePtr(.void, alloc),
            },
        },
    });
    try self.registerBuiltin(alloc, "nil", "nil", .nil);
    try self.registerBuiltin(alloc, "undefined", "undefined", .undefined);

    _ = try self.register(alloc, .{
        .name = "cast",
        .inner_name = "cast",
        .type = .{ .template = .{ .kind = .builtin_cast, .module = self } },
        .binding = .@"const",
        .free_name = false,
        .free_inner_name = false,
        .free_type = false,
    });

    _ = try self.register(alloc, .{
        .name = "sizeof",
        .inner_name = "sizeof",
        .type = .{ .template = .{ .kind = .builtin_sizeof, .module = self } },
        .binding = .@"const",
        .free_name = false,
        .free_inner_name = false,
        .free_type = false,
    });

    return self;
}

pub fn deinit(self: *Module, alloc: std.mem.Allocator) void {
    for (self.scopes.items) |_| self.popScope(alloc);
    self.scopes.deinit(alloc);

    var it = self.instantiations.iterator();
    while (it.next()) |entry| {
        alloc.free(entry.key_ptr.*);
        entry.value_ptr.deinit(alloc);
    }
    self.instantiations.deinit();
    alloc.free(self.name);
    if (self.source_map.len > 0) alloc.free(self.source_map[0].path);
    alloc.free(self.source_map);
    alloc.destroy(self);
}

pub fn registerAtTopLevel(self: *Module, alloc: std.mem.Allocator, symbol: Symbol) !*Symbol {
    var new_symbol = symbol;
    if (!new_symbol.free_name) {
        const old_name = new_symbol.name;
        new_symbol.name = try alloc.dupe(u8, old_name);
        new_symbol.free_name = true;
    }
    if (!new_symbol.free_inner_name) {
        const old_inner = new_symbol.inner_name;
        new_symbol.inner_name = try alloc.dupe(u8, old_inner);
        new_symbol.free_inner_name = true;
    }
    const symbol_ptr = try alloc.create(Symbol);
    errdefer alloc.destroy(symbol_ptr);
    symbol_ptr.* = new_symbol;

    const res = try self.scopes.items[0].symbols.getOrPut(symbol_ptr.name);
    if (res.found_existing) {
        const existing = res.value_ptr.*;
        existing.deinit(alloc);
        existing.* = symbol_ptr.*;
        res.key_ptr.* = existing.name;
        alloc.destroy(symbol_ptr);
        return existing;
    } else {
        res.value_ptr.* = symbol_ptr;
        return symbol_ptr;
    }
}

pub fn register(self: *Module, alloc: std.mem.Allocator, symbol: Symbol) !*Symbol {
    var new_symbol = symbol;
    if (!new_symbol.free_name) {
        const old_name = new_symbol.name;
        new_symbol.name = try alloc.dupe(u8, old_name);
        new_symbol.free_name = true;
    }
    if (!new_symbol.free_inner_name) {
        const old_inner = new_symbol.inner_name;
        new_symbol.inner_name = try alloc.dupe(u8, old_inner);
        new_symbol.free_inner_name = true;
    }
    const symbol_ptr = try alloc.create(Symbol);
    errdefer alloc.destroy(symbol_ptr);
    symbol_ptr.* = new_symbol;

    const res = try self.scopes.getLast().symbols.getOrPut(symbol_ptr.name);
    if (res.found_existing) {
        const existing = res.value_ptr.*;
        existing.deinit(alloc);
        existing.* = symbol_ptr.*;
        res.key_ptr.* = existing.name;
        alloc.destroy(symbol_ptr);
        return existing;
    } else {
        res.value_ptr.* = symbol_ptr;
        return symbol_ptr;
    }
}

pub fn registerPtrAtTopLevel(self: *Module, alloc: std.mem.Allocator, symbol: *Symbol) !*Symbol {
    if (!symbol.free_name) {
        const old_name = symbol.name;
        symbol.name = try alloc.dupe(u8, old_name);
        symbol.free_name = true;
    }
    if (!symbol.free_inner_name) {
        const old_inner = symbol.inner_name;
        symbol.inner_name = try alloc.dupe(u8, old_inner);
        symbol.free_inner_name = true;
    }

    const res = try self.scopes.items[0].symbols.getOrPut(symbol.name);
    if (res.found_existing) {
        const existing = res.value_ptr.*;
        existing.deinit(alloc);
        existing.* = symbol.*;
        res.key_ptr.* = existing.name;
        alloc.destroy(symbol);
        return existing;
    } else {
        res.value_ptr.* = symbol;
        return symbol;
    }
}

pub fn registerPtr(self: *Module, alloc: std.mem.Allocator, symbol: *Symbol) !*Symbol {
    if (!symbol.free_name) {
        const old_name = symbol.name;
        symbol.name = try alloc.dupe(u8, old_name);
        symbol.free_name = true;
    }
    if (!symbol.free_inner_name) {
        const old_inner = symbol.inner_name;
        symbol.inner_name = try alloc.dupe(u8, old_inner);
        symbol.free_inner_name = true;
    }

    const res = try self.scopes.getLast().symbols.getOrPut(symbol.name);
    if (res.found_existing) {
        const existing = res.value_ptr.*;
        existing.deinit(alloc);
        existing.* = symbol.*;
        res.key_ptr.* = existing.name;
        alloc.destroy(symbol);
        return existing;
    } else {
        res.value_ptr.* = symbol;
        return symbol;
    }
}

pub fn pushScope(self: *Module, alloc: std.mem.Allocator) !void {
    const new_scope = try alloc.create(Scope);
    errdefer alloc.destroy(new_scope);
    new_scope.defers = .empty;
    new_scope.symbols = .init(alloc);
    try self.scopes.append(alloc, new_scope);
}

pub fn popScope(self: *Module, alloc: std.mem.Allocator) void {
    const last_scope = self.scopes.pop().?;
    var it = last_scope.symbols.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit(alloc);
        alloc.destroy(entry.value_ptr.*);
    }
    last_scope.symbols.deinit();
    last_scope.defers.deinit(alloc);
    alloc.destroy(last_scope);
}

pub fn getSymbol(self: *Module, name: []const u8) ?*Symbol {
    var it = std.mem.reverseIterator(self.scopes.items);
    while (it.next()) |scope| {
        if (scope.symbols.get(name)) |symbol| return symbol;
    }

    return null;
}

pub fn findSymbolByType(self: *Module, t: Type) ?*Symbol {
    for (self.scopes.items) |scope| {
        var it = scope.symbols.iterator();
        while (it.next()) |entry| {
            const symbol = entry.value_ptr.*;
            if (symbol.type == .type and symbol.value != null and
                symbol.value.? == .type and symbol.value.?.type.eql(t))
                return symbol;
        }
    }

    return null;
}

pub fn getExpressionMutability(
    self: *Module,
    alloc: std.mem.Allocator,
    io: std.Io,
    expr: *const ast.Expression,
    c: *Compiler,
) errors.Error!bool {
    return switch (expr.*) {
        .ident => |ident| b: {
            const symbol = self.getSymbol(ident.payload) orelse
                return errors.unknownSymbol(io, ident.payload, self.source_map[ident.pos]);
            break :b symbol.binding == .let_mut;
        },
        .reference => |ref| try self.getExpressionMutability(alloc, io, ref.inner, c),
        .dereference => |deref| b: {
            const t = try Type.infer(alloc, io, deref.parent, c, self);
            defer t.deinit(alloc);

            break :b switch (t) {
                .reference => |ref| ref.is_mut,
                else => errors.cannotDereference(io, t, self.source_map[deref.pos]),
            };
        },
        .member => |member| b: {
            const parent_t = try Type.infer(alloc, io, member.parent, c, self);
            defer parent_t.deinit(alloc);

            break :b switch (parent_t) {
                inline .@"struct", .@"union" => try self.getExpressionMutability(alloc, io, member.parent, c),
                .@"enum" => false,
                .slice => if (std.mem.eql(u8, member.member_name, "ptr") or
                    std.mem.eql(u8, member.member_name, "len"))
                    true
                else
                    errors.badMemberAccessSlice(io, parent_t, member.member_name, self.source_map[member.pos]),
                else => errors.badMemberAccess(io, parent_t, member.member_name, self.source_map[member.pos]),
            };
        },
        .index => |index| {
            const lhs_t: Type = try .infer(alloc, io, index.lhs, c, self);
            defer lhs_t.deinit(alloc);

            return switch (lhs_t) {
                .slice => |slice| slice.is_mut,
                .array => self.getExpressionMutability(alloc, io, index.lhs, c),
                else => errors.cannotIndex(io, lhs_t, self.source_map[index.pos]),
            };
        },
        else => false,
    };
}

pub fn getSymbolFromExpression(
    self: *Module,
    alloc: std.mem.Allocator,
    io: std.Io,
    expr: *const ast.Expression,
    c: *Compiler,
) ?*Symbol {
    return switch (expr.*) {
        .ident => |ident| self.getSymbol(ident.payload),
        .type => |t| switch (t.payload) {
            .symbol => |symbol| self.getSymbol(symbol.inner),
            else => null,
        },
        .generic => |generic| {
            const lhs_t = Type.infer(alloc, io, generic.lhs, c, self) catch return null;
            defer lhs_t.deinit(alloc);

            if (lhs_t != .template) return null;

            const template = lhs_t.template;
            const template_name = switch (template.kind) {
                .builtin_cast => "cast",
                .builtin_sizeof => "sizeof",
                inline else => |d| d.name,
            };

            const mangled_name = Type.getMangledName(alloc, io, template_name, generic.arguments, c, self) catch return null;
            defer alloc.free(mangled_name);

            return self.getSymbol(mangled_name);
        },
        else => null,
    };
}
