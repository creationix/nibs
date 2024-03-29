import { isRef, isScope, isIndexed } from "./symbols.js"

/**
 * Decode a tibs value to native JS values.
 * @param {string} str input tibs encoded string (JSON superset)
 * @param {string} filename optional filename for error messages
 */
export function decode(str, filename = '(string)') {
    if (typeof str !== 'string') throw new Error("String expected to Tibs.decode")
    let offset = 0
    return decodeAny()

    /** @returns {never} */
    function syntaxError() {
        const code = str.codePointAt(offset)
        if (!code) throw new SyntaxError('Unexpected EOS')
        const c = String.fromCodePoint(code)
        const name = filename || "(input string)"
        let row = 0
        let col
        for (const line of str.substring(0, offset).split("\n")) {
            row++
            col = line.length + 1
        }
        throw new SyntaxError(`Unexpected ${JSON.stringify(c)} at ${name}:${row}:${col}`)
    }

    /** @returns {string} */
    function nextToken() {
        for (; ;) {
            const c = str[offset]
            if (!c) return syntaxError()
            if (c !== '\t' && c !== '\n' && c !== '\r' && c !== ' ') {
                return c
            }
            offset++
        }
    }

    function decodeAny() {
        const c = nextToken()
        if (c >= '0' && c <= '9')
            return decodeNumber()
        switch (c) {
            case '-':
                if (str.substring(offset, offset + 4) === "-inf") {
                    offset += 4
                    return -Infinity
                }
                return decodeNumber()
            case 'i':
                if (str.substring(offset, offset + 3) === 'inf') {
                    offset += 3
                    return Infinity
                }
                syntaxError()
            case 'n':
                switch (str.substring(offset, offset + 3)) {
                    case 'nan':
                        offset += 3
                        return NaN
                    case 'nul':
                        if (str[offset + 3] == 'l') {
                            offset += 4
                            return null
                        }
                }
                syntaxError()
            case 'f':
                if (str.substring(offset, offset + 5) === 'false') {
                    offset += 5
                    return false
                }
                syntaxError()
            case 't':
                if (str.substring(offset, offset + 4) === 'true') {
                    offset += 4
                    return true
                }
                syntaxError()
            case "<":
                return decodeBytes()
            case '"':
                return decodeString()
            case '&':
                return decodeRef()
            case '[':
                return decodeListOrArray()
            case '{':
                return decodeMapOrTrie()
            case '(':
                return decodeScope()
            default:
                return syntaxError()
        }
    }

    /** @returns {number|BigInt} */
    function decodeNumber() {
        const start = offset

        let num = 0n
        let sign = 1n
        let c = str[offset]

        // Parse optional leading negative sign
        if (c === '-') {
            sign = -1n
            offset++
        }

        for (; ;) {
            c = str[offset]
            if (c >= '0' && c <= '9') {
                num = num * 10n + BigInt(c.charCodeAt(0) - 0x30)
                offset++
            } else if (c === '.' || c === 'e' || c === 'E') {
                offset = start
                return decodeFloat()
            } else {
                break
            }
        }

        // Return as normal number when safe
        return num <= Number.MAX_SAFE_INTEGER ?
            Number(num * sign) : num * sign
    }

    /** @returns {number} */
    function decodeFloat() {
        const m = str.substr(offset).match(/^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/)
        if (!m) syntaxError()
        const match = m[0]
        offset += match.length
        return parseFloat(match)
    }

    /** @returns {string} */
    function decodeString() {
        const start = offset
        offset++
        for (; ;) {
            const s = str[offset]
            if (!s) syntaxError()

            // Break on closing double quote
            if (s === '"') {
                offset++
                break
            }

            // Reject newlines
            if (s === '\n' || s === '\r') syntaxError()

            // Consume a character
            offset++

            // Skip the rest of escapes if found
            if (s === '\\') {
                const e = str[offset]
                if (!e) syntaxError()
                if (e === 'u') {
                    offset += 4
                } else {
                    offset++
                }
            }
        }

        // Let JSON.parse to the hard work for us :D
        return JSON.parse(str.substring(start, offset))
    }

    /** @returns {Uint8Array} */
    function decodeBytes() {
        // Skip leading angle bracket
        offset++

        const start = offset
        let count = 0
        for (; ;) {

            // Allow whitespace by using nextToken
            const c = nextToken()

            // Stop when we reach end of value
            if (c === '>') break

            // Count valid nibbles
            if (c >= '0' && c <= '9' ||
                c >= 'a' && c <= 'f' ||
                c >= 'A' && c <= 'F') {
                offset++
                count++
                continue
            }

            // Reject other characters
            syntaxError()
        }
        const end = offset + 1

        // Reject odd number of nibbles
        if (count % 2) syntaxError()
        count >>= 1

        const buf = new Uint8Array(count)

        // Loop again, but write into the buffer
        offset = start
        let index = 0
        while (index < count) {
            let code = nextToken().charCodeAt(0)
            const high = code <= 57 ? code - 48 :
                code <= 70 ? code - 55 :
                    code - 87
            offset++
            code = nextToken().charCodeAt(0)
            const low = code <= 57 ? code - 48 :
                code <= 70 ? code - 55 :
                    code - 87
            offset++
            buf[index++] = (high << 4) | low
        }
        offset = end
        return buf
    }

    function decodeRef() {
        offset++ // Skip ampersand

        let ref = 0
        for (; ;) {
            const c = nextToken()
            if (c >= '0' && c <= '9') {
                ref = ref * 10 + c.charCodeAt(0) - 48
                offset++
            }
            break
        }
        const obj = {}
        Object.defineProperty(obj, isRef, { value: ref })
        return obj
    }

    /** @returns {array} */
    function decodeListOrArray() {
        const arr = []

        // Skip leading square bracket
        offset++

        if (str[offset] === '#') {
            Object.defineProperty(arr, isIndexed, { value: true })
            offset++
        }
        for (let expectComma = false; ; expectComma = true) {
            // Read the next token
            let c = nextToken()

            // Exit the loop if it's a closing square bracket
            if (c === ']') {
                offset++
                break
            }

            // Consume a comma if we're not on the first loop
            if (expectComma) {
                if (c !== ',') return syntaxError()
                offset++
                c = nextToken()
            }

            // Allow trailing commas by checking again for closing bracket
            if (c === ']') {
                offset++
                break
            }

            // Parse a single value
            const value = decodeAny()

            // Store it in the array
            arr.push(value)
        }

        return arr
    }

    /** @returns {object} */
    function decodeMapOrTrie() {
        let obj = new Map()
        let allStrings = true
        let hasIndex = false

        // Skip leading curly brace
        offset++

        // If the object is annotated with `#` mark it as indexed for nibs.
        if (str[offset] === '#') {
            hasIndex = true
            offset++
        }

        for (let expectComma = false; ; expectComma = true) {
            // Read the next token
            let c = nextToken()

            // Exit the loop if it's a closing curly brace
            if (c === '}') {
                offset++
                break
            }

            // Consume a comma if we're not on the first loop
            if (expectComma) {
                if (c !== ',') return syntaxError()
                offset++
                c = nextToken()
            }

            // Allow trailing commas by checking again for closing brace
            if (c === '}') {
                offset++
                break
            }

            // Parse a single value as key
            const key = decodeAny()

            // Consume the colon
            c = nextToken()
            if (c !== ':') syntaxError()
            offset++

            // Parse a single value
            const value = decodeAny()

            if (typeof key !== 'string') allStrings = false

            // Store it in the object
            obj.set(key, value)
        }
        if (allStrings) {
            obj = Object.fromEntries(obj.entries())
        }
        if (hasIndex) {
            Object.defineProperty(obj, isIndexed, { value: true })
        }
        return obj
    }
    function decodeScope() {
        const scope = []

        Object.defineProperty(scope, isScope, { value: true })

        offset++ // Skip leading paren

        for (let expectComma = false; ; expectComma = true) {

            // Read the next token
            let c = nextToken()

            // Exit the loop if it's a closing paren
            if (c === ')') {
                offset++
                break
            }

            // Consume a comma if we're not on the first loop
            if (expectComma) {
                if (c !== ',') return syntaxError()
                offset++
                c = nextToken()
            }

            // Allow trailing commas by checking again for closing paren
            if (c === ')') {
                offset++
                break
            }

            // Parse a single value
            const value = decodeAny()

            // Store it in the object
            scope.push(value)
        }

        return scope
    }
}

