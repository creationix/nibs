import { fstat, readFileSync } from "node:fs"

const colors = {
    property: "38;5;253",
    braces: "38;5;247",
    sep: "38;5;240",

    nil: "38;5;244",
    boolean: "38;5;220", // yellow-orange
    number: "38;5;202", //orange
    string: "38;5;34", //darker green
    quotes: "38;5;40", //green
    escape: "38;5;46", //bright green
    function: "38;5;129", //purple
    thread: "38;5;199", //pink

    table: "38;5;27", //blue
    userdata: "38;5;39", //blue2
    cdata: "38;5;69", //teal

    err: "38;5;196", //bright red
    success: "38;5;120;48;5;22", //bright green on dark green
    failure: "38;5;215;48;5;52", //bright red on dark red
    highlight: "38;5;45;48;5;236", //bright teal on dark grey
}

/**
 * @param {string} colorName 
 * @returns string
 */
function color(colorName) {
    return `\u001b[${colors[colorName] || '0'}m`
}

function colorize(colorName, string, resetName) {
    return color(colorName) + string + color(resetName)
}

const tests = readFileSync("../nibs-tests.txt", "utf8")

const section = /^([^=|]+)$/
const config = /([^=]+)=([^=]+)/
const test = /([^|]+)\|([^|]+)/

for (const line of tests.split("\n")) {
    let m = line.match(section)
    if (m) {
        const title = m[1].trim()
        console.log("\n" + colorize("highlight", line) + "\n")
        continue
    }
    m = line.match(config)
    if (m) {
        const name = m[1].trim()
        const val = parseInt(m[2].trim(), 10)
        console.log("config", { name, val })
        continue
    }
    m = line.match(test)
    if (m) {
        const text = m[1].trim()
        const hex = m[2].trim()
        console.log("test", { text, hex })
        continue
    }
}

