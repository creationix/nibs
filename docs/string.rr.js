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
