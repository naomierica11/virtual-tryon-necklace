import cv2
import socket
import struct
import time
import numpy as np
from collections import deque

# Load Haar Cascades
face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
eye_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_eye.xml')

# UDP Configuration
MAX_PACKET_SIZE = 65000
CHUNK_SIZE = 60000

# Performance tracking
class PerformanceTracker:
    def __init__(self, window_size=30):
        self.frame_times = deque(maxlen=window_size)
        self.send_times = deque(maxlen=window_size)
        self.detection_times = deque(maxlen=window_size)
        
    def add_frame_time(self, t):
        self.frame_times.append(t)
        
    def add_send_time(self, t):
        self.send_times.append(t)
        
    def add_detection_time(self, t):
        self.detection_times.append(t)
        
    def get_avg_fps(self):
        if not self.frame_times:
            return 0
        return len(self.frame_times) / sum(self.frame_times)
    
    def get_stats(self):
        return {
            'fps': self.get_avg_fps(),
            'avg_send_ms': sum(self.send_times) / len(self.send_times) * 1000 if self.send_times else 0,
            'avg_detect_ms': sum(self.detection_times) / len(self.detection_times) * 1000 if self.detection_times else 0
        }

def detect_face_angle(eyes):
    """Calculate face rotation angle from eye positions"""
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

def enhance_frame(frame):
    """Apply image enhancements for better detection"""
    # Histogram equalization for better lighting
    lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
    l = clahe.apply(l)
    enhanced = cv2.merge([l, a, b])
    enhanced = cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)
    return enhanced

def send_frame_udp(sock, addr, frame, face_data, angle, frame_id):
    """Send frame via UDP with chunking"""
    try:
        # Encode JPEG
        encode_params = [
            cv2.IMWRITE_JPEG_QUALITY, 75,  # Slightly better quality
            cv2.IMWRITE_JPEG_OPTIMIZE, 1
        ]
        ret, jpg = cv2.imencode('.jpg', frame, encode_params)
        if not ret:
            return False, 0
        
        jpg_bytes = jpg.tobytes()
        jpg_size = len(jpg_bytes)
        
        # Pack face metadata
        has_face = 1 if face_data else 0
        fx = face_data[0] if face_data else 0
        fy = face_data[1] if face_data else 0
        fw = face_data[2] if face_data else 0
        fh = face_data[3] if face_data else 0
        
        # Calculate chunks
        num_chunks = (jpg_size + CHUNK_SIZE - 1) // CHUNK_SIZE
        
        # Send chunks
        start_time = time.time()
        for chunk_idx in range(num_chunks):
            start_idx = chunk_idx * CHUNK_SIZE
            end_idx = min(start_idx + CHUNK_SIZE, jpg_size)
            chunk_data = jpg_bytes[start_idx:end_idx]
            chunk_len = len(chunk_data)
            
            header = struct.pack('<IIIIIIiiiif',
                frame_id, chunk_idx, num_chunks, chunk_len, jpg_size,
                has_face, fx, fy, fw, fh, angle
            )
            
            packet = header + chunk_data
            sock.sendto(packet, addr)
        
        send_time = time.time() - start_time
        return True, send_time
        
    except Exception as e:
        print(f"❌ Send error: {e}")
        return False, 0

