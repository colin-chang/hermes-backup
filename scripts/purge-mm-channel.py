#!/usr/bin/env python3
"""清空 Mattermost 指定频道的所有消息记录

用法:
  python3 purge_mm_channel.py <CHANNEL_ID>

前置条件:
  - MATTERMOST_URL 和 MATTERMOST_TOKEN 在 ~/.hermes/.env 中
  - 或者直接设置环境变量

原理:
  1. GET /api/v4/channels/{id}/posts?per_page=200  取一批帖子
  2. 收集所有 post_id
  3. 跳过分页继续拉取直到空
  4. DELETE /api/v4/posts/{id} 逐条删除
"""

import os
import sys
import json
import time
import urllib.request
import urllib.error

# ── 从 .env 或环境变量读取 ──────────────────────────────────
def load_env():
    env_file = os.path.expanduser("~/.hermes/.env")
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))

load_env()

MM_URL = os.environ.get("MATTERMOST_URL", "").rstrip("/")
MM_TOKEN = os.environ.get("MATTERMOST_TOKEN", "")

if not MM_URL or not MM_TOKEN:
    print("❌ MATTERMOST_URL 或 MATTERMOST_TOKEN 未设置")
    sys.exit(1)

# ── 参数 ──────────────────────────────────────────────────
CHANNEL_ID = sys.argv[1] if len(sys.argv) > 1 else None
if not CHANNEL_ID:
    print("用法: python3 purge_mm_channel.py <CHANNEL_ID>")
    sys.exit(1)

# ── 安全确认 ──────────────────────────────────────────────
channel_url = f"{MM_URL}/api/v4/channels/{CHANNEL_ID}"
req = urllib.request.Request(channel_url, headers={"Authorization": f"Bearer {MM_TOKEN}"})
try:
    with urllib.request.urlopen(req) as resp:
        channel = json.loads(resp.read())
    ch_name = channel.get("display_name") or channel.get("name") or CHANNEL_ID
except Exception as e:
    print(f"❌ 无法读取频道信息: {e}")
    sys.exit(1)

print(f"\n⚠️  即将清空频道: {ch_name} (ID: {CHANNEL_ID})")
print(f"    服务器: {MM_URL}")
confirm = input("\n输入频道名确认删除 (或 Ctrl+C 取消): ").strip()
if confirm != ch_name:
    print("❌ 频道名不匹配，取消")
    sys.exit(0)

# ── 批量拉取帖子 ──────────────────────────────────────────
all_post_ids = []
page = 0
per_page = 200

while True:
    page_url = f"{MM_URL}/api/v4/channels/{CHANNEL_ID}/posts?page={page}&per_page={per_page}"
    req = urllib.request.Request(page_url, headers={"Authorization": f"Bearer {MM_TOKEN}"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"❌ HTTP {e.code}: {e.reason}")
        sys.exit(1)

    posts = data.get("posts", {})
    order = data.get("order", [])
    if not order:
        break

    for pid in order:
        if pid not in all_post_ids:
            all_post_ids.append(pid)

    page += 1
    sys.stdout.write(f"\r📥 已拉取 {len(all_post_ids)} 条消息...")
    sys.stdout.flush()
    time.sleep(0.3)  # 温和速率

print(f"\n📊 共 {len(all_post_ids)} 条消息待删除")

if not all_post_ids:
    print("✅ 频道已空，无需操作")
    sys.exit(0)

# ── 逐条删除 ──────────────────────────────────────────────
deleted = 0
errors = 0
for pid in all_post_ids:
    del_url = f"{MM_URL}/api/v4/posts/{pid}"
    req = urllib.request.Request(del_url, method="DELETE", headers={"Authorization": f"Bearer {MM_TOKEN}"})
    try:
        with urllib.request.urlopen(req) as resp:
            pass
        deleted += 1
    except urllib.error.HTTPError as e:
        errors += 1
        if errors <= 3:
            print(f"\n⚠️  删除 {pid} 失败: HTTP {e.code}")

    if deleted % 50 == 0:
        sys.stdout.write(f"\r🗑️  已删除 {deleted}/{len(all_post_ids)}...")
        sys.stdout.flush()
    time.sleep(0.15)

print(f"\n✅ 完成: {deleted} 删除, {errors} 失败")