/**
 * @param {any} val 
 * @returns {string}
 */
export function encode(val) {
    if (val === Infinity) return 'inf'
    if (val === -Infinity) return '-inf'
    if (val !== val) return 'nan'
    const t = typeof (val)
    if (t === 'bigint') return val.toString(10)
    if (t !== 'object' || !val) return JSON.stringify(val)
    if (val[isScope]) {
        return '(' +
            val
                .map(entry => encode(entry))
                .join(",") +
            ')'
    }
    if (val[isRef] !== undefined) {
        return '&' + val[isRef]
    }
    const c = Object.prototype.toString.call(val)
    switch (c) {
        case '[object Map]':
            return '{' + (val[isIndexed] ? "#" : "") +
                Array.from(val.entries())
                    .map((([k, v]) => encode(k) + ":" + encode(v)))
                    .join(',') +
                '}'
        case '[object Array]':
            return '[' + (val[isIndexed] ? "#" : "") +
                val
                    .map(entry => encode(entry))
                    .join(",") +
                ']'
        case '[object Uint8Array]':
            return '<' +
                Array.prototype.map.call(val, byte => byte.toString(16).padStart(2, '0'))
                    .join('') +
                '>'
    }
    return '{' + (val[isIndexed] ? "#" : "") +
        Array.from(Object.entries(val))
            .map((([k, v]) => encode(k) + ":" + encode(v)))
            .join(',') +
        '}'
}