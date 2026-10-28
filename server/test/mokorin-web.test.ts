// 統合先のもこりん JavaScript（iOS アプリに同梱する MindWaveGraphic/MindWaveGraphic/Mokorin/Web/mokorin.js）の動作テスト。
// 最小限の疑似 DOM の上で実行し、原本（third_party/mokorin_friend_source/static/script.js）との違いを確認する。

import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const INTEGRATED = new URL("../../MindWaveGraphic/MindWaveGraphic/Mokorin/Web/mokorin.js", import.meta.url);
const ORIGINAL = new URL("../../third_party/mokorin_friend_source/static/script.js", import.meta.url);

class FakeClassList {
  private set: Set<string>;
  constructor(initial: string[] = []) { this.set = new Set(initial); }
  add(...c: string[]) { c.forEach((x) => this.set.add(x)); }
  remove(...c: string[]) { c.forEach((x) => this.set.delete(x)); }
  contains(c: string) { return this.set.has(c); }
  values() { return [...this.set]; }
}

function makeDom() {
  const el = (classes: string[] = []) => ({ classList: new FakeClassList(classes), textContent: "", hidden: true, offsetWidth: 220 });
  const elements = { character: el(["mocorin", "calm"]), emotion: el(), dialogue: el() };
  const posted: unknown[] = [];
  const styleProps: Record<string, string> = {};
  const window: Record<string, any> = {
    innerWidth: 110, innerHeight: 125,
    addEventListener: () => {},
    webkit: { messageHandlers: { mokorin: { postMessage: (m: unknown) => posted.push(m) } } },
  };
  const document = {
    getElementById: (id: string) => elements[id as keyof typeof elements],
    body: { classList: new FakeClassList() },
    documentElement: { style: { setProperty: (k: string, v: string) => { styleProps[k] = v; } } },
  };
  return { elements, posted, styleProps, window, document };
}

function run(file: URL) {
  const dom = makeDom();
  const context = vm.createContext({ window: dom.window, document: dom.document, setTimeout, clearTimeout, console });
  vm.runInContext(readFileSync(file, "utf8"), context);
  return { ...dom, api: dom.window };
}

test("原本の確認: setEmotion がセリフを固定文で上書きする（統合先で分離した理由）", () => {
  const { api, elements } = run(ORIGINAL);
  elements.dialogue.textContent = "AI の返答";
  api.setEmotion("happy");
  assert.equal(elements.dialogue.textContent, "うれしいね！一緒に喜ぼう！");
});

test("統合先: setEmotion は表情とラベルだけ変え、セリフ（AI の返答）を上書きしない", () => {
  const { api, elements } = run(INTEGRATED);
  api.setDialogue("面接前なんだね。");
  const cases: Array<[string, string]> = [["happy", "HAPPY ✨"], ["calm", "RELAX ☁️"], ["sad", "SAD 💧"], ["sleepy", "SLEEPY 🌙"]];
  for (const [emotion, label] of cases) {
    assert.equal(api.setEmotion(emotion), true);
    assert.ok(elements.character.classList.contains(emotion));
    assert.equal(elements.emotion.textContent, label);
    assert.equal(elements.dialogue.textContent, "面接前なんだね。");
  }
  // 表情クラスは1つだけ
  assert.deepEqual(elements.character.classList.values().filter((c) => ["happy", "calm", "sad", "sleepy"].includes(c)), ["sleepy"]);
  assert.equal(api.setEmotion("angry"), false, "未知の表情は無視");
  assert.ok(elements.character.classList.contains("sleepy"));
});

test("統合先: setAction は原本と同じく wave/jump/nod を付け、2.5 秒後に外す。未知の動作は無視", () => {
  mock.timers.enable({ apis: ["setTimeout"] });
  try {
    const dom = makeDom();
    const context = vm.createContext({ window: dom.window, document: dom.document, setTimeout, clearTimeout, console });
    vm.runInContext(readFileSync(INTEGRATED, "utf8"), context);
    const api = dom.window, ch = dom.elements.character;
    assert.equal(api.setAction("jump"), true);
    assert.ok(ch.classList.contains("jump"));
    api.setAction("nod");
    assert.ok(ch.classList.contains("nod") && !ch.classList.contains("jump"), "前の動作は外す");
    mock.timers.tick(2499);
    assert.ok(ch.classList.contains("nod"));
    mock.timers.tick(2);
    assert.ok(!ch.classList.contains("nod"));
    assert.equal(api.setAction("dance"), false);
  } finally {
    mock.timers.reset();
  }
});

test("統合先: setDialogue は textContent（HTML として解釈しない）、原本の固定文は getDefaultLine で参照のみ", () => {
  const { api, elements } = run(INTEGRATED);
  api.setDialogue("<b>こんにちは</b>");
  assert.equal(elements.dialogue.textContent, "<b>こんにちは</b>");
  assert.equal(api.getDefaultLine("calm"), "ゆっくり深呼吸してみよう ☁️");
  assert.equal(elements.dialogue.textContent, "<b>こんにちは</b>");
});

test("統合先: 準備完了をアプリへ通知し、表示枠に合わせて縮小率を設定する", () => {
  const { posted, styleProps, api } = run(INTEGRATED);
  assert.equal(JSON.stringify(posted), JSON.stringify([{ type: "ready" }]));
  assert.equal(styleProps["--mokorin-scale"], "0.5");
  assert.equal(api.mokorinState().emotion, "calm");
});

test("統合先: setSpeaking は読み上げ中の口の動き（speaking クラス）を付け外しし、表情・セリフに触れない", () => {
  const { api, elements } = run(INTEGRATED);
  api.setDialogue("そっか。何か予定があるの？");
  api.setEmotion("calm");
  api.setSpeaking(true);
  assert.ok(elements.character.classList.contains("speaking"));
  assert.ok(elements.character.classList.contains("calm"));
  assert.equal(elements.dialogue.textContent, "そっか。何か予定があるの？");
  api.setSpeaking(false);
  assert.ok(!elements.character.classList.contains("speaking"));
  assert.equal(api.mokorinState().speaking, false);
});

test("統合先の HTML: 原本のキャラクター要素とクラスを保持し、手足（.feet）を追加。CSS に原本の表情・動作の定義が残る", () => {
  const html = readFileSync(new URL("../../MindWaveGraphic/MindWaveGraphic/Mokorin/Web/mokorin.html", import.meta.url), "utf8");
  for (const part of ['class="mocorin calm"', 'class="sprout"', 'class="body"', 'class="cheek left"', 'class="cheek right"', 'class="eyes"', 'class="mouth"', 'class="feet"']) {
    assert.ok(html.includes(part), part);
  }
  const css = readFileSync(new URL("../../MindWaveGraphic/MindWaveGraphic/Mokorin/Web/mokorin.css", import.meta.url), "utf8");
  for (const rule of [".happy .mouth", ".sad .mouth", ".sleepy .eyes span", "@keyframes jump", "@keyframes wave", "@keyframes nod", "#character.wave", "#character.jump", "#character.nod", "prefers-reduced-motion"]) {
    assert.ok(css.includes(rule), rule);
  }
});
