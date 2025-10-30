const lexer = @import("lexer/root.zig");
const std = @import("std");

// NOTE: we could start code execution at the label "_start"'s index instead of 0

// TODO: translate `offset of` to an index inside dataseg

pub const CPUContext = struct {
    ax: lexer.Register,
    bx: lexer.Register,
    cx: lexer.Register,
    dx: lexer.Register,
    si: lexer.Register,
    di: lexer.Register,
    bp: lexer.Register,

    dataseg: [65536]u8,

    code: []const lexer.Instruction,
    /// map of label_name -> instruction index in `code`
    label_references: std.AutoHashMap([]const u8, usize),
};
