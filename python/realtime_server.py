"""
Realtime webcam streamer dengan hybrid detection:
1. Haar Cascade untuk proposal (fast)
2. ORB BoVW + SVM untuk verification (accurate)
"""
import cv2
import json
import socket
import struct
import time
import numpy as np
import os
from pathlib import Path
import joblib

HOST, PORT = "127.0.0.1", 5006

def load_haar_cascades():
    """Load Haar Cascade classifiers"""
    face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
    eye_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_eye.xml')
    return face_cascade, eye_cascade

def load_svm_models(model_dir="models"):
    """Load trained SVM model, scaler, dan codebook"""
    print("[Python] Loading SVM models...")
    
    svm = joblib.load(Path(model_dir) / "svm.pkl")
    scaler = joblib.load(Path(model_dir) / "scaler.pkl")
    codebook_km = joblib.load(Path(model_dir) / "codebook.pkl")
    
    print(f"[Python] ✓ Models loaded | Codebook: {codebook_km.n_clusters} clusters")
    return svm, scaler, codebook_km

def orb_desc(img_gray, max_kp=500):
    """Extract ORB descriptors"""
    orb = cv2.ORB_create(nfeatures=max_kp)
    kps, des = orb.detectAndCompute(img_gray, None)
    return des

def encode_bovw(desc, codebook_km):
    """
    Convert ORB descriptor array into normalized BoVW histogram
    """
    k = codebook_km.n_clusters
    
    if desc is None or len(desc) == 0:
        # Return uniform histogram if no features
        h = np.ones(k, dtype=np.float32) / float(k)
        return h
    
    # Predict cluster assignments
    idx = codebook_km.predict(desc)
    
    # Build histogram
    h, _ = np.histogram(idx, bins=np.arange(k + 1))
    h = h.astype(np.float32)
    h /= (h.sum() + 1e-6)
    
    return h

def verify_face_with_svm(window, svm, scaler, codebook_km):
    """
    Verify apakah window adalah face menggunakan SVM
    Returns: (is_face: bool, confidence: float)
    """
    # Resize to training size (128x128)
    window_resized = cv2.resize(window, (128, 128))
    
    # Extract ORB descriptors
    desc = orb_desc(window_resized)
    
    if desc is None or len(desc) < 5:
        return False, 0.0
    
    # Encode to BoVW histogram
    hist = encode_bovw(desc, codebook_km)
    hist = hist.reshape(1, -1)
    
    # Scale
    hist_scaled = scaler.transform(hist)
    
    # Predict
    pred = svm.predict(hist_scaled)[0]
    confidence = svm.decision_function(hist_scaled)[0]
    
    return (pred == 1), float(confidence)

def eye_angle(gray, face_rect, eye_cascade):
    """Calculate head angle based on eye positions"""
    if face_rect is None:
        return 0.0
    
    x, y, w, h = face_rect
    roi = gray[y:y+h, x:x+w]
    eyes = eye_cascade.detectMultiScale(roi, 1.1, 3, minSize=(15, 15))
    
    if len(eyes) >= 2:
        # Sort by x position
        eyes = sorted(eyes, key=lambda e: e[0])[:2]
        
        # Calculate eye centers
        p1 = (x + eyes[0][0] + eyes[0][2]//2, y + eyes[0][1] + eyes[0][3]//2)
        p2 = (x + eyes[1][0] + eyes[1][2]//2, y + eyes[1][1] + eyes[1][3]//2)
        
        # Calculate angle
        ang = np.degrees(np.arctan2(p2[1] - p1[1], p2[0] - p1[0]))
        return float(ang)
    
    return 0.0

def nms(boxes, scores, iou_threshold=0.3):
    """Non-Maximum Suppression"""
    if len(boxes) == 0:
        return []
    
    boxes = np.array(boxes, dtype=np.float32)
    scores = np.array(scores, dtype=np.float32)
    
    x1 = boxes[:, 0]
    y1 = boxes[:, 1]
    x2 = boxes[:, 0] + boxes[:, 2]
    y2 = boxes[:, 1] + boxes[:, 3]
    
    order = scores.argsort()[::-1]
    keep = []
    
    while order.size > 0:
        i = order[0]
        keep.append(i)
        
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        
        inter = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1)
        area_i = (x2[i] - x1[i]) * (y2[i] - y1[i])
        area_j = (x2[order[1:]] - x1[order[1:]]) * (y2[order[1:]] - y1[order[1:]])
        iou = inter / (area_i + area_j - inter + 1e-6)
        
        inds = np.where(iou <= iou_threshold)[0]
        order = order[inds + 1]
    
    return keep

def send_packet(conn, meta: dict, frame_bgr):
    """Send meta + JPEG frame to Godot"""
    ok, buf = cv2.imencode(".jpg", frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, 70])
    if not ok:
        return
    
    meta_bytes = json.dumps(meta).encode("utf-8")
    conn.sendall(struct.pack("!II", len(meta_bytes), len(buf)))
    conn.sendall(meta_bytes)
    conn.sendall(buf)

