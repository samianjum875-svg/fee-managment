import os

TEMPLATES_DIR = "templates/tenant"

# 1. Fee Structure
fee_structure_html = '''{% extends 'tenant/base.html' %}
{% load static %}
{% block title %}Fee Structure | {{ tenant.name }}{% endblock %}
{% block nav_fee_active %}active{% endblock %}

{% block body %}
<div class="page-head">
    <div>
        <h1 class="page-title">Fee Structure</h1>
        <p class="page-description">Set monthly fee per class/grade</p>
    </div>
</div>

<div class="page-card">
    <h3 style="margin-bottom: 20px;">Add/Update Fee</h3>
    <form method="post" class="form-card" style="margin-top: 0;">
        {% csrf_token %}
        <div class="field-card">
            <label>Class/Grade</label>
            {{ form.grade }}
        </div>
        <div class="field-card">
            <label>Monthly Fee (Rs)</label>
            {{ form.monthly_fee }}
        </div>
        <div style="margin-top: 20px;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
                </svg>
                Save Fee
            </button>
        </div>
    </form>
</div>

<div class="page-card">
    <h3>Current Fee Structure</h3>
    <div style="overflow-x: auto;">
        <table class="data-table">
            <thead>
                <tr>
                    <th>Class/Grade</th>
                    <th>Monthly Fee (Rs)</th>
                    <th>Last Updated</th>
                </tr>
            </thead>
            <tbody>
                {% for fs in fee_structures %}
                <tr>
                    <td><strong>{{ fs.grade }}</strong></td>
                    <td>Rs {{ fs.monthly_fee }}</td>
                    <td>{{ fs.updated_at|date:"Y-m-d" }}</td>
                </tr>
                {% empty %}
                <tr>
                    <td colspan="3" style="text-align: center;">No fee structures defined yet.</td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<style>
    .btn-primary {
        background: var(--primary);
        color: white;
        padding: 10px 20px;
        border-radius: 6px;
        border: none;
        font-weight: 600;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        transition: background 0.2s;
    }
    .btn-primary:hover { background: var(--primary-strong); }
    .data-table {
        width: 100%;
        border-collapse: collapse;
    }
    .data-table th, .data-table td {
        padding: 12px;
        text-align: left;
        border-bottom: 1px solid var(--border);
    }
    .data-table th {
        background: var(--surface-alt);
        font-weight: 600;
        color: var(--muted);
        text-transform: uppercase;
        font-size: 0.75rem;
    }
</style>
{% endblock %}'''

# 2. Generate Fees
fee_generate_html = '''{% extends 'tenant/base.html' %}
{% block title %}Generate Fees | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-head">
    <h1 class="page-title">Generate Monthly Fees</h1>
    <p class="page-description">Generate fee records for a specific month/year</p>
</div>

<div class="page-card">
    <form method="post">
        {% csrf_token %}
        <div class="field-card">
            <label>Month</label>
            {{ form.month }}
        </div>
        <div class="field-card">
            <label>Year</label>
            {{ form.year }}
        </div>
        <div class="field-card" style="flex-direction: row; align-items: center; gap: 10px;">
            {{ form.generate_for_all }}
            <label>Generate for all active students (including those with existing records)</label>
        </div>
        <div style="margin-top: 20px;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                Generate Fees
            </button>
        </div>
    </form>
</div>

<style>
    .btn-primary {
        background: var(--primary);
        color: white;
        padding: 10px 20px;
        border-radius: 6px;
        border: none;
        font-weight: 600;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: 8px;
    }
    .btn-primary:hover { background: var(--primary-strong); }
</style>
{% endblock %}'''

