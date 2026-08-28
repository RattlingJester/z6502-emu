const std = @import("std");

pub const Addresses = struct {
    ram_start: usize,
    cold_start_addr: usize,
};

const lbl = @embedFile("out/msbasic.lbl");

pub fn parse_lbl() Addresses {
    @setEvalBranchQuota(100_000_000);

    var ram_start: ?usize = null;
    var cold_start_addr: ?usize = null;

    var line_iter = std.mem.tokenizeAny(u8, lbl, "\n\r");
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t");

        var word_iter = std.mem.tokenizeAny(u8, line, " \t");

        const prefix = word_iter.next() orelse continue;
        if (!std.mem.eql(u8, prefix, "al")) continue;

        const hex_str = word_iter.next() orelse continue;
        const label_name = word_iter.next() orelse continue;

        if (std.mem.eql(u8, label_name, ".COLD_START")) {
            cold_start_addr = std.fmt.parseInt(usize, hex_str, 16) catch {
                @compileError("Failed to parse hex string for COLD_START");
            };
        } else if (std.mem.eql(u8, label_name, ".RAMSTART2")) {
            ram_start = std.fmt.parseInt(usize, hex_str, 16) catch {
                @compileError("Failed to parse hex string for RAMSTART2");
            };
        }

        if (ram_start != null and cold_start_addr != null) break;
    }

    if (ram_start == null) @compileError("Could not find .RAMSTART2 in lbl file!");
    if (cold_start_addr == null) @compileError("Could not find .COLD_START in lbl file!");

    return .{
        .ram_start = ram_start.?,
        .cold_start_addr = cold_start_addr.?,
    };
}
