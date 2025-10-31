const std = @import("std");
const parser = @import("parser/root.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allcator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("Memory was leaked!");
    }

    const instructions = try parser.parse(allcator,
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
    _ = @import("parser/instruction.zig");
    _ = @import("parser/root.zig");
    _ = @import("parser/operand.zig");
}
