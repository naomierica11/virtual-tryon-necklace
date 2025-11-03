# python/utils.py
import cv2, numpy as np, os
from typing import Tuple

def _cascade_path_default(name: str) -> str:
    # Prefer local 'cascades' folder; fallback to OpenCV's built-in data path
    local = os.path.join(os.path.dirname(__file__), "cascades", name)
    if os.path.exists(local):
        return local
    return os.path.join(cv2.data.haarcascades, name)

def load_cascades(base: str = None):
    if base is None:
        face_path = _cascade_path_default("haarcascade_frontalface_default.xml")
        eye_path  = _cascade_path_default("haarcascade_eye.xml")
    else:
        face_path = os.path.join(base, "haarcascade_frontalface_default.xml")
        eye_path  = os.path.join(base, "haarcascade_eye.xml")
    face = cv2.CascadeClassifier(face_path)
    eye  = cv2.CascadeClassifier(eye_path)
    return face, eye

def nms(boxes, scores, iou_thr=0.3):
    if len(boxes)==0: return []
    boxes = np.array(boxes, dtype=np.float32)
    scores = np.array(scores, dtype=np.float32)
    x1,y1,w,h = boxes[:,0], boxes[:,1], boxes[:,2], boxes[:,3]
    x2, y2 = x1+w, y1+h
    order = scores.argsort()[::-1]
    keep = []
    while order.size > 0:
        i = order[0]
        keep.append(i)
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        inter = np.maximum(0, xx2-xx1) * np.maximum(0, yy2-yy1)
        area_i = (x2[i]-x1[i])*(y2[i]-y1[i])
        area_j = (x2[order[1:]]-x1[order[1:]])*(y2[order[1:]]-y1[order[1:]])
        iou = inter / (area_i + area_j - inter + 1e-6)
        inds = np.where(iou <= iou_thr)[0]
        order = order[inds + 1]
    return keep

def eye_angle(gray, face_rect, eye_cascade) -> float:
    if face_rect is None:
        return 0.0
    x,y,w,h = face_rect
    roi = gray[y:y+h, x:x+w]
    eyes = eye_cascade.detectMultiScale(roi, 1.1, 3, minSize=(15,15))
    if len(eyes) >= 2:
        e = sorted(eyes, key=lambda a:a[0])[:2]
        p1 = (x+e[0][0]+e[0][2]//2, y+e[0][1]+e[0][3]//2)
        p2 = (x+e[1][0]+e[1][2]//2, y+e[1][1]+e[1][3]//2)
        ang = np.degrees(np.arctan2(p2[1]-p1[1], p2[0]-p1[0]))
        return float(ang)
    return 0.0
