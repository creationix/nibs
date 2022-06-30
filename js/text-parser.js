const NUMBER = /^[-+]?(?:0|[1-9][0-9]*)(?:\.[0-9]+(?:[eE][-+]?[0-9]+)?)?/
const STRING = /^"(?:[^"\r\n\\]|\\.)*"/
const BYTES = /^\<(?:[0-9a-f][0-9a-f]|[ \t\r\n]+|\/\/[^\r\n]*[\r\n]*)*\>/
const KEYWORD = /^(?:null|true|false|inf|-inf|nan)(?![a-z])/
const WHITESPACE = /^(?:[ \t\r\n]+|\/\/[^\r\n]*[\r\n]*)+/

function skipWhitespace(str) {
    let m = WHITESPACE.exec(str)
    return m ? str.substring(m[0].length) : str
}

function parseArray(str) {
    // Consume opening `[`
    if (str[0] !== "[") throw new SyntaxError("Expected '[' at start of array")
    str = skipWhitespace(str.substring(1))

    const arr = []
    let hadComma = true
    while (true) {
        if (str.length === 0) {
            throw new SyntaxError("Unexpected EOS in array")
        }

        if (str[0] === "]") {
            // consume closing `]` and exit if there is one
            str = skipWhitespace(str.substr(1))
            break
        }

        if (!hadComma) {
            throw new SyntaxError("Missing comma between values")
        }

        // Consume a value
        const [val, extra] = parseValue(str)
        arr.push(val)
        str = extra

        hadComma = false
        if (str[0] === ",") {
            // consume `,` if there is one
            str = skipWhitespace(str.substr(1))
            hadComma = true
        }

    }
    return [arr, str]
}

function parseObject(str) {
    // Consume opening `{`
    if (str[0] !== "{") throw new SyntaxError("Expected '[' at start of array")
    str = skipWhitespace(str.substring(1))

    const obj = new Map()
    let hadComma = true
    while (true) {
        if (str.length === 0) {
            throw new SyntaxError("Unexpected EOS in array")
        }

        if (str[0] === "}") {
            // consume closing `}` and exit if there is one
            str = skipWhitespace(str.substr(1))
            break
        }

        if (!hadComma) {
            throw new SyntaxError("Missing comma between values")
        }

        // Consume a key
        const [key, extra] = parseValue(str)
        str = extra

        // Consume a `:`
        if (str[0] === ":") {
            str = skipWhitespace(str.substr(1))
        } else {
            throw new SyntaxError("Missing `:` after object key")
        }

        // Consume a value
        const [val, extra2] = parseValue(str)
        str = extra2

        obj.set(key, val)

        hadComma = false
        if (str[0] === ",") {
            // consume `,` if there is one
            str = skipWhitespace(str.substr(1))
            hadComma = true
        }

    }
    return [obj, str]
}

function parseBytes(str) {
    const bytes = []
    let m
    const re = /[0-9a-f][0-9a-f]/ig
    while (m = re.exec(str)) {
        bytes.push(parseInt(m[0], 16))
    }
    return new Uint8Array(bytes)
}

/**
 * @param {string} str 
 * @returns {[any,string]}
 */
function parseValue(str) {
    str = skipWhitespace(str)
    if (str[0] === "[") {
        return parseArray(str)
    }
    if (str[0] === "{") {
        return parseObject(str)
    }
    let m = NUMBER.exec(str)
    if (m) {
        return [parseFloat(m[0]), skipWhitespace(str.substring(m[0].length))]
    }
    m = STRING.exec(str)
    if (m) {
        return [JSON.parse(m[0]), skipWhitespace(str.substring(m[0].length))]
    }
    m = BYTES.exec(str)
    if (m) {
        return [parseBytes(m[0]), skipWhitespace(str.substring(m[0].length))]
    }
    m = KEYWORD.exec(str)
    if (m) {
        return [
            m[0] === "null" ? null :
                m[0] === "true" ? true :
                    m[0] === "false" ? false :
                        m[0] === "inf" ? Infinity :
                            m[0] === "-inf" ? -Infinity :
                                m[0] === "nan" ? NaN : undefined,
            skipWhitespace(str.substring(m[0].length))
        ]
    }
    throw new Error("Nope")
}

export function parse(str) {
    const [val, extra] = parseValue(str)
    if (extra.length > 0) throw new SyntaxError(`Extra input: ${extra.trim().split("\n")[0]}`)
    return val
}
