"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { NativeHostFixture: Host, ServiceHubFixture } = require("./native-host-fixture.cjs");
const code = expected => error => error && error.code === expected;
const plain = value => JSON.parse(JSON.stringify(value));

test("service calls cross isolated contexts, await promises and identify the actual consumer", async () => {
  const serviceHub = new ServiceHubFixture();
  const provider = new Host({ id: "provider", serviceHub });
  const consumer = new Host({ id: "consumer", serviceHub });
  provider.run("wg.services.provide('math',{sum:async function(a,b,ctx){return {sum:a+b,consumer:ctx.consumer};}},{version:'2.1'});");
  assert.deepEqual(plain(consumer.run("wg.services.list()")), [{ name: "math", version: "2.1", pluginId: "provider" }]);
  const api = consumer.run("wg.services.consume('math')");
  assert.equal(api.then, undefined);
  assert.deepEqual(plain(await api.sum(4, 5)), { sum: 9, consumer: "consumer" });
  await provider.stop(); await consumer.stop();
});

test("service ownership, account isolation and prototype methods reject", async () => {
  const serviceHub = new ServiceHubFixture();
  const provider = new Host({ id: "provider", serviceHub });
  const consumer = new Host({ id: "consumer", serviceHub });
  const other = new Host({ id: "other", scope: "other-account", serviceHub });
  provider.run("wg.services.provide('only',{ok:function(){return true;}})");
  assert.throws(() => consumer.run("wg.services.provide('only',{})"), code("SERVICE_CONFLICT"));
  assert.deepEqual(plain(other.run("wg.services.list()")), []);
  await assert.rejects(other.run("wg.services.call('only','ok')"), code("SERVICE_NOT_FOUND"));
  for (const method of ["constructor", "prototype", "__proto__"]) {
    await assert.rejects(consumer.run(`wg.services.call('only',${JSON.stringify(method)})`), code("INVALID_ARGUMENT"));
  }
  await assert.rejects(consumer.run("wg.services.call('only','missing')"), code("SERVICE_METHOD_NOT_FOUND"));
  assert.equal(consumer.run("wg.__sdk.callSync('services.resolve',['forged',{ok:true,value:1}]).error.code"), "UNSUPPORTED_API");
  await provider.stop(); await consumer.stop(); await other.stop();
});

test("binary service arguments/results preserve sliced views and JSON own properties", async () => {
  const serviceHub = new ServiceHubFixture();
  const provider = new Host({ id: "provider", serviceHub });
  const consumer = new Host({ id: "consumer", serviceHub });
  provider.run("wg.services.provide('bytes',{echo:function(value){if(!(value.bytes instanceof Uint8Array))throw Error('not bytes');return value;}})");
  const result = await consumer.run("wg.services.call('bytes','echo',[{bytes:new Uint8Array([0,127,128,255]).subarray(1,3),extra:JSON.parse('{\"__proto__\":{\"safe\":true}}')}])");
  assert.deepEqual(Array.from(result.bytes), [127, 128]);
  assert.equal(Object.getPrototypeOf(result.extra), null);
  assert.equal(result.extra.__proto__.safe, true);
  await provider.stop(); await consumer.stop();
});

test("service failures reject; replacement cancels outstanding provider calls", async () => {
  const serviceHub = new ServiceHubFixture();
  const provider = new Host({ id: "provider", serviceHub });
  const consumer = new Host({ id: "consumer", serviceHub });
  provider.run(`wg.services.provide('state',{
    fail:async function(){throw Object.assign(Error('provider failed'),{code:'CUSTOM_ERROR'});},
    pending:function(){return new Promise(function(resolve){globalThis.late=resolve;});},
    cyclic:function(){var value={};value.self=value;return value;}
  })`);
  await assert.rejects(consumer.run("wg.services.call('state','fail')"), code("CUSTOM_ERROR"));
  await assert.rejects(consumer.run("wg.services.call('state','cyclic')"), code("INVALID_ARGUMENT"));
  const pending = consumer.run("wg.services.call('state','pending')");
  const check = assert.rejects(pending, code("SERVICE_UNAVAILABLE"));
  await consumer.flush();
  provider.run("wg.services.provide('state',{pending:function(){return 7;}})");
  await check;
  provider.run("late(999)");
  assert.equal(await consumer.run("wg.services.call('state','pending')"), 7);
  await provider.stop(); await consumer.stop();
});

