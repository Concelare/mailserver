// Zig Imports
const std = @import("std");
const Config = @import("config.zig");

const TlsError = error{Plain};

pub const TlsStream = struct {
    allocator: std.mem.Allocator,
    certs: std.crypto.Certificate.Bundle,
    stream: std.net.Stream,
    client: std.crypto.tls.Client,

    pub fn to_tls(allocator: std.mem.Allocator, stream: std.net.Stream, config: Config.Config) !TlsStream {
        var bundle = std.crypto.Certificate.Bundle{};

        std.crypto.Certificate.Bundle.addCertsFromDirPath(&bundle, allocator, std.fs.cwd(), "certs") catch |err| {
            std.log.err("Error Occurred Reading Certificates", .{});
            return err;
        };

        var client = std.crypto.tls.Client.init(stream, bundle, config.host) catch |err| {
            std.log.err("Error Occurred Initialising TLS Client", .{});
            return err;
        };

        var tlsStream: TlsStream = TlsStream{
            .allocator = allocator,
            .certs = bundle,
            .stream = stream,
            .client = client,
        };

        return tlsStream;
    }

    pub fn start_tls(allocator: std.mem.Allocator, stream: std.net.Stream, config: Config.Config) !TlsStream {
        var bundle = std.crypto.Certificate.Bundle{};

        std.crypto.Certificate.Bundle.addCertsFromDirPath(&bundle, allocator, std.fs.cwd(), "certs") catch |err| {
            std.log.err("Error Occurred Reading Certificates", .{});
            return err;
        };

        stream.writeAll("EHLO");

        stream.writeAll("STARTTLS");

        var client = std.crypto.tls.Client.init(stream, bundle, config.host) catch |err| {
            std.log.err("Error Occurred Initialising STARTTLS Client", .{});
            return err;
        };

        var tlsStream: TlsStream = TlsStream{
            .allocator = allocator,
            .certs = bundle,
            .stream = stream,
            .client = client,
        };

        return tlsStream;
    }

    pub fn writeAll(message: []u8) !void {
        _ = message;}
};
