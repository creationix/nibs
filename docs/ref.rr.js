Diagram(Start({ label: "ref" }),
  "&",
  Choice(0,
    Sequence(NonTerminal("digit 1-9"), ZeroOrMore(NonTerminal("digit"))),
    Sequence("0"))
)
