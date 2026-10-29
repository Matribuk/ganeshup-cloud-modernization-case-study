#!/bin/bash

# Config
URL="http://localhost:3000/api/courses/share"
PAYLOAD_FILE="payload_heavy.json"
CONCURRENCY=${1:-10}

echo "<==========================================================="
echo "📊 AS-IS BENCHMARK: Load Test & RAM/CPU Impact"
echo "===========================================================>"

echo "[*] Generation of a heavy test payload (simulating images/audio)..."
node -e '
const fs = require("fs");
const chunk = "A".repeat(1024 * 1024); // 1 Mo of fake data in base64
const images = Array.from({ length: 15 }, (_, i) => ({
  index: i,
  base64Data: Buffer.from(chunk).toString("base64"),
  filename: `image_${i}.jpg`
}));
const payload = {
  courseData: {
    metadata: { courseId: "bench-uuid-" + Date.now() },
    content: { images, audioFiles: [] }
  }
};
fs.writeFileSync("'${PAYLOAD_FILE}'", JSON.stringify(payload));
console.log("[+] Payload generated : ~15 Mo on disk.");
'

NODE_PID=$(pgrep -f "ts-node src/server.as-is.ts")

if [ -z "$NODE_PID" ]; then
  echo "[!] Error : The legacy mock-api server does not seem to be running (run 'npm run dev:as-is' in another terminal)."
  rm -f ${PAYLOAD_FILE}
  exit 1
fi

echo "[*] PID of the target Node.js server detected : $NODE_PID"

echo "[*] System state before the request :"
ps -p $NODE_PID -o %cpu,%mem,rss,vsz

echo "[*] Send $CONCURRENCY heavy POST requests in parallel (synchronous fs.writeFileSync)..."

TIME_START=$(date +%s%N)

for ((i=1; i<=CONCURRENCY; i++)); do
  curl -s -o /dev/null -X POST $URL \
    -H "Content-Type: application/json" \
    -d @${PAYLOAD_FILE} &
done

wait

TIME_END=$(date +%s%N)
DURATION=$(( (TIME_END - TIME_START) / 1000000 ))

echo ""
echo "<==========================================================="
echo "📈 RESULTS BENCHMARK AS-IS :"
echo "===========================================================>"
echo "Total request time for $CONCURRENCY concurrent requests (ms) : ${DURATION}ms"
echo ""
echo "[*] System state after the request (Peak of RAM / RSS) :"
ps -p $NODE_PID -o %cpu,%mem,rss,vsz

rm -f ${PAYLOAD_FILE}