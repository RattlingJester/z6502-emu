pub const root = @This();

const opcodes = @import("opcodes.zig");

pub const RomBuilder = @import("builder.zig").RomBuilder;
pub const Opcode = opcodes.Opcode;

const std = @import("std");
const log = std.log.scoped(.emulator);

pub const StatusFlag = enum(u8) {
    CARRY = 1 << 0,
    ZERO = 1 << 1,
    INTERRUPT_DISABLE = 1 << 2,
    DECIMAL = 1 << 3,
    BREAK = 1 << 4,
    UNUSED = 1 << 5,
    OVERFLOW = 1 << 6,
    NEGATIVE = 1 << 7,
};

pub fn CPU(comptime Bus: type) type {
    return struct {
        const Self = @This();

        PC: u16 = 0xFFFC,

        A: u8 = 0,
        X: u8 = 0,
        Y: u8 = 0,

        SP: u8 = Bus.STACK_START,
        status: u8 = 0b00110100,

        bus: *Bus,

        pub fn init(bus: *Bus) Self {
            return .{ .bus = bus };
        }

        pub fn reset(self: *Self) void {
            const lo: u16 = self.bus.read(0xFFFC);
            const hi: u16 = self.bus.read(0xFFFD);

            self.PC = (hi << 8) | lo;
            self.A = 0;
            self.X = 0;
            self.Y = 0;

            self.SP = 0xFD;
            self.status = 0b00110100;
        }

        pub fn fetch_byte(self: *Self) u8 {
            const op = self.read_byte(self.PC);
            self.PC +%= 1;
            return op;
        }

        pub fn fetch_word(self: *Self) u16 {
            const lo: u16 = self.fetch_byte();
            const hi: u16 = self.fetch_byte();

            return (hi << 8) | lo;
        }

        pub fn read_byte(self: *const Self, addr: u16) u8 {
            return self.bus.read(addr);
        }

        pub fn read_word(self: *const Self, addr: u16) u16 {
            const lo: u16 = self.read_byte(addr);
            const hi: u16 = self.read_byte(addr +% 1);

            return (hi << 8) | lo;
        }

        pub fn write_byte(self: *Self, addr: u16, value: u8) void {
            self.bus.write(addr, value);
        }

        pub fn write_word(self: *Self, addr: u16, value: u16) void {
            self.write_byte(addr, @truncate(value & 0xFF));
            self.write_byte(addr +% 1, @truncate(value >> 8));
        }

        /// Stack is located on page 1, so 0x0100 is added to the adress
        pub fn push_byte(self: *Self, value: u8) void {
            self.write_byte(@as(u16, self.SP) + 0x0100, value);
            self.SP -%= 1;
        }

        /// Stack is located on page 1, so 0x0100 is added to the adress
        pub fn pop_byte(self: *Self) u8 {
            self.SP +%= 1;
            const value = self.read_byte(@as(u16, self.SP) + 0x0100);

            return value;
        }

        pub fn push_word(self: *Self, value: u16) void {
            self.push_byte(@truncate(value & 0xFF));
            self.push_byte(@truncate(value >> 8));
        }

        pub fn pop_word(self: *Self) u16 {
            const hi: u16 = self.pop_byte();
            const lo: u16 = self.pop_byte();

            return (hi << 8) | lo;
        }

        pub fn set_flag(self: *Self, flag: StatusFlag, on: bool) void {
            const bit = @intFromEnum(flag);

            if (on) {
                self.status |= bit;
            } else {
                self.status &= ~bit;
            }
        }

        pub fn get_flag(self: *const Self, flag: StatusFlag) bool {
            return (self.status & @intFromEnum(flag)) != 0;
        }

        pub fn execute(self: *Self, op: Opcode) u8 {
            return switch (op) {
                Opcode.LDA_IM => blk: {
                    self.A = self.fetch_byte();
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
                    break :blk 2;
                },
                Opcode.LDA_ZP => blk: {
                    const addr = self.fetch_byte();
                    self.A = self.read_byte(addr);
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
                    break :blk 3;
                },
                Opcode.LDA_ZP_X => blk: {
                    const addr = self.fetch_byte();
                    self.A = self.read_byte(addr +% self.X);
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
                    break :blk 4;
                },
                Opcode.LDA_ABS => blk: {
                    const addr = self.fetch_word();
                    self.A = self.read_byte(addr);
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
                    break :blk 4;
                },
                Opcode.LDA_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    self.A = self.read_byte(addr);
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.LDA_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    self.A = self.read_byte(addr);
                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
                    const extra: u8 = if (page_crossed(base, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.JSR_ABS => blk: {
                    const target = self.fetch_word();
                    self.push_word(self.PC -% 1);
                    self.PC = target;
                    break :blk 6;
                },
                Opcode.RTS_IMPL => blk: {
                    const return_addr = self.pop_word();
                    self.PC = return_addr +% 1;
                    break :blk 6;
                },
                else => {
                    log.err("Instruction {} (0x{X}) is not handled", .{ op, op });
                    self.print_state();
                    unreachable;
                },
            };
        }

        /// Returns elapsed cycle count
        pub fn tick(self: *Self) u8 {
            const op = self.fetch_byte();

            return self.execute(@enumFromInt(op));
        }

        pub fn print_state(self: *const Self) void {
            log.info("--- CPU State ---", .{});
            log.info("CPU PC register: 0x{X}", .{self.PC});
            log.info("CPU A register: 0x{X}", .{self.A});
            log.info("CPU X register: 0x{X}", .{self.X});
            log.info("CPU Y register: 0x{X}", .{self.Y});
            log.info("CPU SP register: 0x{X}", .{self.SP});
            log.info("CPU status register: 0b{b}", .{self.status});
            self.print_stack();
        }

        pub fn print_stack(self: *const Self) void {
            log.info("--- Stack Trace (SP: 0x{X:02}) ---", .{self.SP});

            var current_sp = self.SP + 1;
            const stack_start = Bus.STACK_START;

            if (self.SP >= stack_start) {
                log.info("  [Stack Empty]", .{});
                return;
            }

            while (current_sp <= stack_start) : (current_sp +%= 1) {
                const absolute_addr: u16 = (0x0100 + @as(u16, current_sp & 0xFF));
                const value = self.read_byte(absolute_addr);

                log.info("  Addr: 0x{X:04} -> Value: 0x{X:02}", .{
                    absolute_addr,
                    value,
                });
            }
            log.info("---------------------------------", .{});
        }
    };
}

fn page_crossed(base: u16, final: u16) bool {
    return (base & 0xFF00) != (final & 0xFF00);
}
