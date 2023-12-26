const std = @import("std");
const dnsresolver = @import("dns.zig");

pub fn main() !void {
    const domain: []const u8 = "unnoticed.dev";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();
    const ip = dnsresolver.GetMXRecord(&allocator, @constCast(domain)) catch |err| {
        std.log.err("{any}", .{err});
        return;
    };

    try std.json.stringify(&ip, .{}, std.io.getStdOut().writer());

    return;
}
