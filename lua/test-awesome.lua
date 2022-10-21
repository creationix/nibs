local fs = require 'coro-fs'
local Json = require 'ordered-json'
local Nibs = require 'nibs'
local PrettyPrint = require('pretty-print')
local colorize = PrettyPrint.colorize
local spawn = require('coro-spawn')
local split = require('coro-split')

-- Files that contain large sample JSON data
local prefix = "/Users/tim/sites/"
local postfix = ".json"
local big_json_files = {

    "shotgun.live/deployment",
    "www.euroleaguebasketball.net/deployment",
    "invoice.2go.com/deployment",
    "www.breastcancer.org/deployment",
    "www.rejectshop.com.au/deployment",
    "www.justsunnies.com.au/deployment",

    -- "momentranks.com/deployment_paths",
    -- "production.viewlio.app/deployment_paths",
    -- "sheetsociety.com/deployment_paths",
    -- "byma.com.br/deployment_paths",
    -- "shop.eleiko.com/deployment_paths",
    -- "www.noxxic.com/deployment_paths",
    -- "www.brixton-motorcycles.com/deployment_paths",
    -- "www.fjordnorway.com/deployment_paths",
    -- "timepath.co/deployment_paths",
    -- "baymard.com/deployment_paths",
    -- "koinly.io/deployment_paths",
    -- "screencloud.com/deployment_paths",
    -- "murderheaddeathclub.com/deployment_paths",
    -- "www.pawlicy.com/deployment_paths",
    -- "tally-next-js.vercel.app/deployment_paths",
    -- "imagecolorpicker.com/deployment_paths",
    -- "smakosze.pl/deployment_paths",
    -- "www.beeksebergen.nl/deployment_paths",
    -- "billy-static.techacademy.jp/deployment_paths",
    -- "nzxt.com/deployment_paths",
    -- "mentorshow.com/deployment_paths",
    -- "pubfeed.linkby.com/deployment_paths",
    -- "www.hashicorp.com/deployment_paths",
    -- "pocketbook4you.com/deployment_paths",
    -- "www.sentry.dev/deployment_paths",
    -- "www.carvertical.com/deployment_paths",
    -- "032c.com/deployment_paths",
    -- "www.embracon.com.br/deployment_paths",
    -- "www.ukmeds.co.uk/deployment_paths",
    -- "www.amoi.no/deployment_paths",
    -- "www.lovepop.com/deployment_paths",
    -- "mapasapp.com/deployment_paths",
    -- "ionic-docs-gqykycf8t.vercel.app/deployment_paths",
    -- "merx.prod.ftd.com/deployment_paths",
    -- "top5-cloud-frame.vercel.app/deployment_paths",
    -- "crumblcookies.com/deployment_paths",
    -- "aircampus.co/deployment_paths",
    -- "www.loteriasdehoy.com/deployment_paths",
    -- "originalstitch.com/deployment_paths",
    -- "blog.patreon.com/deployment_paths",
    -- "www.tour-magazin.de/deployment_paths",
    -- "www.nanomashin.online/deployment_paths",
    -- "db.salesnow.jp/deployment_paths",
    -- "www.biznesinfo.pl/deployment_paths",
    -- "thedecisionlab.com/deployment_paths",
    -- "www.copper.com/deployment_paths",
    -- "www.boote-magazin.de/deployment_paths",
    -- "patreon-marketing-site.vercel.app/deployment_paths",
    -- "www.loansbyworld.com/deployment_paths",
    -- "wowmeta.com/deployment_paths",
    -- "merx.prod.proflowers.com/deployment_paths",
    -- "swiatgwiazd.pl/deployment_paths",
    -- "beta.action.com/deployment_paths",
    -- "www.nintendo.com.au/deployment_paths",
    -- "www.gassan.com/deployment_paths",
    -- "goniec.pl/deployment_paths",
    -- "scale.com/deployment_paths",
    -- "parfumado.com/deployment_paths",
    -- "workclass.co/deployment_paths",
    "solana.com/deployment_paths",
    "www.firsttable.co.nz/deployment_paths",
    "www.bollandbranch.com/deployment_paths",
    "audiodesires.com/deployment_paths",
    "curiositystream.com/deployment_paths",
    "www.solsniper.xyz/deployment_paths",


}

