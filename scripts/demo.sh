#!/usr/bin/env bash
# demo.sh — 実演（Mac＋iPhone シミュレーター）用。本物の OpenAI（REAL MODE）だけを使い、STUB を使う事故を防ぐ。
#
#   scripts/demo.sh check        # 実演前の確認（無料。サーバーの起動・アプリの起動はしない）
#   scripts/demo.sh start        # 確認 → REAL MODE サーバーを 127.0.0.1:8789 で起動（起動済みならモードを確認）
#   scripts/demo.sh launch       # 起動中のシミュレーターでアプリを開き、REAL MODE サーバーへ接続させる
#                                #   DEMO_ASK_CONSENT=1 で「AIと話す」の同意を最初からやり直す（同意の場面も見せたいとき）
#   scripts/demo.sh live-check   # OpenAI へ 1 件だけ実際に送って返答を確認（有料・約 $0.0003）
#   scripts/demo.sh stop         # このスクリプトが起動した REAL MODE サーバーを止める（他のサーバーは止めない）
#
# 守ること: API キー・トークンを画面に出さない（値は表示せず、アプリへは環境変数で直接渡す）／
#           サーバーは 127.0.0.1 だけで待ち受ける（外部に公開しない）／自動で再送しない。
# 実機 iPhone での実演は scripts/dev-device-setup.sh（同じ Wi-Fi・http は暗号化なし）を参照。

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/server"
VARS="$SERVER/.dev.vars"
PORT="${DEMO_PORT:-8789}"
URL="http://127.0.0.1:${PORT}"
STATE="$ROOT/build/demo"
BUNDLE_ID="com.kobayashiproject2026.mindwavegraphic"
mkdir -p "$STATE"

ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; exit 1; }
health() { curl -s -m 3 "${URL}/v1/health" 2>/dev/null || true; }
mode_of() { printf '%s' "$1" | sed -nE 's/.*"provider_mode":"([a-z]+)".*/\1/p'; }
token() { sed -nE 's/^CLIENT_TOKENS[[:space:]]*=[[:space:]]*"?([^",[:space:]]+).*/\1/p' "$VARS" | head -1; }

check() {
  echo "1. 設定（値は表示しません）"
  command -v node >/dev/null || fail "node が見つかりません"
  ok "node $(node -v)"
  [[ -f "$VARS" ]] || fail "server/.dev.vars がありません"
  git -C "$ROOT" check-ignore -q "$VARS" && ok ".dev.vars は Git 管理外" || fail ".dev.vars が .gitignore に入っていません"
  grep -qE '^OPENAI_API_KEY[[:space:]]*=[[:space:]]*"?sk-' "$VARS" && ok "OPENAI_API_KEY: 設定あり" || fail "OPENAI_API_KEY がありません"
  local t; t="$(token)"; [[ ${#t} -ge 16 ]] && ok "CLIENT_TOKENS: 設定あり" || fail "CLIENT_TOKENS が未設定か短すぎます"
  local model; model="$(sed -nE 's/^OPENAI_MODEL[[:space:]]*=[[:space:]]*"?([^"[:space:]]+).*/\1/p' "$VARS" | head -1)"
  ok "モデル: ${model:-（既定）}"

  echo "2. API キー（OpenAI への無料の確認。キーの有効期限そのものは API から取得できないため、Platform の API keys 画面で確認してください）"
  local code
  code="$(cd "$SERVER" && node -e '
    const fs=require("fs"); const k=(/^OPENAI_API_KEY\s*=\s*"?([^"\n]+)/m.exec(fs.readFileSync(".dev.vars","utf8"))||[])[1]?.trim()||"";
    fetch("https://api.openai.com/v1/models", {headers:{Authorization:"Bearer "+k}}).then(async r=>{const t=await r.text(); console.log(r.status+" "+(t.includes("api.model.read")?"scope":""))}).catch(()=>console.log("network"))')"
  case "$code" in
    "200 "*)     ok "キーは有効" ;;
    "403 scope") ok "キーは有効（モデル一覧の権限がない制限付きキー。会話には影響なし）" ;;
    "401 "*)     fail "キーが無効か期限切れです（401）。Platform で新しいキーを作り server/.dev.vars を更新してください" ;;
    network)     fail "OpenAI に接続できません（ネットワークを確認してください）" ;;
    *)           warn "想定外の応答（${code}）。live-check で確認してください" ;;
  esac

  echo "3. サーバー（${URL}）"
  local h; h="$(health)"
  if [[ -z "$h" ]]; then warn "起動していません（scripts/demo.sh start）"; return 0; fi
  local m; m="$(mode_of "$h")"
  [[ "$m" == "openai" ]] && ok "REAL MODE（provider_mode=openai）" || fail "ポート ${PORT} のサーバーは ${m:-不明（古い STUB の可能性）} です。実演には使えません"
  local wrong right
  wrong="$(curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST "${URL}/v1/context-assist" -H 'Content-Type: application/json' -H 'Authorization: Bearer wrong-token-0000000000' -d '{}')"
  right="$(curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST "${URL}/v1/context-assist" -H 'Content-Type: application/json' -H "Authorization: Bearer $(token)" -d '{}')"
  [[ "$wrong" == 401 ]] && ok "誤ったトークンは 401" || fail "誤ったトークンで ${wrong}"
  [[ "$right" == 400 ]] && ok "正しいトークンは認証を通過（空の要求なので 400。OpenAI へは送られない）" || fail "正しいトークンで ${right}（認証の設定を確認）"
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | grep -q "127.0.0.1:${PORT}" && ok "待ち受けは 127.0.0.1 のみ（外部に公開していない）" || warn "待ち受けアドレスを確認してください"
}

