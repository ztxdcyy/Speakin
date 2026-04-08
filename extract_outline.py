#!/usr/bin/env python3
"""
从 logo_bird.png 中提取小鸟的边缘轮廓。
- 白色轮廓 + 透明背景（macOS 菜单栏 template image 风格）
- 保留肚皮线条
- 忽略眼睛和声波（先用白色覆盖再做边缘检测）
"""

import cv2
import numpy as np
import os

def extract_bird_outline(input_path, output_dir="bird_outline_output"):
    os.makedirs(output_dir, exist_ok=True)
    
    # 读取图片
    img = cv2.imread(input_path)
    if img is None:
        print(f"Error: Cannot read {input_path}")
        return
    
    h, w = img.shape[:2]
    print(f"Image size: {w}x{h}")
    
    # === 第一步：用颜色掩码定位鸟身体 ===
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    
    # 橙色范围（鸟的身体颜色，包括声波）
    lower_orange = np.array([0, 80, 100])
    upper_orange = np.array([35, 255, 255])
    bird_color_mask = cv2.inRange(hsv, lower_orange, upper_orange)
    
    # 找到鸟身体的轮廓和边界框
    bird_contours, _ = cv2.findContours(bird_color_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not bird_contours:
        print("Warning: Could not find bird body")
        return
    
    # 找最大的连通区域（鸟身体本体，不含声波）
    bird_contours = sorted(bird_contours, key=cv2.contourArea, reverse=True)
    main_bird = bird_contours[0]
    bx, by, bw, bh = cv2.boundingRect(main_bird)
    print(f"Bird body bounding box: x={bx}, y={by}, w={bw}, h={bh}")
    
    # 创建只包含鸟身体（最大连通区域）的掩码
    main_bird_mask = np.zeros_like(bird_color_mask)
    cv2.drawContours(main_bird_mask, [main_bird], -1, 255, -1)
    
    # === 第二步：找到鸟身体每行的右边界 ===
    bird_right_boundary = np.zeros(h, dtype=np.int32)
    for row in range(h):
        cols = np.where(main_bird_mask[row] > 0)[0]
        if len(cols) > 0:
            bird_right_boundary[row] = cols[-1]
    
    # === 第三步：在原图上用白色(背景色)覆盖声波区域 ===
    img_clean = img.copy()
    
    # 获取背景色（左上角像素）
    bg_color = img[5, 5].tolist()  # BGR
    print(f"Background color: {bg_color}")
    
    # 覆盖声波：将鸟身体右边界之外、且在鸟垂直范围内的橙色像素用背景色覆盖
    margin = 5  # 留少量余量给嘴尖
    for row in range(by, by + bh):
        right = bird_right_boundary[row] + margin
        if right > 0 and right < w:
            # 这一行中，右边界之外的所有像素用背景色覆盖
            img_clean[row, right:] = bg_color
    
    # === 第四步：覆盖眼睛 ===
    # 眼睛是鸟头部的深色小圆，在鸟身体上半部分
    # 用灰度找暗色区域
    gray_orig = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    # 眼睛区域：在鸟身体内部、颜色非常暗（黑色/深色）
    eye_mask = np.zeros_like(gray_orig)
    # 眼睛在鸟的上半部分
    bird_cy = by + bh // 2
    for row in range(by, bird_cy):
        for col in range(bx, bx + bw):
            if main_bird_mask[row, col] > 0 and gray_orig[row, col] < 80:
                eye_mask[row, col] = 255
    
    # 膨胀眼睛区域
    kernel_eye = np.ones((7, 7), np.uint8)
    eye_mask = cv2.dilate(eye_mask, kernel_eye, iterations=2)
    
    # 用周围的橙色覆盖眼睛
    # 取鸟身体的平均颜色
    bird_pixels = img[main_bird_mask > 0]
    avg_bird_color = np.mean(bird_pixels, axis=0).astype(np.uint8).tolist()
    print(f"Average bird color: {avg_bird_color}")
    img_clean[eye_mask > 0] = avg_bird_color
    
    cv2.imwrite(os.path.join(output_dir, "01_cleaned_image.png"), img_clean)
    
    # === 第五步：在清理后的图上做边缘检测 ===
    gray_clean = cv2.cvtColor(img_clean, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray_clean, (3, 3), 0)
    edges = cv2.Canny(blurred, 30, 120)
    
    cv2.imwrite(os.path.join(output_dir, "02_edges.png"), edges)
    
    # === 第六步：只保留鸟身体附近的边缘 ===
    # 膨胀鸟身体掩码，作为区域限制
    kernel_large = np.ones((25, 25), np.uint8)
    bird_region = cv2.dilate(main_bird_mask, kernel_large, iterations=2)
    final_edges = cv2.bitwise_and(edges, bird_region)
    
    # 膨胀使线条更粗（macOS 菜单栏图标需要较粗线条）
    kernel_thin = np.ones((3, 3), np.uint8)
    final_edges = cv2.dilate(final_edges, kernel_thin, iterations=2)
    
    cv2.imwrite(os.path.join(output_dir, "03_final_edges.png"), final_edges)
    
    # === 第七步：创建白色轮廓 + 透明背景的输出 ===
    result = np.zeros((h, w, 4), dtype=np.uint8)
    result[final_edges > 0] = [255, 255, 255, 255]
    
    cv2.imwrite(os.path.join(output_dir, "bird_outline_white.png"), result)
    print(f"Saved: {os.path.join(output_dir, 'bird_outline_white.png')}")
    
    # === 生成不同尺寸 ===
    for size in [512, 128, 64, 36, 18]:
        resized = cv2.resize(result, (size, size), interpolation=cv2.INTER_AREA)
        alpha = resized[:, :, 3]
        threshold = 64 if size <= 64 else 128
        resized[alpha < threshold] = [0, 0, 0, 0]
        resized[alpha >= threshold] = [255, 255, 255, 255]
        filename = f"bird_outline_white_{size}x{size}.png"
        cv2.imwrite(os.path.join(output_dir, filename), resized)
        print(f"Saved: {os.path.join(output_dir, filename)}")

if __name__ == "__main__":
    extract_bird_outline("logo_bird.png")
