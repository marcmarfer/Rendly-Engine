#!/bin/bash
set -e

if [[ $# -lt 2 ]]; then
    echo "❌ Uso: $0 <gameplay> <music>"
    echo "   Ejemplo: $0 mining lofi"
    exit 1
fi

GAMEPLAY="$1"
MUSIC="$2"
DATE=$(date +"%Y%m%d_%H%M")
OUTPUT_DIR="output/videos/${GAMEPLAY}_${MUSIC}"
mkdir -p "$OUTPUT_DIR"

MAX_DURATION=3600

echo "🎬 Generando video: $GAMEPLAY + $MUSIC"
echo "⏱️  Duración objetivo: $(awk "BEGIN {printf \"%.1f\", $MAX_DURATION/60}") minutos"

CLIPS=(clips/$GAMEPLAY/*.mp4)
SHUFFLED_CLIPS=($(printf "%s\n" "${CLIPS[@]}" | shuf))

INPUTS=()
FILTERS=""
DURATIONS=()
OFFSET=0
CURRENT_DURATION=0

for i in "${!SHUFFLED_CLIPS[@]}"; do
  CLIP="${SHUFFLED_CLIPS[$i]}"
  
  DUR=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
        -of default=noprint_wrappers=1:nokey=1 "$CLIP")
  
  INPUTS+=( -i "$CLIP" )
  DURATIONS+=("$DUR")
  CURRENT_DURATION=$(awk "BEGIN {print $CURRENT_DURATION + $DUR}")
  
  FILTERS+="[$i:v]format=yuv420p,setsar=1,settb=AVTB[v$i]; "
  FILTERS+="[$i:a]aformat=fltp:48000:stereo[a$i]; "
  
  echo "📹 Clip $((i+1)): $(basename "$CLIP") (${DUR}s) - Total: ${CURRENT_DURATION}s"
  
  if [[ $(awk "BEGIN {print ($CURRENT_DURATION >= $MAX_DURATION)}") == 1 ]]; then
    echo "✅ Alcanzada duración objetivo con clip $((i+1)) - Total: ${CURRENT_DURATION}s"
    break
  fi
done

CLIP_COUNT=${#DURATIONS[@]}
FINAL_VIDEO_DURATION=$(awk "BEGIN {print $CURRENT_DURATION - ($CLIP_COUNT - 1)}")

V_LAST="v0"
A_LAST="a0"
OFFSET=0
for ((i=1; i<${#DURATIONS[@]}; i++)); do
  OFFSET=$(awk "BEGIN {print $OFFSET + ${DURATIONS[$((i-1))]} - 1}")
  V_NEXT="v${i}out"
  A_NEXT="a${i}out"
  FILTERS+="[$V_LAST][v$i]xfade=transition=fade:duration=1:offset=${OFFSET}[$V_NEXT]; "
  FILTERS+="[$A_LAST][a$i]acrossfade=d=1[$A_NEXT]; "
  V_LAST="$V_NEXT"
  A_LAST="$A_NEXT"
done

MUSIC_FILES=(audio/generated/$MUSIC/*.mp3)
SHUFFLED_MUSIC=($(printf "%s\n" "${MUSIC_FILES[@]}" | shuf))
MUSIC_INPUTS=()
MUSIC_FILTER=""
MUSIC_LABELS=()
TOTAL_MUSIC_DURATION=0
TARGET_DURATION=$FINAL_VIDEO_DURATION

echo "🎵 Procesando música para ${TARGET_DURATION}s de video..."

for i in "${!SHUFFLED_MUSIC[@]}"; do
  MUSIC_FILE="${SHUFFLED_MUSIC[$i]}"
  DUR=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration \
        -of default=noprint_wrappers=1:nokey=1 "$MUSIC_FILE")
  [[ -z "$DUR" ]] && continue

  MUSIC_INPUTS+=( -i "$MUSIC_FILE" )
  INPUT_INDEX=$((CLIP_COUNT + i))
  
  FADE_IN=2
  FADE_OUT=2
  TRIM=$(awk "BEGIN {print $DUR - $FADE_OUT}")
  
  MUSIC_FILTER+="[$INPUT_INDEX:a]aformat=fltp:48000:stereo,afade=t=in:st=0:d=$FADE_IN,afade=t=out:st=$(awk "BEGIN {print $TRIM - $FADE_OUT}"):d=$FADE_OUT,volume=0.5[music$i]; "
  MUSIC_LABELS+=("music$i")
  
  TOTAL_MUSIC_DURATION=$(awk "BEGIN {print $TOTAL_MUSIC_DURATION + $TRIM}")
  
  echo "   🎶 Canción $((i+1)): $(basename "$MUSIC_FILE") (${TRIM}s) - Total música: ${TOTAL_MUSIC_DURATION}s"
  
  if [[ $(awk "BEGIN {print ($TOTAL_MUSIC_DURATION >= $TARGET_DURATION)}") == 1 ]] && [[ $i -gt 0 ]]; then
    echo "   ✅ Suficiente música para cubrir el video"
    break
  fi
done

echo "🔄 Concatenando ${#MUSIC_LABELS[@]} canciones..."

if (( ${#MUSIC_LABELS[@]} > 1 )); then
  CONCAT_INPUT="[${MUSIC_LABELS[0]}]"
  for ((i=1; i<${#MUSIC_LABELS[@]}; i++)); do
    MUSIC_FILTER+="$CONCAT_INPUT[${MUSIC_LABELS[$i]}]concat=n=2:v=0:a=1[musicconcat$i]; "
    CONCAT_INPUT="[musicconcat$i]"
  done
  FINAL_MUSIC_LABEL="${CONCAT_INPUT:1:-1}"
elif (( ${#MUSIC_LABELS[@]} == 1 )); then
  FINAL_MUSIC_LABEL="${MUSIC_LABELS[0]}"
fi

if (( ${#MUSIC_LABELS[@]} > 0 )); then
  FILTERS+="[$A_LAST]volume=0.25[a_game]; [a_game][$FINAL_MUSIC_LABEL]amix=inputs=2:duration=longest:dropout_transition=2[a_final]; "
  A_LAST="a_final"
fi

FILTERS+="[$V_LAST]trim=duration=${FINAL_VIDEO_DURATION}[v_final]; "
FILTERS+="[$A_LAST]atrim=duration=${FINAL_VIDEO_DURATION}[a_final_trim]; "
V_LAST="v_final"
A_LAST="a_final_trim"

OUT_VIDEO="$OUTPUT_DIR/${DATE}_final_video.mp4"
echo -e "\n🚀 Ejecutando FFmpeg con ${#DURATIONS[@]} clips de video y ${#MUSIC_LABELS[@]} canciones...\n"

ffmpeg -y \
  "${INPUTS[@]}" \
  "${MUSIC_INPUTS[@]}" \
  -filter_complex "${FILTERS}${MUSIC_FILTER::-1}" \
  -map "[$V_LAST]" -map "[$A_LAST]" \
  -c:v h264_nvenc -preset p3 -cq:v 23 \
  -c:a aac -b:a 192k -pix_fmt yuv420p \
  "$OUT_VIDEO"

echo -e "\n✅ Video generado: $OUT_VIDEO"
echo "   Duración real: $(awk 'BEGIN {printf "%.1f", '$FINAL_VIDEO_DURATION'/60}')min ($(awk 'BEGIN {printf "%.0f", '$FINAL_VIDEO_DURATION'}')s)"
echo "   Duración objetivo: $(awk 'BEGIN {printf "%.1f", '$MAX_DURATION'/60}')min (${MAX_DURATION}s)" 
echo "   Clips usados: ${#DURATIONS[@]}"
echo "   Música usada: ${#MUSIC_LABELS[@]}"