# 3. Pending Fees
pending_fees_html = '''{% extends 'tenant/base.html' %}
{% block title %}Pending Fees | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-head">
    <div>
        <h1 class="page-title">Pending Fees</h1>
        <p class="page-description">View and manage outstanding fee records</p>
    </div>
    <div class="stat-badge">Total Pending: <strong>Rs {{ total_pending }}</strong></div>
</div>

<div class="page-card" style="overflow-x: auto;">
    <table class="data-table">
        <thead>
            <tr>
                <th>Roll No</th>
                <th>Student Name</th>
                <th>Month/Year</th>
                <th>Amount (Rs)</th>
                <th>Paid (Rs)</th>
                <th>Due Date</th>
                <th>Status</th>
                <th>Action</th>
            </tr>
        </thead>
        <tbody>
            {% for fr in fee_records %}
            <tr>
                <td>{{ fr.student.roll_number }}</td>
                <td>{{ fr.student.name }}</td>
                <td>{{ fr.month }}/{{ fr.year }}</td>
                <td>{{ fr.amount }}</td>
                <td>{{ fr.paid_amount }}</td>
                <td>{{ fr.due_date|date:"Y-m-d" }}</td>
                <td>
                    <span class="status-badge status-{{ fr.status }}">{{ fr.get_status_display }}</span>
                </td>
                <td>
                    <a href="{% url 'make_payment' schema_name=tenant.schema_name student_id=fr.student.id %}" class="btn-small">
                        Pay Now
                    </a>
                </td>
            </tr>
            {% empty %}
            <tr><td colspan="8" style="text-align: center;">No pending fees.</td></tr>
            {% endfor %}
        </tbody>
    </table>
</div>

<style>
    .stat-badge {
        background: var(--primary);
        color: white;
        padding: 8px 16px;
        border-radius: 40px;
        font-size: 0.9rem;
    }
    .data-table {
        width: 100%;
        border-collapse: collapse;
    }
    .data-table th, .data-table td {
        padding: 12px;
        text-align: left;
        border-bottom: 1px solid var(--border);
    }
    .data-table th {
        background: var(--surface-alt);
        font-weight: 600;
        color: var(--muted);
        text-transform: uppercase;
        font-size: 0.75rem;
    }
    .status-badge {
        display: inline-block;
        padding: 4px 10px;
        border-radius: 20px;
        font-size: 0.75rem;
        font-weight: 600;
    }
    .status-pending { background: #fff3e0; color: #e67e22; }
    .status-partial { background: #e6f0fa; color: #1e3a8a; }
    .status-paid { background: #e6f4ea; color: #137333; }
    .status-overdue { background: #fdeded; color: #c0392b; }
    .btn-small {
        background: var(--primary);
        color: white;
        padding: 6px 12px;
        border-radius: 4px;
        font-size: 0.8rem;
        text-decoration: none;
        display: inline-block;
    }
    .btn-small:hover { background: var(--primary-strong); }
</style>
{% endblock %}'''

# 4. Payment History
payment_history_html = '''{% extends 'tenant/base.html' %}
{% block title %}Payment History | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-head">
    <h1 class="page-title">Payment History</h1>
    <p class="page-description">All recorded fee transactions</p>
</div>

<div class="page-card" style="overflow-x: auto;">
    <table class="data-table">
        <thead>
            <tr>
                <th>Receipt No</th>
                <th>Student</th>
                <th>Amount (Rs)</th>
                <th>Date</th>
                <th>Mode</th>
                <th>Type</th>
                <th>Receipt</th>
            </tr>
        </thead>
        <tbody>
            {% for p in payments %}
            <tr>
                <td><code>{{ p.receipt_number }}</code></td>
                <td>{{ p.student.name }}</td>
                <td>Rs {{ p.amount }}</td>
                <td>{{ p.payment_date|date:"Y-m-d" }}</td>
                <td>{{ p.get_payment_mode_display }}</td>
                <td>{{ p.get_payment_type_display }}</td>
                <td>
                    <a href="{% url 'fee_receipt' schema_name=tenant.schema_name receipt_id=p.id %}" target="_blank" class="btn-small">
                        View
                    </a>
                </td>
            </tr>
            {% empty %}
            <tr><td colspan="7" style="text-align: center;">No payments recorded yet.</td></tr>
            {% endfor %}
        </tbody>
    </table>
</div>

<style>
    .data-table {
        width: 100%;
        border-collapse: collapse;
    }
    .data-table th, .data-table td {
        padding: 12px;
        text-align: left;
        border-bottom: 1px solid var(--border);
    }
    .data-table th {
        background: var(--surface-alt);
        font-weight: 600;
        color: var(--muted);
        text-transform: uppercase;
        font-size: 0.75rem;
    }
    .btn-small {
        background: var(--primary);
        color: white;
        padding: 6px 12px;
        border-radius: 4px;
        font-size: 0.8rem;
        text-decoration: none;
        display: inline-block;
    }
    code {
        background: var(--surface-alt);
        padding: 2px 6px;
        border-radius: 4px;
        font-family: monospace;
    }
</style>
{% endblock %}'''

