// dev-host.ts
// 開発用サーバー（dev-server.ts）の待ち受けアドレスを決める。
//
// 既定は 127.0.0.1（この Mac の中だけ）。iPhone 実機から同じ Wi-Fi で試す場合だけ、
// DEV_LAN_ACCESS=1 と HOST=<この Mac のプライベート IP> を明示したときに限り、そのアドレスで待ち受ける。
// インターネットに公開しないため、0.0.0.0・グローバル IP・ホスト名は受け付けない（docs/DEVICE_CONNECTION.md）。

import { networkInterfaces } from "node:os";

const PRIVATE_V4 = [/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, /^192\.168\.\d{1,3}\.\d{1,3}$/, /^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$/];

export type ListenHost = { host: string; lan: boolean } | { error: string };

type Interfaces = Record<string, Array<{ address: string; family: string | number; internal: boolean }> | undefined>;

/** この Mac のプライベート IPv4 アドレス（Wi-Fi など）。HOST=auto のときに使う（アドレスはハードコードしない） */
export function detectPrivateIPv4(interfaces: Interfaces = networkInterfaces() as Interfaces): string[] {
  const found: string[] = [];
  for (const list of Object.values(interfaces)) {
    for (const i of list ?? []) {
      const v4 = i.family === "IPv4" || i.family === 4;
      if (v4 && !i.internal && PRIVATE_V4.some((re) => re.test(i.address))) found.push(i.address);
    }
  }
  return found;
}


export function resolveListenHost(env: Record<string, string | undefined>, interfaces?: Interfaces): ListenHost {
  let host = env.HOST?.trim();
  if (host === "auto") {
    if (env.DEV_LAN_ACCESS !== "1") return { error: "HOST=auto を使うには DEV_LAN_ACCESS=1 も指定してください" };
    const candidates = detectPrivateIPv4(interfaces);
    if (candidates.length === 0) return { error: "この Mac のプライベート IP が見つかりません（Wi-Fi に接続しているか確認してください）" };
    host = candidates[0]!;
  }
  if (!host || host === "127.0.0.1" || host === "localhost") return { host: "127.0.0.1", lan: false };
  if (env.DEV_LAN_ACCESS !== "1") {
    return { error: `HOST=${host} で待ち受けるには DEV_LAN_ACCESS=1 も指定してください（同じ Wi-Fi の機器から接続できるようになります）` };
  }
  const octetsOk = host.split(".").every((o) => Number(o) >= 0 && Number(o) <= 255);
  if (!octetsOk || !PRIVATE_V4.some((re) => re.test(host))) {
    return { error: `HOST=${host} は使えません。この Mac のプライベート IP（10.x / 172.16-31.x / 192.168.x）だけを指定できます（0.0.0.0・グローバル IP・ホスト名は不可）` };
  }
  return { host, lan: true };
}
