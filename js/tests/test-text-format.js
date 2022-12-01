import { readFileSync } from 'fs'
import { join as pathJoin } from 'path'
import { fileURLToPath } from 'url';

import * as Tibs from "../tibs.js"

// Read file as newlines and trim whitespace/blank-lines
const filename = pathJoin(fileURLToPath(import.meta.url), '../../../fixtures/tibs-fixtures.txt')
const tests = readFileSync(filename, 'utf8')
    .split("\n")
    .map(t => t.trim())
    .filter(t => t)

for (const t of tests) {
    const decoded = Tibs.decode(t)
    const encoded = Tibs.encode(decoded)
    console.log({ t, decoded, encoded })
    if (encoded !== t) throw new Error("Mismatch")
}
