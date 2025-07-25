import requests
import time
import os
import datetime
import re
from dotenv import load_dotenv

load_dotenv()
API_KEY = os.getenv("MUREKA_API_KEY")

API_URL = "https://api.mureka.ai/v1/instrumental/generate"
STATUS_URL = "https://api.mureka.ai/v1/instrumental/query"

PROMPT = "Generate an instrumental at ~74 BPM with warm Rhodes-style chords (flat and ambient), deep sustained sub bass, light drums, NO melody, NO movement. Static, minimal, background-focused."
MODEL = "auto"

print("📂 Introduce el género para la carpeta (ej: lofi, jazz):")
GENRE = input("> ").strip().lower()

date_str = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
keywords = "_".join(re.findall(r'\w+', PROMPT.lower()))[:30]

BASE_OUTPUT_DIR = os.path.join("audio", "generated")
OUTPUT_DIR = os.path.join(BASE_OUTPUT_DIR, GENRE)
os.makedirs(OUTPUT_DIR, exist_ok=True)

payload = {
    "model": MODEL,
    "prompt": PROMPT
}

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

print("🚀 Enviando solicitud de generación...")
response = requests.post(API_URL, json=payload, headers=headers)
response.raise_for_status()
data = response.json()

task_id = data["id"]
print(f"✅ Tarea creada. ID: {task_id}")

while True:
    time.sleep(5)
    status_resp = requests.get(f"{STATUS_URL}/{task_id}", headers=headers)
    status_resp.raise_for_status()
    status_data = status_resp.json()
    status = status_data["status"]
    print(f"⏳ Estado actual: {status}")

    if status == "succeeded":
        break
    elif status in ["failed", "timeouted", "cancelled"]:
        raise Exception(f"❌ La generación falló: {status_data.get('failed_reason', 'sin razón')}")

print("🎉 Generación completada. Descargando canciones...")

choices = status_data.get("choices", [])
if not choices:
    raise Exception("❌ No se encontraron canciones generadas.")

for idx, choice in enumerate(choices, start=1):
    mp3_url = choice.get("url")
    if mp3_url:
        filename = f"{date_str}_{keywords}_{idx}.mp3"
        file_path = os.path.join(OUTPUT_DIR, filename)
        mp3_resp = requests.get(mp3_url)
        mp3_resp.raise_for_status()
        with open(file_path, "wb") as f:
            f.write(mp3_resp.content)
        print(f"✅ Guardado MP3: {file_path}")
