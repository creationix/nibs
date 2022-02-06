import { readFileSync } from 'fs'
import { encode, decode } from "../js/nibs.js"

const json = readFileSync("data.json", 'utf8')
const nibs = readFileSync("data.nibs")


function bench(name, action, fn) {
    let start = Date.now()
    console.log(`Running ${name} ${action} for 5 seconds...`)
    let count = 0
    while (Date.now() - start < 1000 * 5) {
        fn(count)
        count++
    }
    const rps = count / (Date.now() - start) * 1000
    console.log(`${name} ${action}s per second:`, rps)
    return rps
}

function walk(data, i) {
    const { weather: { [i]: { Station: { City, State } } } } = data
    return { City, State }
}

for (let i = 0; i < 5; i++) {
    bench("nibs", "decode", () => decode(nibs))
    const nibsData = decode(nibs)
    bench("nibs", "walk", (i) => walk(nibsData, i % 100))
    bench("json", "parse", () => JSON.parse(json))
    const data = JSON.parse(json)
    bench("json", "encode", () => JSON.stringify(data))
    bench("nibs", "encode", () => encode(data))
}
