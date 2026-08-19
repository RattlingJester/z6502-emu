const std = @import("std");

const MAX_MEM = 1024 * 64;

const Instr = enum(u8) {
    LDA_IM = 0xA9,
    _,
};

const CPU = struct {
    PC: u16 = 0xFFFC,

    A: u8 = 0,
    X: u8 = 0,
    Y: u8 = 0,

    SP: u8 = 0xFD,
    status: u8 = 0b00110100,

    memory: [MAX_MEM]u8 = @splat(0),

    pub fn reset(self: *@This()) void {
        self.PC = 0xFFFC;
        self.A = 0;
        self.X = 0;
        self.Y = 0;

        self.SP = 0xFD;
        self.status = 0b00110100;
    }

    pub fn read_mem(self: *@This(), addr: u16) u8 {
        self.PC += 1;
        return self.memory[addr];
    }

    pub fn update_status(self: *@This()) void {
        if (self.A == 0) {
            self.status |= 1 << 1;
        }

        if ((self.A & 1 << 7) != 0) {
            self.status |= 1 << 7;
        }
    }

    pub fn execute(self: *@This(), i: Instr) void {
        switch (i) {
            Instr.LDA_IM => {
                self.A = self.read_mem(self.PC);
                self.update_status();
            },

            else => {
                std.log.err("Instruction 0x{X} is not handled", .{i});
                unreachable;
            },
        }
    }

    pub fn cycle(self: *@This()) void {
        const instr = self.read_mem(self.PC);

        self.execute(@enumFromInt(instr));
    }
};

pub fn main() void {
    var cycles: u8 = 1;

    var cpu = CPU{};
    cpu.reset();

    cpu.memory[cpu.PC] = 0xA9;
    cpu.memory[cpu.PC + 1] = 10;

    while (cycles != 0) {
        cpu.cycle();
        cycles -= 1;
    }

    std.log.info("CPU A register: {}", .{cpu.A});
}
