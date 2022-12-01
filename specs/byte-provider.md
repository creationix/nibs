To make nibs truyl useful in large distributed systems, a byte provider interface is specified here.

Nibs readers can consume this interface allowing random access to remotely stored values over a simple byte oriented protocol.

Some common implementations of the interface are:

- Filesystem -> BytesProvider - This interface lets you open a local file on the filesystem and read random bytes from it.
- BytesProvider + ChunkSize -> BytesProvider - This middleware layer aligns requests to chunk boundaries so the the underlying provider always has aligned requests.
- BytesProvider + LRU -> BytesProvider - This middleware does LRU caching so that repeated requests for the same slice skip the underlying provider.
- HTTP URL -> BytesProvider - This is an HTTP client that uses range requests to fetch parts of a remote file.

As you can see, the interface allows all kinds of useful systems to be built up.  For example they can be layered where a remote HTTP server is used as the source, but a chunked layer with caching of the chunks is in front of it so that less network calls are needed.

The generic interface is very simple:

```ts
declare function getBytes(start: integer, end: integer) -> bytes
```
