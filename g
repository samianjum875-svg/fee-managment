#!/usr/bin/env python3
"""
AXIS Gym Color Scheme Patcher
Replaces blue (#3b82f6) with orange (#f97316) for gym tenant only.
Run: python3 gym_color_patcher.py
"""

import re
from pathlib import Path

BASE_HTML = Path("templates/tenant/base.html")
GYM_RECEIPT = Path("templates/tenant/gym_receipt.html")

def patch_base_html():
    """Add tenant-type body class and gym-specific CSS override."""
    if not BASE_HTML.exists():
        print(f"❌ {BASE_HTML} not found. Run from project root.")
        return False

    content = BASE_HTML.read_text(encoding="utf-8")

    # 1. Add class to <body> tag if not already present
    if 'class="tenant-{{ tenant.tenant_type }}"' not in content:
        content = re.sub(r'<body([^>]*)>', r'<body\1 class="tenant-{{ tenant.tenant_type }}">', content, count=1)
        print("✅ Added tenant-type class to <body>")
    else:
        print("ℹ️ Body class already present")

    # 2. Inject gym color override block (only if not already there)
    override_block = """
    <!-- GYM COLOR OVERRIDE (injected by patcher) -->
    <style>
        .tenant-gym {
            --primary: #f97316;
            --primary-dark: #ea580c;
            --primary-light: #fdba74;
            --primary-bg: rgba(249,115,22,0.1);
        }
        /* Ensure gradient texts use new primary colors */
        .tenant-gym .page-title,
        .tenant-gym .school-info h2,
        .tenant-gym .summary-value {
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
        }
        /* Fix stats card icon color on gym */
        .tenant-gym .kpi-icon {
            color: var(--primary);
        }
        .tenant-gym .btn-primary {
            background: var(--primary);
        }
        .tenant-gym .btn-primary:hover {
            background: var(--primary-dark);
        }
        .tenant-gym .stat-badge[style*="background: var(--primary)"] {
            background: var(--primary) !important;
        }
        .tenant-gym .quick-filter-btn.active,
        .tenant-gym .tab.active {
            background: var(--primary);
        }
    </style>
    """
    if override_block not in content:
        # Insert before closing </head> or after existing style block
        if "</head>" in content:
            content = content.replace("</head>", f"{override_block}\n</head>")
        else:
            content += f"\n{override_block}\n"
        print("✅ Added gym CSS override block")
    else:
        print("ℹ️ CSS override already present")

    BASE_HTML.write_text(content, encoding="utf-8")
    return True


def patch_gym_receipt():
    """Ensure gym_receipt uses CSS variables instead of hardcoded orange."""
    if not GYM_RECEIPT.exists():
        print(f"⚠️ {GYM_RECEIPT} not found – skipping")
        return

    content = GYM_RECEIPT.read_text(encoding="utf-8")

    # Replace hardcoded gym header border color with variable
    content = re.sub(
        r'border-bottom-color:\s*#f97316;',
        'border-bottom-color: var(--primary);',
        content
    )
    content = re.sub(
        r'background:\s*#f97316;',
        'background: var(--primary);',
        content
    )
    content = re.sub(
        r'background:\s*linear-gradient\(135deg,\s*#f97316,\s*#ea580c\);',
        'background: linear-gradient(135deg, var(--primary), var(--primary-dark));',
        content
    )

    # Also fix any possible hardcoded blue leftovers
    content = re.sub(r'#3b82f6', 'var(--primary)', content)
    content = re.sub(r'#2563eb', 'var(--primary-dark)', content)

    GYM_RECEIPT.write_text(content, encoding="utf-8")
    print("✅ Updated gym_receipt.html to use CSS variables")


def main():
    print("🎨 AXIS Gym Color Patcher – Replacing blue with orange for gym only")
    if patch_base_html():
        patch_gym_receipt()
        print("\n✨ Done! The gym portal will now use a fresh orange color scheme.")
        print("   School portal remains blue. No manual changes needed.")
    else:
        print("\n❌ Patcher failed – please run from the root of your Django project.")


if __name__ == "__main__":
    main()
