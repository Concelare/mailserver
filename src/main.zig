// Imports
const std = @import("std");
const dnsresolver = @import("dns.zig");
const smtp_listener = @import("smtp_listener.zig");
const Config = @import("config.zig").Config;
const smtp = @import("smtp.zig");
const imap = @import("imap_listener.zig");
const pg = @import("pg");

// Setting Log Level
pub const log_level: std.log.Level = .debug;

// Returns a void and is Errorable
pub fn main() !void {
    // Initialise the allocator for the app
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();
    // Load the config
    var config = try Config.init(allocator);
    // Seed/Setup the Postgres Database
    try database_setup(&allocator);
    // Start Up the SMTP
    try smtp_listener.listener(&config, allocator);
    return;
}

fn database_setup(allocator: *const std.mem.Allocator) !void {
    const cmds: [2][]const u8 = .{
        "CREATE TABLE IF NOT EXISTS Users (username varchar NOT NULL, password varchar NOT NULL, display_name varchar NOT NULL, email_ids integer ARRAY, PRIMARY KEY (username))",
        "CREATE TABLE IF NOT EXISTS Emails (id bigserial NOT NULL, messageId varchar NOT NULL, \"to\" varchar NOT NULL, \"from\" varchar NOT NULL, subject varchar NOT NULL, body varchar NOT NULL, replyTo varchar NOT NULL, recievedFrom varchar, returnTo varchar NOT NULL, mime varchar, dkimSignature varchar, spf varchar, read bool NOT NULL DEFAULT true, date_created date, raw varchar NOT NULL, PRIMARY KEY (id))",
    };
    // Remove the const from the allocator
    _ = @constCast(allocator);
    // Init the Postgres connection pool
    var pool = try pg.Pool.init(allocator.*, .{ .size = 5, .connect = .{
        .port = 5432,
        .host = "localhost",
    }, .auth = .{
        .username = "postgres",
        .database = "postgres",
        .password = "mysecretpassword",
        .timeout = 10_000,
    } });
    // Sets the deconstructor
    defer pool.deinit();

    std.log.debug("Successfully Connected to Database", .{});
    for (cmds) |cmd| {
        _ = try pool.query(cmd, .{});
        std.log.debug("Successfully Ran DB Command: {s}", .{cmd});
    }
}
