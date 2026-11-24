#!/usr/bin/env bash
# コミット前の秘密情報チェック（ステージ済みのファイルだけを調べる）。
# 見つかった場合はファイル名と種類だけを表示し、値は表示しない。終了コード 1。
#
#   scripts/check-secrets.sh            # git add の後、git commit の前に実行
# pre-commit フックとして使う場合（任意・各自のローカル設定）:
#   ln -s ../../scripts/check-secrets.sh .git/hooks/pre-commit
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
FILES=$(git diff --cached --name-only --diff-filter=ACMR)
[ -z "$FILES" ] && { echo "[secrets] ステージ済みのファイルはありません"; exit 0; }

found=0
report() { echo "[secrets] 要確認: $1 ($2)"; found=1; }

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *.dev.vars|*/.dev.vars) report "$f" "ローカル専用の秘密情報ファイル"; continue ;;
    *DevServer.local.xcconfig) report "$f" "開発用サーバーの接続先・トークン（scripts/dev-device-setup.sh が作るローカル専用ファイル）"; continue ;;
    *.xcscheme)
      if grep -qE 'key = "MW_INSIGHT_CLIENT_TOKEN"' "$f" && grep -A2 -E 'key = "MW_INSIGHT_CLIENT_TOKEN"' "$f" | grep -qE 'value = "[^"]+"'; then
        report "$f" "スキームにクライアントトークンの値"
      fi ;;
  esac
  if git show ":$f" | grep -qE 'sk-(proj-)?[A-Za-z0-9_-]{20,}'; then report "$f" "OpenAI APIキーの形式の文字列"; fi
done <<< "$FILES"

# ローカルの .dev.vars にある実際のキー・トークンがステージ内容に含まれていないか（値は表示しない）
if [ -f server/.dev.vars ]; then
  python3 - "$FILES" <<'PY' || found=1
import re, subprocess, sys
secrets = []
for line in open("server/.dev.vars", encoding="utf-8"):
    m = re.match(r"^\s*(OPENAI_API_KEY|CLIENT_TOKENS)\s*=\s*(.*)\s*$", line)
    if m and m.group(2):
        secrets += [v.strip() for v in m.group(2).split(",") if len(v.strip()) >= 12]
bad = False
for f in sys.argv[1].split("\n"):
    if not f:
        continue
    try:
        content = subprocess.run(["git", "show", f":{f}"], capture_output=True, check=True).stdout.decode("utf-8", "ignore")
    except subprocess.CalledProcessError:
        continue
    if any(s in content for s in secrets):
        print(f"[secrets] 要確認: {f} (.dev.vars の実際のキーまたはトークンと同じ値)")
        bad = True
sys.exit(1 if bad else 0)
PY
fi

if [ $found -eq 0 ]; then echo "[secrets] 問題は見つかりませんでした（$(echo "$FILES" | wc -l | tr -d ' ') ファイル）"; else exit 1; fi
