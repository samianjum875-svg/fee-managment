#!/usr/bin/env python3
"""
AXIS PWA Patcher – Fixes installability and adds a floating install button.
Run this script once from the project root (where manage.py is).
"""

import os
import sys
import shutil
from pathlib import Path

# ----------------------------------------------------------------------
# 1. Generate PWA icons using Pillow
# ----------------------------------------------------------------------
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("❌ Pillow not installed. Installing...")
    os.system(f"{sys.executable} -m pip install Pillow")
    from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(os.getcwd())
STATIC_PWA_DIR = PROJECT_ROOT / "axis_saas" / "static" / "pwa"

def ensure_dir(path):
    path.mkdir(parents=True, exist_ok=True)

def create_icon(size, output_path, text="AXIS"):
    """Generate a simple icon with a gradient background and text."""
    img = Image.new('RGB', (size, size), color=(59, 130, 246))
    draw = ImageDraw.Draw(img)

    # Draw a slightly rounded rectangle overlay
    rect_margin = size // 8
    draw.rectangle(
        [rect_margin, rect_margin, size - rect_margin, size - rect_margin],
        fill=(37, 99, 235),
        outline=None
    )

    # Add text
    try:
        # Try to use a default font
        font_size = size // 3
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
    except:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (size - text_width) // 2
    y = (size - text_height) // 2
    draw.text((x, y), text, fill="white", font=font)

    img.save(output_path)
    print(f"✅ Created icon: {output_path}")

# Create icons
ensure_dir(STATIC_PWA_DIR)
create_icon(192, STATIC_PWA_DIR / "icon-192x192.png")
create_icon(512, STATIC_PWA_DIR / "icon-512x512.png")

# ----------------------------------------------------------------------
# 2. Update pwa_views.py – new service worker with proper caching
# ----------------------------------------------------------------------
PWA_VIEWS_PATH = PROJECT_ROOT / "axis_saas" / "pwa_views.py"

if not PWA_VIEWS_PATH.exists():
    print(f"❌ {PWA_VIEWS_PATH} not found. Ensure the script is run from the project root.")
    sys.exit(1)

with open(PWA_VIEWS_PATH, "r") as f:
    content = f.read()

# Replace the service_worker function content with a robust one
new_sw = '''def service_worker(request):
    """Service Worker for AXIS PWA – modern caching strategy."""
    sw_js = """// AXIS PWA Service Worker
const CACHE_NAME = 'axis-pwa-v2';
const STATIC_EXTENSIONS = ['css', 'js', 'png', 'jpg', 'svg', 'ico', 'json', 'woff2'];
const STATIC_URLS = [
    '/static/pwa/icon-192x192.png',
    '/static/pwa/icon-512x512.png',
    '/static/css/base.css',   // adjust if you have a main CSS file
];

// Install: cache essential static files
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => {
                return cache.addAll(STATIC_URLS)
                    .catch(err => console.warn('Could not cache static URLs:', err));
            })
            .then(() => self.skipWaiting())
    );
});

// Activate: claim clients and clean old caches
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(keys => {
            return Promise.all(
                keys.filter(key => key !== CACHE_NAME)
                    .map(key => caches.delete(key))
            );
        }).then(() => self.clients.claim())
    );
});

// Fetch: cache-first for static files, network-first for everything else
self.addEventListener('fetch', event => {
    const url = new URL(event.request.url);
    const isStatic = STATIC_EXTENSIONS.some(ext => url.pathname.endsWith('.' + ext));
    if (isStatic || url.pathname.startsWith('/static/')) {
        event.respondWith(
            caches.match(event.request)
                .then(response => response || fetch(event.request))
                .catch(() => {
                    // Offline fallback for static files
                    return new Response('Offline', { status: 503 });
                })
        );
    } else {
        // For other requests (HTML, API), try network first, fallback to cache
        event.respondWith(
            fetch(event.request)
                .then(response => {
                    // Cache a copy for offline use
                    const clone = response.clone();
                    caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                    return response;
                })
                .catch(() => caches.match(event.request))
        );
    }
});
"""
    return HttpResponse(sw_js, content_type='application/javascript')
'''

# Find the old service_worker function and replace it
import re
pattern = r'def service_worker\(request\):.*?(?=def |$)'
if re.search(pattern, content, re.DOTALL):
    content = re.sub(pattern, new_sw, content, flags=re.DOTALL)
    print("✅ Updated pwa_views.py with new service worker.")
else:
    print("❌ Could not find service_worker function in pwa_views.py")
    sys.exit(1)

with open(PWA_VIEWS_PATH, "w") as f:
    f.write(content)

# ----------------------------------------------------------------------
# 3. Ensure manifest in pwa_views.py points to the correct icons
# ----------------------------------------------------------------------
# The manifest already uses /static/pwa/icon-192x192.png, which is fine.
# No changes needed.

# ----------------------------------------------------------------------
# 4. Update base.html to hide install button when already installed
# ----------------------------------------------------------------------
BASE_HTML = PROJECT_ROOT / "templates" / "tenant" / "base.html"

if BASE_HTML.exists():
    with open(BASE_HTML, "r") as f:
        base_content = f.read()

    # Add a style to hide the install button when in standalone mode
    hide_style = """
    @media all and (display-mode: standalone) {
        #pwaInstallContainer { display: none !important; }
    }
    """
    if "display-mode: standalone" not in base_content:
        # Insert before </head> or into style section
        if "</style>" in base_content:
            base_content = base_content.replace("</style>", hide_style + "</style>")
        else:
            # Fallback: add a style block at the end of head
            base_content = base_content.replace("</head>", f"<style>{hide_style}</style></head>")
        with open(BASE_HTML, "w") as f:
            f.write(base_content)
        print("✅ Updated base.html: install button hidden in standalone mode.")
    else:
        print("ℹ️  base.html already has standalone-mode hiding.")

# ----------------------------------------------------------------------
# 5. Instructions
# ----------------------------------------------------------------------
print("\n" + "="*60)
print("✅ PWA PATCH COMPLETE!")
print("="*60)
print("\nNext steps:")
print("1. Run `python manage.py collectstatic --noinput` to copy the new icons to STATIC_ROOT.")
print("2. Restart your Django server.")
print("3. Visit your tenant portal (e.g., /portal/your-school/).")
print("4. The floating install button (bottom-right) should appear.")
print("5. Click it to add the app to your home screen.")
print("\nIf the button doesn't appear, ensure:")
print("   - Your browser supports PWA (Chrome, Edge, Samsung Internet, etc.)")
print("   - You are using HTTPS or localhost.")
print("   - The service worker registers successfully (check DevTools -> Application -> Service Workers).")
