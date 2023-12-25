// Zig Imports
const std = @import("std");

// C Imports
const re = @cImport(@cInclude("regez.h"));

pub const DNSRecord = struct { name: []u8, type: []u8, address: []u8 };

pub fn GetMXRecord(allocator: *const std.mem.Allocator, domain: []const u8) !?DNSRecord {
    var alloc: std.mem.Allocator = allocator.*;

    var thread: std.ChildProcess = std.ChildProcess.init(&.{ "dig", domain, "MX +noall +answer +short" }, alloc);

    thread.stdout_behavior = .Pipe;
    thread.spawn() catch |err| {
        return err;
    };

    const max_output_size = 100 * 1024 * 1024;

    const bytes: []const u8 = try thread.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes);

    const term = try thread.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS MX Query Failed With Code: {any}", .{code});
                return null;
            }
        },
        else => {
            std.log.warn("DNS MX Query Failed To Resolve", .{});
            return null;
        },
    }

    var iter = std.mem.split(u8, bytes, " ");

    iter.index = iter.index.? + 1;

    const field = iter.next().?;
    const input: [*:0]u8 = @ptrCast(@constCast(field));
    var found: bool = re.isIP(@constCast(input));

    var name = std.mem.concat(alloc, u8, &.{ domain, " MX Record" }) catch |err| {
        return err;
    };
    defer alloc.free(name);

    if (found) {
        var x: DNSRecord = .{ .name = name, .type = @constCast("MX"), .address = @constCast(field) };
        return x;
    }

    var thread2: std.ChildProcess = std.ChildProcess.init(&.{ "dig", field, "+noall +answer +short" }, alloc);

    thread2.stdout_behavior = .Pipe;

    thread2.spawn() catch |err| {
        return err;
    };

    const bytes_ip: []u8 = try thread2.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes_ip);
    const term2 = try thread2.wait();
    _ = term2;

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS CNAME Query Failed With Code: {any}", .{code});
                return null;
            }
        },
        else => {
            std.log.warn("DNS CNAME Query Failed To Resolve", .{});
        },
    }

    return DNSRecord{ .name = name, .type = @constCast("MX"), .address = bytes_ip };
}

test "MX Record Testing" {
    var testing = try GetMXRecord(&std.testing.allocator, "gmail.com");
    try std.testing.expect(testing != null);
}
