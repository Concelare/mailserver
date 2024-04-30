// Imports
const std = @import("std");
const pg = @import("pg");
const regex = @import("regex").Regex;

pub const User = struct {
    display_name: []const u8,
    username: []const u8,
    password: []const u8,
    email_ids: [][]const u8,
};

pub fn findUser(username: []const u8, pool: pg.Pool, allocator: *std.mem.Allocator) !?User {
    // Email Regex to stop SQL Injection Attacks
    var re = try regex.compile(allocator, "^[\\w-\\.]+@([\\w-]+\\.)+[\\w-]{2,4}$");
    defer re.deinit();

    const regex_res = try re.match(username);

    if (!regex_res) {
        // Returns Undefined if username is not an email
        return undefined;
    }

    // Searchs db for user information
    var result = try pool.query("SELECT * FROM Users WHERE username EQUALS $1 LIMIT 1", .{username});

    // Gets row as only one should be got
    var row = try result.next();

    // if row null return undefined as user does not exist
    if (row == null) {
        return undefined;
    }

    // Get User Information
    const display_name = row.?.get([]const u8, 0);
    const password = row.?.get([]const u8, 2);
    const email_ids = row.?.get([][]const u8, 3);

    return User{ .display_name = display_name, .username = username, .password = password, .email_ids = email_ids };
}
