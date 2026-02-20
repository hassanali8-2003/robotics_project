import asyncio
import websockets
import json
import cv2
import base64
import random
import sys

# ==============================
# CONFIGURATION
# ==============================
SERVER_IP = "172.23.200.150"
SERVER_PORT = 8080
FPS_DELAY = 0.2               # ~5 FPS (stable)
JPEG_QUALITY = 30             # Lower = smaller size
RECONNECT_DELAY = 5           # Seconds before reconnect

# ==============================
# STREAM FUNCTION
# ==============================
async def stream_fpv():

    uri = f"ws://{SERVER_IP}:{SERVER_PORT}"

    while True:  # Auto reconnect loop
        try:
            print(f"Connecting to {uri} ...")

            async with websockets.connect(
                    uri,
                    ping_interval=30,
                    ping_timeout=30,
                    max_size=None
            ) as websocket:

                print("✅ Connected to Hub")
                print("🚁 FPV Camera Streaming...")

                cap = cv2.VideoCapture(0)

                if not cap.isOpened():
                    print("❌ Camera not accessible")
                    return

                while True:
                    try:
                        ret, frame = cap.read()
                        if not ret:
                            print("❌ Failed to grab frame")
                            break

                        # Resize to reduce bandwidth
                        frame = cv2.resize(frame, (640, 480))

                        # Compress image
                        _, buffer = cv2.imencode(
                            ".jpg",
                            frame,
                            [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY]
                        )

                        jpg_as_text = base64.b64encode(buffer).decode("utf-8")

                        # Simulated telemetry (you can replace with real data)
                        telemetry = {
                            "type": "FPV",
                            "battery": round(random.uniform(70, 100), 2),
                            "speed": f"{random.randint(300, 700)} mb/s",
                            "image": jpg_as_text
                        }

                        await websocket.send(json.dumps(telemetry))

                        await asyncio.sleep(FPS_DELAY)

                    except websockets.exceptions.ConnectionClosed:
                        print("⚠️ Connection closed by server")
                        break

                    except Exception as e:
                        print("⚠️ Frame send error:", e)
                        break

                cap.release()

        except Exception as e:
            print("❌ Connection error:", e)

        print(f"🔁 Reconnecting in {RECONNECT_DELAY} seconds...\n")
        await asyncio.sleep(RECONNECT_DELAY)


# ==============================
# ENTRY POINT
# ==============================
if __name__ == "__main__":
    try:
        asyncio.run(stream_fpv())
    except KeyboardInterrupt:
        print("\n🛑 FPV Streaming stopped by user")
        sys.exit(0)