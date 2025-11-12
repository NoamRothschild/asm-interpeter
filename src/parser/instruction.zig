const std = @import("std");
const operand = @import("operand.zig");
const testing = std.testing;

pub const InstructionType = enum {
    mov,
    lea,
    add,
    sub,
    @"and",
    @"or",
    xor,
    not,
    inc,
    dec,
    neg,
    cmp,
    @"test",
    shl,
    shr,
    sal,
    sar,
    rol,
    ror,
    rcl,
    rcr,
    jmp,
    je,
    jne,
    jg,
    jl,
    ja,
    jb,
    jge,
    jle,
    jae,
    jbe,
    jc,
    jnc,
    jz,
    jnz,
    jnle,
    jnge,
    jnl,
    jng,
    jcxz,
    jnbe,
    jnae,
    hlt,
    loop,

    const self = @This();
    pub fn fromString(mnemonic: []const u8) ?self {
        inline for (std.meta.fields(self)) |field| {
            if (std.mem.eql(u8, mnemonic, field.name)) {
                return @field(self, field.name);
            }
        }
        return null;
    }
};

pub const Instruction = struct {
    inst: InstructionType,
    left_operand: ?operand.Operand,
    right_operand: ?operand.Operand,
    indexing_mode: IndexMode,
};

pub const IndexMode = enum {
    _8bit,
    _16bit,
    unknown,
};

test "instruction type from string" {
    const field = InstructionType.fromString("and").?;
    try testing.expectEqual(@as(?InstructionType, .@"and"), field);

    const field2 = InstructionType.fromString("rcr").?;
    try testing.expectEqual(@as(?InstructionType, .rcr), field2);
}
