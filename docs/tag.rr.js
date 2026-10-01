Diagram(Start({ label: "tag" }),
  "!",
  Choice(0,
    Sequence(NonTerminal("digit 1-9"), ZeroOrMore(NonTerminal("digit"))),
    Sequence("0")),
  NonTerminal("value")
)
