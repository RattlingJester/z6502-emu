const std = @import("std");
const emu = @import("emu");
const parse = @import("lbl_parse.zig");
const log = std.log.scoped(.basic);

const addrs = parse.parse_lbl();

const ROM_START = 0x1000; // Start of ROM from kim.cfg
const RAM_START = addrs.ram_start; // Address from .lbl (.RAMSTART2)
const COLD_START_ADDR = addrs.cold_start_addr; // Address from .lbl (.COLD_START)

const rom = @embedFile("out/msbasic.bin");

const Bus = struct {
    const Self = @This();

    pub const STACK_START = 0xFF; // [0x0100...0x01FF]
    pub const SP_RESET = 0xFC;
    pub const RESET_VECTOR_ADDR = 0xFFFC;
    pub const IRQ_VECTOR = 0xFFFE;
    pub const MEM_SIZE = 1024 * 64;

    ram: [MEM_SIZE]u8 = @splat(0xFF),

    io: std.Io,
    alloc: std.mem.Allocator,

    stdout_buf: [64]u8 = undefined,
    stdout_writer: std.Io.File.Writer,

    keys_queue: std.Deque(u8),

    pub fn init(io: std.Io, alloc: std.mem.Allocator) !Self {
        var self: Self = .{
            .io = io,
            .alloc = alloc,
            .stdout_writer = undefined,
            .keys_queue = try .initCapacity(alloc, 64),
        };

        self.stdout_writer = std.Io.File.stdout().writerStreaming(io, &self.stdout_buf);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.keys_queue.deinit(self.alloc);
    }

    pub fn read(self: *Self, addr: u16) !u8 {
        switch (addr) {
            0xFFF0 => {
                // If a key is staged, return it
                if (self.keys_queue.popFront()) |char| {
                    return char;
                }
                return 0x00;
            },
            0xFFF1 => {
                // If we have a key waiting, set Bit 7 high
                return if (self.keys_queue.len > 0) 1 << 7 else 0x00;
            },
            else => return self.ram[addr],
        }
    }

    pub fn write(self: *Self, addr: u16, value: u8) !void {
        switch (addr) {
            0xFFF2 => {
                // Print the character
                self.stdout_writer.interface.writeAll(&.{value}) catch |err| {
                    log.err("stdout write failed: {}", .{err});
                };

                try self.stdout_writer.interface.flush();
            },
            // ROM is read-only
            ROM_START...(RAM_START - 1) => {},
            else => self.ram[addr] = value,
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var kb_buf: [64]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&kb_buf);
    const alloc = fba.allocator();

    var bus = try Bus.init(io, alloc);
    defer bus.deinit();

    // std.debug.print("ROM len: {}\n", .{rom.len});
    @memcpy(bus.ram[ROM_START..][0..rom.len], rom);

    // std.debug.print("COLD_START: 0x{X}\n", .{addrs.cold_start_addr});
    // std.debug.print("RAMSTART2: 0x{X}\n", .{addrs.ram_start});

    var cpu = emu.CPU(Bus, .{}).init(&bus);
    cpu.write_word(Bus.RESET_VECTOR_ADDR, COLD_START_ADDR); // Setting COLD_START as start address
    cpu.reset();

    var kb_task = io.async(keyboard_listener, .{ io, &bus });
    defer kb_task.cancel(io) catch {};

    while (true) {
        _ = cpu.step();
    }
}

fn keyboard_listener(io: std.Io, bus: *Bus) !void {
    var read_buf: [64]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(io, &read_buf);
    const stdin = &reader.interface;

    while (true) {
        const char = try stdin.takeByte();

        if (char == '\n') continue;

        try bus.keys_queue.pushBack(bus.alloc, char);

        // Yielding
        try io.sleep(.fromNanoseconds(0), .awake);
    }
}
