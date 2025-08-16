Diagram(Start({ label: "float" }), Choice(0,
  Sequence(Optional("-", "skip"), Choice(0,
    Stack(
      Choice(0,
        "0",
        Sequence(NonTerminal("digit 1-9"), ZeroOrMore(NonTerminal("digit")))
      ),
      Choice(0, Sequence(
        ".",
        OneOrMore(NonTerminal("digit"))
      )),
      Choice(0, Choice(0, Comment("optional exponent"), Sequence(
        Choice(1, "E", "e"),
        Choice(1, "-", Skip(), "+"),
        OneOrMore(NonTerminal("digit"))
      )))
    ), "inf")
  ),
  "nan"
))
