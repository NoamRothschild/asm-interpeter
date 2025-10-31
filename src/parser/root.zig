const pc = @import("../pc.zig");
const std = @import("std");
const CPUContext = pc.CPUContext;
const testing = std.testing;

pub const Register = @import("register.zig").Register;
pub const Instruction = @import("instruction.zig").Instruction;
pub const InstructionType = @import("instruction.zig").InstructionType;
pub const IndexMode = @import("instruction.zig").IndexMode;
pub const LabelMap = @import("label.zig").LabelMap;

const operand = @import("operand.zig");

pub const ParseErrors = error{
    UnknownInstruction,
    MismatchingOperandSizes,
};

pub const ParseResult = struct {
    instructions: []Instruction,
    label_map: LabelMap,

    pub fn deinit(self: *ParseResult) void {
        self.label_map.allocator.free(self.instructions);

        var it = self.label_map.keyIterator();
        while (it.next()) |str|
            self.label_map.allocator.free(str.*);

        self.label_map.deinit();
    }
};

pub fn parse(allocator: std.mem.Allocator, raw_code: []const u8) !ParseResult {
    var label_map = LabelMap.init(allocator);
    var instructions = std.ArrayList(Instruction).init(allocator);
    defer instructions.deinit();
    errdefer {
        var it = label_map.keyIterator();
        while (it.next()) |str|
            allocator.free(str.*);
        label_map.deinit();
    }

    var it = std.mem.splitAny(u8, raw_code, "\r\n");

    while (it.next()) |raw_line| {
        const line_no_comment = raw_line[0 .. std.mem.indexOfScalar(u8, raw_line, ';') orelse raw_line.len];
        const line_lowercased: []const u8 = blk: {
            var buff = try allocator.alloc(u8, line_no_comment.len);
            @memcpy(buff, line_no_comment);
            for (0..buff.len) |i|
                buff[i] = std.ascii.toLower(buff[i]);
            break :blk buff;
        };
        defer allocator.free(line_lowercased);

        const might_label = std.mem.indexOfScalar(u8, line_lowercased, ':');
        if (might_label) |label_end| {
            const label_name = std.mem.trim(u8, line_lowercased[0..label_end], &std.ascii.whitespace);
            std.debug.print("found a label: {s}.\n", .{label_name});
            const followed_inst = std.mem.trim(u8, line_lowercased[label_end + 1 ..], &std.ascii.whitespace);

            try label_map.put(try allocator.dupe(u8, label_name), instructions.items.len);

            if (followed_inst.len != 0)
                try instructions.append(try parseInstruction(allocator, followed_inst));
        } else {
            const instruction = std.mem.trim(u8, line_lowercased, &std.ascii.whitespace);

            try instructions.append(try parseInstruction(allocator, instruction));
        }
    }
    try instructions.append(try parseInstruction(allocator, "hlt"));

    const instruction_arr: []Instruction = try allocator.alloc(Instruction, instructions.items.len);
    @memcpy(instruction_arr, instructions.items);
    errdefer allocator.free(instruction_arr);

    // TODO: must be cleaned up. perhaps moving some of the code here to label.zig would be fitting.
    var has_invalid_label: bool = false;
    for (instruction_arr) |*inst| {
        inline for (&[_]*?operand.Operand{ &inst.left_operand, &inst.right_operand }) |maybe_operand| {
            if (maybe_operand.* != null and maybe_operand.*.? == .unverified_label) {
                const unverified_label = maybe_operand.*.?.unverified_label;
                if (label_map.get(unverified_label)) |line| {
                    maybe_operand.* = .{ .imm = @truncate(line) };
                } else {
                    std.log.err("Tried to access an unknown label: {s}\n", .{unverified_label});
                    has_invalid_label = true;
                }
                allocator.free(unverified_label);
            }
        }
    }
    if (has_invalid_label)
        return error.UnknownLabel;

    return ParseResult{
        .instructions = instruction_arr,
        .label_map = label_map,
    };
}

pub fn parseInstruction(allocator: std.mem.Allocator, inst_raw: []const u8) !Instruction {
    const inst_type_end = (std.mem.indexOf(u8, inst_raw, " ") orelse inst_raw.len);
    const inst_str_type = inst_raw[0..inst_type_end];
    // std.debug.print("inst_type: {s}\n", .{inst_str_type});
    const might_inst_type = InstructionType.fromString(inst_str_type);
    if (might_inst_type == null) return ParseErrors.UnknownInstruction;
    const inst_type = might_inst_type.?;

    if (inst_type_end == inst_raw.len) {
        return Instruction{
            .inst = inst_type,
            .left_operand = null,
            .right_operand = null,
            .indexing_mode = .unknown,
        };
    }

    var it = std.mem.splitScalar(u8, inst_raw[inst_type_end + 1 ..], ',');
    const left_op_str = std.mem.trim(u8, it.next() orelse "", &std.ascii.whitespace);
    const right_op_str = std.mem.trim(u8, it.next() orelse "", &std.ascii.whitespace);

    var left_index_mode: IndexMode = .unknown;
    var right_index_mode: IndexMode = .unknown;

    const left_op = try operand.parseOperand(allocator, left_op_str, &left_index_mode);
    const right_op = try operand.parseOperand(allocator, right_op_str, &right_index_mode);

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
        .inst = inst_type,
        .left_operand = left_op,
        .right_operand = right_op,
        .indexing_mode = indexing_mode,
    };
}

test "test parse instruction" {
    const allocator = testing.allocator;

    try testing.expectEqual(Instruction{
        .inst = .mov,
        .left_operand = .{ .reg = .{ ._16bit = .ax } },
        .right_operand = .{ .mem = .{ .base = .bx } },
        .indexing_mode = ._16bit,
    }, try parseInstruction(allocator, "mov ax, [bx]"));

    try testing.expectEqual(Instruction{
        .inst = .add,
        .left_operand = .{ .reg = .{ ._8bit = .cl } },
        .right_operand = .{ .mem = .{ .index = .si, .displacement = operand.wrapIntImm(-4) } },
        .indexing_mode = ._8bit,
    }, try parseInstruction(allocator, "add cl, [si - 4]"));

    try testing.expectEqual(Instruction{
        .inst = .mov,
        .left_operand = .{ .mem = .{ .base = .bp, .displacement = operand.wrapIntImm(-0x12), .ptr_type = .byte_ptr } },
        .right_operand = .{ .reg = .{ ._8bit = .dl } },
        .indexing_mode = ._8bit,
    }, try parseInstruction(allocator, "mov [byte ptr bp-12h], dl"));

    try testing.expectEqual(Instruction{
        .inst = .xor,
        .left_operand = .{ .reg = .{ ._16bit = .cx } },
        .right_operand = .{ .imm = 0b10101010 },
        .indexing_mode = ._16bit,
    }, try parseInstruction(allocator, "xor cx, 10101010b"));

    // NOTE: using multiple displacements is VERY BUGGY and should not be done.
    try testing.expectEqual(Instruction{
        .inst = .lea,
        .left_operand = .{ .reg = .{ ._16bit = .bx } },
        .right_operand = .{ .mem = .{ .base = .bp, .index = .si, .displacement = operand.wrapIntImm(0x8 - 2) } },
        .indexing_mode = ._16bit,
    }, try parseInstruction(allocator, "lea bx, [bp + 8h + si-2d]"));

    try testing.expectEqual(Instruction{
        .inst = .hlt,
        .left_operand = null,
        .right_operand = null,
        .indexing_mode = .unknown,
    }, try parseInstruction(allocator, "hlt"));
}
