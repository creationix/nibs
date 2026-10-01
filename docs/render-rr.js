import { readdirSync, readFileSync, writeFileSync } from "node:fs"
import rr from "./railroad.js";
const {
    Diagram, Start, End,
    ZeroOrMore, Optional, Sequence, Choice, Stack, OneOrMore,
    NonTerminal, Comment, Skip,
} = rr;


for (const entry of readdirSync(".")) {
    const match = entry.match(/^([a-z]+)\.rr\.js$/)
    if (!match) continue
    const code = readFileSync(entry, "utf8")
    console.log(match[1])
    const d = eval(code)
    writeFileSync(`${match[1]}.svg`, d.toStandalone())
}
