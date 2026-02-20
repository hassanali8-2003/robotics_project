import asyncio
import websockets
import json
import cv2
import base64
import random

async def stream_data():
    # Use your PC's local IP where server.js is running
    uri = "ws://172.23.200.150:8080"

    async with websockets.connect(uri) as websocket:
        cap = cv2.VideoCapture(0) # Open Front Cam
        print("Streaming started...")

        while True:
            ret, frame = cap.read()
            if not ret: break

            # 1. Encode Video Frame to Base64 (Simple streaming method)
            _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 50])
            jpg_as_text = base64.b64encode(buffer).decode('utf-8')

            # 2. Generate Mock Telemetry
            telemetry = {
                "type": "DATA",
                "battery": round(random.uniform(70.0, 85.0), 1),
                "speed": f"{random.randint(400, 600)} mb/s",
                "image": jpg_as_text
            }

            await websocket.send(json.dumps(telemetry))
            await asyncio.sleep(0.05) # ~20 FPS

        cap.release()

asyncio.get_event_loop().run_until_complete(stream_data())