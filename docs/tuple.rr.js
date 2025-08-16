Diagram(Start({ type: "complex", label: "tuple" }),
  "(",
  ZeroOrMore(NonTerminal("value"), ","),
  Optional(Sequence(NonTerminal("whitespace"), ","), "skip"),
  NonTerminal("whitespace"), ")",
  End({ type: "complex" })
)
