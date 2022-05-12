# Nibs Text Format

Nibs documents can be represented in a textual format.  While this format isn't as fast to parse and takes up more space, it has some various use cases that make it very handy.

## Full Nibs Semantics

The nibs text format can fully encode any nibs document and allow round-tripping back and forth without any data changing.

- Nibs `integer` is encoded as decimal text.
- Nibs `float` is encoded as JSON number, but always has the decimal point and at least one digit of precision.
  - Special Nibs `float` values are encoded as `inf`, `-inf`, and `nan`.
- Nibs `boolean` is encoded as `true` or `false`.
- Nibs `null` is encoded as `null`.
- Nibs `binary` is encoded as `<XXXXXX>` where `XX` is a byte in hexadecimal.
- Nibs `string` is encoded the same way as JSON `string`.
- Nibs `map` is encoded the same way as JSON `object` except any value is allowed for keys (not just strings).
- Nibs `array` is encoded the same way as JSON `array`.
- Nibs `tuple` is encoded like array, except `(` and `)` are used in place of the square brackets.
- Nibs `ref` is encoded as `&` followed by a decimal ref index.
- Nibs `tag` is encoded as `!` followed by a decimal tag index and then a nibs text value.

## Made for Humans

The binary nibs format is optimized for machines, but this text format is for humans.  As such it adds a couple of nice things to make it easier to write and maintain by hand.

- JS style like and block comments.
- Optional trailing comma in lists.
- Insignificant whitespace.

## JSON Interoperability

One property of this format's design is that it is a superset of JSON.  This means that the nibs text format decoder can consume JSON documents since they are all also valid nibs-text documents!

- JSON `number` with no decimal becomes Nibs `integer`
- JSON `number` with a decimal becomes Nibs `float`
- JSON `object` becomes Nibs `map`
- JSON `array` becomes Nibs `array` (index is generated)
- `null`, `string` and `boolean` are the same in both

Also the nibs-text encoder should have an option to limit to the JSON subset.  This has some lossy properties:

- Nibs `integer` becomes JSON `number`
- Nibs `float` becomes JSON `number` that always have a decimal point
- Nibs `binary` becomes hex encoded JSON `string`
- Nibs `array` and `tuple` becomes JSON `array` (tuples get upgraded to arrays)
- Nibs `map` becomes JSON `object` (any non-string keys are encoded in nibs-text as strings)
- Nibs `tag` is discarded
- Nibs `ref` is dereferenced
- `null`, `string` and `boolean` are the same in both

## Embedding in Restricted Storage

Nibs' normal binary format cannot be used in places that don't support arbitrary binary data.  But using the textual representation of a nibs document allows it to be stored in many places:

- Inline in source code
- Configuration files
- HTTP header values (as ASCII)
- Web LocalStorage
- JavaScript strings
- As a debugging tool to log values to the console.
- etc...

*Note*: When storing nibs in HTTP header values to make sure to encode it in ASCII mode by escaping all non-ascii characters using the JSON `\uXXXX` syntax.

## Proposed APIs

When implementing a nibs library, this is a recommended API for the nibs-text portion:

```ts
declare class Nibs {

  // Encode a live nibs value into it's string representation
  // The `ascii` option escapes UTF-8 characters.
  // The `json` option toggles between JSON compability and full
  // data fidelity.
  toString(value: any, opts?: { ascii: boolean, json: boolean }): string;

  // Decode a nibs-text value into a live nibs value.
  fromString(str: string): any;

}
```

## Railroad Diagrams

