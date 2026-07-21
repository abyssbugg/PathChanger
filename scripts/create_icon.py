#!/usr/bin/env python3
"""Create PathChanger app icon - modern location pin design.

Manual developer tool only. It is NOT part of the app runtime or CI, and its
generated assets under Resources/AppIcon.iconset are committed to the repo.
Regenerate only when the brand icon changes. Requires Pillow, which is a
dev-only dependency intentionally excluded from requirements-pathchanger.txt:

    pip install pillow
    python3 scripts/create_icon.py
"""

from PIL import Image, ImageDraw
import math
import os

def create_location_icon(size):
    """Create a modern location pin icon with gradient background"""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    padding = size * 0.08
    center_x = size / 2
    center_y = size / 2
    
    # Background - rounded square with gradient-like effect
    bg_radius = size * 0.22
    bg_rect = [padding, padding, size - padding, size - padding]
    
    # Draw gradient background (dark blue to lighter blue)
    for i in range(int(size - 2 * padding)):
        progress = i / (size - 2 * padding)
        r = int(20 + progress * 30)
        g = int(40 + progress * 60)
        b = int(80 + progress * 100)
        y = padding + i
        draw.line([(padding, y), (size - padding, y)], fill=(r, g, b, 255))
    
    # Create mask for rounded corners
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(bg_rect, radius=bg_radius, fill=255)
    
    # Apply mask
    img.putalpha(mask)
    
    # Draw location pin
    pin_color = (59, 130, 246)  # Blue
    pin_highlight = (147, 197, 253)  # Light blue
    white = (255, 255, 255)
    
    # Pin dimensions
    pin_width = size * 0.4
    pin_height = size * 0.55
    pin_top = size * 0.15
    pin_center_x = center_x
    
    # Draw pin body (teardrop shape)
    # Top circle
    circle_radius = pin_width / 2
    circle_center_y = pin_top + circle_radius
    
    # Draw the pin shape using polygon
    points = []
    # Top arc
    for angle in range(180, 361):
        rad = math.radians(angle)
        x = pin_center_x + circle_radius * math.cos(rad)
        y = circle_center_y + circle_radius * math.sin(rad)
        points.append((x, y))
    
    # Bottom point
    bottom_y = pin_top + pin_height
    points.append((pin_center_x, bottom_y))
    
    # Close the shape
    for angle in range(0, 181):
        rad = math.radians(angle)
        x = pin_center_x + circle_radius * math.cos(rad)
        y = circle_center_y + circle_radius * math.sin(rad)
        points.append((x, y))
    
    draw = ImageDraw.Draw(img)
    draw.polygon(points, fill=pin_color)
    
    # Inner white circle
    inner_radius = circle_radius * 0.45
    inner_bbox = [
        pin_center_x - inner_radius,
        circle_center_y - inner_radius,
        pin_center_x + inner_radius,
        circle_center_y + inner_radius
    ]
    draw.ellipse(inner_bbox, fill=white)
    
    # Small blue dot in center
    dot_radius = inner_radius * 0.4
    dot_bbox = [
        pin_center_x - dot_radius,
        circle_center_y - dot_radius,
        pin_center_x + dot_radius,
        circle_center_y + dot_radius
    ]
    draw.ellipse(dot_bbox, fill=pin_color)
    
    # Add subtle highlight on pin
    highlight_radius = circle_radius * 0.25
    highlight_offset_x = -circle_radius * 0.25
    highlight_offset_y = -circle_radius * 0.25
    highlight_bbox = [
        pin_center_x + highlight_offset_x - highlight_radius,
        circle_center_y + highlight_offset_y - highlight_radius,
        pin_center_x + highlight_offset_x + highlight_radius,
        circle_center_y + highlight_offset_y + highlight_radius
    ]
    
    # Create highlight with transparency
    highlight_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight_img)
    highlight_draw.ellipse(highlight_bbox, fill=(255, 255, 255, 60))
    img = Image.alpha_composite(img, highlight_img)
    
    return img

def main():
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    base_path = os.path.join(project_root, "Resources", "AppIcon.iconset")
    os.makedirs(base_path, exist_ok=True)
    
    # macOS icon sizes
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    for size, filename in sizes:
        icon = create_location_icon(size)
        icon.save(os.path.join(base_path, filename), "PNG")
        print(f"Created {filename} ({size}x{size})")
    
    print("\nIconset created successfully!")
    print(f"Run: iconutil -c icns {base_path}")

if __name__ == "__main__":
    main()
