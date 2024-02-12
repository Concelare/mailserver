const std = @import("std");
const dnsresolver = @import("dns.zig");

pub fn main() !void {
    const domain: []const u8 = "unnoticed.dev";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator: std.mem.Allocator = gpa.allocator();
    var ip = dnsresolver.get_mx_record(allocator, @constCast(domain)) catch |err| {
        std.log.err("{any}", .{err});
        return;
    };

    try std.json.stringify(&ip, .{}, std.io.getStdOut().writer());

    return;
}
