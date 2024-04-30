// Zig Imports
const std = @import("std");
const regex = @import("regex").Regex;

pub const DNSRecord = struct { name: []u8, type: []u8, address: []u8 };

pub fn get_mx_record(alloc: std.mem.Allocator, domain: []const u8) !DNSRecord {
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

    var mx_response: []const u8 = iter.next().?;

    mx_response = mx_response[0 .. mx_response.len - 2];

    var value = try regex.compile(alloc, "([0-9])\\.([0-9])\\.([0-9])\\.([0-9])");
    defer value.deinit();

    const found = try regex.match(&value, mx_response);

    if (found) {
        const x: DNSRecord = .{ .name = @constCast(domain), .type = @constCast("MX"), .address = @constCast(mx_response) };
        return x;
    }

    var thread2: std.ChildProcess = std.ChildProcess.init(&.{ "dig", mx_response, "+noall", "+answer", "+short" }, alloc);

    thread2.stdout_behavior = .Pipe;

    thread2.spawn() catch |err| {
        return err;
    };

    var cname_response: []u8 = try thread2.stdout.?.reader().readAllAlloc(alloc, max_output_size);
    errdefer alloc.free(cname_response);
    const term2 = try thread2.wait();

    switch (term2) {
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

    cname_response = cname_response[0 .. cname_response.len - 2];

    return .{ .name = @constCast(domain), .type = @constCast("MX"), .address = cname_response };
}

test "MX Record Testing" {
    const testing = try get_mx_record(&std.testing.allocator, "gmail.com");
    try std.testing.expect(testing != null);
}
