// Zig Imports
const std = @import("std");
const regex = @import("regex").Regex;

// C Imports
const re = @cImport(@cInclude("regez.h"));

pub const DNSRecord = struct { name: []u8, type: []u8, address: []u8 };

pub fn GetMXRecord(allocator: *const std.mem.Allocator, domain: []const u8) !DNSRecord {
    var alloc: std.mem.Allocator = allocator.*;

    // const threadString = try std.mem.concat(alloc, u8, &.{ "dig ", domain, " MX +noall +answer +short" });
    // defer alloc.free(threadString);

    var thread: std.ChildProcess = std.ChildProcess.init(&.{ "dig", domain, "MX", "+noall", "+answer", "+short" }, alloc);

    thread.stdout_behavior = .Pipe;
    thread.spawn() catch |err| {
        return err;
    };

    const max_output_size = 100 * 1024 * 1024;

    const bytes: []const u8 = try thread.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes);
    defer alloc.free(bytes);
    const term = try thread.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS MX Query Failed With Code: {any}", .{code});
                return DNSRecord{ .name = "", .type = "", .address = "" };
            }
        },
        else => {
            std.log.warn("DNS MX Query Failed To Resolve", .{});
            return DNSRecord{ .name = "", .type = "", .address = "" };
        },
    }

    var iter = std.mem.splitSequence(u8, bytes, " ");
    iter.index = 3;

    var testing: []const u8 = iter.next().?;

    testing = testing[0 .. testing.len - 2];

    var value = try regex.compile(alloc, "([0-9])\\.([0-9])\\.([0-9])\\.([0-9])");
    defer value.deinit();

    // var input: [*:0]u8 = std.mem.sliceTo(field, 0);
    // _ = input;

    const found = try regex.match(&value, testing);

    if (found) {
        var name = std.mem.concat(alloc, u8, &.{ domain, " MX Record" }) catch |err| {
            return err;
        };
        defer alloc.free(name);

        var x: DNSRecord = .{ .name = name, .type = @constCast("MX"), .address = @constCast(testing) };
        return x;
    }

    // std.log.debug("Boom\n {any}", .{bytes});
    try std.json.stringify(&testing, .{}, std.io.getStdOut().writer());

    var thread2: std.ChildProcess = std.ChildProcess.init(&.{ "dig", testing, "+noall", "+answer", "+short" }, alloc);
    std.log.debug("BOOOM", .{});
    thread2.stdout_behavior = .Pipe;

    thread2.spawn() catch |err| {
        return err;
    };

    var bytes_ip: []u8 = try thread2.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(bytes_ip);
    const term2 = try thread2.wait();
    _ = term2;

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.log.warn("DNS CNAME Query Failed With Code: {any}", .{code});
                return DNSRecord{ .name = "", .type = "", .address = "" };
            }
        },
        else => {
            std.log.warn("DNS CNAME Query Failed To Resolve", .{});

            return DNSRecord{ .name = "", .type = "", .address = "" };
        },
    }

    std.log.debug("BANNNNG", .{});

    var name = std.mem.concat(alloc, u8, &.{ domain, " MX Record" }) catch |err| {
        return err;
    };
    defer alloc.free(name);
    bytes_ip = bytes_ip[0 .. bytes_ip.len - 1];
    try std.json.stringify(&bytes_ip, .{}, std.io.getStdOut().writer());

    return DNSRecord{ .name = name, .type = @constCast("MX"), .address = bytes_ip };
}

test "MX Record Testing" {
    var testing = try GetMXRecord(&std.testing.allocator, "gmail.com");
    try std.testing.expect(testing != null);
}
