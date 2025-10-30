const std = @import("std");
const lexer = @import("lexer/root.zig");

pub fn main() !void {}

test "all tests" {
    _ = @import("lexer/instruction.zig");
    _ = @import("lexer/root.zig");
    _ = @import("lexer/operand.zig");
}
