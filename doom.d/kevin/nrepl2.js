import * as bencode from "/Users/kkrausse/dotfiles/doom.d/kevin/deno-bencode/mod.ts"
import { Client , Packet } from "https://deno.land/x/tcp_socket@0.0.2/mods.ts"

// returns a stateful decoder like this:
// https://github.com/mauricioszabo/repl-tooling/blob/36517dd/src/repl_tooling/nrepl/bencode.cljs

let decoder = new bencode.Decoder();


function concatArr(a, b) {
    let c = new Uint8Array(a.length + b.length)
    c.set(a)
    c.set(b, a.length)
    return c;
}

function prn() {
    console.log.apply(null, arguments)
}

let x = bencode.encode({kevin: "has an object"})
let x2 = bencode.encode({kevin2: "has an object also"})

concatArr(x, x2)

prn("decoding 2 things")
prn(decoder.next(concatArr(x, x2)))
prn(decoder.next(concatArr(x, x2)))
prn("done", concatArr(x, x2))
lisp.print(x.slice(3))

function textify(a) {
    return (new TextDecoder()).decode(a)
}

console.log(textify(concatArr(x, x2).slice(0, 30)))

// this dumb. according to this: https://mauricio.szabo.link/blog/2020/04/04/implementing-a-nrepl-client/
// you can ask for the server to create one with the clone op
function uuid() { // helper
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        .replace(/[xy]/g, replacer).toUpperCase();

    function replacer(c) {
        var r = Math.random()*16|0,
            v = c == 'x' ? r : (r&0x3|0x8);
        return v.toString(16);
    }
}

function connector(conn) {
    let buf = new Uint8Array(1024);
    return {
        read: 'wow'
    }
}

async function connect(options) {
    let client = new Client(options);
    await client.connect()
}
