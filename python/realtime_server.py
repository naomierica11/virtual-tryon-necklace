import cv2
import socket
import struct
import time
import numpy as np

# Load Haar Cascades
face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
eye_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_eye.xml')

# UDP Configuration
MAX_PACKET_SIZE = 65000  # Max UDP packet size
CHUNK_SIZE = 60000  # Safe chunk size for UDP

def detect_face_angle(eyes):
    if len(eyes) < 2:
        return 0.0
    eyes_sorted = sorted(eyes, key=lambda e: e[0])
    left_eye = eyes_sorted[0]
    right_eye = eyes_sorted[1]
    dx = right_eye[0] - left_eye[0]
    dy = right_eye[1] - left_eye[1]
    if dx == 0:
        return 0.0
    return np.degrees(np.arctan2(dy, dx))

def send_frame_udp(sock, addr, frame, face_data, angle, frame_id):
    """Send frame via UDP with chunking for large frames"""
    try:
        # Encode JPEG with lower quality for smaller size
        ret, jpg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
        if not ret:
            return False
        
        jpg_bytes = jpg.tobytes()
        jpg_size = len(jpg_bytes)
        
        # Pack face metadata
        has_face = 1 if face_data else 0
        fx = face_data[0] if face_data else 0
        fy = face_data[1] if face_data else 0
        fw = face_data[2] if face_data else 0
        fh = face_data[3] if face_data else 0
        
        # Calculate chunks needed
        num_chunks = (jpg_size + CHUNK_SIZE - 1) // CHUNK_SIZE
        
        # Send each chunk
        for chunk_idx in range(num_chunks):
            start_idx = chunk_idx * CHUNK_SIZE
            end_idx = min(start_idx + CHUNK_SIZE, jpg_size)
            chunk_data = jpg_bytes[start_idx:end_idx]
            chunk_len = len(chunk_data)
            
            # Packet header (40 bytes):
            # - frame_id (4) - unique frame identifier
            # - chunk_idx (4) - current chunk index
            # - num_chunks (4) - total chunks in frame
            # - chunk_len (4) - length of this chunk
            # - jpg_size (4) - total jpeg size
            # - has_face (4) - face detected flag
            # - face data (16) - fx, fy, fw, fh
            # - angle (4) - face rotation
            header = struct.pack('<IIIIIIiiiif',
                frame_id,       # frame ID
                chunk_idx,      # chunk index
                num_chunks,     # total chunks
                chunk_len,      # this chunk length
                jpg_size,       # total jpeg size
                has_face,       # has face flag
                fx, fy, fw, fh, # face rect
                angle           # angle
            )
            
            packet = header + chunk_data
            sock.sendto(packet, addr)
        
        return True
        
    except Exception as e:
        print(f"Send error: {e}")
        return False

def main():
    print("=" * 50)
    print("  UDP VERSION - Real-time Video Streaming")
    print("=" * 50)
    
    print("\n[1/3] Cascades...", end=" ")
    if face_cascade.empty():
        print("FAIL")
        return
    print("OK")
    
    print("[2/3] Camera...", end=" ")
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("FAIL")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240)
    cap.set(cv2.CAP_PROP_FPS, 15)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    print("OK (320x240)")
    
    print("[3/3] UDP Server...", end=" ")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        sock.bind(('127.0.0.1', 5006))
        sock.setblocking(False)  # Non-blocking mode
        print("OK (port 5006)")
    except Exception as e:
        print("FAIL:", e)
        return
    
    print("\n" + "=" * 50)
    print("Waiting for client to send 'START' message...")
    
    client_addr = None
    frame_id = 0
    
    # Wait for initial connection
    while client_addr is None:
        try:
            data, addr = sock.recvfrom(1024)
            if data == b'START':
                client_addr = addr
                print(f"Client connected: {addr}")
                sock.sendto(b'READY', addr)
        except BlockingIOError:
            time.sleep(0.1)
    
    frame_count = 0
    start_time = time.time()
    
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.05)
                continue
            
            # Resize
            frame = cv2.resize(frame, (320, 240))
            
            # Detect face
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = face_cascade.detectMultiScale(gray, 1.1, 3, minSize=(20, 20))
            
            face_data = None
            angle = 0.0
            
            if len(faces) > 0:
                x, y, w, h = faces[0]
                face_data = [int(x), int(y), int(w), int(h)]
                
                roi = gray[y:y+h, x:x+w]
                eyes = eye_cascade.detectMultiScale(roi)
                if len(eyes) >= 2:
                    eyes_full = [(x + ex, y + ey) for (ex, ey, ew, eh) in eyes]
                    angle = detect_face_angle(eyes_full)
            
            # Send frame
            send_frame_udp(sock, client_addr, frame, face_data, angle, frame_id)
            frame_id = (frame_id + 1) % 65536  # Wrap around
            
            frame_count += 1
            
            if frame_count % 45 == 0:
                elapsed = time.time() - start_time
                fps = frame_count / elapsed
                print(f"Frames: {frame_count} | FPS: {fps:.1f} | Face: {'YES' if face_data else 'NO'}")
            
            time.sleep(0.033)  # ~30 FPS target
            
    except KeyboardInterrupt:
        print("\n\nStopping...")
    except Exception as e:
        print(f"Error: {e}")
    
    sock.close()
    cap.release()
    print("Done")

if __name__ == "__main__":
    main()