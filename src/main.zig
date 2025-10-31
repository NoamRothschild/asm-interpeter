const std = @import("std");
const lexer = @import("lexer/root.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allcator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("Memory was leaked!");
    }

    const instructions = try lexer.parse(allcator,
        \\ xor BX, BX
        \\ inc bx
        \\ mov al, [Bx]
        \\ CMP AL, '$'
    );
    defer allcator.free(instructions);

    for (instructions) |inst| {
        std.debug.print("{}\n\n", .{inst});
    }
}

test "all tests" {
    _ = @import("lexer/instruction.zig");
    _ = @import("lexer/root.zig");
    _ = @import("lexer/operand.zig");
}
