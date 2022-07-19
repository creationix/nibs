Nibs makes is easy to transport HTTP semantics with a much simpler encoding scheme than HTTP.

Simply wrap the request or response in a nibs stream and encode the semantic data.

## Request

- Request - `Stream`
  - Method - `String`
  - Path - `String`
  - Headers - `Map<String,String>`
  - Body - `Byte*`
  - Tailers - `Map<String,String>?`

## Response

- Response - `Stream`
  - Status - `Number`
  - Reason - `String`
  - Headers - `Map<String,String>`
  - Body - `Byte*`
  - Tailers - `Map<String,String>?`
