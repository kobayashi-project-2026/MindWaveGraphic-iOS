// dev-host.ts
// 開発用サーバー（dev-server.ts）の待ち受けアドレスを決める。
//
// 既定は 127.0.0.1（この Mac の中だけ）。iPhone 実機から同じ Wi-Fi で試す場合だけ、
// DEV_LAN_ACCESS=1 と HOST=<この Mac のプライベート IP> を明示したときに限り、そのアドレスで待ち受ける。
// インターネットに公開しないため、0.0.0.0・グローバル IP・ホスト名は受け付けない（docs/DEVICE_CONNECTION.md）。

export type ListenHost = { host: string; lan: boolean } | { error: string };

const PRIVATE_V4 = [/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, /^192\.168\.\d{1,3}\.\d{1,3}$/, /^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$/];

export function resolveListenHost(env: Record<string, string | undefined>): ListenHost {
  const host = env.HOST?.trim();
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
