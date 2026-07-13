import numpy as np
import tensorflow as tf
from tensorflow import keras
# from tensorflow.lite.python.lite import TFLiteConverter # บรรทัดนี้ไม่จำเป็นแล้ว เพราะเราจะใช้ tf.lite.TFLiteConverter โดยตรง

# 1. การเตรียมข้อมูล (Data Preparation)
# กำหนดค่าตัวอักษรและตัวเลขที่ใช้แทน
char_to_int = {'A': 0, 'B': 1, 'C': 2}
int_to_char = {0: 'A', 1: 'B', 2: 'C'}
num_classes = len(char_to_int) # จำนวนคลาส (A, B, C) คือ 3

# ลำดับข้อมูลตัวอย่างสำหรับการฝึก
# เพิ่มความหลากหลายของข้อมูลเล็กน้อย เพื่อให้โมเดลเรียนรู้รูปแบบที่แตกต่างกัน
data_sequence = "ACABBABCBABAABAABBAACBACCBCCBBABCBCCABACAABBABABBCACBCBACBBBAACABCBBBBCCCBABBCCCCCACACCABCACCBAABCCBCA" * 50 + "BACBACBACBCAABACCABBA" * 25 # ทำซ้ำเพื่อเพิ่มปริมาณข้อมูล
# คุณสามารถเพิ่มลำดับที่ซับซ้อนและหลากหลายขึ้นได้อีก เพื่อให้โมเดลมีความสามารถในการทำนายที่ดีขึ้นในสถานการณ์จริง

# สร้างคู่ลำดับอินพุต-เอาต์พุต
# เราจะใช้ลำดับ 3 ตัวอักษร (sequence_length) เพื่อทำนายตัวอักษรถัดไป
sequence_length = 3
X = [] # รายการสำหรับเก็บอินพุต (ลำดับตัวเลข)
y = [] # รายการสำหรับเก็บเอาต์พุต (ตัวเลขของตัวอักษรถัดไป)

for i in range(len(data_sequence) - sequence_length):
    seq_in = data_sequence[i:i + sequence_length] # ลำดับอินพุตปัจจุบัน
    seq_out = data_sequence[i + sequence_length]   # ตัวอักษรถัดไป (เอาต์พุต)
    X.append([char_to_int[char] for char in seq_in]) # แปลงตัวอักษรเป็นตัวเลขสำหรับอินพุต
    y.append(char_to_int[seq_out])                   # แปลงตัวอักษรเป็นตัวเลขสำหรับเอาต์พุต

print(f"จำนวนตัวอย่างข้อมูล: {len(X)}")
print(f"ตัวอย่างอินพุตแรก: {X[0]} (แทนด้วย {data_sequence[0:sequence_length]})")
print(f"ตัวอย่างเอาต์พุตแรก: {y[0]} (แทนด้วย {data_sequence[sequence_length]})")

# แปลงข้อมูลให้อยู่ในรูปแบบที่ Keras ต้องการ
# X: [จำนวนตัวอย่าง, ความยาวลำดับ, 1] สำหรับ LSTM (แต่ละตัวอักษรเป็น 1 ฟีเจอร์)
X = np.array(X)
X = np.reshape(X, (X.shape[0], X.shape[1], 1))

# ทำ One-Hot Encoding สำหรับเอาต์พุต y
# เช่น ถ้าเอาต์พุตเป็น 0 ('A') จะแปลงเป็น [1, 0, 0]
y = keras.utils.to_categorical(y, num_classes=num_classes)

print(f"รูปร่าง X หลัง reshape: {X.shape}")
print(f"รูปร่าง y หลัง One-Hot Encoding: {y.shape}")

# 2. การสร้างโมเดล (Model Architecture)
# ใช้โมเดลโครงข่ายประสาทเทียมแบบ Recurrent Neural Network (RNN) - LSTM
model = keras.Sequential([
    # LSTM layer: มี 50 หน่วย (neurons) รับอินพุตขนาด (sequence_length, 1)
    keras.layers.LSTM(50, input_shape=(X.shape[1], X.shape[2])),
    # Dense layer: ชั้นเอาต์พุต มีจำนวนหน่วยเท่ากับจำนวนคลาส (3 สำหรับ A, B, C)
    # activation='softmax' เพื่อให้ได้ค่าความน่าจะเป็นสำหรับแต่ละคลาส (ผลรวมเป็น 1)
    keras.layers.Dense(num_classes, activation='softmax')
])

