import { readdirSync, readFileSync, writeFileSync } from 'fs'
import { encode } from "../js/nibs.js"

console.log("Generating data.json...")
const data = {}
for (const name of readdirSync('./corgis/website/datasets/json')) {
    if (name.indexOf('.') >= 0) continue
    const json = readFileSync(`./corgis/website/datasets/json/${name}/${name}.json`, 'utf8')
    const value = JSON.parse(json)
    data[name] = value
}
const json = JSON.stringify(data)
writeFileSync("data.json", json)

console.log("Generating data.nibs...")
writeFileSync("data.nibs", encode(JSON.parse(json)))

console.log("Done Generating.")