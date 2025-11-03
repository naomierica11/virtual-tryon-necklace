# python/features_bovw.py
import numpy as np
from sklearn.cluster import KMeans

class Codebook:
    def __init__(self, k=256, random_state=42):
        self.k = k
        self.km = KMeans(n_clusters=k, n_init=10, random_state=random_state)

    def fit(self, descs):
        """
        descs: list of ORB descriptor arrays (Ni x 32), possibly containing None.
        Builds a k-means codebook on the stacked descriptors.
        """
        X = np.vstack([d for d in descs if d is not None and len(d) > 0])
        self.km.fit(X)
        return self

    def encode(self, desc):
        """
        Convert ORB descriptor array (M x 32) into a normalized BoVW histogram (k,).
        If desc is None or empty, return a uniform histogram.
        """
        if desc is None or len(desc) == 0:
            h = np.ones(self.k, dtype=np.float32) / float(self.k)
            return h
        idx = self.km.predict(desc)
        h, _ = np.histogram(idx, bins=np.arange(self.k+1))
        h = h.astype(np.float32)
        h /= (h.sum() + 1e-6)
        return h

    def save(self, path:str):
        import joblib
        joblib.dump(self.km, path)

    def load(self, path:str):
        import joblib
        self.km = joblib.load(path)
        self.k = self.km.n_clusters
        return self
