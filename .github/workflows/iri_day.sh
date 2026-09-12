#!/bin/bash
# IRI auto-recorder: Eko FM 89.7, Primary 5 & 6 (Lagos State Radio Service)
set -u
export TZ=Africa/Lagos
mkdir -p transcripts
DAY=$(date +%u)

# Your school windows (timetable + 10min start, + 10min end; Thursday merged P5+P6)
case $DAY in
  1) SLOTS="09:40 P5_lets_go_learning 1800;11:15 P6_auntie_bola 1500" ;;
  3) SLOTS="10:40 P5_lets_go_learning 1800;11:15 P6_auntie_bola 1500" ;;
  4) SLOTS="11:15 THU_P5_and_P6_combined 3300" ;;
  *) echo "No IRI for P5/P6 today."; exit 0 ;;
esac
[ "${1:-}" = "test" ] && SLOTS="now TEST_60sec 60"

stream_sources() {
  [ -n "${FIXED_STREAM_URL:-}" ] && echo "$FIXED_STREAM_URL"
  yt-dlp --get-url "https://zeno.fm/radio/eko-fm-89-7/" 2>/dev/null | head -n1
  echo "https://radio.garden/api/ara/content/listen/yKgmHa7J/channel.mp3"
}

record_slot() {
  local start="$1" name="$2" dur="$3" target now out stream
  if [ "$start" = "now" ]; then target=$(date +%s); else target=$(date -d "today $start" +%s); fi
  now=$(date +%s)
  [ "$target" -gt "$now" ] && { echo "Waiting until $start (Lagos)..."; sleep $((target - now)); }
  out="transcripts/$(date +%F_%a)_${name}"
  while read -r stream; do
    [ -z "$stream" ] && continue
    echo "Recording $name (${dur}s) from: $stream"
    ffmpeg -y -v error -user_agent "Mozilla/5.0" -reconnect 1 -reconnect_streamed 1 \
      -reconnect_delay_max 5 -i "$stream" -t "$dur" -vn -ac 1 -ar 16000 -b:a 32k "$out.mp3" \
      && [ -f "$out.mp3" ] && [ "$(stat -c%s "$out.mp3")" -gt 50000 ] && break
    echo "Source failed, trying next..."
  done < <(stream_sources)
  [ -f "$out.mp3" ] || { echo "ALL SOURCES FAILED for $name"; return 1; }
  python3 - "$out.mp3" "$out.txt" <<'PY'
import sys
from faster_whisper import WhisperModel
model = WhisperModel("small", device="cpu", compute_type="int8")
segs, _ = model.transcribe(sys.argv[1], language="en", vad_filter=True)
with open(sys.argv[2], "w", encoding="utf-8") as f:
    for s in segs:
        m, sec = divmod(int(s.start), 60)
        f.write(f"[{m:02d}:{sec:02d}] {s.text.strip()}\n")
print("Transcript saved:", sys.argv[2])
PY
  rm -f "$out.mp3"
}

IFS=';' read -ra ARR <<< "$SLOTS"
for slot in "${ARR[@]}"; do read -r t n d <<< "$slot"; record_slot "$t" "$n" "$d" || true; done
echo "Done for today."
