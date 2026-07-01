#!/usr/bin/env python3
"""
OmniFlow Log Anomaly Detection — Simple Demo

This script walks through the ENTIRE pipeline step by step, so you can
understand exactly what "anomaly detection on logs" means.

Think of it like this:
  - Your CI pipeline outputs logs every time it runs
  - Most of the time, those logs look the same (same events, same order)
  - When something goes WRONG, the logs look DIFFERENT (new error types,
    missing events, weird sequences)
  - Loglizer learns what "normal" looks like, then flags anything different

We use the HDFS dataset (included in this repo) because it's a real,
well-studied dataset with known anomalies — perfect for learning.
"""

import os
import sys
import urllib.request

# Add this directory to path so we can import the local loglizer package
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
import pandas as pd
from loglizer.models import PCA, IsolationForest, InvariantsMiner
from loglizer import dataloader, preprocessing


def print_header(title):
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}\n")


def print_step(step_num, title):
    print(f"\n--- Step {step_num}: {title} ---\n")


def download_hdfs_data(data_dir):
    """Download the HDFS dataset from the LogPAI loghub repository."""
    structured_log = os.path.join(data_dir, 'HDFS_100k.log_structured.csv')
    label_file = os.path.join(data_dir, 'anomaly_label.csv')

    if os.path.exists(structured_log) and os.path.exists(label_file):
        print(f"Data already exists at {data_dir}")
        return structured_log, label_file

    os.makedirs(data_dir, exist_ok=True)
    print(f"Downloading HDFS dataset to {data_dir}...")

    # Download from logpai/loglizer (the official source for this data)
    base_url = "https://raw.githubusercontent.com/logpai/loglizer/master/data/HDFS"
    files = {
        'HDFS_100k.log_structured.csv': structured_log,
        'anomaly_label.csv': label_file,
    }

    for filename, dest in files.items():
        url = f"{base_url}/{filename}"
        print(f"  Downloading {filename}...")
        try:
            urllib.request.urlretrieve(url, dest)
        except Exception as e:
            print(f"  ERROR: Could not download {filename}: {e}")
            print(f"  Please manually download from https://github.com/logpai/loghub/tree/master/HDFS")
            sys.exit(1)

    print("Download complete.\n")
    return structured_log, label_file