test("provider stop rejects consumers and consumer stop releases its pending calls", async () => {
  const serviceHub = new ServiceHubFixture();
  const provider = new Host({ id: "provider", serviceHub });
  const consumer = new Host({ id: "consumer", serviceHub });
  provider.run("wg.services.provide('wait',{wait:function(){return new Promise(function(){});}})");
  const result = consumer.run("wg.services.call('wait','wait')");
  const check = assert.rejects(result, code("SERVICE_UNAVAILABLE"));
  await consumer.flush();
  await provider.stop();
  await check;
  assert.deepEqual(plain(consumer.run("wg.services.list()")), []);
  await consumer.stop();
  const nextProvider = new Host({ id: "nextProvider", serviceHub });
  const nextConsumer = new Host({ id: "nextConsumer", serviceHub });
  nextProvider.run("wg.services.provide('wait',{wait:function(){return new Promise(function(){});}})");
  const cancelled = nextConsumer.run("wg.services.call('wait','wait')");
  const cancelledCheck = assert.rejects(cancelled, code("PLUGIN_STOPPED"));
  await nextConsumer.flush();
  await nextConsumer.stop();
  await cancelledCheck;
  assert.equal(serviceHub.pending.size, 0);
  await nextProvider.stop();
});

test("CommonJS directories, scoped node_modules and main containment use one cache", async () => {
  const host = new Host({ files: {
    "main.js": "", "lib/use.js": "module.exports=require('@scope/math');",
    "node_modules/@scope/math/package.json": '{"main":"./dist/api.cjs"}',
    "node_modules/@scope/math/dist/api.cjs": "globalThis.packageRuns=(globalThis.packageRuns||0)+1;module.exports={answer:42};",
    "folder/index.cjs": "module.exports=require('../lib/use');",
    "escape/package.json": '{"main":"../main.js"}',
    "loop/package.json": '{"main":"./next"}', "loop/next/package.json": '{"main":"../"}'
  } });
  assert.equal(host.run("require('./folder').answer"), 42);
  assert.equal(host.run("require('@scope/math')===require('./lib/use')"), true);
  assert.equal(host.run("packageRuns"), 1);
  assert.throws(() => host.run("require('./escape')"), code("INVALID_PATH"));
  assert.throws(() => host.run("require('./loop')"), code("INVALID_PATH"));
  await host.stop();
});

test("overlay and layered HTML nodes retain SDK callbacks and stop invalidates them", async () => {
  const host = new Host();
  const id = host.run("var messages=[];var overlay=wg.ui.overlay({width:250,height:180,content:wg.ui.ZStack([wg.ui.Text('background'),wg.ui.Web('<b>Hi</b>',{onMessage:function(v){messages.push(v);}})])});overlay.id");
  assert.equal(host.surface(id).kind, "overlay");
  assert.equal(host.surface(id).tree.type, "zstack");
  const callback = host.surface(id).tree.children[1].props.onMessage.slice(5);
  host.context.__wgUIDispatch(id, callback, { value: { clicked: true } });
  assert.deepEqual(plain(host.run("messages")), [{ clicked: true }]);
  await host.stop();
  host.context.__wgUIDispatch(id, callback, { value: { clicked: false } });
  assert.equal(host.run("messages.length"), 1);
  assert.equal(host.run("overlay.isClosed"), true);
});

test("WebAssembly loads real bytes when the host implements it, and rejects malformed modules", async () => {
  const wasm = Buffer.from("0061736d010000000105016000017f0302010007080104616e737700000a06010400412a0b", "hex");
  const host = new Host({ files: { "main.js": "", "answer.wasm": wasm, "broken.wasm": "invalid" } });
  assert.equal(host.run("wg.wasm.available"), true);
  const instance = await host.run("wg.wasm.load('answer.wasm')");
  assert.equal(instance.exports.answ(), 42);
  await assert.rejects(host.run("wg.wasm.load('broken.wasm')"), /WebAssembly|expected|magic/);
  await assert.rejects(host.run("wg.wasm.load('missing.wasm')"), code("FILE_NOT_FOUND"));
  await host.stop();
});

test("compiler absence is explicit and transpiled default-export lifecycle loads once", async () => {
  const host = new Host();
  assert.equal(host.run("wg.lang.ts.installed"), false);
  assert.equal(host.run("wg.capabilities.has('lang.typescript.transpile')"), false);
  assert.throws(() => host.run("wg.lang.ts.transpile('const n: number = 1;')"), /UNSUPPORTED_LANGUAGE/);
  await host.entry("Object.defineProperty(exports,'__esModule',{value:true});exports.default=class {onLoad(){wg.storage.set('defaultLoads',1);}onUnload(){wg.storage.set('defaultUnloaded',true);}};");
  assert.equal(host.state, "running");
  assert.equal(host.storage.defaultLoads, 1);
  await host.stop();
  assert.equal(host.storage.defaultUnloaded, true);
});
