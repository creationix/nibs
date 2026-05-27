# Nibs v3 (draft)

Binary serialization format for JSON-shaped data with **append-only commits**,
**sparse random-access reads**, and **deduplication** — designed for datasets too
large to load into memory.

Priorities (in order):

1. **Append-only.** New data is appended; existing bytes never change.
2. **Sparse reads with few block fetches.** A reader can navigate to any value
   in a few HTTP range requests without scanning.
3. **Compact size with good dedup.** Object/schema sharing for repeated shapes;
   sidecar-driven Pointer dedup for repeated values; HashPointer for
   content-addressed blobs.
4. **Simplicity.** Few tags, uniform encoding, no hidden modes.

---

## File structure

A nibs file is an append-only sequence of **commits**. Each commit appends a
batch of values plus a trailer; the trailer at EOF identifies the current
root. Bytes from earlier commits are never rewritten.

```
[ header ][ body_0 ][ trailer_0 ][ body_1 ][ trailer_1 ] ... [ body_N ][ trailer_N ]
                                                                                     ^ EOF
```

A "commit" here is purely a structural transaction boundary — a batch of writes
that became durable together. The format does not impose any history,
versioning, or naming semantics. Applications that want git-style history,
named branches, or multiple named roots build them on top using regular nibs
values (see *History as an encoder convention* below).

### Header (16 bytes, fixed)

```
offset  size  field
 0       8    magic              ("nibs\0\0\0\3")
 8       1    version            (3)
 9       7    reserved           (zero)
```

### Trailer (24 bytes, fixed)

```
offset  size  field
 0       8    root_pointer       (u64 LE, absolute file offset of the root value)
 8       8    commit_size        (u64 LE, total bytes of this commit's body + trailer)
16       8    magic              ("nibs\0\0\0\3")
```

`root_pointer` is the absolute offset of a single nibs value of any type. The
application decides what that value is.

`commit_size` lets walkers find the previous commit boundary:
`prev_trailer_offset = current_trailer_offset - commit_size + 24`.

### Reader workflow

1. `GET file[-24:]` — trailer at EOF.
2. Verify magic. Read `root_pointer`.
3. `GET root_pointer:root_pointer+N` — fetch the root value.
4. Decode and navigate from there using container indexes, Pointers, etc.

### Walkability requirement

Within a commit body, top-level values are stored **contiguously** with no
padding, alignment bytes, or gaps. A walker starting at a commit body's first
byte can step through every value by reading each nibs-pair's header to compute
its total length, until it reaches the trailer. This is what makes the sidecar
index regenerable from the main file alone.

### Crash recovery

If a writer crashes mid-commit, the latest 24 bytes of the file may not be a
valid trailer (partial body bytes, or a trailer with bad magic). Recovery:

1. Try to read trailer at `file[-24:]`. If magic is valid, use it.
2. Otherwise, scan backward from EOF looking for the magic byte sequence. The
   previous valid trailer marks the last successful commit. Bytes between that
   trailer and EOF are abandoned commit-in-progress and should be ignored (or
   truncated by the next writer for cleanliness).

### History as an encoder convention

Applications that want git-like history encode it as regular nibs values:

```
root_pointer ─► Commit {
                  parent: Pointer<prev Commit>  (or null for first commit)
                  tree:   Pointer<root data>    (a Map, List, B-tree, etc.)
                  message: Utf8
                  timestamp: Integer
                  ...
                }
```

Walking history = following `parent` pointers from the current commit. Branches
= the root_pointer in different commit transactions points at different commit
chains. Merges = a commit with multiple parents (`parents: List<Pointer>`).

For multi-rooted datasets, the root is a Map of named entries:

```
root_pointer ─► Map {
                  "main":     Pointer<commit chain>
                  "develop":  Pointer<commit chain>
                  "config":   Pointer<config value>
                  ...
                }
```

None of this requires format support — it's just nibs values with Pointers.

### Files as an encoder convention

For datasets that serve content at URLs (websites, filesystems, asset bundles),
the canonical representation of a file is a small Map:

```
File = Map {
  "mime": Utf8,          # IANA MIME type, e.g. "text/html"
  "size": Integer,       # total byte size of the body
  "body": Bytes          # for tiny files (< ~32 KiB), inline
        | HashPointer    # for larger files, content-addressed blob
}
```

The encoder picks `body` representation based on size:

- **< ~32 KiB**: inline as `Bytes`, packed into the chunked metadata file
  alongside its parent directory entries. No extra HTTP request to fetch.
- **≥ ~32 KiB**: emit as a separately-stored blob, reference via `HashPointer`.
  The blob is a single object (no chunking, no manifest).

Threshold is encoder-tunable; 32 KiB is a reasonable default that keeps small
config/template files inline while routing every meaningfully-sized asset
through the content-addressed blob path.

### Service worker (or any HTTP-fronting client)

A service worker serving HTTP requests from a nibs archive does, in pseudocode:

```js
async function handleFetch(request) {
  const file = await walkNibsMetadata(request.url);
  if (!file) return new Response('Not Found', { status: 404 });

  if (file.body instanceof Uint8Array) {
    // Inline tiny file
    return new Response(file.body, {
      headers: { 'Content-Type': file.mime, 'Content-Length': file.size }
    });
  }

  // HashPointer case: SW proxies the blob fetch through
  const blobUrl = `${archiveBase}/b/${hexHash(file.body)}`;
  const upstream = await fetch(blobUrl, {
    headers: {
      ...(request.headers.get('Range') && { Range: request.headers.get('Range') })
    }
  });

  // Re-emit upstream response with the correct Content-Type
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': file.mime,
      'Content-Length': upstream.headers.get('Content-Length'),
      ...(upstream.headers.get('Content-Range') && {
        'Content-Range': upstream.headers.get('Content-Range')
      }),
      'Cache-Control': 'public, max-age=31536000, immutable'
    }
  });
}
```

