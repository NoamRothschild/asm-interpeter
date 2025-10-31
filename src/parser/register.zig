const std = @import("std");

pub const Register = struct {
    const Self = @This();
    value: u16,

    pub fn getValue(self: Self) u16 {
        return self.value;
    }

    pub fn getLow(self: Self) i8 {
        return self.value << 8; // TODO: GO OVER AGAIN MAKE SURE DIDNT DO ANYTHING STUPID
    }
};

pub const RegisterIdentifier16bit = enum { ax, bx, cx, dx, si, di, bp };
pub const RegisterIdentifier8bit = enum { al, ah, bl, bh, cl, ch, dl, dh };

pub const RegisterIdentifier = union(enum) { _8bit: RegisterIdentifier8bit, _16bit: RegisterIdentifier16bit };

pub fn fromString(mnemonic: []const u8) ?RegisterIdentifier {
    inline for (std.meta.fields(RegisterIdentifier8bit)) |field| {
        if (std.mem.eql(u8, mnemonic, field.name)) {
            return .{
                ._8bit = @field(RegisterIdentifier8bit, field.name),
            };
        }
    }

    inline for (std.meta.fields(RegisterIdentifier16bit)) |field| {
        if (std.mem.eql(u8, mnemonic, field.name)) {
            return .{
                ._16bit = @field(RegisterIdentifier16bit, field.name),
            };
        }
    }
    return null;
}
