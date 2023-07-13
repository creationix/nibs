declare module "nibs" {
    // Look for refs in the object and replace them with nibs refs.
    // Also mark large array/objects to use indexes
    // Returns a new object with the refs and indexes
    export function optimize(doc: any, indexLimit: number, refs?: Map<any, number>): any
    // Convert a JS object to a nibs binary
    export function encode(val: any): Uint8Array
    // Convert Objects back to maps and assume integers are integers and boolean is boolean.
    export function toMap(obj: object): Map<any, any>
    // Decode nibs binary to a JS object (with lazy reads)
    export function decode(buf: Uint8Array): any
}