def main():
    print_header("OmniFlow Log Anomaly Detection Demo")
    print("This demo shows how ML can detect anomalies in system logs.")
    print("We'll walk through each step so you understand WHAT is happening\n"
          "and WHY it works.\n")

    # ─── Configuration ────────────────────────────────────────────
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, 'data', 'HDFS')

    # Download data if needed
    structured_log, label_file = download_hdfs_data(data_dir)

    # ─── Step 1: What do the raw structured logs look like? ───────
    print_step(1, "Look at the raw data")
    print("Before any ML, logs are just text. After parsing with logparser (Drain),")
    print("each log line gets an EventId — a template that captures the PATTERN.")
    print()
    print("For example, these two lines:")
    print("  081109 203635 143 INFO dfs.DataNode$PacketResponder: PacketResponder 1 for block blk_-1608999687919862906 terminating")
    print("  081109 203640 144 INFO dfs.DataNode$PacketResponder: PacketResponder 3 for block blk_7508430987891234567 terminating")
    print()
    print("Both match the SAME template:")
    print("  PacketResponder <*> for block <*> terminating  →  EventId: E5")
    print()
    print("The <*> are parameters (variable parts). The template is the PATTERN.")
    print("This is what logparser does — it turns raw text into structured events.\n")

    # Load and show a few rows
    df = pd.read_csv(structured_log, nrows=10)
    print("First 5 rows of the structured log file:")
    print(df[['LineId', 'Date', 'Time', 'Level', 'EventId', 'EventTemplate']].to_string(index=False))
    print()

    # ─── Step 2: What does "anomaly" mean here? ──────────────────
    print_step(2, "What is an anomaly?")
    print("In HDFS, each 'block' (like a file chunk) has a lifecycle of log events.")
    print("A NORMAL block might have this sequence of events:")
    print("  E5, E22, E5, E11, E5, E22, E5, E11  (repeating pattern)")
    print()
    print("An ANOMALOUS block might have:")
    print("  E5, E22, E41, E26, E5  (unexpected events E41, E26 that don't")
    print("                           normally appear in this context)")
    print()
    print("The label file tells us which blocks are normal vs anomalous.")
    print("Let's see the distribution:\n")

    labels_df = pd.read_csv(label_file)
    label_counts = labels_df['Label'].value_counts()
    print(f"Total blocks: {len(labels_df)}")
    for label, count in label_counts.items():
        print(f"  {label}: {count} ({count/len(labels_df)*100:.1f}%)")
    print()
    print("So most blocks are Normal, and a small fraction are Anomaly.")
    print("This is typical in real systems — anomalies are rare.\n")

    # ─── Step 3: Group logs into sessions ─────────────────────────
    print_step(3, "Group logs into sessions")
    print("Loglizer groups all log lines that belong to the same 'session'")
    print("(in HDFS, a session = one block ID). Each session becomes a")
    print("COUNT VECTOR — how many times each event type appeared.\n")
    print("For example, if block blk_123 had events: E5, E22, E5, E11, E5")
    print("Its count vector would be: E5=3, E11=1, E22=1, everything else=0")
    print()

    # ─── Step 4: Load data using loglizer ─────────────────────────
    print_step(4, "Load data and create feature vectors")
    print("Now we load the data through loglizer's pipeline:")
    print("  1. Group lines by block ID (session window)")
    print("  2. Count events per session → count vectors")
    print("  3. Apply TF-IDF weighting (rare events matter more)")
    print("  4. Normalize (zero-mean centering)")
    print()

    (x_train, y_train), (x_test, y_test) = dataloader.load_HDFS(
        structured_log,
        label_file=label_file,
        window='session',
        train_ratio=0.5,
        split_type='uniform'
    )

    print(f"Training samples: {len(x_train)}")
    print(f"Test samples:     {len(x_test)}")
    print()

    # Show what a session looks like (raw event sequence)
    normal_idx = np.where(y_train == 0)[0][0]
    anomaly_idx = np.where(y_train == 1)[0][0] if 1 in y_train else None

    print("Example NORMAL session (event sequence):")
    print(f"  {x_train[normal_idx]}")
    if anomaly_idx is not None:
        print("Example ANOMALY session (event sequence):")
        print(f"  {x_train[anomaly_idx]}")
    print()
    print("See? The anomaly has different event types (like E26) that")
    print("don't normally appear in healthy sessions.\n")

    # Apply feature extraction
    print("Now we convert event sequences into NUMERIC feature vectors:")
    print("  1. Count how many times each event type appears per session")
    print("  2. Apply TF-IDF weighting (rare events matter more)")
    print("  3. Normalize (zero-mean centering)")
    print()

    feature_extractor = preprocessing.FeatureExtractor()
    x_train_feat = feature_extractor.fit_transform(
        x_train, term_weighting='tf-idf', normalization='zero-mean'
    )
    x_test_feat = feature_extractor.transform(x_test)

    print(f"After feature extraction:")
    print(f"  Feature matrix shape: {x_train_feat.shape}")
    print(f"  {x_train_feat.shape[0]} sessions × {x_train_feat.shape[1]} event types")
    print(f"  Each row = one block's log session")
    print(f"  Each column = one event type's weighted count")
    print()

    # ─── Step 5: Run PCA (unsupervised) ───────────────────────────
    print_step(5, "Run PCA — Unsupervised Anomaly Detection")
    print("PCA (Principal Component Analysis) is UNSUPERVISED — it doesn't")
    print("need labels. It learns what 'normal' looks like from the training")
    print("data, then flags anything that deviates significantly.\n")
    print("How it works:")
    print("  1. Find the principal components (directions of most variation)")
    print("  2. Project data onto these components")
    print("  3. If the reconstruction error is large → it's an anomaly")
    print("     (because the normal components can't explain it well)")
    print()

    model_pca = PCA()
    model_pca.fit(x_train_feat)

    print("Training complete. Now evaluating on test data:\n")
    precision, recall, f1 = model_pca.evaluate(x_test_feat, y_test)
    print(f"  Precision: {precision:.4f}  (of all flagged anomalies, how many were real?)")
    print(f"  Recall:    {recall:.4f}  (of all real anomalies, how many did we find?)")
    print(f"  F1 Score:  {f1:.4f}  (harmonic mean of precision and recall)")
    print()

    # ─── Step 6: Run Isolation Forest (uns upervised) ─────────────
    print_step(6, "Run Isolation Forest — Another Unsupervised Method")
    print("Isolation Forest works differently:")
    print("  1. Randomly split the data along random features")
    print("  2. Anomalies are ISOLATED quickly (fewer splits needed)")
    print("  3. Normal points need many splits to isolate")
    print("  Think: 'anomalies are weird, so they're easy to separate out'\n")

    model_if = IsolationForest()
    model_if.fit(x_train_feat)

    print("Training complete. Evaluating:\n")
    precision_if, recall_if, f1_if = model_if.evaluate(x_test_feat, y_test)
    print(f"  Precision: {precision_if:.4f}")
    print(f"  Recall:    {recall_if:.4f}")
    print(f"  F1 Score:  {f1_if:.4f}")
    print()

    # ─── Step 7: Run Invariants Mining (unsupervised) ──────────────
    print_step(7, "Run Invariants Mining — Discovering Rules")
    print("Invariants Mining finds LINEAR RULES between event counts.")
    print("For example: 'Event E5 always appears exactly 2x with E22'")
    print("When a session VIOLATES these rules → it's an anomaly.\n")

    model_im = InvariantsMiner()
    model_im.fit(x_train_feat)

    print("Training complete. Evaluating:\n")
    precision_im, recall_im, f1_im = model_im.evaluate(x_test_feat, y_test)
    print(f"  Precision: {precision_im:.4f}")
    print(f"  Recall:    {recall_im:.4f}")
    print(f"  F1 Score:  {f1_im:.4f}")
    print()

    # ─── Step 8: Compare models ───────────────────────────────────
    print_step(8, "Comparison of Unsupervised Models")
    print(f"{'Model':<25} {'Precision':>10} {'Recall':>10} {'F1':>10}")
    print("-" * 55)
    print(f"{'PCA':<25} {precision:>10.4f} {recall:>10.4f} {f1:>10.4f}")
    print(f"{'Isolation Forest':<25} {precision_if:>10.4f} {recall_if:>10.4f} {f1_if:>10.4f}")
    print(f"{'Invariants Mining':<25} {precision_im:>10.4f} {recall_im:>10.4f} {f1_im:>10.4f}")
    print()

    # ─── Summary ──────────────────────────────────────────────────
    print_header("Summary — What Did We Just Do?")
    print("""
1. RAW LOGS → PARSED EVENTS
   Log lines like "PacketResponder 1 for block blk_123 terminating"
   become EventId "E5" with template "PacketResponder <*> for block <*> terminating"

2. EVENTS → SESSION VECTORS
   All events from one block/session are counted into a vector:
   [E1=0, E2=3, E3=0, E4=1, E5=5, ...] — how many times each event appeared

3. VECTORS → ML MODEL
   The model learns what normal count vectors look like,
   then flags sessions whose vectors are unusual.

4. ANOMALY = UNUSUAL PATTERN
   A session is "anomalous" when its event pattern deviates from normal.
   It's not just "there's an ERROR" — it's "the COMBINATION of events
   doesn't match what we've seen before."

WHY THIS MATTERS FOR DEVOPS:
   - Your Prometheus alerts catch THRESHOLD violations (CPU > 80%)
   - Loglizer catches PATTERN violations (this pod's log sequence looks weird)
   - Together, they give you much better coverage of what can go wrong

NEXT STEPS:
   - Try supervised models (DecisionTree, SVM) if you have labeled data
   - Connect real K8s logs using the omniflow_dataloader.py
   - Add logparser (Drain) to parse raw logs into structured events
   - Integrate results into Prometheus AlertManager for alerting
""")


if __name__ == '__main__':
    main()