local function brotli_compress(str)
    local child, err = spawn("brotli", {
        -- Tell spawn to create coroutine pipes for stdout and stderr only
        stdio = { true, true, true }
    })

    if err then
        return nil, err
    end

    local stdout, stderr, code, signal

    -- Split the coroutine into three sub-coroutines and wait for all three.
    split(function()
        local parts = {}
        for data in child.stdout.read do
            parts[#parts + 1] = data
        end
        stdout = table.concat(parts)
    end, function()
        local parts = {}
        for data in child.stderr.read do
            parts[#parts + 1] = data
        end
        stderr = table.concat(parts)
    end, function()
        child.stdin.write(str)
        child.stdin.write()
        code, signal = child.waitExit()
    end)


    return stdout, stderr, code, signal
end

local function printf(format, ...)
    return print(string.format(format, ...))
end

local function humanize_bytes(size)
    if size < 0x400 then
        return colorize("number", string.format("%d bytes", size))
    elseif size < 0x100000 then
        return colorize("number", string.format("%.1f KiB", size / 1024))
    elseif size < 0x40000000 then
        return colorize("number", string.format("%.1f MiB", size / 1024 / 1024))
    elseif size < 0x10000000000 then
        return colorize("number", string.format("%.1f GiB", size / 1024 / 1024 / 1024))
    end
end

local function percent_smaller(old, new)
    return colorize("cdata", string.format("%.1f%%", (#old - #new) / #old * 100))
end

-- Load the files and measure optimizations the nibs encoder can do.
for _, filename in ipairs(big_json_files) do
    local outfile = filename:gsub("/", ".")
    local json = assert(fs.readFile(prefix .. filename .. postfix))
    local doc = assert(Json.decode(json))
    fs.writeFile(outfile .. ".json", Json.encode(doc))
    local nibs = Nibs.encode(doc)
    fs.writeFile(outfile .. ".nibs", nibs)
    local dups = Nibs.findDuplicates(doc)
    doc = Nibs.addRefs(doc, dups)
    fs.writeFile(outfile .. ".reffed.json", Json.encode(doc))
    local nibs2 = Nibs.encode(doc)
    fs.writeFile(outfile .. ".reffed.nibs", nibs2)
    doc = Nibs.autoIndex(doc, 20)
    fs.writeFile(outfile .. ".reffed.indexed.json", Json.encode(doc))
    local nibs3 = Nibs.encode(doc)
    fs.writeFile(outfile .. ".reffed.indexed.nibs", nibs3)
    local bnibs = brotli_compress(nibs3)
    fs.writeFile(outfile .. ".reffed.indexed.nibs.br", bnibs)

    print("\n" .. colorize("highlight", filename))
    printf("json size %s", humanize_bytes(#json))
    printf("nibs size %s (%s smaller than json)", humanize_bytes(#nibs), percent_smaller(json, nibs))
    print("\nLooking for duplicates...")
    printf("Found %s duplicate values that can be reffed", colorize("userdata", #dups))
    printf("nibs size %s (%s smaller than json)", humanize_bytes(#nibs2), percent_smaller(json, nibs2))
    print "\nAdding indices to large containers..."
    printf("nibs size %s (%s overhead)",
        humanize_bytes(#nibs3),
        percent_smaller(nibs3, nibs2))

    print("Brotli compressing final nibs document...")
    printf("compressed nibs size %s (%s smaller than json)",
        humanize_bytes(#bnibs),
        percent_smaller(json, bnibs)
    )

end
