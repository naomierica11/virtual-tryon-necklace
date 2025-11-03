# 💎 Virtual Try-On: Necklace Edition

Real-time virtual try-on system untuk kalung menggunakan webcam. Project ini menggabungkan **Godot 4** (rendering), **Python OpenCV** (face detection), dan **SVM + BoVW** (machine learning).

![Demo](assets/demo.gif)
*Screenshot demo akan ditambahkan*

---

## ✨ Features

- ✅ **Real-time face detection** menggunakan Haar Cascade + SVM verification
- ✅ **5 pilihan kalung** yang bisa di-switch dengan keyboard (1-5)
- ✅ **Auto-positioning** kalung menggunakan face bounding box
- ✅ **Head tilt detection** menggunakan eye angle calculation
- ✅ **Screenshot feature** (tekan S untuk save)
- ✅ **FPS counter** dan live debugging info

---

## 🏗️ Architecture

```
┌─────────────────┐         TCP Socket          ┌──────────────────┐
│  Python Server  │ ◄───────────────────────► │  Godot Client    │
│  (OpenCV)       │   [JSON Meta + JPEG Frame]  │  (Rendering)     │
└─────────────────┘                             └──────────────────┘
        │                                                │
        ├─ Webcam capture (640x480)                    ├─ Display video
        ├─ Haar Cascade (fast proposal)                ├─ Overlay necklace
        ├─ SVM + BoVW (verification)                   ├─ Handle keyboard input
        └─ Eye angle detection                         └─ Screenshot capture
```

---

## 📦 Installation

### Requirements

- **Python 3.8+** dengan virtual environment
- **Godot 4.x** (tested on 4.2+)
- **Webcam**

### Python Dependencies

```bash
cd python
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### Godot Setup

1. Download Godot 4 dari [godotengine.org](https://godotengine.org/)
2. Buka project di folder `godot/`
3. Import assets kalung ke `assets/necklaces/` (format PNG dengan background transparan)

---

## 🚀 Usage

### 1. Train SVM Model (Optional - sudah ada pre-trained model)

```bash
cd python
python train_bovw_svm.py \
  --pos_dir data/faces \
  --neg_dir data/non_faces \
  --k 256 \
  --out_dir models
```

**Training results:**
- Accuracy: 91%
- Precision (Face): 95%
- Recall (Face): 94%

### 2. Run Python Server

```bash
cd python
python realtime_server.py
```

Output:
```
[Python] ✓ Haar cascades loaded
[Python] ✓ Models loaded | Codebook: 256 clusters
[Python] ✓ Camera 0 opened
[Python] Waiting for Godot on 127.0.0.1:5006...
```

### 3. Run Godot Client

- Open Godot Editor
- Press **F5** to run the scene
- HUD di kiri atas akan menunjukkan status koneksi

---

## 🎮 Controls

| Key | Action |
|-----|--------|
| **1-5** | Switch kalung (Necklace 1-5) |
| **H** | Hide/Show kalung |
| **S** | Screenshot (disimpan ke `user://`) |
| **Q** | Quit (di test window) |

---

## 📁 Project Structure

```
vtoneck/
├── python/
│   ├── realtime_server.py      # Main server (TCP + face detection)
│   ├── train_bovw_svm.py       # SVM training script
│   ├── features_bovw.py        # BoVW feature extraction
│   ├── test_haar_detection.py  # Testing tool
│   ├── models/
│   │   ├── svm.pkl             # Trained SVM classifier
│   │   ├── scaler.pkl          # Feature scaler
│   │   └── codebook.pkl        # BoVW codebook (256 clusters)
│   ├── data/
│   │   ├── faces/              # Positive samples
│   │   └── non_faces/          # Negative samples
│   └── requirements.txt
├── godot/
│   ├── scenes/
│   │   └── Main.tscn           # Main scene
│   ├── scripts/
│   │   ├── VideoClient.gd      # TCP client + video display
│   │   └── AccessoryController.gd  # Necklace overlay logic
│   ├── assets/
│   │   └── necklaces/          # Necklace PNG assets
│   └── project.godot
└── README.md
```

---

## 🔬 Technical Details

### Face Detection Pipeline

1. **Haar Cascade** → Fast proposal (30+ FPS)
2. **ORB Descriptors** → Extract 500 keypoints from 128x128 face crop
3. **BoVW Encoding** → Quantize to 256-word codebook histogram
4. **StandardScaler** → Normalize features
5. **LinearSVC** → Binary classification (face/non-face)

### Network Protocol

**Packet format:**
```
[meta_len: u32][jpg_len: u32][meta: JSON][jpg: bytes]
```

**Meta JSON:**
```json
{
  "w": 640,
  "h": 480,
  "face": [x, y, w, h],  // null if no face
  "angle": 0.0           // head tilt in degrees
}
```

### Necklace Positioning Algorithm

```gdscript
# Scale: 45% dari lebar wajah
var w_target = face_width * 0.45

# Position: 60% dari tinggi wajah (area leher)
var y = face_y + face_height * 0.60
```

---

## 🐛 Troubleshooting

### Python server tidak bisa buka kamera
```bash
# Coba kamera index berbeda
python realtime_server.py  # cam=0 (default)
# Edit main() di script jadi cam=1 atau cam=2
```

### Godot stuck di "Connecting..."
- Pastikan Python server jalan **dulu** sebelum Godot
- Check firewall tidak block port 5006
- Restart kedua aplikasi

### Face tidak terdeteksi
```python
# Disable SVM verification (lebih cepat, less accurate)
main(cam=0, use_svm_verification=False)
```

### FPS rendah
- Pakai mode Haar-only (set `use_svm_verification=False`)
- Kurangi resolusi kamera ke 320x240
- Increase stride di sliding window detection

---

## 📊 Performance

| Mode | FPS | Accuracy |
|------|-----|----------|
| **Haar only** | ~30 | Medium |
| **Haar + SVM verify** | ~11-15 | High |

*Tested on: Intel i5-8250U, 8GB RAM, Webcam 640x480*

---

## 🎓 Academic Context

Project ini dibuat untuk **Mata Kuliah Pengolahan Citra Digital** Semester 5.

**Dosen:** [Nama Dosen]  
**Universitas:** [Nama Universitas]  
**Tahun:** 2024/2025

---

## 📝 TODO

- [ ] Add more necklace designs
- [ ] Implement color customization
- [ ] Add earring support
- [ ] Web-based interface (replace Godot with HTML5)
- [ ] Better lighting compensation
- [ ] Multi-face support

---

## 📄 License

MIT License - feel free to use for educational purposes!

---

## 🙏 Credits

- **OpenCV** - Computer vision library
- **Godot Engine** - Game engine untuk rendering
- **scikit-learn** - Machine learning library
- **Haar Cascades** - Face detection classifier

---

## 📧 Contact

Nama: [Nama Kamu]  
Email: [Email Kamu]  
GitHub: [@username](https://github.com/username)

---

**⭐ Star this repo if you find it useful!**
