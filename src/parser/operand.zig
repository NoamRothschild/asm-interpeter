const std = @import("std");
const testing = std.testing;
const register = @import("register.zig");
const RegisterIdentifier = register.RegisterIdentifier;
const IndexMode = @import("instruction.zig").IndexMode;
const RegisterIdentifier16bit = @import("register.zig").RegisterIdentifier16bit;

pub const Operand = union(enum) {
    imm: u16,
    reg: RegisterIdentifier,
    mem: MemoryExpr,
    unverified_label: []const u8, // a temporary value that will either be replaced with imm later or result in an err
};

const MemExprPtrType = enum { unknown, byte_ptr, word_ptr };
const byte_ptr_str = "byte ptr";
const word_ptr_str = "word ptr";
const base_registers = [_][]const u8{ "bx", "bp" };
const index_registers = [_][]const u8{ "si", "di" };
pub const MemoryExpr = struct {
    base: ?RegisterIdentifier16bit = null, // bx or bp
    index: ?RegisterIdentifier16bit = null, // si or di
    displacement: u16 = 0,
    ptr_type: MemExprPtrType = .unknown,
};

// TODO: OR the parse errors with all the possible error sets
pub const OperandParseErrors = error{
    NoOperandForString,
};

/// parses an operand.
/// returns `null` when raw_op.len == 0
/// fails if an operand was found, but was unable to be diagnosed, or
/// an error had occured while parsig after the operand type had been found.
pub fn parseOperand(allocator: std.mem.Allocator, raw_op: []const u8, mode: *IndexMode) !?Operand {
    if (raw_op.len == 0) return null;

    const might_reg = register.fromString(raw_op);
    if (might_reg) |reg| {
        switch (reg) {
            ._8bit => {
                mode.* = ._8bit;
            },
            ._16bit => {
                mode.* = ._16bit;
            },
        }
        return Operand{ .reg = reg };
    }

    // TODO: place label recognition over here

    const might_imm = try parseImmediate(raw_op);
    if (might_imm) |imm| {
        return Operand{ .imm = imm };
    }

    const might_mem_expr = try parseMemoryExpr(raw_op);
    if (might_mem_expr) |mem_expr| {
        if (mem_expr.ptr_type == .byte_ptr) {
            mode.* = ._8bit;
        } else if (mem_expr.ptr_type == .word_ptr) {
            mode.* = ._16bit;
        }
        return Operand{ .mem = mem_expr };
    }

    return Operand{ .unverified_label = try allocator.dupe(u8, raw_op) };
}

fn parseImmediate(imm: []const u8) !?u16 {
    var rvalue: isize = 0;
    if (imm.len == 0)
        return null;

    if (imm.len == 3 and imm[0] == imm[2] and imm[0] == '\'') {
        rvalue = imm[1];
    } else if (std.mem.startsWith(u8, imm, "0b")) {
        rvalue = try std.fmt.parseInt(isize, imm[2..], 2);
    } else if (std.mem.startsWith(u8, imm, "0x")) {
        rvalue = try std.fmt.parseInt(isize, imm[2..], 16);
    } else if ((imm[0] == '0' or imm[0] == '1') and imm[imm.len - 1] == 'b') {
        rvalue = try std.fmt.parseInt(isize, imm[0 .. imm.len - 1], 2);
    } else if (std.ascii.isHex(imm[0]) and imm[imm.len - 1] == 'h') {
        rvalue = try std.fmt.parseInt(isize, imm[0 .. imm.len - 1], 16);
    } else if ((std.ascii.isDigit(imm[0]) or imm[0] == '-') and imm[imm.len - 1] == 'd') {
        rvalue = try std.fmt.parseInt(isize, imm[0 .. imm.len - 1], 10);
    } else {
        rvalue = std.fmt.parseInt(isize, imm, 10) catch {
            return null;
        };
    }

    return @bitCast(@as(i16, @truncate(rvalue)));
}

