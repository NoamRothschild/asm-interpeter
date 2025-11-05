const std = @import("std");

const Context = @import("context.zig").Context;
const Register = @import("register.zig").Register;
const Instruction = @import("../parser/instruction.zig").Instruction;
const InstructionType = @import("../parser/instruction.zig").InstructionType;
const Operand = @import("../parser/operand.zig").Operand;
const RegisterIdentifier = @import("../parser/register.zig").RegisterIdentifier;
const BaseRegister = @import("../parser/register.zig").BaseRegister;
const ByteSelector = @import("../parser/register.zig").ByteSelector;
const valueOf = @import("../parser/operand.zig").valueOf;

pub fn executeInstruction(ctx: *Context) !void {
    defer ctx.*.ip +%= 1;
    const inst = ctx.instructions[ctx.ip];
    var exit: bool = true;

    // instructions with no operands:
    switch (inst.inst) {
        .hlt => ctx.*.ip -%= 1,
        else => exit = false,
    }
    if (exit) return;
    exit = true;

    // instructions with only left operand:
    const lhs = inst.left_operand orelse unreachable;
    switch (inst.inst) {
        .inc => {
            const lval = valueOf(lhs, ctx);
            const res = lval +% 1;
            store(ctx, lhs, res);
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            // Overflow: (positive + 1 = negative) or (0xFFFF + 1 = 0)
            const lval_signed = @as(i16, @bitCast(lval));
            ctx.flags.o = (lval_signed == 0x7FFF); // Max positive -> becomes negative
        },
        .dec => {
            const lval = valueOf(lhs, ctx);
            const res = lval -% 1;
            store(ctx, lhs, res);
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            // Overflow: (negative - 1 = positive) or (0x8000 - 1 = 0x7FFF)
            const lval_signed = @as(i16, @bitCast(lval));
            ctx.flags.o = (lval_signed == -32768); // Min negative -> becomes positive
        },
        .not => {
            const res = ~valueOf(lhs, ctx);
            store(ctx, lhs, res);
        },
        .neg => {
            const val = valueOf(lhs, ctx);
            const res = 0 -% val;
            store(ctx, lhs, res);
            ctx.flags.c = val != 0;
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            ctx.flags.o = val == 0x8000;
        },
        .jmp, .je, .jne, .jg, .jl, .ja, .jb, .jge, .jle, .jae, .jbe, .jc, .jnc, .jz, .jnz, .jcxz, .jnbe, .jnae => {
            // Jump instructions - check condition and jump if true
            if (shouldJump(ctx, inst.inst)) {
                const target_addr = valueOf(lhs, ctx);
                ctx.*.ip = target_addr;
                // Don't increment IP after jump
                ctx.*.ip -%= 1; // undo the defer increment
            }
        },
        else => exit = false,
    }
    if (exit) return;
    exit = true;

    // instructions with both operands:
    const rhs = inst.right_operand orelse unreachable;
    switch (inst.inst) {
        .mov => store(ctx, lhs, valueOf(rhs, ctx)),
        .lea => {
            // Load Effective Address - only works with memory operands
            try assert(rhs == .mem);
            const mem_expr = rhs.mem;
            const addr = mem_expr.finalAddr(ctx);
            store(ctx, lhs, addr);
        },
        .@"and" => {
            const res = valueOf(lhs, ctx) & valueOf(rhs, ctx);
            store(ctx, lhs, res);
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            ctx.flags.c = false;
            ctx.flags.o = false;
        },
        .@"or" => {
            const res = valueOf(lhs, ctx) | valueOf(rhs, ctx);
            store(ctx, lhs, res);
            ctx.flags.c = false;
            ctx.flags.o = false;
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
        },
        .xor => {
            const res = valueOf(lhs, ctx) ^ valueOf(rhs, ctx);
            store(ctx, lhs, res);
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            ctx.flags.c = false;
            ctx.flags.o = false;
        },
        .add => {
            const lval = valueOf(lhs, ctx);
            const rval = valueOf(rhs, ctx);
            const res = lval +% rval;
            store(ctx, lhs, res);
            ctx.flags.c = res < lval; // unsigned overflow
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            // Signed overflow: (positive + positive = negative) or (negative + negative = positive)
            const lval_signed = @as(i16, @bitCast(lval));
            const rval_signed = @as(i16, @bitCast(rval));
            const res_signed = lval_signed + rval_signed;
            ctx.flags.o = (lval_signed > 0 and rval_signed > 0 and res_signed < 0) or
                (lval_signed < 0 and rval_signed < 0 and res_signed > 0);
        },
        .sub => {
            const lval = valueOf(lhs, ctx);
            const rval = valueOf(rhs, ctx);
            const res = lval -% rval;
            store(ctx, lhs, res);
            ctx.flags.c = lval < rval; // unsigned underflow
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            // Signed overflow: (positive - negative = negative) or (negative - positive = positive)
            const lval_signed = @as(i16, @bitCast(lval));
            const rval_signed = @as(i16, @bitCast(rval));
            const res_signed = lval_signed - rval_signed;
            ctx.flags.o = (lval_signed > 0 and rval_signed < 0 and res_signed < 0) or
                (lval_signed < 0 and rval_signed > 0 and res_signed > 0);
        },
        .cmp => {
            // Compare - sets flags without storing result
            const lval = valueOf(lhs, ctx);
            const rval = valueOf(rhs, ctx);
            const res = lval -% rval;
            ctx.flags.c = lval < rval;
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            const lval_signed = @as(i16, @bitCast(lval));
            const rval_signed = @as(i16, @bitCast(rval));
            const res_signed = lval_signed - rval_signed;
            ctx.flags.o = (lval_signed > 0 and rval_signed < 0 and res_signed < 0) or
                (lval_signed < 0 and rval_signed > 0 and res_signed > 0);
        },
        .@"test" => {
            // Test - bitwise AND without storing result
            const res = valueOf(lhs, ctx) & valueOf(rhs, ctx);
            ctx.flags.z = res == 0;
            ctx.flags.s = (res >> 15) != 0;
            ctx.flags.c = false;
            ctx.flags.o = false;
        },
        .shl, .sal => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u4, @truncate(valueOf(rhs, ctx) & 0xF));
            const res = lval << shift_count;
            store(ctx, lhs, res);
            if (shift_count > 0) {
                const rs: u4 = @as(u4, @truncate(15 - (shift_count - 1)));
                ctx.flags.c = (lval >> rs) != 0;
                ctx.flags.z = res == 0;
                ctx.flags.s = (res >> 15) != 0;
                ctx.flags.o = (shift_count == 1) and ((lval >> 15) != (res >> 15));
            }
            // If shift_count == 0, flags remain unchanged
        },
        .shr => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u4, @truncate(valueOf(rhs, ctx) & 0xF));
            const res = lval >> shift_count;
            store(ctx, lhs, res);
            if (shift_count > 0) {
                ctx.flags.c = (lval >> (shift_count - 1)) & 1 != 0;
                ctx.flags.z = res == 0;
                ctx.flags.s = (res >> 15) != 0;
                ctx.flags.o = (shift_count == 1) and ((lval >> 15) != 0);
            }
            // If shift_count == 0, flags remain unchanged
        },
        .sar => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u4, @truncate(valueOf(rhs, ctx) & 0xF));
            const lval_signed = @as(i16, @bitCast(lval));
            const res_signed = lval_signed >> shift_count;
            const res = @as(u16, @bitCast(res_signed));
            store(ctx, lhs, res);
            if (shift_count > 0) {
                ctx.flags.c = (lval >> (shift_count - 1)) & 1 != 0;
                ctx.flags.z = res == 0;
                ctx.flags.s = (res >> 15) != 0;
                ctx.flags.o = false;
            }
            // If shift_count == 0, flags remain unchanged
        },
        .rol => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u5, @truncate(valueOf(rhs, ctx) & 0x1F));
            const res = rol(lval, shift_count);
            store(ctx, lhs, res);
            if (shift_count > 0) {
                const effective_shift_u5 = shift_count % 16;
                const eff: u4 = @truncate(effective_shift_u5);
                const one: u16 = 1;
                const c_from: u4 = if (eff == 0) 15 else @as(u4, @truncate(15 - (eff - 1)));
                ctx.flags.c = ((lval >> c_from) & one) != 0;
                ctx.flags.o = (eff == 1) and (((res >> 15) & one) != @as(u16, @intFromBool(ctx.flags.c)));
            }
            // If shift_count == 0, flags remain unchanged
        },
        .ror => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u5, @truncate(valueOf(rhs, ctx) & 0x1F));
            const res = ror(lval, shift_count);
            store(ctx, lhs, res);
            if (shift_count > 0) {
                const effective_shift_u5 = shift_count % 16;
                const eff = @as(u4, @truncate(effective_shift_u5));
                const one = @as(u16, 1);
                const c_from = if (eff == 0) 0 else @as(u4, @truncate(eff - 1));
                ctx.flags.c = ((lval >> c_from) & one) != 0;
                ctx.flags.o = (eff == 1) and ((((res >> 15) & one) != 0) != ctx.flags.c);
            }
            // If shift_count == 0, flags remain unchanged
        },
        .rcl => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u5, @truncate(valueOf(rhs, ctx) & 0x1F));
            const rot_result = rcl(lval, shift_count, ctx.flags.c);
            store(ctx, lhs, rot_result.value);
            if (shift_count > 0) {
                ctx.flags.c = rot_result.carry;
                const msb_set: bool = ((rot_result.value >> 15) & 1) != 0;
                ctx.flags.o = (shift_count == 1) and (msb_set != rot_result.carry);
            }
            // If shift_count == 0, flags remain unchanged
        },
        .rcr => {
            const lval = valueOf(lhs, ctx);
            const shift_count = @as(u5, @truncate(valueOf(rhs, ctx) & 0x1F));
            const rot_result = rcr(lval, shift_count, ctx.flags.c);
            store(ctx, lhs, rot_result.value);
            if (shift_count > 0) {
                ctx.flags.c = rot_result.carry;
                ctx.flags.o = (shift_count == 1) and (((rot_result.value >> 15) != 0) != rot_result.carry);
            }
            // If shift_count == 0, flags remain unchanged
        },
        else => {},
    }
}

