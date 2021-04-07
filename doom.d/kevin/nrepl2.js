import { Client , Packet } from "https://deno.land/x/tcp_socket@0.0.2/mods.ts"
import { assert } from "https://deno.land/std@0.90.0/testing/asserts.ts"
import * as datetime from 'https://deno.land/std@0.90.0/datetime/mod.ts'
import * as bencode from "/Users/kkrausse/dotfiles/doom.d/kevin/deno-bencode/mod.ts"

// function relative(p) {
//     let path =  lisp.buffer_file_name().split('/');
//     path.pop();
//     return `${path.join('/')}/${p}`
// }
// let bencode = await import(relative("deno-bencode/mod.ts"))

// returns a stateful decoder like this:
// https://github.com/mauricioszabo/repl-tooling/blob/36517dd/src/repl_tooling/nrepl/bencode.cljs

function prn() {
    console.log.apply(null, arguments)
}

let makeBencodeReader = (conn) => {
    let decoder = new bencode.Decoder();
    let buf = new Uint8Array(1024 * 1024);

    return async () => {
        let msg = decoder.next(new Uint8Array(0));
        while (!msg) {
            prn("reading...")
            let nBytes = await conn.read(buf);
            if (nBytes < 1) {
                throw "connection must be closed!"
            }
            msg = decoder.next(buf.slice(0, nBytes));
            prn("read:", msg)
        }
        return msg;
    }
}

let makeBencodeWriter = (conn) => {
    return async (obj) => {
        let toWrite = bencode.encode(obj);
        let x = 0;
        while (x < toWrite.length) {
            x += await conn.write(toWrite.slice(x));
        }
    }
}

function plistKeys(lispPList, keys) {
    let m = {};
    keys.map(k => m[k] = lisp.plist_get(lispPList, lisp.keywords[k]));
    return m;
}

let getLaunchParams = () => {
    let repl = lisp.cider_current_repl();
    let launchParams = null;
    repl &&
        lisp.with_current_buffer(repl, () => {
            launchParams = lisp.eval(lisp.symbols.cider_launch_params)
        });
    return plistKeys(launchParams, ["host", "port", "project_dir"]);
}

let makeId = (() => {
    let i = 1;
    return () => i++;
})();

let timeStamp = () => datetime.format(new Date(), "yyyy-dd-MM HH:mm:ss.SSS");

let msgHandler = () => {

}

// I think in Deno, unhandled promises kill everything (which is good)
async function startReadLoop(connector) {
    let msg = await connector.readMsg();
    connector.outstanding[msg.id](msg);
    startReadLoop(connector);
}

let makeConnector = async () => {
    let {host, port} = getLaunchParams()
    //assert(host && port, lisp.print("couldn't find host or port. can't connect"));
    prn("trying to connect with", host, port)
    let conn = await Deno.connect({port: port})
    prn("connected!")
    return {
        readMsg: makeBencodeReader(conn),
        writeMsg: makeBencodeWriter(conn),
        outstanding: {} // map of msg-id -> handler
    }
}

let sendRecv = async (connector, msg) =>
    new Promise((resolve, _) => {
        let id = makeId();
        msg.id = id
        connector.outstanding[id] = resolve;
        connector.writeMsg(msg);
    })

let makeEvaluator = async connector => {
    let resp = await sendRecv(connector, {op: "clone", "time-stamp": timeStamp()});
    prn("session made!")
    let id = makeId();
    connector.outstanding[id] = msg => {
        lisp.eval(
            lisp.car(
                lisp.read_from_string(msg.lisp)));
    };
    connector.writeMsg({id: id,
                        session: resp["new-session"],
                        op: "kevin",
                        req: '[:follower "do with me as you please"]'})
}

var msgConnector = null;

let ensureConnector = async () => {
    msgConnector = msgConnector || await (async () => {
        let connector = await makeConnector();
        startReadLoop(connector);
        return connector;
    })();
}

let becomeRepl = async () => {
    await ensureConnector();
    makeEvaluator(msgConnector);
}

lisp.defun({name: "kevin-js-initialize",
            docString: "",
            interactive: true,
            args: "",
            func: () => becomeRepl()
           });
