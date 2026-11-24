import os
import json
from flask import Flask, render_template, request, jsonify
from openai import OpenAI

app = Flask(__name__)

@app.route("/")
def home():
    return render_template("index.html")

@app.route("/chat", methods=["POST"])
def chat():
    message = request.json.get("message", "").strip()

    if not message:
        return jsonify({"error": "メッセージが空です"}), 400

    if not os.environ.get("OPENAI_API_KEY"):
        return jsonify({
            "dialogue": "お話ししてくれてありがとう！無理しないでね。",
            "emotion": "calm",
            "action": "nod"
        })

    client = OpenAI()

    response = client.responses.create(
        model="gpt-4.1-mini",
        instructions="""
あなたはMindWaveのAIキャラクター「モコりん」です。
優しく寄り添うキャラクターとして日本語で短く返答してください。
必ずJSON形式だけで返してください。
emotionはhappy, calm, sad, sleepyのいずれか。
actionはwave, jump, nodのいずれか。
形式：
{"dialogue":"セリフ","emotion":"calm","action":"nod"}
""",
        input=message
    )

    try:
        data = json.loads(response.output_text)

        if data["emotion"] not in ["happy", "calm", "sad", "sleepy"]:
            raise ValueError()

        if data["action"] not in ["wave", "jump", "nod"]:
            raise ValueError()

        return jsonify(data)

    except (ValueError, KeyError, TypeError):
        return jsonify({
            "dialogue": response.output_text,
            "emotion": "calm",
            "action": "nod"
        })

if __name__ == "__main__":
    app.run(debug=True)
