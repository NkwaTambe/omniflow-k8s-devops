# Log Anomaly Detection with Loglizer

## AI Anomaly Detection Course — Project Presentation

---

## 1. What Problem Are We Solving?

Traditional monitoring (Prometheus, Grafana) uses **threshold-based alerts**:

> "Alert when CPU > 80%" or "Alert when pod restarts > 3 times"

These work for **known** problems. But what about **unknown** problems — the pod whose logs look *weird* even though no single metric crossed a threshold?

**Log anomaly detection** answers: *"Does this log session look like normal behavior or not?"*

| Traditional Monitoring | Log Anomaly Detection |
|---|---|
| Checks individual metrics | Checks patterns across events |
| Threshold-based (CPU > 80%) | ML-based (pattern deviation) |
| Catches known failures | Catches unknown failures |
| "Something is high" | "Something is unusual" |

---

## 2. What Is an Anomaly?

In log analysis, an **anomaly** is a log session whose **event pattern** deviates significantly from what normal sessions look like.

**Normal session** (a healthy HDFS block):
```
E5, E22, E5, E11, E9, E11, E9, E26, E26
```
→ Predictable pattern. Same event types appear in consistent ratios.

**Anomalous session** (a failing HDFS block):
```
E5, E22, E5, E5, E26, E26, E26, E2, E2
```
→ Unexpected events (E2), unusual ratios (E26 appears 3× instead of 2×).

It's not about "there's an ERROR line." It's about **the combination and distribution of events being unusual**.

---

## 3. Loglizer Architecture

Loglizer is an open-source ML toolkit by the LogPAI team (CUHK), published alongside the paper *"Experience Report: System Log Analysis for Anomaly Detection"* (ISSRE 2016, Most Influential Paper award).

### 3.1 The Pipeline

```
┌─────────────┐    ┌──────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Raw Logs    │───▶│  Log Parser   │───▶│  Feature         │───▶│  ML Models      │
│  (unstructured)│   │  (Drain)      │    │  Extraction      │    │  (9 algorithms)  │
└─────────────┘    └──────────────┘    └──────────────────┘    └─────────────────┘
```

Each stage transforms the data:

### Stage 1: Raw Logs → Structured Events (Log Parser)

Raw log text is parsed into **event templates** with parameters replaced by `<*>`:

```
Before: "PacketResponder 1 for block blk_-1608999687919862906 terminating"
After:  EventTemplate = "PacketResponder <*> for block <*> terminating"
        EventId = E5
```

Two different log lines with different parameters map to the **same event template**. This is done by the Drain algorithm (in `logparser`, a separate tool).

### Stage 2: Structured Events → Session Vectors (Data Loader)

All events belonging to the same session (e.g., one HDFS block, one K8s pod lifecycle) are grouped and counted:

```
Session blk_123: [E5, E22, E5, E11, E9, E11, E9, E26, E26]
                ↓
Count vector:    E5=2, E9=2, E11=2, E22=1, E26=2, everything else=0
```

This is implemented in `dataloader.py` — the `load_HDFS()` function:
1. Reads the structured CSV
2. Groups lines by block ID (regex: `blk_-?\d+`)
3. Creates an `EventSequence` for each block
4. Splits into train/test sets

### Stage 3: Count Vectors → Feature Vectors (FeatureExtractor)

The `FeatureExtractor` class in `preprocessing.py` transforms count vectors:

1. **Event Counting**: `Counter()` tallies each event type per session
2. **TF-IDF Weighting** (optional): Rare events get higher weight
   ```
   idf(event) = log(N / (df + ε))    where df = number of sessions containing this event
   weighted_count = raw_count × idf
   ```
3. **Normalization** (optional): Zero-mean centering
   ```
   X_normalized = X - mean(X)
   ```

Result: A numeric matrix of shape `(num_sessions × num_event_types)` ready for ML.

### Stage 4: Feature Vectors → Anomaly Detection (ML Models)

Nine models are implemented. We use three **unsupervised** ones (no labels needed):

#### 3.2.1 PCA (Principal Component Analysis)

**Reference**: Xu et al., SOSP 2009 — *"Large-Scale System Problems Detection by Mining Console Logs"*

