#!/usr/bin/env python3
"""
Enhance mobile fee structure page:
- Compute stats in view (avg, min, max)
- Update template to use context variables
- Ensure more.html uses mobile_fee_structure
"""

import re

# 1. MODIFY views.py
VIEWS_FILE = "axis_saas/views.py"

with open(VIEWS_FILE, "r") as f:
    content = f.read()

# Insert stats computation after structures = list(...)
insert_point = "structures = list(FeeStructure.objects.all().order_by('grade'))"
stats_code = """
        # Compute stats
        total_structures = len(structures)
        if structures:
            fees = [fs.monthly_fee for fs in structures]
            avg_fee = sum(fees) / len(fees)
            min_fee = min(fees)
            max_fee = max(fees)
        else:
            avg_fee = min_fee = max_fee = 0
"""

if insert_point in content:
    # Insert after that line
    content = content.replace(insert_point, insert_point + "\n" + stats_code)
    print("✅ Inserted stats computation in views.py")
else:
    print("⚠️ Could not find insertion point. Skipping stats computation.")

# Replace old context with new one including stats
old_context = """    context = {
        'tenant': tenant,
        'form': form,
        'fee_structures': structures,
        'edit_grade': edit_grade,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'debug_count': len(structures),
    }"""

new_context = """    context = {
        'tenant': tenant,
        'form': form,
        'fee_structures': structures,
        'edit_grade': edit_grade,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'debug_count': len(structures),
        'total_structures': total_structures,
        'avg_fee': avg_fee,
        'min_fee': min_fee,
        'max_fee': max_fee,
    }"""

if old_context in content:
    content = content.replace(old_context, new_context)
    print("✅ Updated context with stats.")
else:
    print("⚠️ Could not find old context block. Please check manually.")

# Write back
with open(VIEWS_FILE, "w") as f:
    f.write(content)
print("✅ views.py updated.")

# 2. UPDATE TEMPLATE
TEMPLATE_FILE = "templates/mobile/fee_structure.html"
with open(TEMPLATE_FILE, "r") as f:
    template = f.read()

# Replace stats strip with new version using context variables
old_stats_block = """<!-- ===== STATS STRIP ===== -->
<div class="stats-strip">
  <div class="stat-card">
    <div class="stat-value">{{ fee_structures|length }}</div>
    <div class="stat-label">Total</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">
      {% if fee_structures %}
        ₹{{ fee_structures|map_attribute:"monthly_fee"|slice:":1"|first|default:0|floatformat:2 }}
      {% else %}
        ₹0
      {% endif %}
    </div>
    <div class="stat-label">Avg Fee</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">
      {% if fee_structures %}
        ₹{{ fee_structures|map_attribute:"monthly_fee"|min|floatformat:2 }}
      {% else %}
        ₹0
      {% endif %}
    </div>
    <div class="stat-label">Min</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">
      {% if fee_structures %}
        ₹{{ fee_structures|map_attribute:"monthly_fee"|max|floatformat:2 }}
      {% else %}
        ₹0
      {% endif %}
    </div>
    <div class="stat-label">Max</div>
  </div>
</div>"""

new_stats_block = """<!-- ===== STATS STRIP ===== -->
<div class="stats-strip">
  <div class="stat-card">
    <div class="stat-value">{{ total_structures }}</div>
    <div class="stat-label">Total</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">₹{{ avg_fee|floatformat:2 }}</div>
    <div class="stat-label">Avg Fee</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">₹{{ min_fee|floatformat:2 }}</div>
    <div class="stat-label">Min</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">₹{{ max_fee|floatformat:2 }}</div>
    <div class="stat-label">Max</div>
  </div>
</div>"""

if old_stats_block in template:
    template = template.replace(old_stats_block, new_stats_block)
    print("✅ Updated stats strip in template.")
else:
    print("⚠️ Could not find old stats block in template. Skipping.")

# Write back
with open(TEMPLATE_FILE, "w") as f:
    f.write(template)

print("\n✅ All changes applied. Restart the server to see the enhanced mobile fee structure page.")