# 5. Family Payment
family_payment_html = '''{% extends 'tenant/base.html' %}
{% block title %}Family Payment | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-head">
    <h1 class="page-title">Family Payment</h1>
    <p class="page-description">Pay fees for all children using father's CNIC</p>
</div>

<div class="page-card">
    <form method="post">
        {% csrf_token %}
        <div class="field-card">
            <label>Father CNIC</label>
            {{ form.father_cnic }}
        </div>
        <div class="field-card">
            <label>Amount to Pay (leave empty to pay all pending)</label>
            {{ form.amount }}
        </div>
        <div class="field-card">
            <label>Payment Mode</label>
            {{ form.payment_mode }}
        </div>
        <div class="field-card">
            <label>Remarks (Optional)</label>
            {{ form.remarks }}
        </div>
        <div style="margin-top: 20px;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm0 0v2"/>
                </svg>
                Process Payment
            </button>
        </div>
    </form>
</div>

<style>
    .btn-primary {
        background: var(--primary);
        color: white;
        padding: 10px 20px;
        border-radius: 6px;
        border: none;
        font-weight: 600;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: 8px;
    }
    .btn-primary:hover { background: var(--primary-strong); }
</style>
{% endblock %}'''

# 6. Fee Settings
fee_settings_html = '''{% extends 'tenant/base.html' %}
{% block title %}Fee Settings | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-head">
    <h1 class="page-title">Fee Generation Settings</h1>
    <p class="page-description">Configure automatic fee generation parameters</p>
</div>

<div class="page-card">
    <form method="post">
        {% csrf_token %}
        <div class="field-card">
            <label>Fee Generation Day (1-31)</label>
            {{ form.fee_generation_day }}
        </div>
        <div class="field-card">
            <label>Due Date Offset (days after generation)</label>
            {{ form.due_date_offset }}
        </div>
        <div class="field-card">
            <label>Late Fee Penalty (%)</label>
            {{ form.late_fee_penalty }}
        </div>
        <div style="margin-top: 20px;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                </svg>
                Save Settings
            </button>
        </div>
    </form>
</div>

<style>
    .btn-primary {
        background: var(--primary);
        color: white;
        padding: 10px 20px;
        border-radius: 6px;
        border: none;
        font-weight: 600;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: 8px;
    }
    .btn-primary:hover { background: var(--primary-strong); }
</style>
{% endblock %}'''

# 7. Make Payment
make_payment_html = '''{% extends 'tenant/base.html' %}
{% block title %}Make Payment | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-head">
    <div>
        <h1 class="page-title">Pay Fees for {{ student.name }}</h1>
        <p class="page-description">Pending Total: <strong>Rs {{ total_pending }}</strong></p>
    </div>
</div>

<div class="page-card">
    <form method="post">
        {% csrf_token %}
        <div class="field-card">
            <label>Amount (Rs)</label>
            {{ form.amount }}
        </div>
        <div class="field-card">
            <label>Payment Mode</label>
            {{ form.payment_mode }}
        </div>
        <div class="field-card">
            <label>Remarks (Optional)</label>
            {{ form.remarks }}
        </div>
        <div style="margin-top: 20px;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm0 0v2"/>
                </svg>
                Submit Payment
            </button>
        </div>
    </form>
</div>

<div class="page-card">
    <h3>Pending Fee Records</h3>
    <div style="overflow-x: auto;">
        <table class="data-table">
            <thead>
                <tr><th>Month/Year</th><th>Amount (Rs)</th><th>Paid (Rs)</th><th>Remaining (Rs)</th></tr>
            </thead>
            <tbody>
                {% for fr in pending_fees %}
                <tr>
                    <td>{{ fr.month }}/{{ fr.year }}</td>
                    <td>{{ fr.amount }}</td>
                    <td>{{ fr.paid_amount }}</td>
                    <td><strong>{{ fr.remaining }}</strong></td>
                </tr>
                {% empty %}
                <tr><td colspan="4">No pending fees for this student.</td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<style>
    .btn-primary {
        background: var(--primary);
        color: white;
        padding: 10px 20px;
        border-radius: 6px;
        border: none;
        font-weight: 600;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        gap: 8px;
    }
    .data-table {
        width: 100%;
        border-collapse: collapse;
    }
    .data-table th, .data-table td {
        padding: 10px;
        text-align: left;
        border-bottom: 1px solid var(--border);
    }
    .data-table th {
        background: var(--surface-alt);
        font-weight: 600;
        font-size: 0.75rem;
        text-transform: uppercase;
    }
</style>
{% endblock %}'''