**How it works**:
1. Compute the covariance matrix of the feature vectors
2. Perform SVD to find principal components (directions of most variance)
3. Keep the top-k components that explain 95% of variance → this is the "normal subspace"
4. For each test session, project it onto the **abnormal subspace** (everything outside the normal subspace)
5. Compute SPE (Squared Prediction Error) = `||C × x||²` where C is the projection matrix
6. If SPE > threshold → anomaly

**Key insight**: Normal sessions cluster in a low-dimensional subspace. Anomalous sessions have large components outside this subspace.

```
Normal subspace (P)          Abnormal subspace (C = I - P×Pᵀ)
  ┌──────────┐                  ┌──────────┐
  │ 95% of   │                  │ 5% of    │
  │ variance │                  │ variance │
  │ = normal│                  │ = anomaly│
  └──────────┘                  └──────────┘
```

The threshold is computed using Q-statistics with a configurable significance level (`c_alpha`).

#### 3.2.2 Isolation Forest

**Reference**: Liu et al., ICDM 2008 — *"Isolation Forest"*

**How it works**:
1. Build an ensemble of random binary trees
2. At each node, randomly pick a feature and a split value
3. Anomalies are **easy to isolate** — they reach leaf nodes in few splits (short path length)
4. Normal points require many splits to isolate (long path length)
5. Anomaly score = inverse of average path length across all trees

**Key insight**: Anomalies are "few and different" — they sit in sparse regions, so random cuts isolate them quickly.

```
Normal point:  ████████████████ (many splits needed)
Anomaly:       ██ (isolated quickly)
```

#### 3.2.3 Invariants Mining

**Reference**: Lou et al., ATC 2010 — *"Mining Invariants from Console Logs for System Problem Detection"*

**How it works**:
1. Estimate the dimension of the "invariant space" using SVD
2. Search for **linear invariants** — relationships between event counts that always hold in normal data
3. Example invariant: `E11 - E9 = 0` (meaning E11 and E9 always appear the same number of times)
4. For each test session, check if all invariants hold
5. If any invariant is violated → anomaly

**Key insight**: Normal system behavior follows rules (invariants). When something breaks, the rules are violated.

```
Normal:  E11=3, E9=3  →  E11 - E9 = 0  ✓ (invariant holds)
Anomaly: E11=3, E9=1  →  E11 - E9 = 2  ✗ (invariant violated)
```

### 3.3 Model Comparison

| Model | Type | How It Detects | Best For |
|---|---|---|---|
| **PCA** | Unsupervised | Large reconstruction error in abnormal subspace | Subtle pattern shifts |
| **Isolation Forest** | Unsupervised | Short path length in random trees | Point anomalies |
| **Invariants Mining** | Unsupervised | Violation of linear rules between events | Systems with strong regularity |

---

## 4. Our Integration Architecture

### 4.1 What We Built

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Actions CI/CD                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  anomaly-detection.yml                                  │   │
│  │  1. Checkout code                                        │   │
│  │  2. Setup Python 3.11                                    │   │
│  │  3. Install dependencies (scikit-learn, pandas, etc.)    │   │
│  │  4. Run demo.py                                          │   │
│  │     ├── Downloads HDFS dataset from logpai/loglizer      │   │
│  │     ├── Loads & structures data (dataloader.py)          │   │
│  │     ├── Extracts features (preprocessing.py)              │   │
│  │     ├── Trains PCA, Isolation Forest, Invariants Mining  │   │
│  │     └── Outputs comparison table                         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 File Structure

```
anomaly-detection/
├── demo.py                    ← Main pipeline script (8 steps)
├── requirements.txt           ← 5 Python dependencies
└── loglizer/                  ← Bundled loglizer package
    ├── __init__.py
    ├── dataloader.py          ← Loads & groups logs into sessions
    ├── preprocessing.py       ← FeatureExtractor (TF-IDF, normalization)
    ├── utils.py               ← Evaluation metrics
    └── models/
        ├── PCA.py             ← PCA anomaly detection
        ├── IsolationForest.py ← Isolation Forest
        ├── InvariantsMiner.py← Invariants Mining
        ├── DecisionTree.py   ← (supervised, not used in demo)
        ├── LR.py             ← (supervised, not used in demo)
        ├── SVM.py            ← (supervised, not used in demo)
        └── LogClustering.py  ← (unsupervised, not used in demo)
```

### 4.3 The Demo Pipeline (Step by Step)

