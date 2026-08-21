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

        PC: u16 = Bus.RESET_VECTOR,

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

        pub fn read_word_zp(self: *const Self, addr: u8) u16 {
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

        pub fn get_flag(self: *const Self, flag: StatusFlag) u1 {
            return @intFromBool((self.status & @intFromEnum(flag)) != 0);
        }

        pub fn execute(self: *Self, op: Opcode) u8 {
            return switch (op) {
                Opcode.ADC_IM => blk: {
                    const operand = self.fetch_byte();
                    self._adc(operand);
                    break :blk 2;
                },
                Opcode.ADC_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    break :blk 3;
                },
                Opcode.ADC_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr: u8 = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    break :blk 4;
                },
                Opcode.ADC_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    break :blk 4;
                },
                Opcode.ADC_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._adc(operand);

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.ADC_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);

                    self._adc(operand);

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.ADC_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._adc(operand);

                    break :blk 6;
                },
                Opcode.ADC_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);

                    self._adc(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;

                    break :blk 6 + extra;
                },

                Opcode.AND_IM => blk: {
                    const operand = self.fetch_byte();
                    self._and(operand);

                    break :blk 2;
                },
                Opcode.AND_ZP => blk: {
                    const addr = self.fetch_byte();
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    break :blk 3;
                },
                Opcode.AND_ZP_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    break :blk 4;
                },
                Opcode.AND_ABS => blk: {
                    const addr = self.fetch_word();
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    break :blk 4;
                },
                Opcode.AND_ABS_X => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.X;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.AND_ABS_Y => blk: {
                    const base = self.fetch_word();
                    const addr = base +% self.Y;
                    const operand = self.read_byte(addr);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(addr, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.AND_IND_X => blk: {
                    const base = self.fetch_byte();
                    const addr = base +% self.X;
                    const target = self.read_word_zp(addr);
                    const operand = self.read_byte(target);
                    self._and(operand);

                    break :blk 6;
                },
                Opcode.AND_IND_Y => blk: {
                    const operand_addr = self.fetch_byte();
                    const base = self.read_word_zp(operand_addr);
                    const target = base +% self.Y;
                    const operand = self.read_byte(target);
                    self._and(operand);

                    const extra: u8 = if (page_crossed(base, target)) 1 else 0;
                    break :blk 5 + extra;
                },

                Opcode.LDA_IM => blk: {
                    self.A = self.fetch_byte();

                    self.set_flag(.ZERO, self.A == 0);
                    self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);

                    break :blk 2;
                },
                Opcode.LDA_ZP => blk: {
                    const target = self.fetch_byte();
                    self._lda(target);

                    break :blk 3;
                },
                Opcode.LDA_ZP_X => blk: {
                    const operand = self.fetch_byte();
                    const target: u8 = operand +% self.X;
                    self._lda(target);

                    break :blk 4;
                },
                Opcode.LDA_ABS => blk: {
                    const operand = self.fetch_word();
                    self._lda(operand);

                    break :blk 4;
                },
                Opcode.LDA_ABS_X => blk: {
                    const operand = self.fetch_word();
                    const addr = operand +% self.X;
                    self._lda(addr);

                    const extra: u8 = if (page_crossed(operand, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.LDA_ABS_Y => blk: {
                    const operand = self.fetch_word();
                    const addr = operand +% self.Y;
                    self._lda(addr);

                    const extra: u8 = if (page_crossed(operand, addr)) 1 else 0;
                    break :blk 4 + extra;
                },
                Opcode.LDA_IND_X => blk: {
                    const operand = self.fetch_byte();
                    const addr = operand +% self.X;
                    const target = self.read_word_zp(addr);
                    self._lda(target);

                    break :blk 6;
                },
                Opcode.LDA_IND_Y => blk: {
                    const operand = self.fetch_byte();
                    const addr = self.read_word_zp(operand);
                    const target = addr +% self.Y;
                    self._lda(target);

                    const extra: u8 = if (page_crossed(addr, target)) 1 else 0;
                    break :blk 5 + extra;
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

                Opcode.BRK_IMPL => blk: {
                    self.push_word(self.PC);
                    self.push_byte(self.status);

                    self.PC = Bus.IRQ_VECTOR;
                    self.set_flag(.BREAK, true);

                    break :blk 7;
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

            if (self.SP == Bus.STACK_START) {
                log.info("[Stack Empty]", .{});
                return;
            }

            const start_addr: u16 = self.SP;
            const end_addr: u16 = Bus.STACK_START;

            for (start_addr..end_addr) |i| {
                const addr: u16 = @intCast(Bus.STACK_START + i);
                const value = self.read_byte(addr);

                log.info("Addr: 0x{X:04} -> Value: 0x{X:02}", .{
                    addr,
                    value,
                });
            }
            log.info("---------------------------------", .{});
        }

        inline fn _lda(self: *Self, target: u16) void {
            self.A = self.read_byte(target);
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
        }

        inline fn _adc(self: *Self, operand: u8) void {
            const sum = self.A + operand + self.get_flag(.CARRY);
            self.set_flag(.CARRY, sum > 0xFF);
            const overflow = ((self.A ^ sum) & (operand ^ sum) & 1 << 7) != 0;
            self.set_flag(.OVERFLOW, overflow);

            self.A = sum;
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & 1 << 7) != 0);
        }

        inline fn _and(self: *Self, operand: u8) void {
            self.A &= operand;
            self.set_flag(.ZERO, self.A == 0);
            self.set_flag(.NEGATIVE, (self.A & (1 << 7)) != 0);
        }
    };
}

inline fn page_crossed(base: u16, final: u16) bool {
    return (base & 0xFF00) != (final & 0xFF00);
}
