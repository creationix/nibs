declare module "nibs" {
    export function optimize(doc: any, indexLimit: number, refs?:Map<any,number>) : any;
    export function encode(val: any) : Uint8Array;
}