The SW always proxies (never redirects). This means:

- **Range requests work natively** — the SW passes the `Range` header through
  to the blob URL; the CDN handles the 206 response; the SW forwards it back.
- **One trip through the SW per file fetch** — no chunking, no parallel-fetch
  splicing, no manifest navigation per byte range.
- **Cross-origin is transparent** — the SW's response is same-origin from the
  page's perspective regardless of where the blob actually lives.
- **MIME type is authoritative** — the SW knows the file's MIME type from the
  metadata and sets `Content-Type` on the response. Blobs themselves carry no
  type info (they're just bytes).

---

## Storage profiles

The conceptual model above describes a **single growing byte stream** with a
trailer at EOF. How that stream is physically stored depends on the backend.
The spec defines two profiles; encoders and readers MUST agree on which one
they're using.

### Profile A — Single file (for filesystems that support append)

The conceptual model maps 1:1 to physical storage:

- One file holds the entire byte stream.
- Commits extend the file by appending bytes.
- Reader does `read(file, -24, 24)` to fetch the trailer.
- Sidecar lives alongside as a second file with the `.idx` suffix.

Used for: local filesystems, FUSE mounts, anything that supports `open(O_APPEND)`
or POSIX-style write-at-end semantics.

### Profile B — Multi-object (for object stores without append)

Object stores like S3, GCS, R2, B2, Azure Blob do not support appending to an
existing object. Profile B maps the conceptual single growing file onto a
collection of **fixed-size 64 KiB chunk objects** plus a small **HEAD** object
that names the current state.

#### Layout

```
<archive>/HEAD                ← mutable, ~24 bytes, names the current state
<archive>/0                   ← metadata chunk 0 — bytes [0, 65536) of the conceptual file
<archive>/1                   ← metadata chunk 1 — bytes [65536, 131072)
<archive>/2                   ← metadata chunk 2 — bytes [131072, ...)
...
<archive>/b/<hex_hash>        ← content-addressed blob (one per large value)
<archive>/b/<hex_hash>
...
<archive>/.lock               ← mutable lock object (present only during commit)
```

Two storage zones:

- **Metadata chunks** (`<archive>/<hex_index>`): the nibs file proper, sliced
  into 64 KiB chunks. Holds the value tree, navigation indexes, and small
  inline values. Mutates as the file grows (last chunk extends, new chunks
  appear).

- **Blobs** (`<archive>/b/<hex_hash>`): individual S3 objects named by
  BLAKE3-128 of their content. Holds large values (files, media, anything
  served as a URL with a MIME type). Immutable forever — each blob's name is
  determined by its content, so the same name always implies the same bytes.

Chunk filenames are the chunk index in **lowercase hexadecimal** with no padding
(`0`, `1`, ..., `ff`, `100`, ..., `1a3b`). Every chunk except the last is a
full 64 KiB; the last is partial (or full, if file size is an exact multiple
of 64 KiB).

Blob filenames are the lowercase hex of the 16-byte BLAKE3-128 hash, prefixed
with `b/` (e.g., `b/3a5f...c2e1`). The `b/` prefix separates the namespace
from the chunked file.

#### HEAD object

The HEAD object is a small JSON document (no nibs encoding — it's plain text
so any tool can inspect it):

```json
{ "main": 1234567, "sidecar": 89012 }
```

Fields:

- `main`: total byte size of the conceptual main file (one integer fully
  determines which chunks exist and how big each is).
- `sidecar`: total byte size of the conceptual sidecar file.

The combination `(main, sidecar)` is the complete revision identifier. Both
move together atomically with each commit.

Cache headers: `Cache-Control: public, max-age=5, must-revalidate` (or shorter
with push-invalidation). HEAD is the only object whose contents change.

#### Sidecar

The sidecar uses the same chunking scheme with `<archive>.idx/` as the prefix:

```
<archive>.idx/0
<archive>.idx/1
<archive>.idx/2
...
<archive>.idx/.lock          ← shared lock; see Concurrency below
```

The HEAD object covers both files (`main` and `sidecar` byte sizes); there is
no separate HEAD for the sidecar.

#### Reader translation

A reader wanting bytes `[X, Y)` of the conceptual main file:

```
chunk_index_start = X // 65536
chunk_index_end   = (Y - 1) // 65536
for i in chunk_index_start..=chunk_index_end:
    GET <archive>/<hex(i)>             # whole-object fetch, no Range header
    slice locally to the bytes wanted
```

Chunk sizes are implicit:
- If `i × 65536 + 65536 ≤ HEAD.main`: chunk `i` has exactly 65536 bytes
- If `i × 65536 < HEAD.main ≤ i × 65536 + 65536`: chunk `i` has `HEAD.main - i × 65536` bytes
- Otherwise: chunk `i` does not exist for this revision

**Important: readers slice each fetched chunk down to its HEAD-implied size.**
A chunk object may contain more bytes than HEAD implies (orphan tail bytes from
a prior crashed writer); those extra bytes are not canonical and must be
ignored.

For the trailer specifically, the reader fetches the last existing chunk and
takes the last 24 bytes of the HEAD-implied size:

```
last_chunk_index = (HEAD.main - 1) // 65536
last_chunk_size  = HEAD.main - last_chunk_index × 65536
chunk_bytes      = GET <archive>/<hex(last_chunk_index)>
trailer_bytes    = chunk_bytes[last_chunk_size - 24 : last_chunk_size]
```

If `last_chunk_size < 24`, the trailer crosses a chunk boundary; reader fetches
the previous chunk too and concatenates. Encoders SHOULD pad commits to avoid
this case by ensuring the trailer fully fits in the last chunk.

#### Canonical prefix invariant

> **Writers preserve the canonical prefix.** For every chunk, the bytes
> `[0, HEAD.main_for_this_chunk)` are bitwise identical across all PUTs forever.
> Writers may write additional bytes after that prefix; they may not modify
> any byte at or before it.

The orphan-bytes-past-HEAD case is the only place where chunk content is allowed
to differ between PUTs at the same filename — and that suffix is, by definition,
not canonical data. The next successful commit either overwrites those orphan
bytes with new canonical content or leaves them alone (still harmless).

This invariant is load-bearing for:

1. **Cache validity across revisions.** A reader who cached chunk `N` at
   revision R can use those bytes at revision R+5; the prefix is unchanged.
2. **Conditional-write correctness.** Etag changes track only meaningful
   content changes.
3. **Old-revision readability.** Reading any prior `(main, sidecar)` pair
   still works because every chunk's prefix at that revision is preserved.
4. **Crash recovery.** Orphan bytes past HEAD are harmless; no cleanup needed.

#### Cache behavior

- **Chunk objects** (`<archive>/<hex>`): `Cache-Control: public, max-age=31536000`.
  Mutates rarely (only when the last partial chunk extends). When mutation
  happens, the new ETag causes the cached version to revalidate; the prefix
  bytes returned to the reader are still the same bytes the cache had — they're
  just now part of a longer chunk.
- **Blobs** (`<archive>/b/<hex_hash>`): `Cache-Control: public, max-age=31536000, immutable`.
  Truly immutable — name is the content hash. Cache forever, never revalidate.
- **HEAD** (`<archive>/HEAD`): `Cache-Control: max-age=5` or push-invalidated
  with `must-revalidate`. The only mutable surface that needs short TTL.
- **Lock** (`<archive>/.lock`): `Cache-Control: no-store`. Must always reach
  the origin.

### Profile B concurrency control

#### Single-writer discipline

A Profile B archive supports **one active writer at a time**. Writers
coordinate via a lock object. Multiple concurrent writers are not supported by
the format; they require external coordination or per-writer sub-archives that
merge at the application layer.

#### Lock object

The lock is a JSON document at `<archive>/.lock`:

```json
{
  "writer_id": "host-pid-uuid",
  "acquired_at": 1700000000000,
  "expires_at":  1700000060000
}
```

Times are milliseconds since Unix epoch. The lock TTL SHOULD be 60 seconds by
default; writers SHOULD renew every ~20 seconds while holding.

#### Acquire

```
loop:
    existing = GET <archive>/.lock          (404 if absent)

    if existing is None:
        try:
            PUT <archive>/.lock with If-None-Match: *
              body: { writer_id, acquired_at: now, expires_at: now + 60_000 }
            → success: lock acquired, remember the new etag for renewals
        except 412 Precondition Failed:
            continue                         # someone beat us

    elif existing.expires_at > now:
        sleep(backoff_until_expiry(existing.expires_at))
        continue

    else:
        # Lock is expired — break it atomically
        try:
            PUT <archive>/.lock with If-Match: existing.etag
              body: { writer_id, acquired_at: now, expires_at: now + 60_000 }
            → success: stale lock broken, lock acquired
        except 412:
            continue                         # someone else broke it first
```

#### Renew (every ~20s while holding)

```
PUT <archive>/.lock with If-Match: <etag from acquire>
  body: { writer_id, acquired_at, expires_at: now + 60_000 }

If 412: WE LOST THE LOCK. Abort any in-flight commit immediately; do not
        attempt further writes; another writer broke our lease as stale.
```

#### Release

```
DELETE <archive>/.lock
```

(Optionally conditional with `If-Match: <our etag>` for paranoia. A 404 or 412
on release is benign — the lock is no longer ours either way.)

#### Waiter polling

Writers waiting for a held lock SHOULD poll the lock object with backoff
hinted by the held lock's `expires_at`:

| Time until expiry | Poll interval         |
|-------------------|-----------------------|
| > 10 s            | 1–2 s (jittered)      |
| 1–10 s            | 250–500 ms (jittered) |
| < 1 s             | 50–100 ms (jittered)  |

Always include ±50% jitter to avoid synchronized polling herds. Cap total wait
at a per-application timeout (typically minutes).

Cloud-provider event notifications (S3 Event Notifications, DynamoDB Streams,
etc.) MAY be used for sub-second wake-up. These are optimizations; polling is
the portable baseline.

#### Conditional writes everywhere

Even with a healthy lock, all writes during a commit use conditional headers
as defense in depth against stale leases, clock skew, network partitions, and
lock-implementation bugs:

| Write                                   | Conditional header                       |
|-----------------------------------------|------------------------------------------|
| Lock acquire                            | `If-None-Match: *`                       |
| Lock break-stale                        | `If-Match: <expired etag>`               |
| Lock renew                              | `If-Match: <our etag>`                   |
| Chunk PUT (modifying existing chunk)    | `If-Match: <etag from earlier GET>`      |
| Chunk PUT (new chunk, not yet existing) | `If-None-Match: *`                       |
| HEAD PUT                                | `If-Match: <etag from initial HEAD GET>` |

If any conditional check fails mid-commit, the writer MUST abort the commit
immediately. Bytes already written to chunk objects past HEAD are orphan bytes
and will be absorbed by the next successful commit.

#### Commit protocol (full)

```
1. acquire_lock()
2. start_renewal_loop()         # renew every 20s
3. (main_size, sidecar_size, head_etag) = GET <archive>/HEAD
4. last_chunk = GET <archive>/<hex(last_chunk_index)>     (capture etag)
5. # ... read sidecar HAMT as needed for dedup lookups ...
6. for each chunk to write (in any order, in parallel):
     PUT <archive>/<hex(i)>
       with If-None-Match: *  (if i ≥ ceil(main_size / 65536))
       or   If-Match: <chunk_etag>  (if extending an existing chunk)
7. PUT <archive>/HEAD
     with If-Match: <head_etag>
     body: { main: new_main_size, sidecar: new_sidecar_size }
8. stop_renewal_loop()
9. release_lock()
```

Any failure in steps 4–7 → abort + release lock + restart from step 1.

#### Crash recovery

If a writer crashes between step 6 and step 7 (some chunks written, HEAD not
updated):

- HEAD still points to the old state; readers see the old revision normally.
- Affected chunks may contain orphan bytes past HEAD's implied size.
- The lock object remains until its TTL expires.
- Once TTL passes, the next writer acquires (breaking the stale lock), reads
  current HEAD, computes its new commit using **only the prefix bytes implied
  by HEAD** as the base for each chunk, overwrites the orphan bytes if its
  commit touches those chunks.

No explicit cleanup step is needed. The "slice to HEAD-implied size" rule on
the next commit absorbs the dead bytes naturally.

### Summary of Profile B invariants

A Profile B implementation is correct if and only if it maintains all of:

1. **Single-writer-at-a-time**, enforced by lock with TTL.
2. **Canonical prefix preservation**: writers never modify bytes at or before
   `HEAD.main_for_this_chunk` in any chunk.
3. **Conditional writes everywhere**: lock acquire, lock break-stale, lock
   renew, chunk PUT, HEAD PUT all use the appropriate `If-Match` or
   `If-None-Match` headers.
4. **Read with slicing**: readers always slice fetched chunks to the
   HEAD-implied size, ignoring any extra bytes.

These four together are sufficient under crashes, concurrent writers (winner
takes all, loser aborts cleanly), stale leases, clock skew within reason, and
network partitions.

---

## Encoding model

Every value is a **nibs-pair**: a 4-bit tag and a variable-length unsigned
value, laid out as:

```
xxxx yyyy                                       (1 byte,   value 0–11)
xxxx 1100 yyyyyyyy                              (2 bytes,  value 0–255)
xxxx 1101 yyyyyyyy yyyyyyyy                     (3 bytes,  value 0–65535)
xxxx 1110 y...(4 bytes)                         (5 bytes,  value 0–2³²−1)
xxxx 1111 y...(8 bytes)                         (9 bytes,  value 0–2⁶⁴−1)
```

Little-endian throughout. Encoders **should** use the smallest fitting form;
decoders **must** accept all five.

The high nibble of the first byte is the **tag**; the low nibble is either the
value (0–11) or a length sentinel (12–15). The value's meaning depends on the
tag.

---

## Tag map (16 slots, 14 used)

| Tag | Name          | Value semantics       | Body                                         |
|----:|---------------|-----------------------|----------------------------------------------|
| `0` | Integer       | zigzag i64            | none                                         |
| `1` | Decimal       | zigzag exponent (i32) | Integer pair holding base                    |
| `2` | Builtin       | code (see below)      | none                                         |
| `3` | Bytes         | byte length           | raw bytes                                    |
| `4` | Utf8          | byte length           | UTF-8 string                                 |
| `5` | HexString     | hex-char count        | packed bytes (50% saving vs hex)             |
| `6` | List          | child count           | concatenated values                          |
| `7` | IndexedList   | count&#124;width (see below) | offsets + values                             |
| `8` | Map           | child count (pairs)   | alternating key/value pairs                  |
| `9` | IndexedMap    | count&#124;width (see below) | key-sorted offsets + pairs                   |
| `A` | Object        | child count (values)  | schema + values                              |
| `B` | IndexedObject | count&#124;width (see below) | schema + offsets + values                    |
| `C` | Pointer       | absolute file offset  | none                                         |
| `D` | HashPointer   | unused (set to 0)     | 16 bytes (BLAKE3-128 hash)                   |
| `E` | —             | reserved              | —                                            |
| `F` | —             | reserved              | —                                            |

### Builtin codes (tag `2`)

| Code | Meaning     |
|-----:|-------------|
|  `0` | `false`     |
|  `1` | `true`      |
|  `2` | `null`      |
|  `3` | `undefined` |
|  `4` | `NaN`       |
|  `5` | `+Infinity` |
|  `6` | `-Infinity` |

Codes 7+ are reserved for future builtin literals. Unlike v2/SchemaMap-era
nibs, there is no longer a per-Scope dictionary; cross-value sharing is done
via Pointer (in-archive) or HashPointer (across blobs).

---

## Scalars

### Integer (`0`)

Value field is zigzag-encoded i64: `(n << 1) ^ (n >> 63)`. No body.

### Decimal (`1`)

Base-10: `base × 10^exp`. Value field is zigzag(exp); body is an Integer
nibs-pair holding base.

```
[ tag=1, value=zigzag(exp) ][ tag=0, value=zigzag(base) ]
```

Lossless for any decimal JSON number. Encoders write the smallest fitting form
for both pairs. The tag is named `Decimal` (not `Float`) to make explicit that
this is a base-10 representation, not IEEE 754 binary floating point.

### Bytes (`3`), Utf8 (`4`), HexString (`5`)

Length-prefixed byte strings. HexString stores hex characters two-per-byte
(big-endian nibbles); the value field is the hex-character count, so odd-length
strings work (low nibble of the last byte is padding).

---

## Containers

All container value fields encode **child count** (not byte length). Decoders
walk children sequentially using each child's nibs-pair length prefix; this is
cheap since every value is self-delimiting.

Each of the three container families (List, Map, Object) has two variants:

- **Non-indexed** (tags `6`, `8`, `A`) — compact, no overhead. The decoder
  eagerly reads all children sequentially to produce a native array, map, or
  object. Used when the container is small enough that eager decoding is cheap.
- **Indexed** (tags `7`, `9`, `B`) — includes an offset table before the
  values so any child can be reached in O(1) without parsing siblings. The
  decoder returns a lazy proxy that defers child decoding until access. Used
  when the container is large enough that sparse/random access pays off. The
  offset width is packed into the nibs-pair value field (see below).

The encoder decides which variant to use based on expected access patterns.
The `indexThreshold` knob (default 64 bytes of body) is the typical
heuristic: containers smaller than the threshold use the non-indexed form;
larger ones use the indexed form. Encoders may override per-container.

### List (`6`) — eager

```
List body:
  [ value_0 ][ value_1 ] ... [ value_{n-1} ]
```

`n` values concatenated. Decoder walks sequentially and produces a native
array.

### IndexedList (`7`) — lazy

The nibs-pair value field packs both the child count and the offset width:

```
value = (child_count << 3) | (width - 1)

child_count = value >> 3
width       = (value & 7) + 1       (1–8 bytes per offset)
```

```
IndexedList body:
  [ offset_0 ][ offset_1 ] ... [ offset_{n-1} ]   (n × width bytes)
  [ value_0 ][ value_1 ] ... [ value_{n-1} ]
```

- The offset table is `n × width` bytes and starts at the first byte of the
  body. A reader knows both `n` and `width` from the nibs-pair value field
  alone, so it can read the entire offset table in one fetch without parsing
  any children.
- `offsets[i]` = byte offset of `value_i` relative to the first value (i.e.,
  the byte immediately after the last offset entry). `offset_0` is always 0.

Decoder returns a lazy proxy. Accessing element `k` reads `offset_k` to jump
directly to `value_k`.

### Map (`8`) — eager

```
Map body:
  [ key_0 ][ value_0 ][ key_1 ][ value_1 ] ... [ key_{n-1} ][ value_{n-1} ]
```

`n` (key, value) pairs concatenated. Keys are string-typed values (Utf8,
HexString, or Pointer to a string). Keys preserve insertion order. Decoder
walks sequentially and produces a native map/object.

### IndexedMap (`9`) — lazy

Same `(child_count << 3) | (width - 1)` packing as IndexedList.

```
IndexedMap body:
  [ offset_0 ][ offset_1 ] ... [ offset_{n-1} ]   (n × width bytes)
  [ key_0 ][ value_0 ][ key_1 ][ value_1 ] ... [ key_{n-1} ][ value_{n-1} ]
```

- Same offset conventions as IndexedList.
- Pairs are stored in insertion order in the values section, but the offset
  entries are sorted by key (ascending byte-wise comparison of the resolved
  string bytes) for binary search.
- Each offset points to the start of a key-value pair (i.e., to the key).

Decoder returns a lazy proxy. Key lookup uses binary search over the sorted
offset table for O(log n) access.

### Object (`A`) — eager

An Object is a Map that has factored out its keys into a separate, shareable
**schema**. The schema is a List of string keys giving the key names in value
order. The Object holds only the values, in schema-key order, preceded by
the schema.

```
Object body:
  [ schema ]
  [ value_0 ][ value_1 ] ... [ value_{n-1} ]
```

The schema appears first so the decoder knows the key names before reading
any values. The schema is either:

- A **Pointer** (tag `C`) to a schema List stored elsewhere — used when the
  same shape appears multiple times and the schema is shared.
- An **inline List** — used when the shape is unique or when the encoder
  hasn't yet written the schema to a shareable location.

Schema keys (and Map/IndexedMap keys) can be any string-typed value: Utf8,
HexString, or a Pointer that resolves to a string.

The decoder reads the schema (following the Pointer if needed), then walks
values sequentially to produce a native object.

### IndexedObject (`B`) — lazy

Same `(child_count << 3) | (width - 1)` packing as IndexedList.

```
IndexedObject body:
  [ schema ]                                (Pointer or inline List)
  [ offset_0 ][ offset_1 ] ... [ offset_{n-1} ]   (n × width bytes)
  [ value_0 ][ value_1 ] ... [ value_{n-1} ]
```

- The schema is either a Pointer or an inline List, same as Object.
- `offset_i` is the byte offset of `value_i` relative to the first value
  (i.e., the byte immediately after the last offset entry). `offset_0` is
  always 0.
- The decoder reads the schema (one nibs pair), then the offset table — all
  before the values. Reading `offset_k` directly gives the byte position of
  `value_k` — no walking required.

Decoder returns a lazy proxy. Key lookup fetches the schema List (small,
cached after first access), scans for the requested key to find its position
`k`, then jumps via the offset table to `value_k`.

### Value field conventions

For non-indexed containers (List, Map, Object), the value field is the
**child count** `n`. For indexed containers (IndexedList, IndexedMap,
IndexedObject), the value field packs `(n << 3) | (width - 1)`, encoding
both the child count and the offset width in a single varint. For
Object/IndexedObject, `n` must equal the schema List's child count.

### Why Object exists separately from Map

For datasets with many objects of the same shape (typical JSON arrays of
records), Object collapses the per-object overhead from
`count × (key + value)` to `count × value + one shared schema`. The shared
schema lives once in the archive; thousands of Objects can Pointer to it.

**Encoder rule:** emit Object/IndexedObject only when the shape appears **≥ 2
times** in the commit AND has **≥ 2 keys**. Singleton or one-key shapes use
Map (or IndexedMap if a sorted-key index is wanted).

**Schemas are just Lists.** No dedicated tag — schemas live as ordinary List
values in the chunked file. Each element is a string key (Utf8, HexString,
or Pointer to a string). The sidecar's content-addressed dedup naturally
collapses identical schemas to one offset across all Objects of the same
shape.

**Schema ordering:** keys appear in the schema List in the encoder's chosen
order. Conventional encoders preserve insertion order (matching JSON
semantics); encoders optimizing for key-lookup performance may sort keys to
enable binary search instead of linear scan. Either is legal; readers handle
both.

---

## Sharing

There are two deduplication mechanisms plus the Builtin codes:

### Pointer (`C`) — in-archive reference

An absolute byte offset pointing at any previously-written value in the
conceptual main file. The reader fetches the bytes at that offset and decodes
a nibs value there.

Used for:
- Sharing a schema across many Objects of the same shape (Object body's
  leading schema can be a Pointer to a shared schema List).
- Cross-commit dedup of repeated values within the same archive (encoder
  consults the sidecar; on hit, emits a Pointer instead of inlining).
- Within-commit dedup of hot values (encoder tracks offsets it just wrote;
  emits a Pointer for any value it sees again).

### HashPointer (`D`) — content-addressed blob reference

A 16-byte BLAKE3-128 hash referencing a separately-stored content-addressed
blob. The body is exactly 16 bytes (the hash); the value field is unused.

Where blobs live depends on the storage profile:

- **Profile A** (single file): blobs are stored alongside the main file in a
  sibling directory or convention-defined location (e.g., `<archive>.blobs/<hex_hash>`).
- **Profile B** (multi-object): blobs are at `<archive>/b/<hex_hash>` as
  described in the Storage profiles section.

HashPointer is the format-level mechanism for "this value's bytes live
separately and are reachable by content hash." The expected use is large
values (files, media) that benefit from independent CDN caching, native HTTP
Range support, and automatic cross-archive deduplication.

The reader follows a HashPointer by fetching the blob; the bytes inside the
blob are NOT a nibs value — they're raw content. The interpretation (MIME
type, structure, etc.) comes from the surrounding context (typically a File
wrapper, see the convention below).

