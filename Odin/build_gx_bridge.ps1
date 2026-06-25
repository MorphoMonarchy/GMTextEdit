param(
    [Parameter(Mandatory = $true)]
    [string] $WasmPath,

    [Parameter(Mandatory = $true)]
    [string] $OutJs
)

$ErrorActionPreference = "Stop"

$wasmBytes = [System.IO.File]::ReadAllBytes($WasmPath)
$wasmBase64 = [System.Convert]::ToBase64String($wasmBytes)
$wasmChunks = for ($i = 0; $i -lt $wasmBase64.Length; $i += 120) {
    $length = [Math]::Min(120, $wasmBase64.Length - $i)
    '"' + $wasmBase64.Substring($i, $length) + '"'
}
$wasmLiteral = $wasmChunks -join " +`n            "

$template = @'
(function(root) {
    "use strict";

    var GMTextEdit = (function() {
        var wasmBase64 = __WASM_BASE64_LITERAL__;
        var encoder = new TextEncoder();
        var decoder = new TextDecoder("utf-8");
        var instance = null;
        var exports = null;
        var memory = null;
        var bridgeError = "";

        function bytesFromBase64(value) {
            if (typeof atob === "function") {
                var binary = atob(value);
                var bytes = new Uint8Array(binary.length);
                for (var i = 0; i < binary.length; i += 1) {
                    bytes[i] = binary.charCodeAt(i);
                }
                return bytes;
            }

            if (typeof Buffer !== "undefined") {
                return new Uint8Array(Buffer.from(value, "base64"));
            }

            throw new Error("No base64 decoder is available for GMTextEdit.");
        }

        function readString(ptr, len) {
            if (!memory || ptr === 0 || len <= 0) {
                return "";
            }
            return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
        }

        function readCString(ptr) {
            ptr = Number(ptr);
            if (!memory || ptr === 0) {
                return "";
            }

            var bytes = new Uint8Array(memory.buffer);
            var end = ptr;
            while (end < bytes.length && bytes[end] !== 0) {
                end += 1;
            }

            return decoder.decode(bytes.subarray(ptr, end));
        }

        function randomBytes(ptr, len) {
            var bytes = new Uint8Array(memory.buffer, ptr, len);
            var cryptoSource = root.crypto || root.msCrypto;

            if (cryptoSource && cryptoSource.getRandomValues) {
                cryptoSource.getRandomValues(bytes);
                return;
            }

            for (var i = 0; i < bytes.length; i += 1) {
                bytes[i] = Math.floor(Math.random() * 256);
            }
        }

        function ensure() {
            if (exports) {
                return exports;
            }

            var imports = {
                odin_env: {
                    write: function(fd, ptr, len) {
                        var text = readString(ptr, len);
                        if (fd === 2 && root.console && root.console.error) {
                            root.console.error(text);
                        } else if (root.console && root.console.log) {
                            root.console.log(text);
                        }
                    },
                    rand_bytes: randomBytes,
                    tick_now: function() {
                        if (root.performance && root.performance.now) {
                            return root.performance.now();
                        }
                        return Date.now();
                    },
                },
            };

            var module = new WebAssembly.Module(bytesFromBase64(wasmBase64));
            instance = new WebAssembly.Instance(module, imports);
            exports = instance.exports;
            memory = exports.memory;
            bridgeError = "";
            return exports;
        }

        function rememberError(error) {
            bridgeError = error && error.message ? error.message : String(error);
            if (error && error.stack) {
                bridgeError += "\n" + error.stack;
            }
            if (root.console && root.console.error) {
                root.console.error("GMTextEdit bridge error: " + bridgeError);
            }
        }

        function protect(fallback, body) {
            try {
                return body();
            } catch (error) {
                rememberError(error);
                return fallback;
            }
        }

        function writeArg(slot, value) {
            var text = value === undefined || value === null ? "" : String(value);
            var bytes = encoder.encode(text);
            var ptr = Number(ensure().gmte_wasm_arg_ptr(slot, bytes.length + 1));
            var target = new Uint8Array(memory.buffer, ptr, bytes.length + 1);
            target.set(bytes);
            target[bytes.length] = 0;
            return ptr;
        }

        function userArgs(args, expected) {
            var values = [];
            var source = args;

            if (
                args.length === 1 &&
                args[0] &&
                typeof args[0] === "object" &&
                typeof args[0].length === "number" &&
                typeof args[0] !== "function"
            ) {
                source = args[0];
            }

            for (var i = 0; i < source.length; i += 1) {
                values.push(source[i]);
            }

            if (values.length > expected) {
                values = values.slice(values.length - expected);
            }

            while (values.length < expected) {
                values.push(undefined);
            }

            return values;
        }

        function number0(name) {
            return protect(0, function() {
                return Number(ensure()[name]());
            });
        }

        function number1(name, a) {
            return protect(0, function() {
                return Number(ensure()[name](writeArg(0, a)));
            });
        }

        function number2String(name, a, b) {
            return protect(0, function() {
                return Number(ensure()[name](writeArg(0, a), writeArg(1, b)));
            });
        }

        function numberStringReal(name, a, b) {
            return protect(0, function() {
                return Number(ensure()[name](writeArg(0, a), Number(b) || 0));
            });
        }

        function string0(name) {
            return protect("", function() {
                return readCString(ensure()[name]());
            });
        }

        function string1(name, a) {
            return protect("", function() {
                return readCString(ensure()[name](writeArg(0, a)));
            });
        }

        function string2(name, a, b) {
            return protect("", function() {
                return readCString(ensure()[name](writeArg(0, a), writeArg(1, b)));
            });
        }

        function stringCommand(a, command) {
            return protect("", function() {
                return readCString(ensure().gmte_command(writeArg(0, a), Number(command) || 0));
            });
        }

        function stringSelection(a, head, tail) {
            return protect("", function() {
                return readCString(ensure().gmte_set_selection(writeArg(0, a), Number(head) || 0, Number(tail) || 0));
            });
        }

        function numberLineNavigation(a, lineStart, lineEnd, upIndex, downIndex) {
            return protect(0, function() {
                return Number(ensure().gmte_set_line_navigation(
                    writeArg(0, a),
                    Number(lineStart) || 0,
                    Number(lineEnd) || 0,
                    Number(upIndex) || 0,
                    Number(downIndex) || 0
                ));
            });
        }

        return {
            number0: number0,
            number1: number1,
            number2String: number2String,
            numberStringReal: numberStringReal,
            string0: string0,
            string1: string1,
            string2: string2,
            stringCommand: stringCommand,
            stringSelection: stringSelection,
            numberLineNavigation: numberLineNavigation,
            userArgs: userArgs,
            lastBridgeError: function() {
                return bridgeError;
            },
        };
    })();

    root.GMTextEditBridge = GMTextEdit;

    root.gmte_create = function() {
        var a = GMTextEdit.userArgs(arguments, 2);
        return GMTextEdit.number2String("gmte_create", a[0], a[1]);
    };
    root.gmte_destroy = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_destroy", a[0]);
    };
    root.gmte_destroy_all = function() { return GMTextEdit.number0("gmte_destroy_all"); };
    root.gmte_exists = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_exists", a[0]);
    };
    root.gmte_set_text = function() {
        var a = GMTextEdit.userArgs(arguments, 2);
        return GMTextEdit.string2("gmte_set_text", a[0], a[1]);
    };
    root.gmte_get_text = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.string1("gmte_get_text", a[0]);
    };
    root.gmte_input_text = function() {
        var a = GMTextEdit.userArgs(arguments, 2);
        return GMTextEdit.string2("gmte_input_text", a[0], a[1]);
    };
    root.gmte_command = function() {
        var a = GMTextEdit.userArgs(arguments, 2);
        return GMTextEdit.stringCommand(a[0], a[1]);
    };
    root.gmte_set_selection = function() {
        var a = GMTextEdit.userArgs(arguments, 3);
        return GMTextEdit.stringSelection(a[0], a[1], a[2]);
    };
    root.gmte_get_caret = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_get_caret", a[0]);
    };
    root.gmte_get_anchor = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_get_anchor", a[0]);
    };
    root.gmte_get_selection_start = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_get_selection_start", a[0]);
    };
    root.gmte_get_selection_end = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_get_selection_end", a[0]);
    };
    root.gmte_get_text_length = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_get_text_length", a[0]);
    };
    root.gmte_get_selected_text = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.string1("gmte_get_selected_text", a[0]);
    };
    root.gmte_set_line_navigation = function() {
        var a = GMTextEdit.userArgs(arguments, 5);
        return GMTextEdit.numberLineNavigation(a[0], a[1], a[2], a[3], a[4]);
    };
    root.gmte_set_translate_by_grapheme = function() {
        var a = GMTextEdit.userArgs(arguments, 2);
        return GMTextEdit.numberStringReal("gmte_set_translate_by_grapheme", a[0], a[1]);
    };
    root.gmte_clipboard_set = function() {
        var a = GMTextEdit.userArgs(arguments, 1);
        return GMTextEdit.number1("gmte_clipboard_set", a[0]);
    };
    root.gmte_clipboard_get = function() { return GMTextEdit.string0("gmte_clipboard_get"); };
    root.gmte_last_status = function() {
        if (GMTextEdit.lastBridgeError() !== "") {
            return -1;
        }
        return GMTextEdit.number0("gmte_last_status");
    };
    root.gmte_last_error = function() {
        var bridgeError = GMTextEdit.lastBridgeError();
        if (bridgeError !== "") {
            return bridgeError;
        }
        return GMTextEdit.string0("gmte_last_error");
    };
})(typeof globalThis !== "undefined" ? globalThis : this);
'@

$js = $template.Replace("__WASM_BASE64_LITERAL__", $wasmLiteral)
$outDir = [System.IO.Path]::GetDirectoryName($OutJs)
if ($outDir -and -not [System.IO.Directory]::Exists($outDir)) {
    [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutJs, $js, $utf8)
