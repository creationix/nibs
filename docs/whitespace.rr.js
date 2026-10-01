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