def main(cam=0, use_svm_verification=True):
    # Load Haar cascades
    face_cascade, eye_cascade = load_haar_cascades()
    print("[Python] ✓ Haar cascades loaded")
    
    # Load SVM models (optional)
    svm, scaler, codebook_km = None, None, None
    if use_svm_verification:
        try:
            svm, scaler, codebook_km = load_svm_models("models")
        except Exception as e:
            print(f"[WARNING] Failed to load SVM models: {e}")
            print("[Python] Falling back to Haar-only detection")
            use_svm_verification = False
    
    # Open webcam
    cap = cv2.VideoCapture(cam)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    
    if not cap.isOpened():
        print(f"[ERROR] Cannot open camera {cam}")
        return
    
    print(f"[Python] ✓ Camera {cam} opened")
    
    # Setup TCP server
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(1)
    print(f"[Python] Waiting for Godot on {HOST}:{PORT}...")
    
    conn, addr = srv.accept()
    print(f"[Python] ✓ Godot connected from {addr}")
    
    # FPS counter
    t0, frame_count = time.time(), 0
    detect_count = 0
    
    while True:
        ok, frame = cap.read()
        if not ok:
            print("[Python] Failed to read frame")
            break
        
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # Step 1: Fast proposal with Haar Cascade
        faces = face_cascade.detectMultiScale(gray, 1.1, 4, minSize=(80, 80))
        
        # Convert to list format
        boxes = []
        scores = []
        for (x, y, w, h) in faces:
            boxes.append([int(x), int(y), int(w), int(h)])
            scores.append(float(w * h))  # Initial score = area
        
        # Step 2: Verify with SVM (if enabled) - ONLY verify largest box
        svm_status = ""
        if use_svm_verification and boxes:
            # Only verify the largest face (fastest)
            largest_idx = np.argmax(scores)
            box = boxes[largest_idx]
            x, y, w, h = box
            
            # Extract face region
            face_region = gray[y:y+h, x:x+w]
            
            # Verify with SVM
            is_face, confidence = verify_face_with_svm(face_region, svm, scaler, codebook_km)
            
            svm_status = f"| SVM: conf={confidence:.2f} pred={'FACE' if is_face else 'NOT'}"
            
            # LOWERED THRESHOLD untuk testing
            if is_face and confidence > -0.5:  # THRESHOLD RENDAH DULU
                boxes = [box]
                scores = [confidence]
            else:
                boxes = []
                scores = []
        
        # Apply NMS
        face = None
        if boxes:
            keep = nms(boxes, scores, 0.3)
            if keep:
                # Get best face (highest score)
                best_idx = keep[np.argmax([scores[i] for i in keep])]
                face = boxes[best_idx]
                detect_count += 1
        
        # Calculate eye angle
        ang = eye_angle(gray, face, eye_cascade) if face is not None else 0.0
        
        # Prepare metadata
        meta = {
            "w": int(frame.shape[1]),
            "h": int(frame.shape[0]),
            "face": face,
            "angle": float(ang)
        }
        
        # Send to Godot
        try:
            send_packet(conn, meta, frame)
        except (BrokenPipeError, ConnectionResetError):
            print("[Python] Godot disconnected")
            break
        
        frame_count += 1
        if time.time() - t0 >= 1.0:
            mode = "Haar+SVM" if use_svm_verification else "Haar only"
            face_status = "✓ FACE" if face else "✗ no face"
            haar_proposals = len(faces)  # Berapa face yang diusulkan Haar
            print(f"[Python] FPS: {frame_count:2d} | Mode: {mode:10s} | {face_status} | Haar proposals: {haar_proposals} {svm_status}")
            frame_count = 0
            t0 = time.time()
            svm_status = ""  # Reset status
    
    cap.release()
    conn.close()
    srv.close()
    print("[Python] Server closed")

if __name__ == "__main__":
    # TESTING MODE: Disable SVM untuk cek apakah Haar bisa detect
    print("="*50)
    print("RUNNING IN HAAR-ONLY MODE FOR TESTING")
    print("="*50)
    main(cam=0, use_svm_verification=False)