# คอมไพล์โมเดล: กำหนด optimizer, loss function และ metrics
model.compile(optimizer='adam', loss='categorical_crossentropy', metrics=['accuracy'])

# แสดงสรุปโครงสร้างโมเดล (จำนวนชั้น, พารามิเตอร์)
model.summary()

# 3. การฝึกโมเดล (Training the Model)
# กำหนดจำนวน Epochs (รอบการฝึก) และ Batch Size
epochs = 200 # จำนวนรอบที่โมเดลจะเรียนรู้จากชุดข้อมูลทั้งหมด
batch_size = 1 # จำนวนตัวอย่างข้อมูลที่โมเดลจะประมวลผลในแต่ละครั้งก่อนที่จะปรับปรุงน้ำหนัก

print("\nกำลังเริ่มฝึกโมเดล...")
# model.fit: ทำการฝึกโมเดลด้วยข้อมูล X และ y
# verbose=1 เพื่อแสดงความคืบหน้าของการฝึกในแต่ละ epoch
history = model.fit(X, y, epochs=epochs, batch_size=batch_size, verbose=1)
print("ฝึกโมเดลเสร็จสิ้น.")

# ประเมินความแม่นยำของโมเดลบนชุดข้อมูลฝึก
loss, accuracy = model.evaluate(X, y, verbose=0)
print(f"ความแม่นยำในการฝึก: {accuracy*100:.2f}%")

# 4. การแปลงเป็น TFLite (Convert to TFLite)
# สร้าง TFLiteConverter จากโมเดล Keras ที่ฝึกแล้ว
converter = tf.lite.TFLiteConverter.from_keras_model(model)

# *** แก้ไข: เพิ่มการตั้งค่าสำหรับ Converter เพื่อแก้ไขปัญหา TensorListReserve ***
converter.target_spec.supported_ops = [
    tf.lite.OpsSet.TFLITE_BUILTINS, # ใช้ Built-in Ops ของ TFLite
    tf.lite.OpsSet.SELECT_TF_OPS    # อนุญาตให้ใช้ TensorFlow Ops ที่เลือก (Custom Ops)
]
converter._experimental_lower_tensor_list_ops = False # ปิดการลดรูป TensorList Ops แบบทดลอง

# แปลงโมเดลเป็นรูปแบบ TensorFlow Lite
tflite_model = converter.convert()

# บันทึกโมเดล TFLite ลงในไฟล์ชื่อ 'model.tflite'
tflite_model_path = 'model.tflite'
with open(tflite_model_path, 'wb') as f:
    f.write(tflite_model)

print(f"\nโมเดล TensorFlow Lite ถูกบันทึกที่: {tflite_model_path}")
print("คุณสามารถนำไฟล์นี้ไปใช้ในแอป Flutter ของคุณได้เลย!")

# ตัวอย่างการทำนายด้วยโมเดลที่ฝึกแล้ว (ใน Python)
def predict_next_char(input_sequence_str):
    # เข้ารหัสลำดับอินพุตเป็นตัวเลข
    input_encoded = [char_to_int[char] for char in input_sequence_str]
    # จัดรูปร่างอินพุตให้เหมาะสมกับโมเดล (batch_size, sequence_length, features)
    input_reshaped = np.reshape(np.array(input_encoded), (1, sequence_length, 1))
    
    # ทำการทำนายด้วยโมเดล
    prediction = model.predict(input_reshaped)
    # หา index ของค่าความน่าจะเป็นสูงสุด
    predicted_int = np.argmax(prediction)
    # แปลงตัวเลขที่ทำนายได้กลับเป็นตัวอักษร
    predicted_char = int_to_char[predicted_int]
    
    # ส่งคืนตัวอักษรที่ทำนายได้และความมั่นใจ (ความน่าจะเป็นสูงสุด)
    return predicted_char, prediction[0][predicted_int]

# ทดสอบการทำนายด้วยลำดับตัวอย่าง
test_sequence = "ABC"  # Must be 3 characters (matches sequence_length)
predicted_char, confidence = predict_next_char(test_sequence)
print(f"\nทำนายตัวอักษรถัดไปของ '{test_sequence}': {predicted_char} (ความมั่นใจ: {confidence*100:.2f}%)")

test_sequence_2 = "AAB"  # Must be 3 characters (matches sequence_length)
predicted_char_2, confidence_2 = predict_next_char(test_sequence_2)
print(f"ทำนายตัวอักษรถัดไปของ '{test_sequence_2}': {predicted_char_2} (ความมั่นใจ: {confidence_2*100:.2f}%)")
