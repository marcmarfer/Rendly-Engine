import os
import random
import datetime
from moviepy.video.io.VideoFileClip import VideoFileClip
from moviepy.audio.io.AudioFileClip import AudioFileClip
from moviepy.video.compositing.CompositeVideoClip import concatenate_videoclips
from moviepy.audio.AudioClip import CompositeAudioClip

CLIPS_FOLDER = "clips"
AUDIO_FOLDER = "audio/generated"
OUTPUT_FOLDER = os.path.join("output", "videos")
TARGET_DURATION = 3600
MUSIC_VOLUME = 0.3

os.makedirs(OUTPUT_FOLDER, exist_ok=True)

date_str = datetime.datetime.now().strftime("%Y%m%d_%H%M")
OUTPUT_FILE = os.path.join(OUTPUT_FOLDER, f"{date_str}_final_video.mp4")

print("🎬 Buscando archivos de video...")
video_files = [os.path.join(CLIPS_FOLDER, f) for f in os.listdir(CLIPS_FOLDER) if f.endswith(".mp4")]
if not video_files:
    raise Exception("❌ No se encontraron archivos .mp4 en la carpeta 'clips'.")

print(f"✅ Se encontraron {len(video_files)} archivos de video.")
random.shuffle(video_files)

print("🔄 Cargando clips de video...")
clips = []
total_duration = 0

for file in video_files:
    clip = VideoFileClip(file)
    clip_duration = clip.duration
    clips.append(clip)
    total_duration += clip_duration
    print(f"  - Añadido: {os.path.basename(file)} ({clip_duration:.2f} segundos)")
    
    if total_duration >= TARGET_DURATION:
        break

if not clips:
    raise Exception("❌ No se pudieron seleccionar clips para alcanzar la duración objetivo.")

print(f"✅ Total de clips utilizados: {len(clips)} — Duración total: {total_duration / 60:.2f} minutos")

print("🔄 Combinando clips de video...")
final_video = concatenate_videoclips(clips, method='compose')
print(f"✅ Video base generado con duración de {final_video.duration / 60:.2f} minutos")

print("🎵 Buscando archivos de música...")
audio_files = [os.path.join(AUDIO_FOLDER, f) for f in os.listdir(AUDIO_FOLDER) if f.endswith(".mp3")]
if not audio_files:
    print("⚠️ No se encontraron archivos .mp3 en la carpeta 'audio/generated'. El video se generará sin música de fondo.")
    has_music = False
else:
    print(f"✅ Se encontraron {len(audio_files)} archivos de música.")
    random.shuffle(audio_files)
    has_music = True

if has_music:
    print("🔄 Preparando música de fondo...")
    music_clips = []
    current_time = 0

    while current_time < total_duration:
        for audio_file in audio_files:
            if current_time >= total_duration:
                break
                
            audio_clip = AudioFileClip(audio_file)
            audio_clip = audio_clip.with_start(current_time)
            audio_clip = audio_clip.with_volume_scaled(MUSIC_VOLUME)
            
            music_clips.append(audio_clip)
            print(f"  - Añadida música: {os.path.basename(audio_file)} (inicio: {current_time:.2f}s)")
            current_time += audio_clip.duration
            
            if current_time >= total_duration:
                break
        
        if current_time < total_duration:
            random.shuffle(audio_files)

    print(f"✅ Total de clips de música utilizados: {len(music_clips)}")

    print("🔄 Mezclando audio original con música de fondo...")
    original_audio = final_video.audio
    if original_audio is not None:
        new_audio = CompositeAudioClip([original_audio] + music_clips)
        final_video = final_video.with_audio(new_audio)
        print("✅ Audio combinado correctamente")
    else:
        print("⚠️ El video no tiene audio original. Se utilizará solo la música de fondo.")
        combined_music = CompositeAudioClip(music_clips)
        final_video = final_video.with_audio(combined_music)

print(f"🔄 Generando video final{' con música de fondo' if has_music else ''}...")
print(f"⏳ Este proceso puede tardar varios minutos. Por favor, espera...")
final_video.write_videofile(OUTPUT_FILE, codec="libx264", audio_codec="aac")

for c in clips:
    c.close()
if has_music:
    for m in music_clips:
        m.close()
final_video.close()

print(f"🎉 ¡Video final guardado como: {OUTPUT_FILE}!")
print(f"   Duración: {total_duration / 60:.2f} minutos")
print(f"   Clips de video: {len(clips)}")
if has_music:
    print(f"   Clips de música: {len(music_clips)}")
print("✅ Proceso completado con éxito")