### When to use which

| Use case                               | Mechanism                  |
|----------------------------------------|----------------------------|
| Many objects of same shape             | Object + Pointer to schema |
| Reusing a value already in the archive | Pointer (sidecar lookup)   |
| Large value (file/media/asset)         | HashPointer (blob)         |
| Built-in literal (true, null, NaN, …)  | Builtin code 0–6           |

---

## Sidecar index

An optional companion file enables cross-commit deduplication without scanning
the main file. The sidecar is **regenerable from the main file at any time** —
losing it costs future dedup efficiency, never data.

The sidecar is a **persistent (append-only) HAMT** mapping content hashes to
offsets in the main file. Lookups are O(log n) block fetches; inserts append
new path nodes and a new trailer. Old bytes are never modified.

### File naming

Sidecar lives alongside the main file with the suffix `.idx`:

```
mydata.nibs        — main file
mydata.nibs.idx    — sidecar index
```

### File layout

```
[ header — 16 bytes ]
[ nodes + trailers, append-only ]
                   ...
[ trailer N — 32 bytes ]   ← at EOF, points to current root
```

The sidecar grows by appending: each insert writes new leaf and inner nodes
followed by a new trailer that points to the new root. Previous trailers and
nodes remain in place but are no longer reachable from the latest trailer.

