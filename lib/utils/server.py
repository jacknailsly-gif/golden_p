"""
TFLite Feedback & Retrain Server (V20.4 Stable)
==============================================
รับข้อมูลจาก Flutter App แล้ว Retrain Model ให้ฉลาดขึ้น
"""

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import numpy as np
import tensorflow as tf
from tensorflow import keras
import os
import json
from datetime import datetime

app = Flask(__name__)
app.url_map.strict_slashes = False
CORS(app)

# --- Configuration ---
MODEL_PATH = 'model.tflite'
KERAS_MODEL_PATH = 'model_keras.weights.h5'
TRAINING_DATA_PATH = 'training_data.json'
SEQUENCE_LENGTH = 3
NUM_CLASSES = 3

CHAR_TO_INT = {'A': 0, 'B': 1, 'C': 2}
INT_TO_CHAR = {0: 'A', 1: 'B', 2: 'C'}

training_buffer = []

def load_training_data():
    global training_buffer
    if os.path.exists(TRAINING_DATA_PATH):
        try:
            with open(TRAINING_DATA_PATH, 'r') as f:
                content = f.read()
                if not content.strip():
                    training_buffer = []
                else:
                    training_buffer = json.loads(content)
            print(f"[DATA] Loaded {len(training_buffer)} samples.")
        except json.JSONDecodeError as e:
            print(f"[ERROR] JSON Decode Error at {e.pos}: {e.msg}")
            print(f"[INFO] Attempting to recover partial data...")
            # Simple recovery: try to find the last valid closure
            try:
                import re
                # Find all complete JSON objects in the list
                matches = re.findall(r'\{[^{}]*\}', content)
                recovered = []
                for m in matches:
                    try:
                        recovered.append(json.loads(m))
                    except:
                        continue
                training_buffer = recovered
                print(f"[SUCCESS] Recovered {len(training_buffer)} samples.")
            except Exception as e2:
                print(f"[CRITICAL] Recovery failed: {e2}")
                training_buffer = []
        except Exception as e:
            print(f"[ERROR] Loading data: {e}")
            training_buffer = []
    return training_buffer

def save_training_data():
    try:
        with open(TRAINING_DATA_PATH, 'w') as f:
            json.dump(training_buffer, f)
        print(f"[SUCCESS] Saved {len(training_buffer)} samples.")
    except Exception as e:
        print(f"[ERROR] Saving data: {e}")

def create_model():
    model = keras.Sequential([
        keras.layers.LSTM(64, input_shape=(SEQUENCE_LENGTH, 1), return_sequences=False),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(32, activation='relu'),
        keras.layers.Dense(NUM_CLASSES, activation='softmax')
    ])
    model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])
    return model

def load_or_create_model():
    model = create_model()
    if os.path.exists(KERAS_MODEL_PATH):
        try:
            model.load_weights(KERAS_MODEL_PATH)
            print("[MODEL] Loaded existing weights.")
        except Exception as e:
            print(f"[INFO] Weights incompatible: {e}. Starting fresh.")
    return model

def convert_to_tflite(model):
    try:
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS,
            tf.lite.OpsSet.SELECT_TF_OPS
        ]
        converter._experimental_lower_tensor_list_ops = False
        tflite_model = converter.convert()
        with open(MODEL_PATH, 'wb') as f:
            f.write(tflite_model)
        print(f"[SUCCESS] TFLite saved to {MODEL_PATH}")
        return True
    except Exception as e:
        print(f"[ERROR] TFLite conversion failed: {e}")
        return False

def retrain_model():
    global training_buffer
    if len(training_buffer) < 5:
        print("[INFO] Need at least 5 samples to retrain.")
        return False
    
    print(f"[PROCESS] Retraining with {len(training_buffer)} samples...")
    X, y = [], []
    for sample in training_buffer:
        ctx, act = sample.get('context', ''), sample.get('actual', '')
        if len(ctx) == SEQUENCE_LENGTH and act in CHAR_TO_INT:
            X.append([CHAR_TO_INT[c] for c in ctx])
            y.append(CHAR_TO_INT[act])
    
    if len(X) < 5: return False
    
    X = np.array(X).reshape(-1, SEQUENCE_LENGTH, 1)
    y = keras.utils.to_categorical(y, num_classes=NUM_CLASSES)
    
    model = load_or_create_model()
    model.fit(X, y, epochs=15, batch_size=4, verbose=0)
    model.save_weights(KERAS_MODEL_PATH)
    return convert_to_tflite(model)

# --- State for Statistics ---
active_clients = set()

@app.route('/feedback', methods=['POST'])
def receive_feedback():
    global active_clients
    data = request.get_json()
    if not data: return jsonify({"error": "No data"}), 400
    
    # Track unique device IPs
    client_ip = request.remote_addr
    active_clients.add(client_ip)
    
    training_buffer.append({
        'context': data.get('context', ''),
        'actual': data.get('actual', ''),
        'predicted': data.get('predicted', ''),
        'correct': data.get('correct', False),
        'client_ip': client_ip,
        'timestamp': datetime.now().isoformat()
    })
    save_training_data()
    
    # Display Dashboard Summary with Colors
    status_text = "WIN" if data.get('correct', False) else "LOSS"
    color_code = "\033[92m" if status_text == "WIN" else "\033[91m"  # Green for WIN, Red for LOSS
    reset_code = "\033[0m"
    
    print(f"[SUCCESS] Saved {len(training_buffer)} samples.", flush=True)
    print("-" * 40, flush=True)
    print(f"[DEVICE FEEDBACK] From IP: {client_ip} -> {color_code}{status_text}{reset_code}", flush=True)
    print(f"Total Unique Devices: {len(active_clients)}")
    print(f"Total Data Samples: {len(training_buffer)}", flush=True)
    print("-" * 40, flush=True)
    
    # Auto-retrain every 10 new samples
    model_updated = False
    if len(training_buffer) % 10 == 0:
        model_updated = retrain_model()
    
    return jsonify({
        "status": "retrained" if model_updated else "received",
        "model_updated": model_updated,
        "samples_collected": len(training_buffer),
        "active_devices": len(active_clients)
    })

@app.route('/model', methods=['GET'])
def get_model():
    if os.path.exists(MODEL_PATH):
        return send_file(MODEL_PATH, as_attachment=True)
    return jsonify({"error": "No model"}), 404

@app.route('/retrain', methods=['POST'])
def force_retrain():
    return jsonify({"status": "success" if retrain_model() else "failed"})

@app.route('/stats', methods=['GET'])
def get_stats():
    total = len(training_buffer)
    correct = sum(1 for s in training_buffer if s.get('correct', False))
    return jsonify({"total": total, "accuracy": f"{(correct/total*100):.1f}%" if total > 0 else "0%"})

@app.route('/clear', methods=['POST'])
def clear_data():
    global training_buffer
    training_buffer = []
    save_training_data()
    return jsonify({"status": "cleared"})

if __name__ == '__main__':
    load_training_data()
    print("=" * 50, flush=True)
    print(f"AI SERVER V20.5 READY ON PORT 5000", flush=True)
    print(f"Samples Loaded: {len(training_buffer)}", flush=True)
    print("=" * 50, flush=True)
    app.run(host='0.0.0.0', port=5000, debug=False)