def main():
    print("=" * 60)
    print("  🚀 ENHANCED UDP VIDEO STREAMING SERVER")
    print("=" * 60)
    
    # Initialize cascades
    print("\n[1/4] Loading cascades...", end=" ")
    if face_cascade.empty() or eye_cascade.empty():
        print("❌ FAIL")
        return
    print("✓ OK")
    
    # Initialize camera
    print("[2/4] Initializing camera...", end=" ")
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("❌ FAIL")
        return
    
    # Camera settings
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240)
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    cap.set(cv2.CAP_PROP_AUTOFOCUS, 1)
    print(f"✓ OK (320x240 @ 30fps)")
    
    # Initialize UDP
    print("[3/4] Setting up UDP server...", end=" ")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)  # 1MB send buffer
    
    try:
        sock.bind(('127.0.0.1', 5006))
        sock.setblocking(False)
        print("✓ OK (port 5006)")
    except Exception as e:
        print(f"❌ FAIL: {e}")
        return
    
    # Performance tracker
    print("[4/4] Initializing performance tracker...", end=" ")
    perf = PerformanceTracker()
    print("✓ OK")
    
    print("\n" + "=" * 60)
    print("⏳ Waiting for client connection...")
    print("   Client should send 'START' message to begin streaming")
    print("=" * 60 + "\n")
    
    client_addr = None
    frame_id = 0
    
    # Wait for connection
    while client_addr is None:
        try:
            data, addr = sock.recvfrom(1024)
            if data == b'START':
                client_addr = addr
                print(f"✓ Client connected: {addr[0]}:{addr[1]}")
                sock.sendto(b'READY', addr)
                print("✓ Sent READY confirmation\n")
        except BlockingIOError:
            time.sleep(0.1)
    
    frame_count = 0
    face_detected_count = 0
    last_stats_time = time.time()
    
    print("🎬 Streaming started! Press Ctrl+C to stop.\n")
    
    try:
        while True:
            frame_start = time.time()
            
            # Capture frame
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.01)
                continue
            
            # Resize
            frame = cv2.resize(frame, (320, 240))
            
            # Enhance for better detection (optional, can be disabled for performance)
            # frame = enhance_frame(frame)
            
            # Face detection
            detect_start = time.time()
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            faces = face_cascade.detectMultiScale(
                gray, 
                scaleFactor=1.1, 
                minNeighbors=4,  # Slightly more lenient
                minSize=(30, 30),
                flags=cv2.CASCADE_SCALE_IMAGE
            )
            detect_time = time.time() - detect_start
            perf.add_detection_time(detect_time)
            
            face_data = None
            angle = 0.0
            
            if len(faces) > 0:
                # Get largest face
                largest_face = max(faces, key=lambda f: f[2] * f[3])
                x, y, w, h = largest_face
                face_data = [int(x), int(y), int(w), int(h)]
                face_detected_count += 1
                
                # Eye detection for angle
                roi = gray[y:y+h, x:x+w]
                eyes = eye_cascade.detectMultiScale(roi, scaleFactor=1.1, minNeighbors=3)
                
                if len(eyes) >= 2:
                    eyes_full = [(x + ex, y + ey) for (ex, ey, ew, eh) in eyes]
                    angle = detect_face_angle(eyes_full)
            
            # Send frame
            success, send_time = send_frame_udp(sock, client_addr, frame, face_data, angle, frame_id)
            if success:
                perf.add_send_time(send_time)
            
            frame_id = (frame_id + 1) % 65536
            frame_count += 1
            
            # Frame timing
            frame_time = time.time() - frame_start
            perf.add_frame_time(frame_time)
            
            # Print stats every 3 seconds
            if time.time() - last_stats_time >= 3.0:
                stats = perf.get_stats()
                face_rate = (face_detected_count / frame_count * 100) if frame_count > 0 else 0
                
                print(f"📊 Frames: {frame_count:5d} | "
                      f"FPS: {stats['fps']:5.1f} | "
                      f"Face: {face_rate:4.1f}% | "
                      f"Send: {stats['avg_send_ms']:5.1f}ms | "
                      f"Detect: {stats['avg_detect_ms']:4.1f}ms")
                
                last_stats_time = time.time()
            
            # Target frame rate control
            target_frame_time = 1.0 / 30  # 30 FPS target
            sleep_time = target_frame_time - frame_time
            if sleep_time > 0:
                time.sleep(sleep_time)
            
    except KeyboardInterrupt:
        print("\n\n⏹ Stopping server...")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Cleanup
        sock.close()
        cap.release()
        
        # Final stats
        print("\n" + "=" * 60)
        print("📈 FINAL STATISTICS")
        print("=" * 60)
        stats = perf.get_stats()
        print(f"Total Frames:     {frame_count}")
        print(f"Average FPS:      {stats['fps']:.2f}")
        print(f"Face Detection:   {face_detected_count} ({face_detected_count/frame_count*100:.1f}%)")
        print(f"Avg Send Time:    {stats['avg_send_ms']:.2f}ms")
        print(f"Avg Detect Time:  {stats['avg_detect_ms']:.2f}ms")
        print("=" * 60)
        print("✓ Server closed cleanly\n")

if __name__ == "__main__":
    main()