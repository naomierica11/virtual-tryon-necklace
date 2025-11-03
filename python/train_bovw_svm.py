# python/train_bovw_svm.py
"""
Train a BoVW + LinearSVC face/non-face classifier.

Usage:
python train_bovw_svm.py --pos_dir data/faces --neg_dir data/non_faces --k 256 --out_dir models
"""
import argparse, glob, cv2, numpy as np
from sklearn.svm import LinearSVC
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split, GridSearchCV
from sklearn.metrics import classification_report, confusion_matrix
from joblib import dump
from pathlib import Path
from features_bovw import Codebook

def load_images(folder, label):
    folder = Path(folder)
    patterns = ["**/*.jpg", "**/*.jpeg", "**/*.png", "**/*.bmp"]
    paths = []
    for pat in patterns:
        paths += list(folder.glob(pat))
    return [(str(p), label) for p in paths]

def orb_desc(img_gray, max_kp=500):
    orb = cv2.ORB_create(nfeatures=max_kp)
    kps, des = orb.detectAndCompute(img_gray, None)
    return des

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pos_dir", required=True, help="folder containing positive (face) images/crops")
    ap.add_argument("--neg_dir", required=True, help="folder containing negative (non-face) images")
    ap.add_argument("--k", type=int, default=256, help="codebook size")
    ap.add_argument("--out_dir", default="models", help="output directory for artifacts")
    args = ap.parse_args()

    out_dir = Path(args.out_dir); out_dir.mkdir(parents=True, exist_ok=True)

    data = load_images(args.pos_dir, 1) + load_images(args.neg_dir, 0)
    if not data:
        print("No images found. Please populate pos/neg folders."); return

    X_desc = []; y = []
    for p, lb in data:
        img = cv2.imread(p, cv2.IMREAD_GRAYSCALE)
        if img is None:
            continue
        img = cv2.resize(img, (128,128))
        des = orb_desc(img)
        X_desc.append(des); y.append(lb)

    # Build codebook
    cb = Codebook(k=args.k).fit(X_desc)

    # Encode BoVW
    X = np.vstack([cb.encode(d) for d in X_desc])
    y = np.array(y, dtype=np.int32)

    # Scale + SVM
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)
    scaler = StandardScaler(with_mean=False).fit(Xtr)
    Xtr_s, Xte_s = scaler.transform(Xtr), scaler.transform(Xte)

    grid = {"C":[0.1, 1.0, 3.0]}
    clf = GridSearchCV(LinearSVC(), grid, cv=5, n_jobs=-1, verbose=0)
    clf.fit(Xtr_s, ytr)
    ypr = clf.predict(Xte_s)

    print("Best C:", clf.best_params_)
    print(classification_report(yte, ypr))
    print("Confusion matrix:\n", confusion_matrix(yte, ypr))

    # Save artifacts
    import joblib
    joblib.dump(cb.km, out_dir / "codebook.pkl")
    joblib.dump(scaler, out_dir / "scaler.pkl")
    joblib.dump(clf.best_estimator_, out_dir / "svm.pkl")
    print("Saved artifacts to", out_dir)

if __name__ == "__main__":
    main()
