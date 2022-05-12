Diagram(Start({ type: "complex", label: "map" }),
  "{",
  ZeroOrMore(
    Sequence(NonTerminal("value"), ":", NonTerminal("value")),
    ","
  ),
  Optional(Sequence(NonTerminal("whitespace"), ","), "skip"),
  NonTerminal("whitespace"), "}",
  End({ type: "complex" })
)