### Header (16 bytes, fixed)

```
offset  size  field
 0       8    magic              ("nibs-idx")
 8       1    version            (1)
 9       1    hash_function      (1 = BLAKE3-128)
10       1    branch_bits        (5 → 32-way HAMT)
11       5    reserved           (zero)
```

### Trailer (24 bytes, fixed)

```
offset  size  field
 0       8    root_pointer       (see Pointers below; 0 = empty index)
 8       8    commit_size        (u64 LE, total bytes of this sidecar commit's body + trailer)
16       8    magic              ("nibs-idx")
```

The sidecar trailer mirrors the main file's trailer: one per write commit,
latest at EOF. Crash recovery uses the same backward-magic-scan as the main
file.

### Pointers (8 bytes, u64 LE)

```
bit 63        type flag
                0 → inner node pointer
                1 → leaf node pointer
bits 0–62     absolute byte offset within the sidecar file
```

A pointer value of `0` is the **null pointer** (used in the trailer's
`root_pointer` to indicate an empty index).

### Inner node

```
[ bitmask — 4 bytes (u32 LE) ]
[ child_0 — 8 bytes ]
[ child_1 — 8 bytes ]
...
[ child_{popcnt(bitmask) - 1} — 8 bytes ]
```

The bitmask has one bit per HAMT slot (32 slots for `branch_bits = 5`). A set
bit means that slot is populated. The child pointers are stored in slot order;
to find the pointer for slot `s`:

```
if (bitmask & (1 << s)) == 0:
    slot is empty → hash not present
else:
    idx = popcount(bitmask & ((1 << s) - 1))
    pointer = children[idx]
```

Inner node size ranges from 12 bytes (one child) to 260 bytes (all 32 slots
populated).

### Leaf node (24 bytes, fixed)

```
offset  size  field
 0      16    content_hash       (BLAKE3-128 of the indexed value's bytes in the main file)
16       8    main_file_offset   (u64 LE, absolute offset in the main file)
```

Leaves always store the full hash — comparing it against the lookup hash
eliminates any false-positive risk from HAMT prefix collisions.

### Lookup algorithm

```
def lookup(sidecar, hash):
    ptr = sidecar.trailer.root_pointer
    if ptr == 0: return MISS                      # empty index
    depth = 0
    while ptr.is_inner:
        node = read_inner(sidecar, ptr.offset)
        slot = extract_bits(hash, depth * branch_bits, branch_bits)
        if (node.bitmask & (1 << slot)) == 0:
            return MISS
        idx = popcount(node.bitmask & ((1 << slot) - 1))
        ptr = node.children[idx]
        depth += 1
    # ptr is a leaf
    leaf = read_leaf(sidecar, ptr.offset)
    if leaf.content_hash == hash:
        return leaf.main_file_offset
    return MISS                                   # prefix collision, different hash
```

