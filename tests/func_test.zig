const std = @import("std");
const emu = @import("emu");
const log = std.log.scoped(.ftest);

const MemoryBus = struct {
    const Self = @This();

    pub const STACK_START = 0xFF; // [0x0100...0x01FF]
    pub const SP_RESET = 0xFD;
    pub const RESET_VECTOR_ADDR = 0xFFFC;
    pub const IRQ_VECTOR = 0xFFFE;
    pub const MEM_SIZE = 1024 * 64;

    ram: [MEM_SIZE]u8 = undefined,

    pub fn read(self: *Self, addr: u16) u8 {
        return self.ram[addr];
    }

    pub fn write(self: *Self, addr: u16, value: u8) void {
        self.ram[addr] = value;
    }
};

const rom = @embedFile("6502_functional_test.bin");

pub fn main() !void {
    var bus = MemoryBus{ .ram = rom.* };

    var cpu = emu.CPU(MemoryBus, .{ .decimal_mode = true }).init(&bus);
    cpu.PC = 0x0400;

    var total_cycles: u64 = 0;
    var last_pc: u16 = 0xFFFF;
    var iterations: u64 = 0;

    while (true) {
        const pc_before = cpu.PC;
        const cycles = try cpu.step();
        total_cycles += cycles;
        iterations += 1;

        if (cpu.PC == pc_before) {
            log.info("Trapped at PC=0x{X:04} after {} instructions, {} cycles", .{ cpu.PC, iterations, total_cycles });
            break;
        }
        last_pc = pc_before;

        if (iterations > 200_000_000) {
            log.err("Exceeded iteration limit", .{});
            break;
        }
    }

    cpu.print_state();
}
