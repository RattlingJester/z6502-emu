const std = @import("std");
const emu = @import("emu");

const log = std.log.scoped(.main);

const RomBuilder = emu.RomBuilder;
const Opcodes = emu.Opcodes;
const CPU = emu.CPU;

const MAX_MEM = 1024 * 64;

const MemoryBus = struct {
    const Self = @This();

    ram: [MAX_MEM]u8 = undefined,

    pub fn read(self: *Self, addr: u16) u8 {
        return self.ram[addr];
    }

    pub fn write(self: *Self, addr: u16, value: u8) void {
        self.ram[addr] = value;
    }
};

const rom = blk: {
    var builder = RomBuilder(MAX_MEM){};
    break :blk builder
        .reset_vector(0x8000)
        .org(0x8000)
        .op(Opcodes.LDA_IM).byte(10)
        .op(Opcodes.LDA_ZP).byte(0x42)
        .org(0x42).byte(69)
        .build();
};

pub fn main() void {
    var execute_cycles: i8 = 5;
    var elapsed_cycles: u8 = 0;

    var bus = MemoryBus{ .ram = rom };
    var cpu = CPU(MemoryBus).init(&bus);

    cpu.reset();

    while (execute_cycles > 0) {
        elapsed_cycles = cpu.cycle();
        execute_cycles -= @intCast(elapsed_cycles);
    }

    if (execute_cycles != 0) {
        log.err("Cycle count mismatch! Elapsed: {}, Remaining: {}", .{ elapsed_cycles, execute_cycles });
    }

    log.info("CPU PC register: 0x{X}", .{cpu.PC});
    log.info("CPU A register: {}", .{cpu.A});
    log.info("CPU status register: 0b{b}", .{cpu.status});
}
