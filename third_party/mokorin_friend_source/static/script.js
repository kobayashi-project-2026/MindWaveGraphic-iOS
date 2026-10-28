const character = document.getElementById("character");
const emotionLabel = document.getElementById("emotion");
const dialogue = document.getElementById("dialogue");

const emotionNames = {
  happy: "HAPPY ✨",
  calm: "RELAX ☁️",
  sad: "SAD 💧",
  sleepy: "SLEEPY 🌙"
};

function setEmotion(emotion) {
  const allowed = ["happy", "calm", "sad", "sleepy"];
  if (!allowed.includes(emotion)) return;

  character.classList.remove("happy", "calm", "sad", "sleepy");
  character.classList.add("mocorin", emotion);
  emotionLabel.textContent = emotionNames[emotion];

  const messages = {
    happy: "うれしいね！一緒に喜ぼう！",
    calm: "ゆっくり深呼吸してみよう ☁️",
    sad: "無理に元気を出さなくていいよ。",
    sleepy: "今日もおつかれさま。ゆっくり休もうね。"
  };

  dialogue.textContent = messages[emotion];
}

function setAction(action) {
  const allowed = ["wave", "jump", "nod"];
  if (!allowed.includes(action)) return;

  character.classList.remove("wave", "jump", "nod");
  void character.offsetWidth;
  character.classList.add(action);

  setTimeout(() => {
    character.classList.remove(action);
  }, 2500);
}

window.setAction = setAction;
window.setEmotion = setEmotion;
