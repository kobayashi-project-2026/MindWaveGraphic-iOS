// ratelimit.ts
// クライアントトークン単位の簡易レート制限（固定ウィンドウ）。
//
// 注意: Cloudflare Workers ではインスタンス（isolate）ごとにメモリが分かれるため、
// これは「1インスタンス内での連打・暴走の抑止」にすぎない。本番公開前には
// 利用者単位の認証と、Cloudflare の Rate Limiting バインディングや Durable Objects による
// 全体共有のレート制限・1日あたりの上限を必ず導入すること（docs/OPENAI_CHAT_ARCHITECTURE.md）。

export interface RateLimitResult {
  allowed: boolean;
  /** 次に許可されるまでの秒数（allowed=false のとき） */
  retryAfterSeconds: number;
}

export class FixedWindowRateLimiter {
  private readonly windows = new Map<string, { start: number; count: number }>();
  private readonly limit: number;
  private readonly windowMs: number;
  private readonly now: () => number;

  constructor(limit: number, windowMs: number = 60_000, now: () => number = () => Date.now()) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
  }

  check(key: string): RateLimitResult {
    if (this.limit <= 0) return { allowed: true, retryAfterSeconds: 0 };
    const t = this.now();
    const w = this.windows.get(key);
    if (!w || t - w.start >= this.windowMs) {
      this.windows.set(key, { start: t, count: 1 });
      this.prune(t);
      return { allowed: true, retryAfterSeconds: 0 };
    }
    if (w.count >= this.limit) {
      return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((w.start + this.windowMs - t) / 1000)) };
    }
    w.count += 1;
    return { allowed: true, retryAfterSeconds: 0 };
  }

  /** 古いウィンドウを捨ててメモリが増え続けないようにする */
  private prune(t: number): void {
    if (this.windows.size < 1000) return;
    for (const [k, w] of this.windows) if (t - w.start >= this.windowMs) this.windows.delete(k);
  }
}
