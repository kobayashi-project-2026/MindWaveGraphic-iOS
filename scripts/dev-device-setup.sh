#!/usr/bin/env bash
# dev-device-setup.sh — 実機 iPhone（Debug ビルド）から Mac の開発用サーバーへ接続する準備を、1 つのコマンドで行う。
#
#   scripts/dev-device-setup.sh            # STUB（無料・AI なし）で準備
#   scripts/dev-device-setup.sh --real     # 実通信（OpenAI の利用料が発生）で準備
#   scripts/dev-device-setup.sh --check    # 確認だけ（起動・書き込みをしない）
#   scripts/dev-device-setup.sh --stop     # このスクリプトが起動した LAN サーバーを止める
#
# 行うこと:
#   1. server/.dev.vars の CLIENT_TOKENS の有無を確認（値は表示しない）
#   2. この Mac のプライベート IPv4（Wi-Fi）を調べる（アドレスはハードコードしない）
#   3. LAN 用ポート（既定 8788。127.0.0.1:8787 の STUB とは別）を確認し、他のプロセスとの競合を検出
#   4. サーバーが動いていなければ、LAN モード（DEV_LAN_ACCESS=1・そのプライベート IP だけで待ち受け）で起動
#   5. 誤ったトークンが 401 になることを確認
#   6. MindWaveGraphic/DevServer.local.xcconfig（Git 管理外・権限 600）に接続先とトークンを書く（変わったときだけ）
#
# 守ること: APIキー・トークンを表示しない／Git 管理のファイルに書かない／Xcode スキームを変更しない／
#           0.0.0.0 やグローバル IP で待ち受けない／インターネットへ公開しない。
# LAN の通信は http（暗号化なし）。信頼できる Wi-Fi でだけ使い、終わったら --stop で止めること。

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/server"
LOCAL_XCCONFIG="$ROOT/MindWaveGraphic/DevServer.local.xcconfig"
STATE_DIR="$ROOT/build/dev-lan"
PORT="${PORT:-8788}"
MODE="stub"; CHECK_ONLY=0; STOP=0
for a in "$@"; do
  case "$a" in
    --real) MODE="real" ;;
    --check) CHECK_ONLY=1 ;;
    --stop) STOP=1 ;;
    -h|--help) sed -n 2,20p "$0"; exit 0 ;;
    *) echo "不明なオプション: $a" >&2; exit 2 ;;
  esac
done

ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; exit 1; }

mkdir -p "$STATE_DIR"
if [[ $STOP == 1 ]]; then
  if [[ -f "$STATE_DIR/server.pid" ]] && kill -0 "$(cat "$STATE_DIR/server.pid")" 2>/dev/null; then
    kill "$(cat "$STATE_DIR/server.pid")" && rm -f "$STATE_DIR/server.pid" && ok "LAN サーバーを止めました"
  else
    warn "このスクリプトが起動したサーバーは動いていません（他のサーバーは止めません）"
  fi
  exit 0
fi

command -v node >/dev/null || fail "node が見つかりません（server の README の手順で Node.js を入れてください）"

