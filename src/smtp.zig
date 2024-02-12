// Zig Imports
const std = @import("std");
const dns = @import("dns.zig");
const tls = @import("tls.zig");
const Config = @import("config.zig");

pub fn send_message(allocator: std.mem.Allocator, recipient: []u8, sender: []u8, message: []u8) !void {
    var splititer = std.mem.splitSequence(u8, recipient, "@");

    splititer.index = 1;
    const item: []const u8 = splititer.next().?;
    const record = dns.get_mx_record(allocator, item) catch |err| {
        std.log.err("Failed to Get DNS Record Sending Message To \"{any}\" From \"{any}\"", .{ recipient, sender });
        return err;
    };

    const connection = std.net.tcpConnectToHost(allocator, record.address, 25) catch |err| {
        std.log.err("Failed To Open TCP Connection To {any}", record.address);
        return err;
    };

    var currentResponse = allocator.alloc(u8, 256) catch |err| {
        std.log.err("Failed To Allocator Response Buffer For TCP Connection with {any}", .{record.address});
        return err;
    };

    connection.writeAll("HELO") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll("MAIL FROM: " + sender) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll("RCP TO: " + recipient) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 250) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll("DATA") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 354) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.writeAll(message) catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.writeAll("QUIT") catch |err| {
        std.log.err("Error Occurred Writing TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    connection.readAll(&currentResponse) catch |err| {
        std.log.err("Error Occurred Reading TCP Connection with {any}", .{record.address});
        connection.close();
        return err;
    };

    if (currentResponse != 221) {
        std.log.err("Incorrect Response Connection Terminated With {any}\nMessage: {any}", .{ record.address, currentResponse });
        connection.close();
        return;
    }

    connection.close();
}

pub fn send_message_tls(allocator: std.mem.Allocator, recipient: []u8, sender: []u8, message: []u8) !void {
    _ = message;
    var splititer = std.mem.splitSequence(u8, recipient, "@");

    splititer.index = 1;
    const item: []const u8 = splititer.next().?;
    const record = dns.get_mx_record(allocator, item) catch |err| {
        std.log.err("Failed to Get DNS Record Sending Message To \"{any}\" From \"{any}\"", .{ recipient, sender });
        return err;
    };

    const connection = std.net.tcpConnectToHost(allocator, record.address, 587) catch |err| {
        std.log.err("Failed To Open TCP Connection To {any}", record.address);
        return err;
    };

    const config = Config.Config.init(allocator) catch |err| {
        std.log.err("Failed to Load Config, Sending Mail To {any}", .{recipient});
        return err;
    };

    var tls_stream = tls.TlsStream.to_tls(allocator, connection, config) catch |err| {
        std.log.err("Error Occurred Initialising TLS Connection with {any}", .{record.address});
        return err;
    };

    tls_stream.client.writeAll(tls_stream.stream, "EHLO");
}