fn rol(value: u16, count: u5) u16 {
    if (count == 0) return value;
    const shift_count_u5 = count % 16;
    const sc: u4 = @truncate(shift_count_u5);
    if (sc == 0) return value;
    const right_amt: u4 = @as(u4, @truncate(15 - (sc - 1)));
    return (value << sc) | (value >> right_amt);
}

fn ror(value: u16, count: u5) u16 {
    if (count == 0) return value;
    const shift_count_u5 = count % 16;
    const sc: u4 = @truncate(shift_count_u5);
    if (sc == 0) return value;
    const left_amt: u4 = @as(u4, @truncate(15 - (sc - 1)));
    return (value >> sc) | (value << left_amt);
}

const RotateResult = struct {
    value: u16,
    carry: bool,
};

fn rcl(value: u16, count: u5, carry: bool) RotateResult {
    if (count == 0) return RotateResult{ .value = value, .carry = carry };
    var result = value;
    var c = carry;
    const shift_count = count % 17; // 16 bits + 1 carry bit
    var i: u5 = 0;
    while (i < shift_count) : (i += 1) {
        const new_carry = (result >> 15) != 0;
        result = (result << 1) | (@as(u16, @intFromBool(c)));
        c = new_carry;
    }
    return RotateResult{ .value = result, .carry = c };
}

