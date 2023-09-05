Diagram(Start({ label: "string" }),
  '"', ZeroOrMore(
    Choice(0,
      NonTerminal('Any codepoint except\n" or \\ or control characters'),
      Sequence('\\', Choice(0,
        '"', '\\', '/', 'b', 'f', 'n', 'r', 't',
        Sequence('u', NonTerminal('4 hex\ndigits'))
      ))
    )
  ), '"'
)

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

Diagram(Start({ label: "binary" }),
  "<",
  ZeroOrMore(NonTerminal("2 hex digits")),
  ">"
)


Diagram(Start({ label: "map" }),
  "{",
  ZeroOrMore(
    Sequence(NonTerminal("value"), ":", NonTerminal("value")),
    ","
  ),
  Optional(Sequence(NonTerminal("whitespace"), ","), "skip"),
  NonTerminal("whitespace"), "}"
)

Diagram(Start({ label: "array" }),
  "[",
  ZeroOrMore(NonTerminal("value"), ","),
  Optional(Sequence(NonTerminal("whitespace"), ","), "skip"),
  NonTerminal("whitespace"), "]"
)

Diagram(Start({ label: "tuple" }),
  "(",
  ZeroOrMore(NonTerminal("value"), ","),
  Optional(Sequence(NonTerminal("whitespace"), ","), "skip"),
  NonTerminal("whitespace"), ")"
)

Diagram(Start({ label: "ref" }),
  "&",
  Choice(0,
    Sequence(NonTerminal("digit 1-9"), ZeroOrMore(NonTerminal("digit"))),
    Sequence("0"))
)

Diagram(Start({ label: "tag" }),
  "!",
  Choice(0,
    Sequence(NonTerminal("digit 1-9"), ZeroOrMore(NonTerminal("digit"))),
    Sequence("0")),
  NonTerminal("value")
)

Diagram(Start({ label: "value" }),
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
  NonTerminal("whitespace")
)

Diagram(Start({ label: "whitespace" }), ZeroOrMore(Choice(0,
  Sequence(" ", Comment("space")),
  Sequence("\n", Comment("linefeed")),
  Sequence("\r", Comment("carriage return")),
  Sequence("\t", Comment("horizontal tab")),
  Sequence("//", ZeroOrMore(NonTerminal("any codepoint except linefeed")), Comment("line comment")),
  Sequence("/*", ZeroOrMore(Choice(0,
    NonTerminal("any codepoint except *"),
    Sequence("*", NonTerminal("any codepoint except /"))
  )), "*/", Comment("block comment"))
), null, "skip"))