// Imports
const std = @import("std");
const Config = @import("config.zig");

// Tls Errors in Error Enum
const TlsError = error{Plain};

pub const TlsStream = struct {
    // Allocator For Stream
    allocator: std.mem.Allocator,
    // TLS Cert Bundle
    certs: std.crypto.Certificate.Bundle,
    // Connection TCP Stream
    stream: std.net.Stream,
    // TLS Client for encrypting and Decrypting
    client: std.crypto.tls.Client,

    // Converts Stream To TLS Stream
    pub fn to_tls(allocator: std.mem.Allocator, stream: std.net.Stream, config: Config.Config) !TlsStream {
        var bundle = std.crypto.Certificate.Bundle{};

        // Loads Certificates
        std.crypto.Certificate.Bundle.addCertsFromDirPath(&bundle, allocator, std.fs.cwd(), "certs") catch |err| {
            std.log.err("Error Occurred Reading Certificates", .{});
            return err;
        };

        // Initialises client using certificate bundle, stream and config.host value
        const client = std.crypto.tls.Client.init(stream, bundle, config.host) catch |err| {
            std.log.err("Error Occurred Initialising TLS Client", .{});
            return err;
        };

        const tlsStream: TlsStream = TlsStream{
            .allocator = allocator,
            .certs = bundle,
            .stream = stream,
            .client = client,
        };

        return tlsStream;
    }

    // Converts the stream to TLS using the STARTTLS command
    pub fn start_tls(allocator: std.mem.Allocator, stream: std.net.Stream, config: Config.Config) !TlsStream {
        var bundle = std.crypto.Certificate.Bundle{};

        // Loads Certificates
        std.crypto.Certificate.Bundle.addCertsFromDirPath(&bundle, allocator, std.fs.cwd(), "certs") catch |err| {
            std.log.err("Error Occurred Reading Certificates", .{});
            return err;
        };

        stream.writeAll("EHLO");

        stream.writeAll("STARTTLS");

        // The TLS client initialisation handles the tls handshake
        const client = std.crypto.tls.Client.init(stream, bundle, config.host) catch |err| {
            std.log.err("Error Occurred Initialising STARTTLS Client", .{});
            return err;
        };

        const tlsStream: TlsStream = TlsStream{
            .allocator = allocator,
            .certs = bundle,
            .stream = stream,
            .client = client,
        };

        return tlsStream;
    }

    // Used to write to stream for simplicity
    pub fn writeAll(self: TlsStream, message: []const u8) !void {
        self.client.writeAll(self.stream, message) catch |err| {
            return err;
        };
    }

    // Used to read the stream for simplicity
    pub fn readAll(self: TlsStream, response_buffer: *[]const u8) !void {
        self.client.readAll(self.stream, response_buffer) catch |err| {
            return err;
        };
    }
};
