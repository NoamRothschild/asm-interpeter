pub const ParseError = error{
    UnknownInstruction,
    MismatchingOperandSizes,
    InvalidOperandType,
    ImmediateOutOfRange,
    UnknownLabel,
    InvalidExpression,
    InvalidEffectiveAddress,
};

pub const ExecError = error{
    Halted,
    MissingOperand,
};