fn rcr(value: u16, count: u5, carry: bool) RotateResult {
    if (count == 0) return RotateResult{ .value = value, .carry = carry };
    var result = value;
    var c = carry;
    const shift_count = count % 17; // 16 bits + 1 carry bit
    var i: u5 = 0;
    while (i < shift_count) : (i += 1) {
        const new_carry = (result & 1) != 0;
        result = (result >> 1) | (@as(u16, @intFromBool(c)) << 15);
        c = new_carry;
    }
    return RotateResult{ .value = result, .carry = c };
}

fn shouldJump(ctx: *Context, inst: InstructionType) bool {
    return switch (inst) {
        .jmp => true,
        .je, .jz => ctx.flags.z,
        .jne, .jnz => !ctx.flags.z,
        .jg, .jnle => !ctx.flags.z and (ctx.flags.s == ctx.flags.o),
        .jl, .jnge => ctx.flags.s != ctx.flags.o,
        .ja, .jnbe => !ctx.flags.c and !ctx.flags.z,
        .jb, .jnae, .jc => ctx.flags.c,
        .jge, .jnl => ctx.flags.s == ctx.flags.o,
        .jle, .jng => ctx.flags.z or (ctx.flags.s != ctx.flags.o),
        .jae, .jnc => !ctx.flags.c,
        .jbe => ctx.flags.c or ctx.flags.z,
        .jcxz => ctx.getRegister(RegisterIdentifier{ .base = BaseRegister.cx, .selector = ByteSelector.full }) == 0,
        // .jnae handled above with .jb and .jc
        else => false,
    };
}

fn assert(c: bool) error{AssertionFailed}!void {
    if (!c) return error.AssertionFailed;
}

fn store(ctx: *Context, out_operand: Operand, value: u16) void {
    switch (out_operand) {
        .reg => |v| ctx.setRegister(v, value),
        .mem => |v| {
            switch (v.ptr_type) {
                .byte_ptr => ctx.dataseg[v.finalAddr(ctx)] = @as(u8, @truncate(value)),
                .unknown, .word_ptr => ctx.writeWord(v.finalAddr(ctx), value),
            }
        },
        else => {},
    }
}
