#!/bin/bash

# Config
URL="http://localhost:3000/api/courses/share"
PAYLOAD_FILE="payload_metadata.json"
CHUNK_FILE="chunk_1mb.bin"
RESPONSE_FILE="presigned_response.json"
CONCURRENCY=${1:-10}
IMAGE_COUNT=15

echo "<==========================================================="
echo "📊 TO-BE BENCHMARK: Load Test & RAM/CPU Impact"
echo "===========================================================>"

echo "[*] Generation of a metadata-only payload (the bytes never transit the API)..."
node -e '
const fs = require("fs");
const images = Array.from({ length: '${IMAGE_COUNT}' }, (_, i) => ({
  index: i,
  filename: `image_${i}.jpg`
}));
const payload = {
  courseData: {
    metadata: { courseId: "bench-uuid-" + Date.now() },
    content: { images, audioFiles: [] }
  }
};
fs.writeFileSync("'${PAYLOAD_FILE}'", JSON.stringify(payload));
const kb = (fs.statSync("'${PAYLOAD_FILE}'").size / 1024).toFixed(1);
console.log(`[+] Payload generated : ~${kb} Ko (vs ~15 Mo for the As-Is).`);
'

NODE_PID=$(pgrep -f "[.]bin/ts-node src/server.ts")

if [ -z "$NODE_PID" ]; then
  echo "[!] Error : The to-be mock-api server does not seem to be running (run 'npm run dev' in another terminal)."
  rm -f ${PAYLOAD_FILE}
  exit 1
fi

echo "[*] PID of the target Node.js server detected : $NODE_PID"

echo "[*] System state before the request :"
ps -p $NODE_PID -o %cpu,%mem,rss,vsz

echo "[*] Send $CONCURRENCY metadata POST requests in parallel (presigned URL generation only)..."

TIME_START=$(date +%s%N)

for ((i=1; i<=CONCURRENCY; i++)); do
  curl -s -o /dev/null -X POST $URL \
    -H "Content-Type: application/json" \
    -d @${PAYLOAD_FILE} &
done

wait

TIME_END=$(date +%s%N)
DURATION=$(( (TIME_END - TIME_START) / 1000000 ))

echo "<==========================================================="
echo "📈 RESULTS BENCHMARK TO-BE :"
echo "===========================================================>"
echo "Total request time for $CONCURRENCY concurrent requests (ms) : ${DURATION}ms"
echo ""
echo "[*] System state after the request (Peak of RAM / RSS) :"
ps -p $NODE_PID -o %cpu,%mem,rss,vsz

echo ""
echo "[*] Phase 2 : client-side upload of ${IMAGE_COUNT} x 1 Mo directly to S3 via the presigned URLs"
curl -s -X POST $URL -H "Content-Type: application/json" -d @${PAYLOAD_FILE} -o ${RESPONSE_FILE}
dd if=/dev/urandom of=${CHUNK_FILE} bs=1048576 count=1 2>/dev/null

UPLOAD_START=$(date +%s%N)
node -e '
const fs = require("fs");
const urls = JSON.parse(fs.readFileSync("'${RESPONSE_FILE}'", "utf8")).uploadUrls.map(u => u.uploadUrl);
fs.writeFileSync("upload_urls.txt", urls.join("\n"));
'
while read -r u; do
  curl -s -o /dev/null -X PUT --upload-file ${CHUNK_FILE} "$u" &
done < upload_urls.txt
wait
UPLOAD_END=$(date +%s%N)
UPLOAD_MS=$(( (UPLOAD_END - UPLOAD_START) / 1000000 ))

echo "Direct S3 upload time for ${IMAGE_COUNT} x 1 Mo (ms) : ${UPLOAD_MS}ms  [zero API involvement]"
echo ""
echo "[*] Server state after the S3 uploads (must be unchanged -- bytes bypassed it) :"
ps -p $NODE_PID -o %cpu,%mem,rss,vsz

rm -f ${PAYLOAD_FILE} ${CHUNK_FILE} ${RESPONSE_FILE} upload_urls.txt