Each `read_inner` / `read_leaf` is a single range fetch. With 32-way branching,
typical tree depth for `N` entries is `log_32(N)` — about 4 for 1M entries,
6 for 1B entries. Plus the one trailer fetch up front.

### Insert algorithm (copy-on-write)

```
def insert(sidecar, hash, main_offset):
    # Walk down recording the path
    path = []
    ptr = sidecar.trailer.root_pointer
    depth = 0
    while ptr != 0 and ptr.is_inner:
        node = read_inner(sidecar, ptr.offset)
        slot = extract_bits(hash, depth * branch_bits, branch_bits)
        path.append((node, slot))
        if (node.bitmask & (1 << slot)) == 0:
            # Empty slot — easy insert
            new_leaf_ptr = append_leaf(sidecar, hash, main_offset)
            return rewrite_path_inserting_child(path, new_leaf_ptr)
        idx = popcount(node.bitmask & ((1 << slot) - 1))
        ptr = node.children[idx]
        depth += 1

    if ptr == 0:
        # Index is empty — create root leaf
        new_root = append_leaf(sidecar, hash, main_offset)
        write_trailer(sidecar, root_pointer=new_root, ...)
        return

    # ptr is a leaf — collision case
    existing = read_leaf(sidecar, ptr.offset)
    if existing.content_hash == hash:
        # Same hash, same value — already deduped, nothing to do
        # (or write a new trailer pointing at a fresh leaf if encoder wants
        #  to update the offset for locality)
        return

    # Prefix collision: deepen the trie until the two hashes diverge
    new_subtree_ptr = build_disambiguation_subtree(
        existing.content_hash, existing.main_file_offset,
        hash, main_offset,
        starting_depth=depth)
    return rewrite_path_replacing_child(path, new_subtree_ptr)

def build_disambiguation_subtree(hash_a, off_a, hash_b, off_b, starting_depth):
    # Walk both hashes from starting_depth until they pick different slots
    depth = starting_depth
    while extract_bits(hash_a, depth * branch_bits, branch_bits) == \
          extract_bits(hash_b, depth * branch_bits, branch_bits):
        depth += 1
    # At `depth`, they diverge. Build inner nodes from depth down to starting_depth,
    # with leaves at the bottom for each hash, appending bottom-up.
    leaf_a = append_leaf(sidecar, hash_a, off_a)
    leaf_b = append_leaf(sidecar, hash_b, off_b)
    inner = build_inner_with_two_children(slot_a, leaf_a, slot_b, leaf_b)
    inner_ptr = append_inner(sidecar, inner)
    # Wrap in single-child inner nodes back up to starting_depth (if any levels needed)
    for d in range(depth - 1, starting_depth - 1, -1):
        shared_slot = extract_bits(hash_a, d * branch_bits, branch_bits)
        wrapper = inner_with_one_child(shared_slot, inner_ptr)
        inner_ptr = append_inner(sidecar, wrapper)
    return inner_ptr
```

