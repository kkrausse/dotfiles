var PORT = 5001;
var repl = null;

const wrapConn = conn => {
    const buf = new Uint8Array(1024 * 1024);
    return Object.assign(conn, {write:
                                (write => text => write(encoder.encode(text)))(conn.write),
                                read:
                                (read => async () => {
                                    const nBytes = await read(buf);
                                    return decoder.decode(buf.slice(0, nBytes));
                                })});
}

/**
 * TODO
 * source map support?
 * redirect stderr
 * */
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const server = new Deno.listen({ port: PORT });

console.log("listening on ", server.addr.port);


const conn = wrapConn(await server.accept());

console.log("connected!")

function doRepl(server, conn) {
    var buffer = "";
    conn.write("ready");
    conn.write("\0");

    while (true) {
        const data = await conn.read();

        if(data[data.length-1] != "\0") {
            buffer += data;
        } else {
            if(buffer.length > 0) {
                data = buffer + data;
                buffer = "";
            }

            if(data) {
                // not sure how \0's are getting through - David
                data = data.replace(/\0/g, "");

                if(":cljs/quit" == data) {
                    server.close();
                    conn.close();
                    return;
                } else {
                    try {
                        var obj = JSON.parse(data);
                        repl = obj.repl;
                        ret = eval(obj.form);
                    } catch (e) {
                        err = e;
                    }
                }
            }

            if(err) {
                conn.write(JSON.stringify({
                    type: "result",
                    repl: repl,
                    status: "exception",
                    value: cljs.repl.error__GT_str(err)
                }));
            } else if(ret !== undefined && ret !== null) {
                conn.write(JSON.stringify({
                    type: "result",
                    repl: repl,
                    status: "success",
                    value: ret.toString()
                }));
            } else {
                conn.write(JSON.stringify({
                    type: "result",
                    repl: repl,
                    status: "success",
                    value: null
                }));
            }

            ret = null;
            err = null;

            conn.write("\0");
        }
    }
}

setTimeout(() => Deno.exit(0), 20 * 1000)

doRepl(server, conn);
