Diagram(Start({ type: "complex", label: "value" }),
  NonTerminal("whitespace"),
  Choice(0,
    NonTerminal("string"),
    NonTerminal("binary"),
    NonTerminal("integer"),
    NonTerminal("float"),
    NonTerminal("tag"),
    NonTerminal("ref"),
    NonTerminal("map"),
    NonTerminal("array"),
    NonTerminal("tuple"),
    "true", "false", "null"
  ),
  NonTerminal("whitespace"),
  End({ type: "complex" })
)
