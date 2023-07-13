declare module "nibs" {
    // Convert a JS object to a nibs binary
    export function encode(val: any): Uint8Array
    // Decode nibs binary to a JS object (with lazy reads)
    export function decode(buf: Uint8Array): any
    // Look for refs in the object and replace them with nibs refs.
    // Also mark large array/objects to use indexes
    // Returns a new object with the refs and indexes
    // If indexLimit and refs are omitted, automatic values will be provided.
    export function optimize(doc: any, indexLimit?: number, refs?: Map<any, number>): any
    // Convert Objects back to maps and assume integers are integers and boolean is boolean.
    export function toMap(obj: object): Map<any, any>
    // Parse a JSON or Tibs string with optional filename for error messages
    export function fromTibs(tibs: string, filename?: string): any
    // Encode a JS value to a Tibs string
    export function toTibs(val: any): string
}