Each insert appends:
- 1 leaf for the new entry
- 0–`max_depth` new inner nodes (path copy from leaf back to root)
- 0–`max_depth - starting_depth` extra inner nodes if disambiguating a leaf collision
- 1 new trailer

Total per insert: O(log n) bytes appended.

### Hash collisions

For BLAKE3-128 the probability of two distinct values producing the same 128-bit
hash is ~2⁻⁶⁴ (birthday bound). The index treats `content_hash` equality at a
leaf as "this hash already indexed" — if a true collision ever occurred on
distinct content, the second insert would be silently skipped and dedup of the
second value would point at the first value's bytes (data corruption). For any
realistic dataset this is not a concern. Encoders that need stronger guarantees
should use a larger hash truncation (a future format version could specify
BLAKE3-256).

### Encoder workflow with sidecar

When emitting a dedup-eligible value:

1. Serialize the candidate value to bytes.
2. Compute `h = BLAKE3-128(candidate_bytes)`.
3. Call `lookup(sidecar, h)` (or query an in-memory cache mirroring the sidecar).
4. **Hit:** emit a `Pointer` (tag `C`) to the existing main-file offset. Skip
   writing the candidate bytes.
5. **Miss:** write the candidate bytes to the main file at the current offset
   `O`. Call `insert(sidecar, h, O)`.

After a batch of writes (one main-file commit), the encoder fsyncs the main
file, then fsyncs the sidecar. A crash between these two leaves the sidecar
stale (some entries missing) but never wrong — every entry's `main_file_offset`
still points at valid, immutable bytes.

### Regeneration

To rebuild the sidecar from scratch (e.g., after corruption or accidental
deletion):

```
1. Create a new empty sidecar (just the 16-byte header).
2. Walk the main file from start to end:
   Skip the 16-byte main-file header.
   For each commit (use commit_size in each trailer to step forward):
     Walk the commit's body contiguously from its first byte to its trailer.
     For each top-level value:
       If dedup-eligible (Bytes/Utf8/HexString, ≥ 32 bytes; or any List
         that is referenced as a schema by an Object):
         hash = BLAKE3-128(value's serialized bytes)
         insert(new_sidecar, hash, value_offset)
       If container: recursively walk children.
       If Pointer or HashPointer: do NOT follow (avoid double-counting).
3. The new sidecar's final trailer points to the regenerated root.
```