start() {
  check
  local h; h="$(health)"
  if [[ -n "$h" ]]; then ok "起動済みのサーバーを使います"; return 0; fi
  if lsof -nP -tiTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then fail "ポート ${PORT} を別のプロセスが使っています（DEMO_PORT=8791 scripts/demo.sh start）"; fi
  echo "4. REAL MODE サーバーを起動（会話のたびに OpenAI の利用料が発生します。1 往復 約 \$0.0003）"
  ( cd "$SERVER" && PORT="${PORT}" exec nohup node scripts/dev-server.ts > "$STATE/server.log" 2>&1 < /dev/null ) &
  echo $! > "$STATE/server.pid"
  for _ in $(seq 1 40); do h="$(health)"; [[ -n "$h" ]] && break; sleep 1; done
  [[ "$(mode_of "$h")" == "openai" ]] || fail "REAL MODE で起動できませんでした（build/demo/server.log）"
  ok "起動しました（pid $(cat "$STATE/server.pid")）"
  check
}

launch() {
  [[ "$(mode_of "$(health)")" == "openai" ]] || fail "REAL MODE サーバーが動いていません（scripts/demo.sh start）"
  local udid; udid="$(xcrun simctl list devices booted | grep -Eo '\(([0-9A-F-]{36})\) \(Booted\)' | head -1 | grep -Eo '[0-9A-F-]{36}' || true)"
  [[ -n "$udid" ]] || fail "起動中のシミュレーターがありません（Xcode で実行するか Simulator を開いてください）"
  xcrun simctl get_app_container "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || fail "アプリが入っていません（Xcode で MindWaveGraphic を Debug で一度実行してください）"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  # トークンは画面・ログに出さず、環境変数でアプリへ直接渡す（DEBUG ビルドだけが読む）
  SIMCTL_CHILD_MW_INSIGHT_BASE_URL="$URL" SIMCTL_CHILD_MW_INSIGHT_CLIENT_TOKEN="$(token)" \
    SIMCTL_CHILD_INITIAL_AUTH="${DEMO_START_SCREEN:-contextCalibration}" \
    SIMCTL_CHILD_MW_CHAT_TEST_CONSENT="$([[ "${DEMO_ASK_CONSENT:-0}" == 1 ]] && echo 0 || echo "")" \
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
  ok "アプリを起動しました（${URL} の REAL MODE に接続）"
  cat <<EOF
  実演の手順: 「AIと話す」を押す → 文字（またはマイク）で話しかける。
  返答の下に「OpenAI（gpt-6-luna）」と出れば本物の AI。オレンジの「スタブ応答」なら STUB なので止めてください。
EOF
}

live_check() {
  [[ "$(mode_of "$(health)")" == "openai" ]] || fail "REAL MODE サーバーが動いていません"
  echo "OpenAI へ 1 件だけ送ります（約 \$0.0003）"
  local body; body='{"schema_version":1,"request_id":"'"$(uuidgen)"'","conversation_id":"'"$(uuidgen)"'","locale":"ja-JP","step":"tension","messages":[{"role":"assistant","content":"こんにちは。今、緊張してる？"},{"role":"user","content":"少し緊張してる"}],"current":{"scene":null,"conditions":[],"tension":null}}'
  local res; res="$(curl -s -m 30 -X POST "${URL}/v1/context-assist" -H 'Content-Type: application/json' -H "Authorization: Bearer $(token)" -d "$body")"
  local provider model reply
  provider="$(printf '%s' "$res" | sed -nE 's/.*"provider":"([a-z-]+)".*/\1/p')"
  model="$(printf '%s' "$res" | sed -nE 's/.*"model":"([^"]+)".*/\1/p')"
  reply="$(printf '%s' "$res" | sed -nE 's/.*"reply":"([^"]+)".*/\1/p')"
  [[ "$provider" == "openai" ]] || fail "本物の OpenAI の返答ではありません（provider=${provider:-なし}）"
  ok "provider=openai model=${model}"
  ok "もこりん: ${reply}"
}

stop() {
  if [[ -f "$STATE/server.pid" ]] && kill -0 "$(cat "$STATE/server.pid")" 2>/dev/null; then
    kill "$(cat "$STATE/server.pid")" && rm -f "$STATE/server.pid" && ok "REAL MODE サーバーを止めました"
  else
    warn "このスクリプトが起動したサーバーは動いていません（他のサーバーは止めません）"
  fi
}

case "${1:-check}" in
  check) check ;;
  start) start ;;
  launch) launch ;;
  live-check) live_check ;;
  stop) stop ;;
  *) sed -n 2,12p "$0"; exit 2 ;;
esac
