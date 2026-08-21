pub const Opcode = enum(u8) {
    // ADC - Add with Carry
    ADC_IM = 0x69,
    ADC_ZP = 0x65,
    ADC_ZP_X = 0x75,
    ADC_ABS = 0x6D,
    ADC_ABS_X = 0x7D,
    ADC_ABS_Y = 0x79,
    ADC_IND_X = 0x61,
    ADC_IND_Y = 0x71,

    // AND - Logical AND
    AND_IM = 0x29,
    AND_ZP = 0x25,
    AND_ZP_X = 0x35,
    AND_ABS = 0x2D,
    AND_ABS_X = 0x3D,
    AND_ABS_Y = 0x39,
    AND_IND_X = 0x21,
    AND_IND_Y = 0x31,

    // ASL - Arithmetic Shift Left
    ASL_ACC = 0x0A,
    ASL_ZP = 0x06,
    ASL_ZP_X = 0x16,
    ASL_ABS = 0x0E,
    ASL_ABS_X = 0x1E,

    // Branches
    BCC_REL = 0x90,
    BCS_REL = 0xB0,
    BEQ_REL = 0xF0,
    BMI_REL = 0x30,
    BNE_REL = 0xD0,
    BPL_REL = 0x10,
    BVC_REL = 0x50,
    BVS_REL = 0x70,

    // BIT - Bit Test
    BIT_ZP = 0x24,
    BIT_ABS = 0x2C,

    // BRK
    BRK_IMPL = 0x00,

    // Clear flags
    CLC_IMPL = 0x18,
    CLD_IMPL = 0xD8,
    CLI_IMPL = 0x58,
    CLV_IMPL = 0xB8,

    // CMP - Compare
    CMP_IM = 0xC9,
    CMP_ZP = 0xC5,
    CMP_ZP_X = 0xD5,
    CMP_ABS = 0xCD,
    CMP_ABS_X = 0xDD,
    CMP_ABS_Y = 0xD9,
    CMP_IND_X = 0xC1,
    CMP_IND_Y = 0xD1,

    // CPX - Compare X
    CPX_IM = 0xE0,
    CPX_ZP = 0xE4,
    CPX_ABS = 0xEC,

    // CPY - Compare Y
    CPY_IM = 0xC0,
    CPY_ZP = 0xC4,
    CPY_ABS = 0xCC,

    // DEC - Decrement Memory
    DEC_ZP = 0xC6,
    DEC_ZP_X = 0xD6,
    DEC_ABS = 0xCE,
    DEC_ABS_X = 0xDE,

    DEX_IMPL = 0xCA,
    DEY_IMPL = 0x88,

    // EOR - Exclusive OR
    EOR_IM = 0x49,
    EOR_ZP = 0x45,
    EOR_ZP_X = 0x55,
    EOR_ABS = 0x4D,
    EOR_ABS_X = 0x5D,
    EOR_ABS_Y = 0x59,
    EOR_IND_X = 0x41,
    EOR_IND_Y = 0x51,

    // INC - Increment Memory
    INC_ZP = 0xE6,
    INC_ZP_X = 0xF6,
    INC_ABS = 0xEE,
    INC_ABS_X = 0xFE,

    INX_IMPL = 0xE8,
    INY_IMPL = 0xC8,

    // JMP
    JMP_ABS = 0x4C,
    JMP_IND = 0x6C,

    // JSR
    JSR_ABS = 0x20,

    // LDA - Load Accumulator
    LDA_IM = 0xA9,
    LDA_ZP = 0xA5,
    LDA_ZP_X = 0xB5,
    LDA_ABS = 0xAD,
    LDA_ABS_X = 0xBD,
    LDA_ABS_Y = 0xB9,
    LDA_IND_X = 0xA1,
    LDA_IND_Y = 0xB1,

    // LDX - Load X
    LDX_IM = 0xA2,
    LDX_ZP = 0xA6,
    LDX_ZP_Y = 0xB6,
    LDX_ABS = 0xAE,
    LDX_ABS_Y = 0xBE,

    // LDY - Load Y
    LDY_IM = 0xA0,
    LDY_ZP = 0xA4,
    LDY_ZP_X = 0xB4,
    LDY_ABS = 0xAC,
    LDY_ABS_X = 0xBC,

    // LSR - Logical Shift Right
    LSR_ACC = 0x4A,
    LSR_ZP = 0x46,
    LSR_ZP_X = 0x56,
    LSR_ABS = 0x4E,
    LSR_ABS_X = 0x5E,

    // NOP
    NOP_IMPL = 0xEA,

    // ORA - Logical Inclusive OR
    ORA_IM = 0x09,
    ORA_ZP = 0x05,
    ORA_ZP_X = 0x15,
    ORA_ABS = 0x0D,
    ORA_ABS_X = 0x1D,
    ORA_ABS_Y = 0x19,
    ORA_IND_X = 0x01,
    ORA_IND_Y = 0x11,

    // Stack ops
    PHA_IMPL = 0x48,
    PHP_IMPL = 0x08,
    PLA_IMPL = 0x68,
    PLP_IMPL = 0x28,

    // ROL - Rotate Left
    ROL_ACC = 0x2A,
    ROL_ZP = 0x26,
    ROL_ZP_X = 0x36,
    ROL_ABS = 0x2E,
    ROL_ABS_X = 0x3E,

    // ROR - Rotate Right
    ROR_ACC = 0x6A,
    ROR_ZP = 0x66,
    ROR_ZP_X = 0x76,
    ROR_ABS = 0x6E,
    ROR_ABS_X = 0x7E,

    // RTI / RTS
    RTI_IMPL = 0x40,
    RTS_IMPL = 0x60,

    // SBC - Subtract with Carry
    SBC_IM = 0xE9,
    SBC_ZP = 0xE5,
    SBC_ZP_X = 0xF5,
    SBC_ABS = 0xED,
    SBC_ABS_X = 0xFD,
    SBC_ABS_Y = 0xF9,
    SBC_IND_X = 0xE1,
    SBC_IND_Y = 0xF1,

    // Set flags
    SEC_IMPL = 0x38,
    SED_IMPL = 0xF8,
    SEI_IMPL = 0x78,

    // STA - Store Accumulator
    STA_ZP = 0x85,
    STA_ZP_X = 0x95,
    STA_ABS = 0x8D,
    STA_ABS_X = 0x9D,
    STA_ABS_Y = 0x99,
    STA_IND_X = 0x81,
    STA_IND_Y = 0x91,

    // STX - Store X
    STX_ZP = 0x86,
    STX_ZP_Y = 0x96,
    STX_ABS = 0x8E,

    // STY - Store Y
    STY_ZP = 0x84,
    STY_ZP_X = 0x94,
    STY_ABS = 0x8C,

    // Transfers
    TAX_IMPL = 0xAA,
    TAY_IMPL = 0xA8,
    TSX_IMPL = 0xBA,
    TXA_IMPL = 0x8A,
    TXS_IMPL = 0x9A,
    TYA_IMPL = 0x98,

    _,
};