fn parseMemoryExpr(expr: []const u8) !?MemoryExpr {
    if (expr[0] != '[' or expr[expr.len - 1] != ']') {
        return null;
    }
    var body = std.mem.trim(u8, expr, "[]" ++ std.ascii.whitespace);
    var out_expr = MemoryExpr{};

    if (std.mem.startsWith(u8, body, byte_ptr_str)) {
        out_expr.ptr_type = .byte_ptr;
        body = body[byte_ptr_str.len + 1 ..];
    } else if (std.mem.startsWith(u8, body, word_ptr_str)) {
        out_expr.ptr_type = .word_ptr;
        body = body[word_ptr_str.len + 1 ..];
    }

    var it = std.mem.tokenizeAny(u8, body, "+" ++ std.ascii.whitespace);
    outer: while (it.next()) |v| {
        // handle case of "identifier-immediate" with *no whitespace seperator*, ex: "bx-5"
        const value = blk: {
            if (v.len > 1) if (std.mem.indexOfScalar(u8, v, '-')) |sc| {
                out_expr.displacement -%= try parseImmediate(v[sc + 1 ..]) orelse return error.InvalidExpression;
                break :blk v[0..sc];
            };
            break :blk v;
        };

        inline for (base_registers) |reg| {
            if (std.mem.eql(u8, value, reg)) {
                out_expr.base = @field(RegisterIdentifier16bit, reg);
                continue :outer;
            }
        }

        inline for (index_registers) |reg| {
            if (std.mem.eql(u8, value, reg)) {
                out_expr.index = @field(RegisterIdentifier16bit, reg);
                continue :outer;
            }
        }

        // handle cases like "- 5"
        if (value.len == 1 and value[0] == '-') {
            const imm = it.next() orelse return error.InvalidExpression;
            out_expr.displacement -%= try parseImmediate(imm) orelse return error.InvalidExpression;
            continue :outer;
        }

        out_expr.displacement +%= try parseImmediate(value) orelse return error.InvalidEffectiveAdreess;
    }

    return out_expr;
}

pub fn wrapIntImm(v: i16) u16 {
    return @bitCast(v);
}

test "parse immediate" {
    try testing.expectEqual(@as(u16, 0x9876), try parseImmediate("0x9876"));

    try testing.expectEqual(@as(u16, 0b10110111), try parseImmediate("0b10110111"));

    try testing.expectEqual(@as(u16, 12345), try parseImmediate("12345d"));

    try testing.expectEqual(wrapIntImm(-12345), try parseImmediate("-12345d"));

    try testing.expectEqual(@as(u16, 0x77), try parseImmediate("77h"));

    try testing.expectEqual(@as(u16, 0xad), try parseImmediate("adh"));

    try testing.expectEqual(@as(u16, 0b10101), try parseImmediate("10101b"));

    try testing.expectEqual(wrapIntImm(-12345), try parseImmediate("-12345"));

    try testing.expectEqual(@as(u16, 65535), try parseImmediate("65535"));

    try testing.expectEqual(wrapIntImm(-32768), try parseImmediate("-32768"));
}

test "parse memory expression" {
    try testing.expectEqual(null, try parseMemoryExpr("bx"));

    try testing.expectEqual(MemoryExpr{}, try parseMemoryExpr("[]"));

    try testing.expectEqual(MemoryExpr{
        .index = .si,
        .ptr_type = .word_ptr,
    }, try parseMemoryExpr("[word ptr si]"));

    try testing.expectEqual(MemoryExpr{
        .displacement = 0,
    }, try parseMemoryExpr("[0]"));

    try testing.expectEqual(MemoryExpr{
        .base = .bx,
    }, try parseMemoryExpr("[bx ]"));

    try testing.expectEqual(MemoryExpr{
        .index = .si,
        .ptr_type = .byte_ptr,
    }, try parseMemoryExpr("[  byte ptr  si ]"));

    try testing.expectEqual(MemoryExpr{
        .index = .si,
        .base = .bx,
    }, try parseMemoryExpr("[si + bx]"));

    try testing.expectEqual(MemoryExpr{
        .index = .di,
        .base = .bp,
    }, try parseMemoryExpr("[di+bp]"));

    try testing.expectEqual(MemoryExpr{
        .index = .di,
        .displacement = 0b1001,
    }, try parseMemoryExpr("[di + 1001b]"));

    try testing.expectEqual(MemoryExpr{
        .base = .bx,
        .displacement = wrapIntImm(-3),
    }, try parseMemoryExpr("[bx-3]"));

    try testing.expectEqual(MemoryExpr{
        .index = .si,
        .displacement = wrapIntImm(-0x12),
    }, try parseMemoryExpr("[si - 0x12]"));
}
