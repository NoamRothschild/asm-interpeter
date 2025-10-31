const parser = @import("parser/root.zig");
const std = @import("std");

// NOTE: we could start code execution at the label "_start"'s index instead of 0

// TODO: translate `offset of` to an index inside dataseg

pub const CPUContext = struct {
    ax: parser.Register,
    bx: parser.Register,
    cx: parser.Register,
    dx: parser.Register,
    si: parser.Register,
    di: parser.Register,
    bp: parser.Register,

    dataseg: [65536]u8,

    code: []const parser.Instruction,
    /// map of label_name -> instruction index in `code`
    label_references: std.AutoHashMap([]const u8, usize),
};
