import requests, time, json, base64, os
from io import BytesIO
from PIL import Image

base_url = 'https://api-inference.modelscope.cn/'
api_key = "ms-613d078d-4ced-41bb-8fe9-148489b2b3c6"
headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}

def run_edit(image_input, prompt, tag):
    payload = {
        "model": "FireRedTeam/FireRed-Image-Edit-1.1",
        "prompt": prompt,
        "image_url": image_input,
    }
    try:
        r = requests.post(f"{base_url}v1/images/generations",
            headers={**headers, "X-ModelScope-Async-Mode": "true"},
            data=json.dumps(payload, ensure_ascii=False).encode('utf-8'), timeout=30)
    except Exception as e:
        print(f"[{tag}] POST ERROR: {e}")
        return None
    print(f"[{tag}] submit status: {r.status_code}")
    if r.status_code != 200:
        print(f"[{tag}] submit body: {r.text[:600]}")
        return None
    try:
        task_id = r.json()["task_id"]
    except Exception as e:
        print(f"[{tag}] no task_id: {r.text[:300]}")
        return None
    print(f"[{tag}] task_id: {task_id}")
    for i in range(36):
        try:
            res = requests.get(f"{base_url}v1/tasks/{task_id}",
                headers={**headers, "X-ModelScope-Task-Type": "image_generation"}, timeout=30)
            data = res.json()
        except Exception as e:
            print(f"[{tag}] poll error: {e}")
            return None
        st = data.get("task_status")
        if st == "SUCCEED":
            return data.get("output_images", [None])[0]
        elif st == "FAILED":
            print(f"[{tag}] FAILED: {data}")
            return None
        time.sleep(5)
    print(f"[{tag}] poll timeout")
    return None

# 1) 官方示例：确认通路 + key 有效
official = run_edit("https://resources.modelscope.cn/aigc/image_edit.png",
                   "turn the girl's hair blue", "OFFICIAL")
print("OFFICIAL result:", official)

# 2) 猫图 base64：测宠物编辑效果
photos = r'F:/元宝爱拍照/pet_camera/assets/seed/photos/'
cat = os.path.join(photos, 'feat_portrait.jpg')
img = Image.open(cat)
if img.width > 1024:
    h = int(img.height * 1024 / img.width)
    img = img.resize((1024, h))
buf = BytesIO()
img.save(buf, format='JPEG', quality=85)
b64 = base64.b64encode(buf.getvalue()).decode()
cat_result = run_edit(f"data:image/jpeg;base64,{b64}",
                      "make the cat look adorable with a pink bow on its head, cute soft lighting", "CAT")
if cat_result:
    rr = requests.get(cat_result, timeout=30)
    out = r'F:/元宝爱拍照/pet_camera/firered_cat_result.jpg'
    with open(out, 'wb') as f:
        f.write(rr.content)
    print(f"CAT result saved: {out} ({len(rr.content)} bytes)")
else:
    print("CAT edit failed or no result")