# 8. Fee Receipt (improved layout)
fee_receipt_html = '''{% extends 'tenant/base.html' %}
{% block title %}Fee Receipt | {{ tenant.name }}{% endblock %}

{% block body %}
<div class="page-card" id="receipt" style="max-width: 800px; margin: 0 auto;">
    <div style="text-align: center; border-bottom: 1px solid var(--border); padding-bottom: 20px; margin-bottom: 20px;">
        {% if logo_url %}
            <img src="{{ logo_url }}" style="height: 60px; margin-bottom: 10px;">
        {% endif %}
        <h2>{{ tenant.name }}</h2>
        <p style="color: var(--muted);">Official Fee Receipt</p>
    </div>
    <div style="padding: 0 20px;">
        <div style="display: flex; justify-content: space-between; margin-bottom: 15px;">
            <div><strong>Receipt No:</strong> {{ payment.receipt_number }}</div>
            <div><strong>Date:</strong> {{ payment.payment_date|date:"Y-m-d" }}</div>
        </div>
        <div style="margin-bottom: 15px;">
            <div><strong>Student Name:</strong> {{ payment.student.name }}</div>
            <div><strong>Father's Name:</strong> {{ payment.student.father_name }}</div>
        </div>
        <div style="margin-bottom: 15px;">
            <div><strong>Amount Paid:</strong> Rs {{ payment.amount }}</div>
            <div><strong>Payment Mode:</strong> {{ payment.get_payment_mode_display }}</div>
            <div><strong>Remarks:</strong> {{ payment.remarks|default:"-" }}</div>
        </div>
        <hr>
        <h4 style="margin: 20px 0 10px;">Fee Details</h4>
        <table style="width: 100%; border-collapse: collapse;">
            <thead>
                <tr><th style="text-align: left; padding: 8px; background: var(--surface-alt);">Month/Year</th>
                    <th style="text-align: left; padding: 8px; background: var(--surface-alt);">Amount (Rs)</th>
                    <th style="text-align: left; padding: 8px; background: var(--surface-alt);">Paid (Rs)</th>
                    <th style="text-align: left; padding: 8px; background: var(--surface-alt);">Status</th>
                </tr>
            </thead>
            <tbody>
                {% for fr in fee_records %}
                <tr>
                    <td style="padding: 8px; border-bottom: 1px solid var(--border);">{{ fr.month }}/{{ fr.year }}</td>
                    <td style="padding: 8px; border-bottom: 1px solid var(--border);">{{ fr.amount }}</td>
                    <td style="padding: 8px; border-bottom: 1px solid var(--border);">{{ fr.paid_amount }}</td>
                    <td style="padding: 8px; border-bottom: 1px solid var(--border);">{{ fr.get_status_display }}</td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
        <div style="margin-top: 30px; text-align: center; font-size: 12px; color: var(--muted);">
            <p>This is a computer generated receipt. No signature required.</p>
            <p>Thank you for your payment!</p>
        </div>
    </div>
</div>
<div style="text-align: center; margin-top: 20px;">
    <button onclick="window.print()" class="btn-secondary">🖨️ Print Receipt</button>
    <button onclick="downloadReceipt()" class="btn-secondary">⬇️ Download as Image</button>
</div>

<script src="https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js"></script>
<script>
function downloadReceipt() {
    const element = document.getElementById('receipt');
    html2canvas(element, { scale: 2, backgroundColor: getComputedStyle(document.documentElement).getPropertyValue('--surface') }).then(canvas => {
        const link = document.createElement('a');
        link.download = 'receipt_{{ payment.receipt_number }}.png';
        link.href = canvas.toDataURL();
        link.click();
    });
}
</script>
<style>
    .btn-secondary {
        background: var(--surface-alt);
        color: var(--text);
        padding: 8px 16px;
        border-radius: 6px;
        border: 1px solid var(--border);
        font-weight: 500;
        cursor: pointer;
        margin: 0 5px;
    }
    .btn-secondary:hover {
        background: var(--surface);
    }
</style>
{% endblock %}'''

# Write files
files = {
    "fee_structure.html": fee_structure_html,
    "fee_generate.html": fee_generate_html,
    "pending_fees.html": pending_fees_html,
    "payment_history.html": payment_history_html,
    "family_payment.html": family_payment_html,
    "fee_settings.html": fee_settings_html,
    "make_payment.html": make_payment_html,
    "fee_receipt.html": fee_receipt_html,
}

for filename, content in files.items():
    filepath = os.path.join(TEMPLATES_DIR, filename)
    with open(filepath, "w") as f:
        f.write(content)
    print(f"✅ Updated {filename}")

print("\n✨ All fee management templates upgraded with professional UI/UX!")
print("👉 Restart server to see changes: python manage.py runserver")
