const pc = @import("../pc.zig");
const std = @import("std");
const CPUContext = pc.CPUContext;
const testing = std.testing;

pub const Register = @import("register.zig").Register;
pub const Instruction = @import("instruction.zig").Instruction;
pub const InstructionType = @import("instruction.zig").InstructionType;
pub const IndexMode = @import("instruction.zig").IndexMode;

const operand = @import("operand.zig");

pub const ParseErrors = error{
    UnknownInstruction,
    MismatchingOperandSizes,
};

pub fn parse(allocator: std.mem.Allocator, raw_code: []const u8) ![]Instruction {
    var instructions = std.ArrayList(Instruction).init(allocator);
    defer instructions.deinit();
    var it = std.mem.splitAny(u8, raw_code, "\r\n");

    while (it.next()) |raw_line| {
        const line_no_comment = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, ';') orelse raw_line.len];
        const line_lowercased = blk: {
            var buff = try allocator.alloc(u8, line_no_comment.len);
            @memcpy(buff, line_no_comment);
            for (0..buff.len) |i|
                buff[i] = std.ascii.toLower(buff[i]);
            break :blk buff;
        };
        defer allocator.free(line_lowercased);
        const instruction = std.mem.trim(u8, line_lowercased, &std.ascii.whitespace);

        try instructions.append(try parseInstruction(instruction));
    }

    const instruction_arr: []Instruction = try allocator.alloc(Instruction, instructions.items.len);
    @memcpy(instruction_arr, instructions.items);
    return instruction_arr;
}

pub fn parseInstruction(inst_raw: []const u8) !Instruction {
    const inst_type_end = (std.mem.indexOf(u8, inst_raw, " ") orelse inst_raw.len - 1);
    const inst_str_type = inst_raw[0..inst_type_end];
    // std.debug.print("inst_type: {s}\n", .{inst_str_type});
    const inst_type = InstructionType.fromString(inst_str_type);
    if (inst_type == null) return ParseErrors.UnknownInstruction;

    var it = std.mem.splitScalar(u8, inst_raw[inst_type_end + 1 ..], ',');
    const left_op_str = std.mem.trim(u8, it.next() orelse "", &std.ascii.whitespace);
    const right_op_str = std.mem.trim(u8, it.next() orelse "", &std.ascii.whitespace);

    var left_index_mode: IndexMode = .unknown;
    var right_index_mode: IndexMode = .unknown;

    const left_op = try operand.parseOperand(left_op_str, &left_index_mode) orelse return error.NoOperandFound;
    const right_op = try operand.parseOperand(right_op_str, &right_index_mode);

    const indexing_mode: IndexMode = blk: {
        if (left_index_mode != .unknown and right_index_mode != .unknown and left_index_mode != right_index_mode)
            return ParseErrors.MismatchingOperandSizes;

        if (left_index_mode == right_index_mode) {
            if (left_index_mode == .unknown)
                break :blk ._16bit;
            break :blk left_index_mode;
        }

        if (left_index_mode == ._8bit or right_index_mode == ._8bit)
            break :blk ._8bit;

        if (left_index_mode == ._16bit or right_index_mode == ._16bit)
            break :blk ._16bit;

        unreachable;
    };

    return Instruction{
        .inst = inst_type.?,
        .left_operand = left_op,
        .right_operand = right_op,
        .indexing_mode = indexing_mode,
    };
}

test "test parse instruction" {
    try testing.expectEqual(Instruction{
        .inst = .mov,
        .left_operand = .{ .reg = .{ ._16bit = .ax } },
        .right_operand = .{ .mem = .{ .base = .bx } },
        .indexing_mode = ._16bit,
    }, try parseInstruction("mov ax, [bx]"));

    try testing.expectEqual(Instruction{
        .inst = .add,
        .left_operand = .{ .reg = .{ ._8bit = .cl } },
        .right_operand = .{ .mem = .{ .index = .si, .displacement = operand.wrapIntImm(-4) } },
        .indexing_mode = ._8bit,
    }, try parseInstruction("add cl, [si - 4]"));

    try testing.expectEqual(Instruction{
        .inst = .mov,
        .left_operand = .{ .mem = .{ .base = .bp, .displacement = operand.wrapIntImm(-0x12), .ptr_type = .byte_ptr } },
        .right_operand = .{ .reg = .{ ._8bit = .dl } },
        .indexing_mode = ._8bit,
    }, try parseInstruction("mov [byte ptr bp-12h], dl"));

    try testing.expectEqual(Instruction{
        .inst = .xor,
        .left_operand = .{ .reg = .{ ._16bit = .cx } },
        .right_operand = .{ .imm = 0b10101010 },
        .indexing_mode = ._16bit,
    }, try parseInstruction("xor cx, 10101010b"));

    // NOTE: using multiple displacements is VERY BUGGY and should not be done.
    try testing.expectEqual(Instruction{
        .inst = .lea,
        .left_operand = .{ .reg = .{ ._16bit = .bx } },
        .right_operand = .{ .mem = .{ .base = .bp, .index = .si, .displacement = operand.wrapIntImm(0x8 - 2) } },
        .indexing_mode = ._16bit,
    }, try parseInstruction("lea bx, [bp + 8h + si-2d]"));
}