echo "1. 認証の設定"
[[ -f "$SERVER/.dev.vars" ]] || fail "server/.dev.vars がありません（server/.dev.vars.example をコピーして設定してください）"
TOKEN="$(sed -nE 's/^CLIENT_TOKENS[[:space:]]*=[[:space:]]*"?([^",[:space:]]+).*/\1/p' "$SERVER/.dev.vars" | head -1)"
[[ ${#TOKEN} -ge 16 ]] || fail "CLIENT_TOKENS が未設定か短すぎます（16 文字以上）"
ok "CLIENT_TOKENS: 設定あり（値は表示しません）"
if [[ ${MODE} == real ]]; then
  grep -qE '^OPENAI_API_KEY[[:space:]]*=[[:space:]]*"?sk-' "$SERVER/.dev.vars" || fail "実通信には OPENAI_API_KEY が必要です"
  ok "OPENAI_API_KEY: 設定あり（値は表示しません）"
fi

echo "2. この Mac の LAN アドレス"
HOST="$(cd "$SERVER" && node -e 'import("./scripts/dev-host.ts").then(m=>console.log(m.detectPrivateIPv4()[0]??""))')"
[[ -n "${HOST}" ]] || fail "プライベート IP が見つかりません。Mac が Wi-Fi に接続しているか確認してください"
ok "${HOST}（iPhone も同じ Wi-Fi に接続してください）"
URL="http://${HOST}:${PORT}"

echo "3. サーバー（${URL}・${MODE}）"
health() { curl -s -m 3 "${URL}/v1/health" 2>/dev/null || true; }
LISTEN_PID="$(lsof -nP -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | head -1 || true)"
H="$(health)"
want_mode=$([[ ${MODE} == real ]] && echo openai || echo stub)
if [[ -n "${LISTEN_PID}" && -z "$H" ]]; then
  fail "ポート ${PORT} は別のプロセス（pid ${LISTEN_PID}）が使っていて、${HOST} から応答がありません。PORT=8791 scripts/dev-device-setup.sh のように別のポートを指定してください"
elif [[ -n "$H" ]]; then
  running_mode="$(printf '%s' "$H" | sed -nE 's/.*"provider_mode":"([a-z]+)".*/\1/p')"
  if [[ "$running_mode" != "$want_mode" ]]; then
    fail "ポート ${PORT} で別のモード（${running_mode:-不明}）のサーバーが動いています。止めてから（scripts/dev-device-setup.sh --stop など）やり直してください"
  fi
  ok "起動済み（provider_mode=${running_mode}）"
elif [[ $CHECK_ONLY == 1 ]]; then
  warn "サーバーは起動していません（--check のため起動しません）"
else
  [[ ${MODE} == real ]] && warn "実通信モードで起動します。話しかけるたびに OpenAI の利用料が発生します（1 往復 約 \$0.0002）"
  # exec で node 自身を記録する pid にし、標準入出力をこのスクリプトから切り離す（呼び出し元のパイプを塞がない）
  ( cd "$SERVER" && DEV_LAN_ACCESS=1 HOST="${HOST}" PORT="${PORT}" exec nohup node scripts/dev-server.ts $([[ ${MODE} == stub ]] && echo --stub-openai) \
      > "$STATE_DIR/server.log" 2>&1 < /dev/null ) &
  echo $! > "$STATE_DIR/server.pid"
  for _ in $(seq 1 20); do H="$(health)"; [[ -n "$H" ]] && break; sleep 0.5; done
  [[ -n "$H" ]] || fail "起動できませんでした（build/dev-lan/server.log を確認してください）"
  ok "起動しました（pid $(cat "$STATE_DIR/server.pid")・ログ build/dev-lan/server.log）"
fi

if [[ -n "$H" ]]; then
  echo "4. 認証"
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST "${URL}/v1/context-assist" -H 'Content-Type: application/json' -H 'Authorization: Bearer wrong-token-0000000000' -d '{}')"
  [[ "${code}" == 401 ]] && ok "誤ったトークンは 401（OpenAI へは送られない）" || fail "誤ったトークンで ${code} が返りました"
  curl -s -m 2 "http://127.0.0.1:${PORT}/v1/health" >/dev/null 2>&1 && warn "127.0.0.1:${PORT} でも応答があります（別のサーバーの可能性）" || ok "待ち受けは ${HOST} だけ（0.0.0.0 ではない）"
fi

echo "5. アプリの接続設定（Debug ビルドのみ）"
want="$(printf 'MW_DEV_SERVER_HOST = %s\nMW_DEV_SERVER_PORT = %s\nMW_DEV_CLIENT_TOKEN = %s\n' "${HOST}" "${PORT}" "$TOKEN")"
if [[ -f "$LOCAL_XCCONFIG" ]] && [[ "$(grep -E '^MW_DEV_' "$LOCAL_XCCONFIG")" == "$want" ]]; then
  ok "MindWaveGraphic/DevServer.local.xcconfig は最新です"
elif [[ $CHECK_ONLY == 1 ]]; then
  warn "DevServer.local.xcconfig が未作成か古いです（--check なしで実行すると作成します）"
else
  umask 077
  printf '// scripts/dev-device-setup.sh が作成（Git 管理外。共有しない）\n%s\n' "$want" > "$LOCAL_XCCONFIG"
  ok "DevServer.local.xcconfig を更新しました（接続先 ${URL}・トークンは表示しません）"
  warn "Xcode で Debug ビルドし直して iPhone にインストールしてください（設定はビルド時に入ります）"
fi
unset TOKEN want
git -C "$ROOT" check-ignore -q "$LOCAL_XCCONFIG" || fail "DevServer.local.xcconfig が .gitignore に入っていません"

cat <<EOF

次の操作（iPhone）:
  1. iPhone を Mac と同じ信頼できる Wi-Fi に接続
  2. Xcode で実機を選び、Debug で Run（初回の「ローカルネットワーク」の許可は「許可」）
  3. もこりんの画面で「AIと話す」を押してから、マイクで話す
  終わったら: scripts/dev-device-setup.sh --stop
注意: LAN の通信は暗号化されません。信頼できる Wi-Fi でだけ使い、個人情報・実際の健康データは話さないでください。
EOF
