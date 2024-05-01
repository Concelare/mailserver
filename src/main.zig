// Imports
const std = @import("std");
const dnsresolver = @import("dns.zig");
const smtp_listener = @import("smtp_listener.zig");
const Config = @import("config.zig").Config;
const smtp = @import("smtp.zig");
const imap = @import("imap_listener.zig");
const pg = @import("pg");
const email = @import("email.zig");

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

test "MX Record" {
    // Initialise the allocator for the test as testing alloc throws memory errors
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();
    const testing = try dnsresolver.get_mx_record(allocator, "unnoticed.dev");
    try std.testing.expect(!std.mem.eql(u8, testing.address, ""));
}

test "Load Config" {
    // Allocator for testing
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator: std.mem.Allocator = gpa.allocator();

    // Creates Config if not done already
    _ = Config.init(allocator) catch {
        std.log.debug("Ignore Error Since Creating Config File", .{});
    };

    // Actual Config Test
    const config = try Config.init(allocator);
    _ = config; // Supresses Error
    try std.testing.expect(true);
}

test "Parsing Email Headers" {
    // Test Data
    const headers = "Reply-To: John Doe <johndoe@example.com>\r\nReceived: from example.com (example.com [192.0.2.1])\r\nby example.net (Postfix) with ESMTPS id 1234567890ABCDE\r\nReturn-Path: <bounce@example.com>\r\nSubject: Hello, world!\r\nTo: Alice <alice@example.net>\r\nFrom: Jane Doe <janedoe@example.org>\r\nMessage-ID: <1234567890@example.com>\r\nMIME-Version: 1.0\r\nDKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=example.org;\r\nReceived-SPF: pass (example.org: domain of janedoe@example.org designates 192.0.2.1 as permitted sender) client-ip=192.0.2.1;\r\n";

    // Parses to Errorable Header Struct
    const fields = try email.parseEmailHeaders(headers);

    // Checks all struct Values Aren't Null
    try std.testing.expect(fields.replyTo != null);
    try std.testing.expect(fields.received != null);
    try std.testing.expect(fields.returnTo != null);
    try std.testing.expect(fields.subject != null);
    try std.testing.expect(fields.to != null);
    try std.testing.expect(fields.from != null);
    try std.testing.expect(fields.messageId != null);
    try std.testing.expect(fields.dkimSignature != null);
    try std.testing.expect(fields.spf != null);
}

test "Parsing IMAP Command" {

    // Allocator for testing
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator: std.mem.Allocator = gpa.allocator();
    const testData = "Login testusername@example.com testpassword";
    const parsedData = try imap.parseCommand(testData, &allocator);
    try std.testing.expect(parsedData.command == imap.Command.Login);
    try std.testing.expect(std.mem.eql(u8, parsedData.tokens.?[0], "testusername@example.com"));
    try std.testing.expect(std.mem.eql(u8, parsedData.tokens.?[1], "testpassword"));
}
