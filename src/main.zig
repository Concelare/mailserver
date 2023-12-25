const std = @import("std");
const re = @cImport(@cInclude("regez.h"));
const dnsresolver = @import("dns.zig");

pub fn main() !void {
    const domain: []const u8 = "unnoticed.dev";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();
    const ip = dnsresolver.GetMXRecord(&allocator, @constCast(domain)) catch |err| {
        std.log.debug("Err Occurred {any}", .{err});
        return;
    };

    std.log.debug("Error Occurred {any}", .{ip.?.address});
    return;
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
