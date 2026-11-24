// もこりん（統合先のコピー）。原本: third_party/mokorin_friend_source/static/script.js
//
// 原本からの変更:
// - setEmotion() が dialogue.textContent を固定文で上書きしていた処理を分離した。
//   表情の変更はセリフに触れない。セリフは setDialogue() で別に設定する（AI の返答が固定文で消えないように）。
//   原本の固定文は defaultLines として残し、getDefaultLine() で参照できる（端末内の定型文として使う場合のみ）
// - setAction() の許可値・クラスの付け外し・2.5 秒後の解除は原本と同じ
// - 表示サイズに合わせた縮小（fit）と、アプリ（WKWebView）への準備完了通知を追加
// - 2026-10-28: 読み上げ中の口の動き setSpeaking() を追加
// - 2026-11-04: 会話の状態 setActivity()（聞き取り中・考え中）を追加
// - 未知の表情・動作は無視する（原本と同じ）

(function () {
  "use strict";

  const character = document.getElementById("character");
  const emotionLabel = document.getElementById("emotion");
  const dialogue = document.getElementById("dialogue");

  const EMOTIONS = ["happy", "calm", "sad", "sleepy"];
  const ACTIONS = ["wave", "jump", "nod"];

  // 原本と同じ表示名
  const emotionNames = {
    happy: "HAPPY ✨",
    calm: "RELAX ☁️",
    sad: "SAD 💧",
    sleepy: "SLEEPY 🌙"
  };

  // 原本の固定セリフ（setEmotion からは使わない）
  const defaultLines = {
    happy: "うれしいね！一緒に喜ぼう！",
    calm: "ゆっくり深呼吸してみよう ☁️",
    sad: "無理に元気を出さなくていいよ。",
    sleepy: "今日もおつかれさま。ゆっくり休もうね。"
  };

  let currentEmotion = "calm";
  let actionTimer = null;

  /** 表情を変える（セリフは変更しない） */
  function setEmotion(emotion) {
    if (!EMOTIONS.includes(emotion)) return false;
    character.classList.remove("happy", "calm", "sad", "sleepy");
    character.classList.add("mocorin", emotion);
    emotionLabel.textContent = emotionNames[emotion];
    currentEmotion = emotion;
    return true;
  }

  /** 動作を再生する（原本と同じ: クラスを付け直し、2.5 秒後に外す） */
  function setAction(action) {
    if (!ACTIONS.includes(action)) return false;
    character.classList.remove("wave", "jump", "nod");
    void character.offsetWidth;
    character.classList.add(action);
    if (actionTimer) clearTimeout(actionTimer);
    actionTimer = setTimeout(() => {
      character.classList.remove(action);
      actionTimer = null;
    }, 2500);
    return true;
  }

  /** セリフを設定する（textContent なので HTML として解釈しない）。空文字で非表示 */
  function setDialogue(text) {
    const value = typeof text === "string" ? text : "";
    dialogue.textContent = value;
    dialogue.hidden = value.length === 0 || !document.body.classList.contains("show-dialogue");
    return true;
  }

  /** 話している間の口の動き（読み上げ中に SwiftUI から付け外しする） */
  function setSpeaking(on) {
    if (on === true) character.classList.add("speaking");
    else character.classList.remove("speaking");
    return true;
  }

  /** 会話の状態（idle / listening / thinking）。表情（setEmotion）・動作（setAction）とは別のクラスで表す */
  const ACTIVITIES = ["idle", "listening", "thinking"];
  function setActivity(activity) {
    if (!ACTIVITIES.includes(activity)) return false;
    character.classList.remove("activity-listening", "activity-thinking");
    if (activity !== "idle") character.classList.add(`activity-${activity}`);
    return true;
  }

  /** 原本の固定セリフ（端末内の定型文として使う場合のみ） */
  function getDefaultLine(emotion) {
    return defaultLines[emotion] || "";
  }

  /** 表示枠に合わせて縮小する */
  function fit() {
    const scale = Math.min(window.innerWidth / 220, window.innerHeight / 250);
    document.documentElement.style.setProperty("--mokorin-scale", String(Math.max(0.05, scale)));
  }

  function state() {
    return {
      emotion: currentEmotion,
      actions: ACTIONS.filter((a) => character.classList.contains(a)),
      speaking: character.classList.contains("speaking"),
      dialogue: dialogue.textContent
    };
  }

  window.addEventListener("resize", fit);
  fit();

  window.setEmotion = setEmotion;
  window.setAction = setAction;
  window.setDialogue = setDialogue;
  window.setSpeaking = setSpeaking;
  window.setActivity = setActivity;
  window.getDefaultLine = getDefaultLine;
  window.mokorinState = state;

  // アプリへ準備完了を通知（WKWebView 以外のブラウザでは何もしない）
  try {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mokorin) {
      window.webkit.messageHandlers.mokorin.postMessage({ type: "ready" });
    }
  } catch (e) { /* 通知できなくても表示は続ける */ }
})();
