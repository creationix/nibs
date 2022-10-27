import * as Tibs from "../tibs.js"

const tests = [
    '[1,2,3]',
    '(&1,2,3)',
    '[#1,2,3]',
    '[null,2,null]',
    '([&0,null],2,null)',
    '[#null,2,null]',
    '{1:2,3:4,5:null}',
    '{#1:2,3:4,5:null}',
    '<0123456789abcdef>',
    '-9223372036854775808',
    '9223372036854775807',
]
for (const t of tests) {
    const decoded = Tibs.decode(t)
    const encoded = Tibs.encode(decoded)
    console.log({ t, decoded, encoded })
    if (encoded !== t) throw new Error("Mismatch")
}
