# Plugin compatibility

This describes the current client implementation and the remaining original-engine gaps. It supersedes the feature-status assertions in the older `PLUGIN_RUNTIME.md`; ZIP import, native interception, account boot and settings contributions already existed before this pass.

## Original reference

Reference artifact: **Whitegram Beta 3.2 (13.0)**, SHA-256
`5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.

`tests/plugins/check_original_engines.py` hashes that artifact, enumerates named runtime archive-member candidates, and verifies the recovered transpile adapter, common worker bridge, worker host and Lua/Ruby/Go glue as exact byte substrings of its TelegramUIFramework executable. All six checks passed. The named compiler/interpreter search returned no archive members: no `.wasm`, `runtime.json`, TypeScript, Pyodide, Wasmoon, Fengari or Yaegi payload candidates. The common bridge reads `wgrt://app/rt/<language>/runtime.json`; the workers use its entries to load actual interpreters. Embedded glue is not an interpreter installation.

The five recovered SDK/lifecycle/bridge/host sources remain byte-for-byte unchanged. Compatibility repairs are confined to `whitegram-native-bootstrap.js` and native hosts. The recovered hooks HTML remains excluded from execution.

## Supported client paths

| Area | Current implementation |
| --- | --- |
| Installation | UTF-8 `.js` and `.cjs`; ZIP `.plugin`, `.wgplugin`, `.zip`; JSON `.plugin`, `.wgplugin`, `.json`; manifest aliases and one outer archive-directory unwrap. Import never evaluates source. |
| Package modules | JavaScript/CommonJS/JSON files, directory `package.json.main`, directory indexes, scoped `node_modules` and ancestor search. Internal relative parents are supported; main paths must remain in their module directory. Cache identity, entry cycles and eviction after errors are retained. Node built-ins, conditional exports and native addons are not implemented. |
| Lifecycle | Exported objects/classes, transpiled `__esModule` default exports, explicit registration, asynchronous `onLoad`, synchronous unload persistence, account autostart, stop and restart. |
| Local data | Account/plugin-scoped JSON storage and package/data files, binary transfer, bounded timers, logs, permissions and grant-revocation teardown. |
| Telegram | Account/peer/local history reads, current chat, message watches and the existing send/edit/delete/forward/pin/react/read/open operations. Event observations remain post-commit snapshots. |
| Interception | Synchronous outgoing-text cancellation/modification/replacement; request cancellation. Deferred results and arbitrary MTProto/result replacement are not implemented. |
| UI | Recovered normalized controls, reactive state, screens, dialogs, settings pages/rows, message menu items; **new floating overlays, centered `ZStack` layering and `Web` HTML views**. `window`/`panel` still use the existing modal presentation. |
| Services | **New account-scoped `provide`, `unprovide`, `list`, `call`, `consume`**, synchronous registration and Promise-aware provider invocation. Existing service names cannot be taken over by another plugin. Native code supplies `{consumer: <installation ID>}` as the final provider-method argument, matching the recovered service callback shape. |
| WebAssembly | **Loads genuine package bytes when the JavaScript host exposes `WebAssembly.instantiate`**. Missing files/invalid modules reject; `available` and capability discovery reflect that host. Node verification does not establish iOS JSC WebAssembly availability. |
| TypeScript | **Genuine compiler load/transpile path implemented**, with the exact recovered ES2020/CommonJS/React-JSX adapter in an isolated compiler-only JavaScriptCore VM. `.ts`/`.tsx` entry/modules require a separately bundled compiler. No compiler asset is currently present, so installation/transpilation reports unavailable. |

### Services

```js
wg.services.provide("example.math", {
  add: async function (a, b, context) {
    return { value: a + b, consumer: context.consumer };
  }
}, { version: "1.0" });

const math = wg.services.consume("example.math");
const answer = await math.add(2, 3);
```

Only JSON snapshots and encoded bytes cross runtime queues. Sliced ArrayBuffer views preserve their byte range. Provider rejection, missing methods, replacement, unregistration, timeout and plugin teardown settle callers with errors. Late resolutions cannot settle a call twice. Prototype methods are excluded. Per-plugin provision is capped at 32 services; pending-call quotas and the native 65-second request deadline apply. Services do not transfer the provider's native permission grants to the consumer.

### Overlays and HTML

```js
const panel = wg.ui.overlay({
  x: 16, y: 16, width: 280, height: 240,
  content: wg.ui.ZStack([
    wg.ui.Text("Background"),
    wg.ui.Web('<button onclick="window.webkit.messageHandlers.wg.postMessage({clicked:true})">Send</button>', {
      height: 180,
      onMessage: function (value) { wg.log(JSON.stringify(value)); }
    })
  ])
});
// panel.update(...), panel.set(...), panel.hide(), panel.show(), panel.close()
```

