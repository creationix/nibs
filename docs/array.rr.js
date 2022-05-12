Diagram(Start({ type: "complex", label: "array" }),
  "[",
  ZeroOrMore(NonTerminal("value"), ","),
  Optional(Sequence(NonTerminal("whitespace"), ","), "skip"),
  NonTerminal("whitespace"), "]",
  End({ type: "complex" })
)
