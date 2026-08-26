const root = @import("root.zig");
const Op = root.Op;

pub fn RomBuilder(comptime Bus: type) type {
    return struct {
        const Self = @This();

        bytes: [Bus.MEM_SIZE]u8 = @splat(0xEA),
        pos: u16 = 0,

        pub fn org(self: *Self, addr: u16) *Self {
            self.pos = addr;
            return self;
        }

        pub fn byte(self: *Self, b: u8) *Self {
            self.bytes[self.pos] = b;
            self.pos +%= 1;
            return self;
        }

        pub fn word(self: *Self, w: u16) *Self {
            self.bytes[self.pos] = @truncate(w);
            self.bytes[self.pos +% 1] = @truncate(w >> 8);
            self.pos +%= 2;
            return self;
        }

        pub fn op(self: *Self, o: Op) *Self {
            return self.byte(@intFromEnum(o));
        }

        pub fn reset_vector(self: *Self, addr: u16) *Self {
            const saved = self.pos;
            self.pos = Bus.RESET_VECTOR_ADDR;
            _ = self.word(addr);
            self.pos = saved;
            return self;
        }

        pub fn irq_vector(self: *Self, addr: u16) *Self {
            const saved = self.pos;
            self.pos = Bus.IRQ_VECTOR;
            _ = self.word(addr);
            self.pos = saved;
            return self;
        }

        pub fn build(self: *Self) [Bus.MEM_SIZE]u8 {
            return self.bytes;
        }
    };
}