Overlays are bounded child views on the account navigation controller, not tab-bar entries. Web views use an ephemeral website data store, have no file/base URL access, and send bounded JSON through the owning surface callback. Native code supplies the network policy from the actual grant, overriding plugin-supplied policy flags. CSP restricts subresources, blocks nested frames/forms and limits HTTP navigation to plugins granted `network`. Replaced/closed trees remove WebKit message handlers and stop their content. UIKit/WebKit rendering and orientation behavior still need an iOS build/device check.

### Staging a real TypeScript compiler

The resource installer optionally copies an existing
`cleanroom/pluginsdk/typescript-compiler.js` into `WhitegramPluginSDK.bundle`.
Stage an actual browser-compatible TypeScript compiler exposing `ts.transpileModule` or `module.exports.transpileModule`, together with its upstream license/version/provenance. It is not synthesized, fetched or replaced by a handwritten transpiler. The resource limit is 16 MiB; plugin sources remain limited to 2 MiB and compiled output to 4 MiB.

The isolated host evaluates that compiler, then the unchanged
`whitegram-typescript-transpiler.js`, validates the real compiler API and runs a typed compiler probe before accepting transpilation. Diagnostic errors propagate. The SDK adapter uses the recovered `{ok,result}` envelope while the recovered compiler adapter uses `{ok,code}` internally. Compiler initialization and successful TypeScript execution have **not** been tested here because the compiler payload is absent.

## Installer integration

`plugin_hook_patches.py` now declares two additional source mappings in
`PLUGIN_HOOK_RUNTIME_FILES`:

```text
WhitegramPluginServices.swift
  -> submodules/TelegramCore/Sources/WhitegramPluginServices.swift
WhitegramPluginTypeScript.swift
  -> submodules/SettingsUI/Sources/Whitegram/WhitegramPluginTypeScript.swift
```

The existing shared installer already merges this dictionary into `cleanroom_files`; no separate shared-installer edit is required for these mappings. The resource installer now includes the exact recovered TypeScript adapter and conditionally includes the genuine compiler asset when staged. Existing SettingsUI/TelegramCore source globs include the mapped sources. The UI source now imports **WebKit**; its Apple framework linkage must be checked in the iOS build alongside the existing JavaScriptCore linkage. The shared installer/preferences/catalog/menu/workflow were not edited in this scope.

## Remaining parity blockers

* Actual TypeScript compiler payload/provenance; native compiler execution verification.
* Actual Python/Lua/Ruby/Go runtime payloads/configuration and their WebKit-worker/custom-scheme native host, installation and cancellation. Recovered worker glue has not been advertised as a running engine.
* Native tab-bar attachment and original UI provider slots (`ui.provide`/`unprovide`, chat/header/input/message/profile/chat-list contributions), including refresh/invalidation semantics.
* Original scheduler/background-job engine and persistence; sockets, DNS/ping/proxy-specific SDK networking.
* Raw MTProto invocation and typed result/parameter mutation; additional override domains and deferred native interception.
* iOS compilation/device tests for new native services, layered/overlay/WebKit UI, teardown and compiler linkage.

These gaps return unsupported/unavailable errors rather than registering no-op engines or reporting success. This is a substantial client-engine compatibility expansion, **not a claim of complete original plugin parity**.

## Verification

Commands run in `ios-build-ci` with the existing check environment:

```text
node --test whitegram/tests/plugins/bootstrap.test.cjs whitegram/tests/plugins/hooks.test.cjs whitegram/tests/plugins/services.test.cjs
python -B whitegram/tests/plugins/check_swift_syntax.py
python -B whitegram/tests/plugins/check_plugin_resources.py
python -B whitegram/tests/plugins/check_hook_patches.py <assembled Telegram 13.0.0 source>
python -B whitegram/tests/plugins/check_original_engines.py <original Beta 3.2 IPA> <recovered embedded-source>
```

The Node suite exercises the real bootstrap and unchanged recovered SDKs against explicit native fixtures. It covers cross-context service dispatch/errors/bytes/ownership/stop, module-package loading, default-export lifecycle, overlay/Web callback dispatch, compiler absence and genuine WebAssembly bytes in a capable host. Foundation XCTest coverage was added for services, ownership, settlement, replacement/cancellation and package imports/resolution, and included in `run_native.py`. Swift is unavailable on this Windows host: those XCTest cases and the iOS build were not executed. Tree-sitter is a syntax check, not Swift typechecking.

Results: **60/60 Node tests passed**; **21/21 Swift files parsed** with tree-sitter 0.25.2 / tree-sitter-swift 0.7.3; **7 exact SDK resources** and resource-rule idempotence passed; **9 patched Telegram sources** passed composition/idempotence/syntax and unchanged-input checks; original IPA SHA-256 and **6 exact embedded language-source matches** passed. `git diff --check` passed.