<svg class="railroad-diagram" width="783" height="349" viewBox="0 0 783 349" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h64"></path>
<text x="20" y="25" style="text-anchor:start">string</text>
</g>
<path d="M84 40h10"></path>
<g class="terminal ">
<path d="M94 40h0"></path>
<path d="M123 40h0"></path>
<rect x="94" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="108.5" y="44">"</text>
</g>
<path d="M123 40h10"></path>
<g>
<path d="M133 40h0"></path>
<path d="M694 40h0"></path>
<path d="M133 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M153 20h521"></path>
</g>
<path d="M674 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M133 40h20"></path>
<g>
<path d="M153 40h0"></path>
<path d="M674 40h0"></path>
<path d="M153 40h10"></path>
<g>
<path d="M163 40h0"></path>
<path d="M664 40h0"></path>
<path d="M163 40h20"></path>
<g class="non-terminal ">
<path d="M183 40h0"></path>
<path d="M644 40h0"></path>
<rect x="183" y="29" width="461" height="22"></rect>
<text x="413.5" y="44">Any codepoint except
" or \ or control characters</text>
</g>
<path d="M644 40h20"></path>
<path d="M163 40a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g>
<path d="M183 70h102.5"></path>
<path d="M541.5 70h102.5"></path>
<g class="terminal ">
<path d="M285.5 70h0"></path>
<path d="M314.5 70h0"></path>
<rect x="285.5" y="59" width="29" height="22" rx="10" ry="10"></rect>
<text x="300" y="74">\</text>
</g>
<path d="M314.5 70h10"></path>
<g>
<path d="M324.5 70h0"></path>
<path d="M541.5 70h0"></path>
<path d="M324.5 70h20"></path>
<g class="terminal ">
<path d="M344.5 70h74"></path>
<path d="M447.5 70h74"></path>
<rect x="418.5" y="59" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="74">"</text>
</g>
<path d="M521.5 70h20"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 100h74"></path>
<path d="M447.5 100h74"></path>
<rect x="418.5" y="89" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="104">\</text>
</g>
<path d="M521.5 100a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v40a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 130h74"></path>
<path d="M447.5 130h74"></path>
<rect x="418.5" y="119" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="134">/</text>
</g>
<path d="M521.5 130a10 10 0 0 0 10 -10v-40a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v70a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 160h74"></path>
<path d="M447.5 160h74"></path>
<rect x="418.5" y="149" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="164">b</text>
</g>
<path d="M521.5 160a10 10 0 0 0 10 -10v-70a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v100a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 190h74"></path>
<path d="M447.5 190h74"></path>
<rect x="418.5" y="179" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="194">f</text>
</g>
<path d="M521.5 190a10 10 0 0 0 10 -10v-100a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v130a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 220h74"></path>
<path d="M447.5 220h74"></path>
<rect x="418.5" y="209" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="224">n</text>
</g>
<path d="M521.5 220a10 10 0 0 0 10 -10v-130a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v160a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 250h74"></path>
<path d="M447.5 250h74"></path>
<rect x="418.5" y="239" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="254">r</text>
</g>
<path d="M521.5 250a10 10 0 0 0 10 -10v-160a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v190a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M344.5 280h74"></path>
<path d="M447.5 280h74"></path>
<rect x="418.5" y="269" width="29" height="22" rx="10" ry="10"></rect>
<text x="433" y="284">t</text>
</g>
<path d="M521.5 280a10 10 0 0 0 10 -10v-190a10 10 0 0 1 10 -10"></path>
<path d="M324.5 70a10 10 0 0 1 10 10v220a10 10 0 0 0 10 10"></path>
<g>
<path d="M344.5 310h0"></path>
<path d="M521.5 310h0"></path>
<g class="terminal ">
<path d="M344.5 310h0"></path>
<path d="M373.5 310h0"></path>
<rect x="344.5" y="299" width="29" height="22" rx="10" ry="10"></rect>
<text x="359" y="314">u</text>
</g>
<path d="M373.5 310h10"></path>
<path d="M383.5 310h10"></path>
<g class="non-terminal ">
<path d="M393.5 310h0"></path>
<path d="M521.5 310h0"></path>
<rect x="393.5" y="299" width="128" height="22"></rect>
<text x="457.5" y="314">4 hex
digits</text>
</g>
</g>
<path d="M521.5 310a10 10 0 0 0 10 -10v-220a10 10 0 0 1 10 -10"></path>
</g>
</g>
<path d="M644 70a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M664 40h10"></path>
<path d="M163 40a10 10 0 0 0 -10 10v269a10 10 0 0 0 10 10"></path>
<g>
<path d="M163 329h501"></path>
</g>
<path d="M664 329a10 10 0 0 0 10 -10v-269a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M674 40h20"></path>
</g>
<path d="M694 40h10"></path>
<g class="terminal ">
<path d="M704 40h0"></path>
<path d="M733 40h0"></path>
<rect x="704" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="718.5" y="44">"</text>
</g>
<path d="M733 40h10"></path>
<path d="M 743 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="584" height="334" viewBox="0 0 584 334" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 21v20m10 -20v20m-10 -10h50"></path>
<text x="20" y="16" style="text-anchor:start">float</text>
</g>
<g>
<path d="M70 31h0"></path>
<path d="M544 166h0"></path>
<path d="M70 31h20"></path>
<g>
<path d="M90 31h0"></path>
<path d="M524 166h0"></path>
<g>
<path d="M90 31h0"></path>
<path d="M158 31h0"></path>
<path d="M90 31h20"></path>
<g>
<path d="M110 31h28"></path>
</g>
<path d="M138 31h20"></path>
<path d="M90 31a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M110 51h0"></path>
<path d="M138 51h0"></path>
<rect x="110" y="40" width="28" height="22" rx="10" ry="10"></rect>
<text x="124" y="55">-</text>
</g>
<path d="M138 51a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<g>
<path d="M158 31h0"></path>
<path d="M524 166h0"></path>
<path d="M158 31h20"></path>
<g>
<path d="M178 31h0"></path>
<path d="M178 31h10"></path>
<g>
<path d="M188 31h22"></path>
<path d="M472 31h22"></path>
<path d="M210 31h20"></path>
<g class="terminal ">
<path d="M230 31h97"></path>
<path d="M355 31h97"></path>
<rect x="327" y="20" width="28" height="22" rx="10" ry="10"></rect>
<text x="341" y="35">0</text>
</g>
<path d="M452 31h20"></path>
<path d="M210 31a10 10 0 0 1 10 10v19a10 10 0 0 0 10 10"></path>
<g>
<path d="M230 70h0"></path>
<path d="M452 70h0"></path>
<g class="non-terminal ">
<path d="M230 70h0"></path>
<path d="M322 70h0"></path>
<rect x="230" y="59" width="92" height="22"></rect>
<text x="276" y="74">digit 1-9</text>
</g>
<path d="M322 70h10"></path>
<g>
<path d="M332 70h0"></path>
<path d="M452 70h0"></path>
<path d="M332 70a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M352 50h80"></path>
</g>
<path d="M432 50a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M332 70h20"></path>
<g>
<path d="M352 70h0"></path>
<path d="M432 70h0"></path>
<path d="M352 70h10"></path>
<g class="non-terminal ">
<path d="M362 70h0"></path>
<path d="M422 70h0"></path>
<rect x="362" y="59" width="60" height="22"></rect>
<text x="392" y="74">digit</text>
</g>
<path d="M422 70h10"></path>
<path d="M362 70a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M362 90h60"></path>
</g>
<path d="M422 90a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M432 70h20"></path>
</g>
</g>
<path d="M452 70a10 10 0 0 0 10 -10v-19a10 10 0 0 1 10 -10"></path>
</g>
<path d="M494 31a10 10 0 0 1 10 10v47a10 10 0 0 1 -10 10h-306a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M188 118h69"></path>
<path d="M425 118h69"></path>
<path d="M257 118h20"></path>
<g>
<path d="M277 118h0"></path>
<path d="M405 118h0"></path>
<g class="terminal ">
<path d="M277 118h0"></path>
<path d="M305 118h0"></path>
<rect x="277" y="107" width="28" height="22" rx="10" ry="10"></rect>
<text x="291" y="122">.</text>
</g>
<path d="M305 118h10"></path>
<path d="M315 118h10"></path>
<g>
<path d="M325 118h0"></path>
<path d="M405 118h0"></path>
<path d="M325 118h10"></path>
<g class="non-terminal ">
<path d="M335 118h0"></path>
<path d="M395 118h0"></path>
<rect x="335" y="107" width="60" height="22"></rect>
<text x="365" y="122">digit</text>
</g>
<path d="M395 118h10"></path>
<path d="M335 118a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M335 138h60"></path>
</g>
<path d="M395 138a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
</g>
<path d="M405 118h20"></path>
</g>
<path d="M494 118a10 10 0 0 1 10 10v8a10 10 0 0 1 -10 10h-306a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M188 166h0"></path>
<path d="M494 166h0"></path>
<path d="M188 166h20"></path>
<g>
<path d="M208 166h0"></path>
<path d="M474 166h0"></path>
<path d="M208 166h20"></path>
<g class="comment ">
<path d="M228 166h48.5"></path>
<path d="M405.5 166h48.5"></path>
<text x="341" y="171" class="comment">optional exponent</text>
</g>
<path d="M454 166h20"></path>
<path d="M208 166a10 10 0 0 1 10 10v37a10 10 0 0 0 10 10"></path>
<g>
<path d="M228 223h0"></path>
<path d="M454 223h0"></path>
<g>
<path d="M228 223h0"></path>
<path d="M296 223h0"></path>
<path d="M228 223a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
<g class="terminal ">
<path d="M248 193h0"></path>
<path d="M276 193h0"></path>
<rect x="248" y="182" width="28" height="22" rx="10" ry="10"></rect>
<text x="262" y="197">E</text>
</g>
<path d="M276 193a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<path d="M228 223h20"></path>
<g class="terminal ">
<path d="M248 223h0"></path>
<path d="M276 223h0"></path>
<rect x="248" y="212" width="28" height="22" rx="10" ry="10"></rect>
<text x="262" y="227">e</text>
</g>
<path d="M276 223h20"></path>
</g>
<g>
<path d="M296 223h0"></path>
<path d="M364 223h0"></path>
<path d="M296 223a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g class="terminal ">
<path d="M316 203h0"></path>
<path d="M344 203h0"></path>
<rect x="316" y="192" width="28" height="22" rx="10" ry="10"></rect>
<text x="330" y="207">-</text>
</g>
<path d="M344 203a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M296 223h20"></path>
<g>
<path d="M316 223h28"></path>
</g>
<path d="M344 223h20"></path>
<path d="M296 223a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M316 243h0"></path>
<path d="M344 243h0"></path>
<rect x="316" y="232" width="28" height="22" rx="10" ry="10"></rect>
<text x="330" y="247">+</text>
</g>
<path d="M344 243a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<path d="M364 223h10"></path>
<g>
<path d="M374 223h0"></path>
<path d="M454 223h0"></path>
<path d="M374 223h10"></path>
<g class="non-terminal ">
<path d="M384 223h0"></path>
<path d="M444 223h0"></path>
<rect x="384" y="212" width="60" height="22"></rect>
<text x="414" y="227">digit</text>
</g>
<path d="M444 223h10"></path>
<path d="M384 223a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M384 243h60"></path>
</g>
<path d="M444 243a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
</g>
<path d="M454 223a10 10 0 0 0 10 -10v-37a10 10 0 0 1 10 -10"></path>
</g>
<path d="M474 166h20"></path>
</g>
<path d="M494 166h10"></path>
<path d="M504 166h0"></path>
</g>
<path d="M504 166h20"></path>
<path d="M158 31a10 10 0 0 1 10 10v222a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M178 273h141"></path>
<path d="M363 273h141"></path>
<rect x="319" y="262" width="44" height="22" rx="10" ry="10"></rect>
<text x="341" y="277">inf</text>
</g>
<path d="M504 273a10 10 0 0 0 10 -10v-87a10 10 0 0 1 10 -10"></path>
</g>
</g>
<path d="M524 166h20"></path>
<path d="M70 31a10 10 0 0 1 10 10v252a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M90 303h195"></path>
<path d="M329 303h195"></path>
<rect x="285" y="292" width="44" height="22" rx="10" ry="10"></rect>
<text x="307" y="307">nan</text>
</g>
<path d="M524 303a10 10 0 0 0 10 -10v-117a10 10 0 0 1 10 -10"></path>
</g>
<path d="M 544 166 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="588" height="280" viewBox="0 0 588 280" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h73"></path>
<text x="20" y="25" style="text-anchor:start">integer</text>
</g>
<g>
<path d="M93 40h0"></path>
<path d="M162 40h0"></path>
<path d="M93 40h20"></path>
<g>
<path d="M113 40h29"></path>
</g>
<path d="M142 40h20"></path>
<path d="M93 40a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M113 60h0"></path>
<path d="M142 60h0"></path>
<rect x="113" y="49" width="29" height="22" rx="10" ry="10"></rect>
<text x="127.5" y="64">-</text>
</g>
<path d="M142 60a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<g>
<path d="M162 40h0"></path>
<path d="M548 40h0"></path>
<path d="M162 40h20"></path>
<g>
<path d="M182 40h19"></path>
<path d="M509 40h19"></path>
<g class="non-terminal ">
<path d="M201 40h0"></path>
<path d="M302 40h0"></path>
<rect x="201" y="29" width="101" height="22"></rect>
<text x="251.5" y="44">digit 1-9</text>
</g>
<path d="M302 40h10"></path>
<g>
<path d="M312 40h0"></path>
<path d="M509 40h0"></path>
<path d="M312 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M332 20h157"></path>
</g>
<path d="M489 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M312 40h20"></path>
<g>
<path d="M332 40h0"></path>
<path d="M489 40h0"></path>
<path d="M332 40h10"></path>
<g class="non-terminal ">
<path d="M342 40h0"></path>
<path d="M479 40h0"></path>
<rect x="342" y="29" width="137" height="22"></rect>
<text x="410.5" y="44">decimal digit</text>
</g>
<path d="M479 40h10"></path>
<path d="M342 40a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M342 60h137"></path>
</g>
<path d="M479 60a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M489 40h20"></path>
</g>
</g>
<path d="M528 40h20"></path>
<path d="M162 40a10 10 0 0 1 10 10v19a10 10 0 0 0 10 10"></path>
<g>
<path d="M182 79h0"></path>
<path d="M528 79h0"></path>
<g class="terminal ">
<path d="M182 79h0"></path>
<path d="M211 79h0"></path>
<rect x="182" y="68" width="29" height="22" rx="10" ry="10"></rect>
<text x="196.5" y="83">0</text>
</g>
<path d="M211 79h10"></path>
<g>
<path d="M221 79h0"></path>
<path d="M528 79h0"></path>
<path d="M221 79h20"></path>
<g>
<path d="M241 79h267"></path>
</g>
<path d="M508 79h20"></path>
<path d="M221 79a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M241 99h0"></path>
<path d="M508 99h0"></path>
<path d="M241 99h20"></path>
<g>
<path d="M261 99h13.5"></path>
<path d="M474.5 99h13.5"></path>
<g>
<path d="M274.5 99h0"></path>
<path d="M343.5 99h0"></path>
<path d="M274.5 99h20"></path>
<g class="terminal ">
<path d="M294.5 99h0"></path>
<path d="M323.5 99h0"></path>
<rect x="294.5" y="88" width="29" height="22" rx="10" ry="10"></rect>
<text x="309" y="103">x</text>
</g>
<path d="M323.5 99h20"></path>
<path d="M274.5 99a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M294.5 129h0"></path>
<path d="M323.5 129h0"></path>
<rect x="294.5" y="118" width="29" height="22" rx="10" ry="10"></rect>
<text x="309" y="133">X</text>
</g>
<path d="M323.5 129a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M343.5 99h10"></path>
<g>
<path d="M353.5 99h0"></path>
<path d="M474.5 99h0"></path>
<path d="M353.5 99h10"></path>
<g class="non-terminal ">
<path d="M363.5 99h0"></path>
<path d="M464.5 99h0"></path>
<rect x="363.5" y="88" width="101" height="22"></rect>
<text x="414" y="103">hex digit</text>
</g>
<path d="M464.5 99h10"></path>
<path d="M363.5 99a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M363.5 119h101"></path>
</g>
<path d="M464.5 119a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
</g>
<path d="M488 99h20"></path>
<path d="M241 99a10 10 0 0 1 10 10v40a10 10 0 0 0 10 10"></path>
<g>
<path d="M261 159h4.5"></path>
<path d="M483.5 159h4.5"></path>
<g>
<path d="M265.5 159h0"></path>
<path d="M334.5 159h0"></path>
<path d="M265.5 159h20"></path>
<g class="terminal ">
<path d="M285.5 159h0"></path>
<path d="M314.5 159h0"></path>
<rect x="285.5" y="148" width="29" height="22" rx="10" ry="10"></rect>
<text x="300" y="163">o</text>
</g>
<path d="M314.5 159h20"></path>
<path d="M265.5 159a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M285.5 189h0"></path>
<path d="M314.5 189h0"></path>
<rect x="285.5" y="178" width="29" height="22" rx="10" ry="10"></rect>
<text x="300" y="193">O</text>
</g>
<path d="M314.5 189a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M334.5 159h10"></path>
<g>
<path d="M344.5 159h0"></path>
<path d="M483.5 159h0"></path>
<path d="M344.5 159h10"></path>
<g class="non-terminal ">
<path d="M354.5 159h0"></path>
<path d="M473.5 159h0"></path>
<rect x="354.5" y="148" width="119" height="22"></rect>
<text x="414" y="163">octal digit</text>
</g>
<path d="M473.5 159h10"></path>
<path d="M354.5 159a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M354.5 179h119"></path>
</g>
<path d="M473.5 179a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
</g>
<path d="M488 159a10 10 0 0 0 10 -10v-40a10 10 0 0 1 10 -10"></path>
<path d="M241 99a10 10 0 0 1 10 10v100a10 10 0 0 0 10 10"></path>
<g>
<path d="M261 219h0"></path>
<path d="M488 219h0"></path>
<g>
<path d="M261 219h0"></path>
<path d="M330 219h0"></path>
<path d="M261 219h20"></path>
<g class="terminal ">
<path d="M281 219h0"></path>
<path d="M310 219h0"></path>
<rect x="281" y="208" width="29" height="22" rx="10" ry="10"></rect>
<text x="295.5" y="223">b</text>
</g>
<path d="M310 219h20"></path>
<path d="M261 219a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M281 249h0"></path>
<path d="M310 249h0"></path>
<rect x="281" y="238" width="29" height="22" rx="10" ry="10"></rect>
<text x="295.5" y="253">B</text>
</g>
<path d="M310 249a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M330 219h10"></path>
<g>
<path d="M340 219h0"></path>
<path d="M488 219h0"></path>
<path d="M340 219h10"></path>
<g class="non-terminal ">
<path d="M350 219h0"></path>
<path d="M478 219h0"></path>
<rect x="350" y="208" width="128" height="22"></rect>
<text x="414" y="223">binary digit</text>
</g>
<path d="M478 219h10"></path>
<path d="M350 219a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M350 239h128"></path>
</g>
<path d="M478 239a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
</g>
<path d="M488 219a10 10 0 0 0 10 -10v-100a10 10 0 0 1 10 -10"></path>
</g>
<path d="M508 99a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
</g>
<path d="M528 79a10 10 0 0 0 10 -10v-19a10 10 0 0 1 10 -10"></path>
</g>
<path d="M 548 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="783" height="101" viewBox="0 0 783 101" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h37"></path>
<text x="20" y="25" style="text-anchor:start">map</text>
</g>
<path d="M57 40h10"></path>
<g class="terminal ">
<path d="M67 40h0"></path>
<path d="M96 40h0"></path>
<rect x="67" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="81.5" y="44">{</text>
</g>
<path d="M96 40h10"></path>
<g>
<path d="M106 40h0"></path>
<path d="M365 40h0"></path>
<path d="M106 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M126 20h219"></path>
</g>
<path d="M345 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M106 40h20"></path>
<g>
<path d="M126 40h0"></path>
<path d="M345 40h0"></path>
<path d="M126 40h10"></path>
<g>
<path d="M136 40h0"></path>
<path d="M335 40h0"></path>
<g class="non-terminal ">
<path d="M136 40h0"></path>
<path d="M201 40h0"></path>
<rect x="136" y="29" width="65" height="22"></rect>
<text x="168.5" y="44">value</text>
</g>
<path d="M201 40h10"></path>
<path d="M211 40h10"></path>
<g class="terminal ">
<path d="M221 40h0"></path>
<path d="M250 40h0"></path>
<rect x="221" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="235.5" y="44">:</text>
</g>
<path d="M250 40h10"></path>
<path d="M260 40h10"></path>
<g class="non-terminal ">
<path d="M270 40h0"></path>
<path d="M335 40h0"></path>
<rect x="270" y="29" width="65" height="22"></rect>
<text x="302.5" y="44">value</text>
</g>
</g>
<path d="M335 40h10"></path>
<path d="M136 40a10 10 0 0 0 -10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M136 70h85"></path>
<path d="M250 70h85"></path>
<rect x="221" y="59" width="29" height="22" rx="10" ry="10"></rect>
<text x="235.5" y="74">,</text>
</g>
<path d="M335 70a10 10 0 0 0 10 -10v-10a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M345 40h20"></path>
</g>
<g>
<path d="M365 40h0"></path>
<path d="M564 40h0"></path>
<path d="M365 40h20"></path>
<g>
<path d="M385 40h159"></path>
</g>
<path d="M544 40h20"></path>
<path d="M365 40a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M385 60h0"></path>
<path d="M544 60h0"></path>
<g class="non-terminal ">
<path d="M385 60h0"></path>
<path d="M495 60h0"></path>
<rect x="385" y="49" width="110" height="22"></rect>
<text x="440" y="64">whitespace</text>
</g>
<path d="M495 60h10"></path>
<path d="M505 60h10"></path>
<g class="terminal ">
<path d="M515 60h0"></path>
<path d="M544 60h0"></path>
<rect x="515" y="49" width="29" height="22" rx="10" ry="10"></rect>
<text x="529.5" y="64">,</text>
</g>
</g>
<path d="M544 60a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<path d="M564 40h10"></path>
<g class="non-terminal ">
<path d="M574 40h0"></path>
<path d="M684 40h0"></path>
<rect x="574" y="29" width="110" height="22"></rect>
<text x="629" y="44">whitespace</text>
</g>
<path d="M684 40h10"></path>
<path d="M694 40h10"></path>
<g class="terminal ">
<path d="M704 40h0"></path>
<path d="M733 40h0"></path>
<rect x="704" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="718.5" y="44">}</text>
</g>
<path d="M733 40h10"></path>
<path d="M 743 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="667" height="101" viewBox="0 0 667 101" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h55"></path>
<text x="20" y="25" style="text-anchor:start">array</text>
</g>
<path d="M75 40h10"></path>
<g class="terminal ">
<path d="M85 40h0"></path>
<path d="M114 40h0"></path>
<rect x="85" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="99.5" y="44">&#91;</text>
</g>
<path d="M114 40h10"></path>
<g>
<path d="M124 40h0"></path>
<path d="M249 40h0"></path>
<path d="M124 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M144 20h85"></path>
</g>
<path d="M229 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M124 40h20"></path>
<g>
<path d="M144 40h0"></path>
<path d="M229 40h0"></path>
<path d="M144 40h10"></path>
<g class="non-terminal ">
<path d="M154 40h0"></path>
<path d="M219 40h0"></path>
<rect x="154" y="29" width="65" height="22"></rect>
<text x="186.5" y="44">value</text>
</g>
<path d="M219 40h10"></path>
<path d="M154 40a10 10 0 0 0 -10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M154 70h18"></path>
<path d="M201 70h18"></path>
<rect x="172" y="59" width="29" height="22" rx="10" ry="10"></rect>
<text x="186.5" y="74">,</text>
</g>
<path d="M219 70a10 10 0 0 0 10 -10v-10a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M229 40h20"></path>
</g>
<g>
<path d="M249 40h0"></path>
<path d="M448 40h0"></path>
<path d="M249 40h20"></path>
<g>
<path d="M269 40h159"></path>
</g>
<path d="M428 40h20"></path>
<path d="M249 40a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M269 60h0"></path>
<path d="M428 60h0"></path>
<g class="non-terminal ">
<path d="M269 60h0"></path>
<path d="M379 60h0"></path>
<rect x="269" y="49" width="110" height="22"></rect>
<text x="324" y="64">whitespace</text>
</g>
<path d="M379 60h10"></path>
<path d="M389 60h10"></path>
<g class="terminal ">
<path d="M399 60h0"></path>
<path d="M428 60h0"></path>
<rect x="399" y="49" width="29" height="22" rx="10" ry="10"></rect>
<text x="413.5" y="64">,</text>
</g>
</g>
<path d="M428 60a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<path d="M448 40h10"></path>
<g class="non-terminal ">
<path d="M458 40h0"></path>
<path d="M568 40h0"></path>
<rect x="458" y="29" width="110" height="22"></rect>
<text x="513" y="44">whitespace</text>
</g>
<path d="M568 40h10"></path>
<path d="M578 40h10"></path>
<g class="terminal ">
<path d="M588 40h0"></path>
<path d="M617 40h0"></path>
<rect x="588" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="602.5" y="44">&#93;</text>
</g>
<path d="M617 40h10"></path>
<path d="M 627 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="667" height="101" viewBox="0 0 667 101" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h55"></path>
<text x="20" y="25" style="text-anchor:start">tuple</text>
</g>
<path d="M75 40h10"></path>
<g class="terminal ">
<path d="M85 40h0"></path>
<path d="M114 40h0"></path>
<rect x="85" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="99.5" y="44">(</text>
</g>
<path d="M114 40h10"></path>
<g>
<path d="M124 40h0"></path>
<path d="M249 40h0"></path>
<path d="M124 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M144 20h85"></path>
</g>
<path d="M229 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M124 40h20"></path>
<g>
<path d="M144 40h0"></path>
<path d="M229 40h0"></path>
<path d="M144 40h10"></path>
<g class="non-terminal ">
<path d="M154 40h0"></path>
<path d="M219 40h0"></path>
<rect x="154" y="29" width="65" height="22"></rect>
<text x="186.5" y="44">value</text>
</g>
<path d="M219 40h10"></path>
<path d="M154 40a10 10 0 0 0 -10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M154 70h18"></path>
<path d="M201 70h18"></path>
<rect x="172" y="59" width="29" height="22" rx="10" ry="10"></rect>
<text x="186.5" y="74">,</text>
</g>
<path d="M219 70a10 10 0 0 0 10 -10v-10a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M229 40h20"></path>
</g>
<g>
<path d="M249 40h0"></path>
<path d="M448 40h0"></path>
<path d="M249 40h20"></path>
<g>
<path d="M269 40h159"></path>
</g>
<path d="M428 40h20"></path>
<path d="M249 40a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M269 60h0"></path>
<path d="M428 60h0"></path>
<g class="non-terminal ">
<path d="M269 60h0"></path>
<path d="M379 60h0"></path>
<rect x="269" y="49" width="110" height="22"></rect>
<text x="324" y="64">whitespace</text>
</g>
<path d="M379 60h10"></path>
<path d="M389 60h10"></path>
<g class="terminal ">
<path d="M399 60h0"></path>
<path d="M428 60h0"></path>
<rect x="399" y="49" width="29" height="22" rx="10" ry="10"></rect>
<text x="413.5" y="64">,</text>
</g>
</g>
<path d="M428 60a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<path d="M448 40h10"></path>
<g class="non-terminal ">
<path d="M458 40h0"></path>
<path d="M568 40h0"></path>
<rect x="458" y="29" width="110" height="22"></rect>
<text x="513" y="44">whitespace</text>
</g>
<path d="M568 40h10"></path>
<path d="M578 40h10"></path>
<g class="terminal ">
<path d="M588 40h0"></path>
<path d="M617 40h0"></path>
<rect x="588" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="602.5" y="44">)</text>
</g>
<path d="M617 40h10"></path>
<path d="M 627 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="507" height="110" viewBox="0 0 507 110" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h37"></path>
<text x="20" y="25" style="text-anchor:start">tag</text>
</g>
<path d="M57 40h10"></path>
<g class="terminal ">
<path d="M67 40h0"></path>
<path d="M96 40h0"></path>
<rect x="67" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="81.5" y="44">!</text>
</g>
<path d="M96 40h10"></path>
<g>
<path d="M106 40h0"></path>
<path d="M382 40h0"></path>
<path d="M106 40h20"></path>
<g>
<path d="M126 40h0"></path>
<path d="M362 40h0"></path>
<g class="non-terminal ">
<path d="M126 40h0"></path>
<path d="M227 40h0"></path>
<rect x="126" y="29" width="101" height="22"></rect>
<text x="176.5" y="44">digit 1-9</text>
</g>
<path d="M227 40h10"></path>
<g>
<path d="M237 40h0"></path>
<path d="M362 40h0"></path>
<path d="M237 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M257 20h85"></path>
</g>
<path d="M342 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M237 40h20"></path>
<g>
<path d="M257 40h0"></path>
<path d="M342 40h0"></path>
<path d="M257 40h10"></path>
<g class="non-terminal ">
<path d="M267 40h0"></path>
<path d="M332 40h0"></path>
<rect x="267" y="29" width="65" height="22"></rect>
<text x="299.5" y="44">digit</text>
</g>
<path d="M332 40h10"></path>
<path d="M267 40a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M267 60h65"></path>
</g>
<path d="M332 60a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M342 40h20"></path>
</g>
</g>
<path d="M362 40h20"></path>
<path d="M106 40a10 10 0 0 1 10 10v19a10 10 0 0 0 10 10"></path>
<g>
<path d="M126 79h103.5"></path>
<path d="M258.5 79h103.5"></path>
<g class="terminal ">
<path d="M229.5 79h0"></path>
<path d="M258.5 79h0"></path>
<rect x="229.5" y="68" width="29" height="22" rx="10" ry="10"></rect>
<text x="244" y="83">0</text>
</g>
</g>
<path d="M362 79a10 10 0 0 0 10 -10v-19a10 10 0 0 1 10 -10"></path>
</g>
<path d="M382 40h10"></path>
<g class="non-terminal ">
<path d="M392 40h0"></path>
<path d="M457 40h0"></path>
<rect x="392" y="29" width="65" height="22"></rect>
<text x="424.5" y="44">value</text>
</g>
<path d="M457 40h10"></path>
<path d="M 467 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="422" height="110" viewBox="0 0 422 110" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h37"></path>
<text x="20" y="25" style="text-anchor:start">ref</text>
</g>
<path d="M57 40h10"></path>
<g class="terminal ">
<path d="M67 40h0"></path>
<path d="M96 40h0"></path>
<rect x="67" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="81.5" y="44">&#38;</text>
</g>
<path d="M96 40h10"></path>
<g>
<path d="M106 40h0"></path>
<path d="M382 40h0"></path>
<path d="M106 40h20"></path>
<g>
<path d="M126 40h0"></path>
<path d="M362 40h0"></path>
<g class="non-terminal ">
<path d="M126 40h0"></path>
<path d="M227 40h0"></path>
<rect x="126" y="29" width="101" height="22"></rect>
<text x="176.5" y="44">digit 1-9</text>
</g>
<path d="M227 40h10"></path>
<g>
<path d="M237 40h0"></path>
<path d="M362 40h0"></path>
<path d="M237 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M257 20h85"></path>
</g>
<path d="M342 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M237 40h20"></path>
<g>
<path d="M257 40h0"></path>
<path d="M342 40h0"></path>
<path d="M257 40h10"></path>
<g class="non-terminal ">
<path d="M267 40h0"></path>
<path d="M332 40h0"></path>
<rect x="267" y="29" width="65" height="22"></rect>
<text x="299.5" y="44">digit</text>
</g>
<path d="M332 40h10"></path>
<path d="M267 40a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M267 60h65"></path>
</g>
<path d="M332 60a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M342 40h20"></path>
</g>
</g>
<path d="M362 40h20"></path>
<path d="M106 40a10 10 0 0 1 10 10v19a10 10 0 0 0 10 10"></path>
<g>
<path d="M126 79h103.5"></path>
<path d="M258.5 79h103.5"></path>
<g class="terminal ">
<path d="M229.5 79h0"></path>
<path d="M258.5 79h0"></path>
<rect x="229.5" y="68" width="29" height="22" rx="10" ry="10"></rect>
<text x="244" y="83">0</text>
</g>
</g>
<path d="M362 79a10 10 0 0 0 10 -10v-19a10 10 0 0 1 10 -10"></path>
</g>
<path d="M 382 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="410" height="80" viewBox="0 0 410 80" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 30v20m10 -20v20m-10 -10h64"></path>
<text x="20" y="25" style="text-anchor:start">binary</text>
</g>
<path d="M84 40h10"></path>
<g class="terminal ">
<path d="M94 40h0"></path>
<path d="M123 40h0"></path>
<rect x="94" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="108.5" y="44">&#60;</text>
</g>
<path d="M123 40h10"></path>
<g>
<path d="M133 40h0"></path>
<path d="M321 40h0"></path>
<path d="M133 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M153 20h148"></path>
</g>
<path d="M301 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M133 40h20"></path>
<g>
<path d="M153 40h0"></path>
<path d="M301 40h0"></path>
<path d="M153 40h10"></path>
<g class="non-terminal ">
<path d="M163 40h0"></path>
<path d="M291 40h0"></path>
<rect x="163" y="29" width="128" height="22"></rect>
<text x="227" y="44">2 hex digits</text>
</g>
<path d="M291 40h10"></path>
<path d="M163 40a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M163 60h128"></path>
</g>
<path d="M291 60a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M301 40h20"></path>
</g>
<path d="M321 40h10"></path>
<g class="terminal ">
<path d="M331 40h0"></path>
<path d="M360 40h0"></path>
<rect x="331" y="29" width="29" height="22" rx="10" ry="10"></rect>
<text x="345.5" y="44">></text>
</g>
<path d="M360 40h10"></path>
<path d="M 370 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="498" height="392" viewBox="0 0 498 392" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 21v20m10 -20v20m-10 -10h55"></path>
<text x="20" y="16" style="text-anchor:start">value</text>
</g>
<path d="M75 31h10"></path>
<g class="non-terminal ">
<path d="M85 31h0"></path>
<path d="M195 31h0"></path>
<rect x="85" y="20" width="110" height="22"></rect>
<text x="140" y="35">whitespace</text>
</g>
<path d="M195 31h10"></path>
<g>
<path d="M205 31h0"></path>
<path d="M328 31h0"></path>
<path d="M205 31h20"></path>
<g class="non-terminal ">
<path d="M225 31h4.5"></path>
<path d="M303.5 31h4.5"></path>
<rect x="229.5" y="20" width="74" height="22"></rect>
<text x="266.5" y="35">string</text>
</g>
<path d="M308 31h20"></path>
<path d="M205 31a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 61h4.5"></path>
<path d="M303.5 61h4.5"></path>
<rect x="229.5" y="50" width="74" height="22"></rect>
<text x="266.5" y="65">binary</text>
</g>
<path d="M308 61a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v40a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 91h0"></path>
<path d="M308 91h0"></path>
<rect x="225" y="80" width="83" height="22"></rect>
<text x="266.5" y="95">integer</text>
</g>
<path d="M308 91a10 10 0 0 0 10 -10v-40a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v70a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 121h9"></path>
<path d="M299 121h9"></path>
<rect x="234" y="110" width="65" height="22"></rect>
<text x="266.5" y="125">float</text>
</g>
<path d="M308 121a10 10 0 0 0 10 -10v-70a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v100a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 151h18"></path>
<path d="M290 151h18"></path>
<rect x="243" y="140" width="47" height="22"></rect>
<text x="266.5" y="155">tag</text>
</g>
<path d="M308 151a10 10 0 0 0 10 -10v-100a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v130a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 181h18"></path>
<path d="M290 181h18"></path>
<rect x="243" y="170" width="47" height="22"></rect>
<text x="266.5" y="185">ref</text>
</g>
<path d="M308 181a10 10 0 0 0 10 -10v-130a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v160a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 211h18"></path>
<path d="M290 211h18"></path>
<rect x="243" y="200" width="47" height="22"></rect>
<text x="266.5" y="215">map</text>
</g>
<path d="M308 211a10 10 0 0 0 10 -10v-160a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v190a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 241h9"></path>
<path d="M299 241h9"></path>
<rect x="234" y="230" width="65" height="22"></rect>
<text x="266.5" y="245">array</text>
</g>
<path d="M308 241a10 10 0 0 0 10 -10v-190a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v220a10 10 0 0 0 10 10"></path>
<g class="non-terminal ">
<path d="M225 271h9"></path>
<path d="M299 271h9"></path>
<rect x="234" y="260" width="65" height="22"></rect>
<text x="266.5" y="275">tuple</text>
</g>
<path d="M308 271a10 10 0 0 0 10 -10v-220a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v250a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M225 301h13.5"></path>
<path d="M294.5 301h13.5"></path>
<rect x="238.5" y="290" width="56" height="22" rx="10" ry="10"></rect>
<text x="266.5" y="305">true</text>
</g>
<path d="M308 301a10 10 0 0 0 10 -10v-250a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v280a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M225 331h9"></path>
<path d="M299 331h9"></path>
<rect x="234" y="320" width="65" height="22" rx="10" ry="10"></rect>
<text x="266.5" y="335">false</text>
</g>
<path d="M308 331a10 10 0 0 0 10 -10v-280a10 10 0 0 1 10 -10"></path>
<path d="M205 31a10 10 0 0 1 10 10v310a10 10 0 0 0 10 10"></path>
<g class="terminal ">
<path d="M225 361h13.5"></path>
<path d="M294.5 361h13.5"></path>
<rect x="238.5" y="350" width="56" height="22" rx="10" ry="10"></rect>
<text x="266.5" y="365">null</text>
</g>
<path d="M308 361a10 10 0 0 0 10 -10v-310a10 10 0 0 1 10 -10"></path>
</g>
<path d="M328 31h10"></path>
<g class="non-terminal ">
<path d="M338 31h0"></path>
<path d="M448 31h0"></path>
<rect x="338" y="20" width="110" height="22"></rect>
<text x="393" y="35">whitespace</text>
</g>
<path d="M448 31h10"></path>
<path d="M 458 31 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>

