const std = @import("std");
const parser = @import("parser/root.zig");
const ParseResult = parser.ParseResult;
// TODO: write tests for whole code parts with labels.

const Context = @import("CPU/context.zig").Context;
const executor = @import("CPU/executor.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("Memory was leaked!");
    }

    const test_code =
        \\ xor bx, bx
        \\ loop1:
        \\ inc bx
        \\ mov al, [bx]
        \\ cmp al, '$'
        \\ jnz loop1
    ;

    std.log.info("parsing the following code:\n{s}\n", .{test_code});

    std.log.info("parser logs: ", .{});
    var parser_result = parser.parse(allocator, test_code) catch |err| {
        std.debug.print("parser failed!, error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer parser_result.deinit();

    std.log.info("parsed instructions:\n", .{});
    for (parser_result.instructions) |inst| {
        std.debug.print("{}\n\n", .{inst});
    }

    std.log.info("labels found:\n", .{});
    var it = parser_result.label_map.iterator();
    while (it.next()) |entry| {
        std.debug.print("{s}: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    var ctx = Context{
        .ip = 0,
        .instructions = parser_result.instructions,
        .dataseg = undefined,
    };
    @memset(&ctx.dataseg, 0);
    ctx.dataseg[7] = '$';
    while (parser_result.instructions[ctx.ip].inst != .hlt) {
        try executor.executeInstruction(&ctx);
    }
    std.log.info("bx: {}", .{ctx.bx});
    std.log.info("execution finished", .{});
}

test "all tests" {
    _ = @import("parser/instruction.zig");
    _ = @import("parser/root.zig");
    _ = @import("parser/operand.zig");
}
