import { test } from "node:test";
import assert from "node:assert/strict";
import { detectPrivateIPv4, resolveListenHost } from "../scripts/dev-host.ts";

test("待ち受けアドレス: 既定は 127.0.0.1（インターネット・LAN に公開しない）", () => {
  assert.deepEqual(resolveListenHost({}), { host: "127.0.0.1", lan: false });
  assert.deepEqual(resolveListenHost({ HOST: "localhost" }), { host: "127.0.0.1", lan: false });
});

test("待ち受けアドレス: LAN は DEV_LAN_ACCESS=1 とプライベート IP の両方が必要", () => {
  assert.ok("error" in resolveListenHost({ HOST: "192.168.1.20" }), "フラグなしは拒否");
  assert.deepEqual(resolveListenHost({ HOST: "192.168.1.20", DEV_LAN_ACCESS: "1" }), { host: "192.168.1.20", lan: true });
  assert.deepEqual(resolveListenHost({ HOST: "10.0.0.5", DEV_LAN_ACCESS: "1" }), { host: "10.0.0.5", lan: true });
  assert.deepEqual(resolveListenHost({ HOST: "172.20.1.2", DEV_LAN_ACCESS: "1" }), { host: "172.20.1.2", lan: true });
});

test("待ち受けアドレス: 0.0.0.0・グローバル IP・ホスト名・範囲外は拒否", () => {
  for (const HOST of ["0.0.0.0", "8.8.8.8", "172.32.0.1", "192.168.1.300", "mac.local", "example.com", "::"]) {
    assert.ok("error" in resolveListenHost({ HOST, DEV_LAN_ACCESS: "1" }), HOST);
  }
});

test("HOST=auto: この Mac のプライベート IPv4 を自動で選ぶ（ループバック・グローバル・IPv6 は除外）。DEV_LAN_ACCESS=1 が必要", () => {
  const ifaces = {
    lo0: [{ address: "127.0.0.1", family: "IPv4", internal: true }],
    en0: [{ address: "fe80::1", family: "IPv6", internal: false }, { address: "192.168.10.23", family: "IPv4", internal: false }],
    utun: [{ address: "100.64.1.2", family: "IPv4", internal: false }],
  };
  assert.deepEqual(detectPrivateIPv4(ifaces), ["192.168.10.23"]);
  assert.deepEqual(resolveListenHost({ HOST: "auto", DEV_LAN_ACCESS: "1" }, ifaces), { host: "192.168.10.23", lan: true });
  assert.ok("error" in resolveListenHost({ HOST: "auto" }, ifaces), "フラグなしは拒否");
  assert.ok("error" in resolveListenHost({ HOST: "auto", DEV_LAN_ACCESS: "1" }, { lo0: ifaces.lo0 }), "プライベート IP がなければ拒否");
});
