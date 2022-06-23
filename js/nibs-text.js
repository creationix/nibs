const patterns = {
    string: /^[ \r\n\t\b]*(\"(?:[^"]|\\.)*\")/,
    bytes: /^[ \r\n\t\b]*\<((?:[0-9a-f][0-9a-f])*)\>/,
    decimal: /^[ \r\n\t\b]*([-]?[0-9]+(?:\.[0-9]+)?)/,
    special: /^[ \r\n\t\b]*(inf|-inf|nan|true|false)\b/,
}
const decoders = {
    decimal(match) {
        return parseFloat(match[0])
    },
    special(str) {
        return str == "inf" ? Infinity
            : str == "-inf" ? -Infinity
                : str === "nan" ? NaN
                    : undefined
    }
}
/**
 * @param {string} str 
 * @returns {any}
 */
export function decodeText(str) {
    for (const name in patterns) {
        const m = patterns[name].exec(str)
        console.log([name, patterns[name], str, m])
        if (m) {
            return decoders[name](...m)
        }
    }
    throw new TypeError("Unable to parse: " + str)
}
