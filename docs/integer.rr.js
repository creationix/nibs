Diagram(Start({ label: "integer" }),
  Choice(0, Skip(), "-"),
  Choice(0,
    Sequence(NonTerminal("digit 1-9"), ZeroOrMore(NonTerminal("decimal digit"))),
    Sequence("0", Choice(0, Skip(),
      Choice(0,
        Sequence(Choice(0, "x", "X"), OneOrMore(NonTerminal("hex digit"))),
        Sequence(Choice(0, "o", "O"), OneOrMore(NonTerminal("octal digit"))),
        Sequence(Choice(0, "b", "B"), OneOrMore(NonTerminal("binary digit")))
      )
    ))
  )
)