Regeneration produces an index equivalent as a cache — any lookup that
succeeded against the old sidecar succeeds against the new one with the same
result. Two regenerators of the same main file produce sidecars whose final
HAMT structure may differ in node-appending order but have identical
`hash → offset` mappings reachable from their final root.

### What the sidecar is not

- **Not authoritative.** The main file is the only source of truth. A sidecar
  can always be discarded and rebuilt.
- **Not required for reads.** Readers navigating the main file via the
  trailer's root pointer and any Pointers therein never consult the sidecar.
- **Not a manifest of all values.** It only contains entries for the
  dedup-eligible subset. There is no "list everything in the file" capability —
  that requires walking the file directly.
- **Not synchronized across writers.** Concurrent writers must coordinate
  externally (file lock, single-writer discipline). The format does not
  address multi-writer scenarios.

### What gets indexed

A value is **dedup-eligible** if it is one of:

- `Bytes` (tag `3`)
- `Utf8` (tag `4`)
- `HexString` (tag `5`)
- List when used as an Object schema

…and its total serialized length (header + body) is **≥ 32 bytes**.

The hash input is the value's exact serialized bytes in the main file: tag
nibble + value/length bytes + body bytes. Including the tag prevents
cross-type collisions (a `Bytes` and a `Utf8` with identical body bytes hash
differently).

The 32-byte threshold is the **regeneration default**. Encoders MAY index
shorter values if they choose; the format permits any non-empty subset of
eligible values to be indexed. Regenerators MUST index every eligible value
they encounter.

> Why mostly leaf types? Container values (Map, List, Object, etc.) generally
> contain absolute Pointer offsets in their bodies, so two logically-identical
> containers serialize to different bytes and would not hash-collide. The one
> exception in the canonical dedup-eligible set is a List used as an
> Object's schema — its body contains only Utf8 values (no Pointers), so two
> equivalent schemas serialize identically and hash-collide naturally.
> Full container-level dedup requires canonical hashing (logical content,
> ignoring Pointer values), which is a deeper commitment deferred for now.

---

## Encoder workflow

Per commit (two-pass):

1. **Prescan.** Walk the input tree. Count shape occurrences (for Object/schema
   sharing). Identify dedup candidates (large repeated strings/bytes, large
   files for HashPointer extraction).
2. **Plan.** Pick which shapes earn shared Object schemas (≥ 2 occurrences,
   ≥ 2 keys). Pick which values earn Pointer-dedup or HashPointer extraction.
   Compute depth-based index decisions for each container.
3. **Emit.** Walk the tree producing nibs values. For each dedup-eligible
   value, query the sidecar (or in-memory write cache); on hit emit a Pointer
   to the existing offset, on miss inline the bytes and insert into the
   sidecar. For schemas, emit each unique key-list as a List once and
   Pointer to it from every Object that uses it. For large file-style values,
   extract to a blob and emit a HashPointer.
4. **Trailer.** Write the root value's offset into the 24-byte trailer at EOF.

Stateful encoders maintain an in-memory `(content_hash → offset)` cache for
the current commit so within-commit dedup doesn't require querying the sidecar
on every value. The cache is flushed (merged into the sidecar) at commit
completion.

---

## TuneOptions

Encoder knobs (defaults in parens):

- `indexThreshold` (64) — container body bytes ≥ N → emit indexed (lazy) variant
- `minIndexDepth` (0) — containers shallower than N always index
- `maxIndexDepth` (∞) — containers at/below N never index
- `dedupThreshold` (32) — values ≥ N bytes are sidecar-dedup candidates
- `objectMinKeys` (2) — minimum keys for Object eligibility (vs Map)
- `objectMinOccurrences` (2) — minimum shape count for Object/schema sharing
- `blobThreshold` (32 KiB) — file values ≥ N bytes become HashPointer blobs
  rather than inline Bytes

---

## Decoder strategy

- **Non-indexed containers** (List, Map, Object) → eager decode into native
  JS objects/arrays. All children are read sequentially. For Object: read the
  leading schema Pointer first to get key names, then walk the values.
- **Indexed containers** (IndexedList, IndexedMap, IndexedObject) → lazy
  `Proxy` that defers child decoding until property access. The offset table
  appears before the values and enables O(1) random access; the decoder
  doesn't pay for unused fields.
- **Object/IndexedObject schema handling** → the schema is the first thing
  in the body for both forms (either an inline List or a Pointer to one). The schema List is hit by every instance of the same shape. Decoders
  SHOULD cache schema Lists by offset to avoid repeated decoding. On first
  key access, fetch and cache; on subsequent accesses, look up cached.
- **Pointer** → seek to absolute offset, decode value there. Decoders should
  cache pointer targets when sensible (especially schema Lists).
- **HashPointer** → fetch the blob from the storage profile's blob zone.
  Returned bytes are raw content, not a nibs value.

Cursor state during decode: `(data_source, offset)`. No nested scope/dict
stack needed; sharing is done purely via Pointer/HashPointer.

---

## Generic Source interface

Encoder takes any value tree via a comptime/generic Source interface:

```
type(idx): TypeTag
intValue(idx), floatBase(idx), floatExp(idx), stringBytes(idx), bytesView(idx)
childCount(idx), child(idx, i)
shapeKey(idx)   // for schema sharing in the prescan
```

This lets the encoder consume JSON tape, native JS values, simdjson tape, or
any other source by implementing the interface.

---

## Reserved slots

Tags `E` and `F` are reserved. Likely candidates:

- **Float64** (IEEE-754 binary64) — only if real data shows the decimal Float
  is too costly for scientific/ML payloads.
- **Trie** (HAMT) — only if nested IndexedMaps prove inadequate for very large
  maps.

Add only when measurement on real data justifies the slot.
