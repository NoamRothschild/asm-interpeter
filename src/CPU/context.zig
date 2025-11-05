const std = @import("std");
const parser = @import("../parser/root.zig");
const Register = @import("register.zig").Register;
const FlagsRegister = @import("register.zig").FlagsRegister;
const RegisterIdentifier = @import("../parser/register.zig").RegisterIdentifier;

// NOTE: we could start code execution at the label "_start"'s index instead of 0

// TODO: translate `offset of` to an index inside dataseg
pub const Context = struct {
    ax: Register = Register{ .value = undefined },
    bx: Register = Register{ .value = undefined },
    cx: Register = Register{ .value = undefined },
    dx: Register = Register{ .value = undefined },
    si: Register = Register{ .value = undefined },
    di: Register = Register{ .value = undefined },
    bp: Register = Register{ .value = undefined },
    ip: usize, // the index into the instruction list
    flags: FlagsRegister = std.mem.zeroes(FlagsRegister),

    dataseg: [65536]u8,
    instructions: []const parser.Instruction,

    pub fn getRegister(self: *const Context, reg_id: RegisterIdentifier) u16 {
        const base_reg = self.getBaseRegister(reg_id.base);
        return base_reg.get(reg_id.selector);
    }

    pub fn setRegister(self: *Context, reg_id: RegisterIdentifier, value: u16) void {
        const base_reg = self.getBaseRegisterPtr(reg_id.base);
        base_reg.set(reg_id.selector, value);
    }

    fn getBaseRegisterPtr(self: *Context, base: RegisterIdentifier.BaseRegister) *Register {
        return switch (base) {
            .ax => &self.ax,
            .bx => &self.bx,
            .cx => &self.cx,
            .dx => &self.dx,
            .si => &self.si,
            .di => &self.di,
            .bp => &self.bp,
        };
    }

    fn getBaseRegister(self: *Context, base: RegisterIdentifier.BaseRegister) Register {
        return self.getBaseRegisterPtr(base).*;
    }

    pub fn readWord(self: *const Context, addr: u16) u16 {
        return std.mem.readInt(u16, self.dataseg[addr % 65536 .. addr % 65536 + 1], .little);
    }

    pub fn writeWord(self: *Context, addr: u16, word: u16) void {
        std.mem.writeInt(u16, self.dataseg[addr % 65536 .. addr % 65536 + 1], word, .little);
    }
};