<svg class="railroad-diagram" width="844" height="304" viewBox="0 0 844 304" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<g transform="translate(.5 .5)">
<g>
<path d="M20 20v20m10 -20v20m-10 -10h100"></path>
<text x="20" y="15" style="text-anchor:start">whitespace</text>
</g>
<g>
<path d="M120 30h0"></path>
<path d="M804 30h0"></path>
<path d="M120 30h20"></path>
<g>
<path d="M140 30h644"></path>
</g>
<path d="M784 30h20"></path>
<path d="M120 30a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M140 50h0"></path>
<path d="M784 50h0"></path>
<path d="M140 50h10"></path>
<g>
<path d="M150 50h0"></path>
<path d="M774 50h0"></path>
<path d="M150 50h20"></path>
<g>
<path d="M170 50h0"></path>
<path d="M264 50h490"></path>
<g class="terminal ">
<path d="M170 50h0"></path>
<path d="M199 50h0"></path>
<rect x="170" y="39" width="29" height="22" rx="10" ry="10"></rect>
<text x="184.5" y="54"> </text>
</g>
<path d="M199 50h10"></path>
<path d="M209 50h10"></path>
<g class="comment ">
<path d="M219 50h0"></path>
<path d="M264 50h0"></path>
<text x="241.5" y="55" class="comment">space</text>
</g>
</g>
<path d="M754 50h20"></path>
<path d="M150 50a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g>
<path d="M170 80h0"></path>
<path d="M285 80h469"></path>
<g class="terminal ">
<path d="M170 80h0"></path>
<path d="M199 80h0"></path>
<rect x="170" y="69" width="29" height="22" rx="10" ry="10"></rect>
<text x="184.5" y="84">
</text>
</g>
<path d="M199 80h10"></path>
<path d="M209 80h10"></path>
<g class="comment ">
<path d="M219 80h0"></path>
<path d="M285 80h0"></path>
<text x="252" y="85" class="comment">linefeed</text>
</g>
</g>
<path d="M754 80a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
<path d="M150 50a10 10 0 0 1 10 10v40a10 10 0 0 0 10 10"></path>
<g>
<path d="M170 110h0"></path>
<path d="M334 110h420"></path>
<g class="terminal ">
<path d="M170 110h0"></path>
<path d="M199 110h0"></path>
<rect x="170" y="99" width="29" height="22" rx="10" ry="10"></rect>
<text x="184.5" y="114">
</text>
</g>
<path d="M199 110h10"></path>
<path d="M209 110h10"></path>
<g class="comment ">
<path d="M219 110h0"></path>
<path d="M334 110h0"></path>
<text x="276.5" y="115" class="comment">carriage return</text>
</g>
</g>
<path d="M754 110a10 10 0 0 0 10 -10v-40a10 10 0 0 1 10 -10"></path>
<path d="M150 50a10 10 0 0 1 10 10v70a10 10 0 0 0 10 10"></path>
<g>
<path d="M170 140h0"></path>
<path d="M327 140h427"></path>
<g class="terminal ">
<path d="M170 140h0"></path>
<path d="M199 140h0"></path>
<rect x="170" y="129" width="29" height="22" rx="10" ry="10"></rect>
<text x="184.5" y="144"> </text>
</g>
<path d="M199 140h10"></path>
<path d="M209 140h10"></path>
<g class="comment ">
<path d="M219 140h0"></path>
<path d="M327 140h0"></path>
<text x="273" y="145" class="comment">horizontal tab</text>
</g>
</g>
<path d="M754 140a10 10 0 0 0 10 -10v-70a10 10 0 0 1 10 -10"></path>
<path d="M150 50a10 10 0 0 1 10 10v109a10 10 0 0 0 10 10"></path>
<g>
<path d="M170 179h0"></path>
<path d="M663 179h91"></path>
<g class="terminal ">
<path d="M170 179h0"></path>
<path d="M208 179h0"></path>
<rect x="170" y="168" width="38" height="22" rx="10" ry="10"></rect>
<text x="189" y="183">//</text>
</g>
<path d="M208 179h10"></path>
<g>
<path d="M218 179h0"></path>
<path d="M559 179h0"></path>
<path d="M218 179a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M238 159h301"></path>
</g>
<path d="M539 159a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M218 179h20"></path>
<g>
<path d="M238 179h0"></path>
<path d="M539 179h0"></path>
<path d="M238 179h10"></path>
<g class="non-terminal ">
<path d="M248 179h0"></path>
<path d="M529 179h0"></path>
<rect x="248" y="168" width="281" height="22"></rect>
<text x="388.5" y="183">any codepoint except linefeed</text>
</g>
<path d="M529 179h10"></path>
<path d="M248 179a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M248 199h281"></path>
</g>
<path d="M529 199a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M539 179h20"></path>
</g>
<path d="M559 179h10"></path>
<g class="comment ">
<path d="M569 179h0"></path>
<path d="M663 179h0"></path>
<text x="616" y="184" class="comment">line comment</text>
</g>
</g>
<path d="M754 179a10 10 0 0 0 10 -10v-109a10 10 0 0 1 10 -10"></path>
<path d="M150 50a10 10 0 0 1 10 10v157a10 10 0 0 0 10 10"></path>
<g>
<path d="M170 227h0"></path>
<path d="M754 227h0"></path>
<g class="terminal ">
<path d="M170 227h0"></path>
<path d="M208 227h0"></path>
<rect x="170" y="216" width="38" height="22" rx="10" ry="10"></rect>
<text x="189" y="231">/&#42;</text>
</g>
<path d="M208 227h10"></path>
<g>
<path d="M218 227h0"></path>
<path d="M585 227h0"></path>
<path d="M218 227a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M238 207h327"></path>
</g>
<path d="M565 207a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M218 227h20"></path>
<g>
<path d="M238 227h0"></path>
<path d="M565 227h0"></path>
<path d="M238 227h10"></path>
<g>
<path d="M248 227h0"></path>
<path d="M555 227h0"></path>
<path d="M248 227h20"></path>
<g class="non-terminal ">
<path d="M268 227h0"></path>
<path d="M486 227h49"></path>
<rect x="268" y="216" width="218" height="22"></rect>
<text x="377" y="231">any codepoint except &#42;</text>
</g>
<path d="M535 227h20"></path>
<path d="M248 227a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g>
<path d="M268 257h0"></path>
<path d="M535 257h0"></path>
<g class="terminal ">
<path d="M268 257h0"></path>
<path d="M297 257h0"></path>
<rect x="268" y="246" width="29" height="22" rx="10" ry="10"></rect>
<text x="282.5" y="261">&#42;</text>
</g>
<path d="M297 257h10"></path>
<path d="M307 257h10"></path>
<g class="non-terminal ">
<path d="M317 257h0"></path>
<path d="M535 257h0"></path>
<rect x="317" y="246" width="218" height="22"></rect>
<text x="426" y="261">any codepoint except /</text>
</g>
</g>
<path d="M535 257a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M555 227h10"></path>
<path d="M248 227a10 10 0 0 0 -10 10v29a10 10 0 0 0 10 10"></path>
<g>
<path d="M248 276h307"></path>
</g>
<path d="M555 276a10 10 0 0 0 10 -10v-29a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M565 227h20"></path>
</g>
<path d="M585 227h10"></path>
<g class="terminal ">
<path d="M595 227h0"></path>
<path d="M633 227h0"></path>
<rect x="595" y="216" width="38" height="22" rx="10" ry="10"></rect>
<text x="614" y="231">&#42;/</text>
</g>
<path d="M633 227h10"></path>
<path d="M643 227h10"></path>
<g class="comment ">
<path d="M653 227h0"></path>
<path d="M754 227h0"></path>
<text x="703.5" y="232" class="comment">block comment</text>
</g>
</g>
<path d="M754 227a10 10 0 0 0 10 -10v-157a10 10 0 0 1 10 -10"></path>
</g>
<path d="M774 50h10"></path>
<path d="M150 50a10 10 0 0 0 -10 10v214a10 10 0 0 0 10 10"></path>
<g>
<path d="M150 284h624"></path>
</g>
<path d="M774 284a10 10 0 0 0 10 -10v-214a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M784 50a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<path d="M 804 30 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
<style>
 svg {
  background-color: hsl(30,20%,95%);
 }
 path {
  stroke-width: 3;
  stroke: black;
  fill: rgba(0,0,0,0);
 }
 text {
  font: bold 14px monospace;
  text-anchor: middle;
  white-space: pre;
 }
 text.diagram-text {
  font-size: 12px;
 }
 text.diagram-arrow {
  font-size: 16px;
 }
 text.label {
  text-anchor: start;
 }
 text.comment {
  font: italic 12px monospace;
 }
 g.non-terminal text {
  /&#42;font-style: italic;&#42;/
 }
 rect {
  stroke-width: 3;
  stroke: black;
  fill: hsl(120,100%,90%);
 }
 rect.group-box {
  stroke: gray;
  stroke-dasharray: 10 5;
  fill: none;
 }
 path.diagram-text {
  stroke-width: 3;
  stroke: black;
  fill: white;
  cursor: help;
 }
 g.diagram-text:hover path.diagram-text {
  fill: #eee;
 }</style>
</svg>