```
Step 1: Show raw structured logs
        └── "PacketResponder 1 for block blk_123 terminating" → EventId E5

Step 2: Explain what anomaly means
        └── 97.1% Normal, 2.9% Anomaly in HDFS dataset

Step 3: Group logs into sessions
        └── All events for one block ID → one session

Step 4: Create feature vectors
        └── Session → count vector → TF-IDF → zero-mean normalization
        └── Result: 3969 sessions × 14 event types

Step 5: PCA (unsupervised)
        └── Learns normal subspace, flags large reconstruction errors

Step 6: Isolation Forest (unsupervised)
        └── Isolates anomalies by random partitioning

Step 7: Invariants Mining (unsupervised)
        └── Discovers linear rules, flags violations

Step 8: Compare models
        └── Isolation Forest wins: P=0.99, R=0.43, F1=0.60
```

### 4.4 Results on HDFS Dataset

| Model | Precision | Recall | F1 | What It Means |
|---|---|---|---|---|
| **PCA** | 0.966 | 0.363 | 0.528 | When it flags something, it's almost always right. But it misses 64% of anomalies. |
| **Isolation Forest** | 0.985 | 0.427 | 0.596 | Best balance — catches 43% of anomalies with 99% precision. |
| **Invariants Mining** | 1.000 | 0.006 | 0.013 | Perfectly precise but nearly useless — only found 1 anomaly. Too strict. |

**Why Isolation Forest wins**: It handles the high-dimensional sparse data well because anomalies naturally have short path lengths in random trees. PCA's threshold is too conservative, and Invariants Mining's rules are too rigid for this dataset.

---

## 5. How This Fits Into OmniFlow's DevOps Pipeline

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  K8s Pods    │     │  Log         │     │  Log Anomaly      │     │  Alerting    │
│  CI/CD       │────▶│  Aggregation │────▶│  Detection       │────▶│  AlertManager│
│  Nginx       │     │  (Loki)      │     │  (Loglizer)       │     │  (Slack/PD)  │
└──────────────┘     └──────────────┘     └──────────────────┘     └──────────────┘
                            │                      │
                            │                      │
                   ┌────────▼──────────┐    ┌─────▼──────────────┐
                   │  Log Parser        │    │  Prometheus         │
                   │  (Drain/logparser) │    │  (threshold alerts)│
                   │  raw → structured  │    │  CPU > 80%, etc.   │
                   └────────────────────┘    └────────────────────┘
```

| Layer | What It Catches | Example |
|---|---|---|
| **Prometheus** | Known threshold violations | CPU > 80%, pod restarts > 3 |
| **Loglizer** | Unknown pattern deviations | Pod's event sequence looks unusual |
| **Together** | Comprehensive coverage | Known + unknown failures |

---

## 6. Key Takeaways

1. **Anomaly ≠ Error line**. It's about the *pattern* of events being unusual, not any single log line.

2. **The pipeline is**: Raw logs → Parse (Drain) → Group into sessions → Count events → TF-IDF + normalize → ML model → anomaly/normal.

3. **Unsupervised models work without labels**. PCA, Isolation Forest, and Invariants Mining learn from normal data alone — no need to manually label anomalies.

4. **Isolation Forest performed best** on HDFS data (F1=0.60), because anomalies are naturally easy to isolate in random partitioning.

5. **This complements threshold monitoring**. Prometheus catches "CPU is high"; loglizer catches "this pod's log pattern is weird." Together, they provide better coverage.

6. **The missing piece for production**: We need logparser (Drain) to convert raw K8s/CI logs into structured events before loglizer can process them. The demo uses pre-parsed HDFS data.

---

## References

- **Loglizer**: He et al., *"Experience Report: System Log Analysis for Anomaly Detection"*, ISSRE 2016 (Most Influential Paper). [github.com/logpai/loglizer](https://github.com/logpai/loglizer)
- **PCA**: Xu et al., *"Large-Scale System Problems Detection by Mining Console Logs"*, SOSP 2009.
- **Isolation Forest**: Liu et al., *"Isolation Forest"*, ICDM 2008.
- **Invariants Mining**: Lou et al., *"Mining Invariants from Console Logs for System Problem Detection"*, ATC 2010.
- **Drain (log parser)**: He et al., *"Drain: An Online Log Parsing Approach with Fixed Depth Tree"*, ICWS 2017.