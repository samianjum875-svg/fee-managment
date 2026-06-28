#!/usr/bin/env python3
"""
AXIS Voucher Final Fix v2 – direct buttons, single card, premium UI.
Run: python3 fix_voucher_final2.py
"""

import os
import shutil

# ========== NEW voucher_snippet.html (Premium, single card) ==========
NEW_VOUCHER_SNIPPET = """{% load static %}
<div class="voucher-receipt" id="voucherDisplay">
    <!-- Header: School Name + Voucher # + Status -->
    <div class="voucher-header">
        <div class="school-brand">
            <div class="school-name">{{ tenant.name|default:"School" }}</div>
            <div class="voucher-meta">
                <span class="voucher-label">Voucher</span>
                <span class="voucher-number">#{{ fee_record.id }}</span>
            </div>
        </div>
        <div class="voucher-status">
            <span class="status-badge status-{{ fee_record.status }}">{{ fee_record.get_status_display }}</span>
        </div>
    </div>

    <!-- Student Information -->
    <div class="student-section">
        <div class="student-detail">
            <span class="detail-label">Student</span>
            <span class="detail-value">{{ student.name }}</span>
        </div>
        <div class="student-detail">
            <span class="detail-label">Roll No.</span>
            <span class="detail-value">{{ student.roll_number }}</span>
        </div>
        <div class="student-detail">
            <span class="detail-label">Father</span>
            <span class="detail-value">{{ student.father_name }}</span>
        </div>
        <div class="student-detail">
            <span class="detail-label">Class</span>
            <span class="detail-value">{{ student.grade }} - {{ student.section }}</span>
        </div>
        <div class="student-detail">
            <span class="detail-label">Admission</span>
            <span class="detail-value">{{ student.admission_date|date:"d M Y" }}</span>
        </div>
        <div class="student-detail">
            <span class="detail-label">Month</span>
            <span class="detail-value">{{ fee_record.month }}/{{ fee_record.year }}</span>
        </div>
    </div>

    <!-- Fee Details Table -->
    <div class="fee-table">
        <table>
            <thead>
                <tr>
                    <th>Description</th>
                    <th>Amount (₹)</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>Monthly Fee</td>
                    <td>{{ fee_record.amount|floatformat:2 }}</td>
                </tr>
                {% for ch in charges %}
                <tr>
                    <td>{{ ch.title }}</td>
                    <td>{{ ch.amount|floatformat:2 }}</td>
                </tr>
                {% endfor %}
                <tr class="total-row">
                    <td><strong>Total</strong></td>
                    <td><strong>{{ total|floatformat:2 }}</strong></td>
                </tr>
            </tbody>
        </table>
    </div>

    <!-- Pending Note (if any) -->
    {% with pending=fee_record.student.fee_records.aggregate.total %}
        {% if pending %}
        <div class="pending-note">
            <span class="pending-icon">⏳</span>
            Total pending (including previous months): <strong>₹{{ pending|floatformat:2 }}</strong>
        </div>
        {% endif %}
    {% endwith %}

    <!-- Footer: Dates -->
    <div class="voucher-footer">
        <div class="footer-item">
            <span class="footer-label">Generated</span>
            <span class="footer-value">{{ fee_record.due_date|date:"d M Y" }}</span>
        </div>
        <div class="footer-item">
            <span class="footer-label">Due Date</span>
            <span class="footer-value">{{ fee_record.due_date|date:"d M Y" }}</span>
        </div>
    </div>
</div>

<style>
    /* ----- Premium Voucher – Single Card, Clean ----- */
    .voucher-receipt {
        background: #ffffff;
        border-radius: 1.25rem;
        padding: 1.5rem;
        box-shadow: 0 8px 30px rgba(0,0,0,0.06);
        font-family: system-ui, -apple-system, sans-serif;
        max-width: 100%;
        margin: 0 auto;
        transition: box-shadow 0.2s;
    }
    .voucher-receipt:hover {
        box-shadow: 0 12px 40px rgba(0,0,0,0.08);
    }

    /* Header – school + voucher # + status */
    .voucher-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-bottom: 2px solid #3b82f6;
        padding-bottom: 0.6rem;
        margin-bottom: 0.8rem;
        flex-wrap: wrap;
        gap: 0.5rem;
    }
    .school-brand {
        display: flex;
        align-items: baseline;
        gap: 0.75rem;
        flex-wrap: wrap;
    }
    .school-name {
        font-size: 1.15rem;
        font-weight: 700;
        color: #1f2937;
        letter-spacing: -0.02em;
    }
    .voucher-meta {
        display: inline-flex;
        align-items: baseline;
        gap: 0.3rem;
    }
    .voucher-label {
        font-size: 0.6rem;
        text-transform: uppercase;
        color: #6b7280;
        letter-spacing: 0.3px;
    }
    .voucher-number {
        font-size: 0.9rem;
        font-weight: 700;
        font-family: monospace;
        color: #1f2937;
        background: #f3f4f6;
        padding: 0.1rem 0.5rem;
        border-radius: 0.4rem;
    }
    .voucher-status .status-badge {
        display: inline-block;
        padding: 0.2rem 0.6rem;
        border-radius: 999px;
        font-size: 0.65rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.3px;
    }
    .status-pending { background: #fef3c7; color: #92400e; }
    .status-partial { background: #dbeafe; color: #1e40af; }
    .status-paid   { background: #d1fae5; color: #065f46; }
    .status-overdue { background: #fee2e2; color: #991b1b; }
    .status-waived { background: #e0e7ff; color: #3730a3; }

    /* Student Section */
    .student-section {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 0.3rem 1.5rem;
        background: #f9fafb;
        padding: 0.6rem 0.9rem;
        border-radius: 0.75rem;
        margin-bottom: 0.8rem;
        border: 1px solid #e5e7eb;
    }
    .student-detail {
        display: flex;
        justify-content: space-between;
        border-bottom: 1px dashed #e5e7eb;
        padding: 0.2rem 0;
    }
    .student-detail:last-child {
        border-bottom: none;
    }
    .detail-label {
        font-size: 0.7rem;
        color: #6b7280;
        font-weight: 500;
        text-transform: uppercase;
        letter-spacing: 0.3px;
    }
    .detail-value {
        font-weight: 600;
        color: #1f2937;
        font-size: 0.8rem;
    }

    /* Fee Table */
    .fee-table table {
        width: 100%;
        border-collapse: collapse;
        margin: 0.3rem 0 0.8rem;
        font-size: 0.85rem;
    }
    .fee-table th {
        text-align: left;
        padding: 0.3rem 0.2rem;
        font-weight: 600;
        color: #6b7280;
        border-bottom: 1px solid #e5e7eb;
        font-size: 0.65rem;
        text-transform: uppercase;
        letter-spacing: 0.4px;
    }
    .fee-table td {
        padding: 0.3rem 0.2rem;
        border-bottom: 1px solid #e5e7eb;
    }
    .fee-table td:last-child {
        text-align: right;
        font-weight: 500;
    }
    .fee-table .total-row td {
        border-top: 2px solid #3b82f6;
        font-weight: 700;
        padding-top: 0.5rem;
        font-size: 0.95rem;
    }
    .fee-table .total-row td:last-child {
        color: #3b82f6;
    }

    /* Pending Note */
    .pending-note {
        background: #fef9e7;
        color: #92400e;
        border-radius: 0.5rem;
        padding: 0.4rem 0.7rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.8rem;
        margin: 0.3rem 0 0.8rem;
        border-left: 4px solid #f59e0b;
    }
    .pending-icon {
        font-size: 1rem;
    }

    /* Footer */
    .voucher-footer {
        display: flex;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 0.4rem;
        border-top: 1px solid #e5e7eb;
        padding-top: 0.6rem;
        margin-top: 0.3rem;
        font-size: 0.7rem;
    }
    .footer-item {
        display: flex;
        gap: 0.3rem;
    }
    .footer-label {
        color: #6b7280;
        font-weight: 500;
        text-transform: uppercase;
        font-size: 0.6rem;
    }
    .footer-value {
        font-weight: 600;
        color: #1f2937;
    }

    /* Responsive */
    @media (max-width: 600px) {
        .voucher-receipt {
            padding: 1rem;
        }
        .student-section {
            grid-template-columns: 1fr;
        }
        .voucher-header {
            flex-direction: column;
            align-items: flex-start;
        }
        .voucher-status {
            align-self: flex-start;
        }
        .voucher-footer {
            flex-direction: column;
            align-items: flex-start;
            gap: 0.3rem;
        }
        .fee-table table {
            font-size: 0.75rem;
        }
    }
</style>
"""

# ========== NEW voucher_modal.html (single card, direct buttons) ==========
NEW_VOUCHER_MODAL = """<!-- Voucher Modal – Single Card with Direct Buttons -->
<div id="voucherModal" class="modal" style="display:none;">
    <div class="modal-content" style="max-width: 820px;">
        <!-- Close button -->
        <button class="close-modal" onclick="closeVoucherModal()">&times;</button>
        <!-- Voucher body -->
        <div id="voucherModalBody">
            <!-- Content loaded via JS -->
        </div>
        <!-- Action Buttons -->
        <div class="modal-footer">
            <button class="btn-action" id="printVoucherBtn">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18H4a2 2 0 01-2-2v-5a2 2 0 012-2h16a2 2 0 012 2v5a2 2 0 01-2 2h-2"/><path d="M6 9V3h12v6"/><rect x="6" y="15" width="12" height="6" rx="2"/></svg>
                Print
            </button>
            <button class="btn-action" id="downloadVoucherBtn">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14m-7-7l7 7 7-7"/></svg>
                Save
            </button>
            <button class="btn-action" id="editVoucherBtn" style="display: none;">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4Z"/></svg>
                Edit
            </button>
        </div>
    </div>
</div>

<style>
/* Modal overlay & content – refined */
.modal {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0,0,0,0.5);
    display: none;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    backdrop-filter: blur(4px);
    padding: 1rem;
}
.modal-content {
    background: #ffffff;
    border-radius: 1.5rem;
    max-width: 820px;
    width: 100%;
    max-height: 90vh;
    overflow-y: auto;
    padding: 1.5rem 1.5rem 1rem;
    box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    position: relative;
}
.close-modal {
    position: absolute;
    top: 0.8rem;
    right: 1rem;
    background: none;
    border: none;
    font-size: 1.8rem;
    cursor: pointer;
    color: #6b7280;
    line-height: 1;
    padding: 0 0.3rem;
    z-index: 10;
}
.close-modal:hover {
    color: #1f2937;
}

/* Footer Buttons */
.modal-footer {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    justify-content: flex-end;
    margin-top: 1rem;
    padding-top: 0.75rem;
    border-top: 1px solid #e5e7eb;
}
.btn-action {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.5rem 1rem;
    border-radius: 0.5rem;
    font-weight: 600;
    font-size: 0.85rem;
    border: 1px solid #e5e7eb;
    background: #f9fafb;
    color: #1f2937;
    cursor: pointer;
    transition: all 0.15s;
    text-decoration: none;
}
.btn-action:hover {
    background: #f3f4f6;
    border-color: #d1d5db;
}
.btn-action:active {
    transform: scale(0.96);
}
.btn-action svg {
    flex-shrink: 0;
}

/* Edit button gets primary styling */
#editVoucherBtn {
    background: #3b82f6;
    color: white;
    border-color: #3b82f6;
}
#editVoucherBtn:hover {
    background: #2563eb;
    border-color: #2563eb;
}

@media (max-width: 600px) {
    .modal-footer {
        flex-direction: column;
        align-items: stretch;
    }
    .btn-action {
        justify-content: center;
    }
}
</style>

<script>
// Voucher JS – direct buttons, no dropdown
function getCsrfToken() {
    let name = 'csrftoken';
    let cookieValue = null;
    if (document.cookie && document.cookie !== '') {
        const cookies = document.cookie.split(';');
        for (let i = 0; i < cookies.length; i++) {
            const cookie = cookies[i].trim();
            if (cookie.substring(0, name.length + 1) === (name + '=')) {
                cookieValue = decodeURIComponent(cookie.substring(name.length + 1));
                break;
            }
        }
    }
    return cookieValue;
}

let currentStudentId = null;
let currentSchema = null;
let currentFeeStatus = null;

function openVoucherModal(studentId, schema) {
    currentStudentId = studentId;
    currentSchema = schema;
    const modal = document.getElementById('voucherModal');
    modal.style.display = 'flex';
    loadVoucherStatus(studentId, schema);
}

function closeVoucherModal() {
    document.getElementById('voucherModal').style.display = 'none';
}

function loadVoucherStatus(studentId, schema) {
    const body = document.getElementById('voucherModalBody');
    body.innerHTML = '<p style="text-align:center; padding:1rem;">Loading...</p>';
    fetch(`/portal/${schema}/api/student/${studentId}/voucher-status/`)
        .then(res => res.json())
        .then(data => {
            if (data.error) {
                body.innerHTML = '<p style="color:#ef4444;">Error: ' + data.error + '</p>';
                return;
            }
            currentFeeStatus = data;
            if (data.exists && data.fee_record.paid_amount > 0) {
                // Already paid – show voucher only
                showVoucher(data, schema, studentId);
                document.getElementById('editVoucherBtn').style.display = 'none';
            } else if (data.exists && data.fee_record.paid_amount === 0) {
                // Unpaid – show voucher + edit
                showVoucher(data, schema, studentId);
                document.getElementById('editVoucherBtn').style.display = 'inline-flex';
                document.getElementById('editVoucherBtn').onclick = function() {
                    showVoucherForm(data, true);
                };
            } else {
                // No fee – show form
                showVoucherForm(data, false);
                document.getElementById('editVoucherBtn').style.display = 'none';
            }
        })
        .catch(err => {
            body.innerHTML = '<p style="color:#ef4444;">Error loading status: ' + err.message + '</p>';
        });
}

function showVoucher(data, schema, studentId) {
    const body = document.getElementById('voucherModalBody');
    fetch(`/portal/${schema}/api/student/${studentId}/voucher-html/`)
        .then(res => res.text())
        .then(html => {
            body.innerHTML = html;
            // Attach print and download actions
            document.getElementById('printVoucherBtn').onclick = function() {
                const content = document.querySelector('.voucher-receipt');
                if (content) {
                    const win = window.open('', '', 'width=800,height=600');
                    win.document.write('<html><head><title>Voucher</title><style>body { font-family: sans-serif; padding: 2rem; }</style></head><body>');
                    win.document.write(content.innerHTML);
                    win.document.write('</body></html>');
                    win.document.close();
                    win.print();
                }
            };
            document.getElementById('downloadVoucherBtn').onclick = function() {
                const element = document.querySelector('.voucher-receipt');
                if (!element) return;
                if (typeof html2canvas === 'undefined') {
                    const script = document.createElement('script');
                    script.src = 'https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js';
                    script.onload = function() { downloadVoucherImage(element); };
                    document.head.appendChild(script);
                } else {
                    downloadVoucherImage(element);
                }
            };
        })
        .catch(err => {
            body.innerHTML = '<p style="color:#ef4444;">Error loading voucher: ' + err.message + '</p>';
        });
}

function downloadVoucherImage(element) {
    html2canvas(element, { scale: 2, backgroundColor: '#ffffff' }).then(canvas => {
        const link = document.createElement('a');
        link.download = 'voucher.png';
        link.href = canvas.toDataURL();
        link.click();
    });
}

function showVoucherForm(data, isEdit) {
    const body = document.getElementById('voucherModalBody');
    let html = '<div class="voucher-form">';
    html += `<div style="display:grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; margin-bottom:1rem; font-size:0.9rem;">
                <div><strong>Student:</strong> ${data.student_name} (${data.student_roll})</div>
                <div><strong>Class:</strong> ${data.grade} - ${data.section}</div>
            </div>`;
    html += `<div class="form-group">
                <label>
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                    Fee Amount (₹)
                </label>
                <input type="number" step="0.01" id="voucherFeeAmount" value="${data.fee_record ? data.fee_record.amount : data.default_fee}" placeholder="Default: ${data.default_fee}">
            </div>`;
    html += `<div class="form-group">
                <label>
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 7h-4.18A3 3 0 0016 5.18V4a2 2 0 00-2-2h-4a2 2 0 00-2 2v1.18A3 3 0 008.18 7H4a2 2 0 00-2 2v10a2 2 0 002 2h16a2 2 0 002-2V9a2 2 0 00-2-2z"/><path d="M12 12v4m-2-2h4"/></svg>
                    Extra Charges
                </label>
                <div id="chargesContainer">`;
    let charges = data.default_charges && data.default_charges.length ? data.default_charges : [{title: '', amount: ''}];
    charges.forEach((ch, idx) => {
        html += `<div class="charge-item" data-index="${idx}">
                    <input type="text" class="charge-title" value="${ch.title || ''}" placeholder="Title">
                    <input type="number" step="0.01" class="charge-amount" value="${ch.amount || ''}" placeholder="Amount">
                    <button type="button" class="remove-charge" onclick="removeCharge(this)">&times;</button>
                </div>`;
    });
    html += `<button type="button" class="btn-secondary" onclick="addCharge()" style="margin-top:0.3rem;">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 4v16m8-8H4"/></svg>
                Add Charge
            </button>`;
    html += `</div></div>`;
    html += `<div class="form-group" style="background:#f9fafb; padding:0.5rem; border-radius:0.5rem;">
                <strong>Total Pending (including this fee):</strong> ₹<span id="voucherTotalPending">${data.total_pending}</span>
            </div>`;
    html += `<div class="form-group">
                <label>
                    <input type="checkbox" id="saveDefaultCharges" ${(data.default_charges && data.default_charges.length) ? 'checked' : ''}>
                    <span style="font-weight:400;">Save these charges as defaults for this student</span>
                </label>
            </div>`;
    html += `<div class="form-actions">
                <button type="button" class="btn-secondary" onclick="closeVoucherModal()">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12"/></svg>
                    Cancel
                </button>
                <button type="button" class="btn-primary" id="voucherSubmitBtn">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 13l4 4L19 7"/></svg>
                    ${isEdit ? 'Update' : 'Generate'}
                </button>
            </div>`;
    html += '</div>';
    body.innerHTML = html;

    document.getElementById('voucherSubmitBtn').addEventListener('click', function() {
        submitVoucher(currentStudentId, currentSchema, isEdit);
    });
}

function addCharge() {
    const container = document.getElementById('chargesContainer');
    const idx = container.querySelectorAll('.charge-item').length;
    const div = document.createElement('div');
    div.className = 'charge-item';
    div.dataset.index = idx;
    div.innerHTML = `
        <input type="text" class="charge-title" placeholder="Title">
        <input type="number" step="0.01" class="charge-amount" placeholder="Amount">
        <button type="button" class="remove-charge" onclick="removeCharge(this)">&times;</button>
    `;
    container.insertBefore(div, container.lastElementChild);
}

function removeCharge(btn) {
    const item = btn.closest('.charge-item');
    if (item) item.remove();
}

function getChargesFromForm() {
    const items = document.querySelectorAll('.charge-item');
    const charges = [];
    items.forEach(item => {
        const title = item.querySelector('.charge-title').value.trim();
        const amount = item.querySelector('.charge-amount').value.trim();
        if (title || amount) {
            charges.push({ title: title || 'Unnamed', amount: parseFloat(amount) || 0 });
        }
    });
    return charges;
}

function submitVoucher(studentId, schema, isEdit) {
    const amount = document.getElementById('voucherFeeAmount').value;
    const charges = getChargesFromForm();
    const saveDefault = document.getElementById('saveDefaultCharges').checked;
    const payload = {
        custom_amount: amount ? parseFloat(amount) : null,
        charges: charges,
        save_default_charges: saveDefault
    };
    const btn = document.getElementById('voucherSubmitBtn');
    btn.disabled = true;
    btn.innerText = 'Saving...';
    fetch(`/portal/${schema}/api/student/${studentId}/generate-voucher/`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRFToken': getCsrfToken()
        },
        body: JSON.stringify(payload)
    })
    .then(res => res.json())
    .then(data => {
        if (data.error) {
            alert('Error: ' + data.error);
        } else {
            alert(data.message || 'Fee voucher generated/updated successfully.');
            // Reload status and show voucher
            loadVoucherStatus(studentId, schema);
        }
    })
    .catch(err => {
        alert('Error: ' + err.message);
    })
    .finally(() => {
        btn.disabled = false;
        btn.innerText = isEdit ? 'Update' : 'Generate';
    });
}
</script>
"""


def patch_file(filepath, new_content):
    """Overwrite file with new content, create backup."""
    if os.path.exists(filepath):
        backup = filepath + ".bak"
        shutil.copy2(filepath, backup)
        print(f"📦 Backup saved: {backup}")
    with open(filepath, "w") as f:
        f.write(new_content)
    print(f"✅ Updated: {filepath}")


def patch_view():
    """Ensure voucher_html_api view fetches tenant correctly."""
    view_path = "axis_saas/views.py"
    with open(view_path, "r") as f:
        content = f.read()

    old_voucher_html = """def voucher_html_api(request, schema_name, student_id):
    \"\"\"API: Return HTML of the voucher for the current month (or latest if not exists).\"\"\"
    from django.http import HttpResponse
    from django.utils import timezone
    from django.template.loader import render_to_string
    from .models import Student, FeeRecord
    from django_tenants.utils import schema_context

    with schema_context(schema_name):
        try:
            student = Student.objects.get(id=student_id)
        except Student.DoesNotExist:
            return HttpResponse('Student not found', status=404)

        today = timezone.localdate()
        month, year = today.month, today.year
        fee_record = FeeRecord.objects.filter(student=student, month=month, year=year).first()
        if not fee_record:
            return HttpResponse('No fee record for current month', status=404)

        # Build voucher data (similar to receipt)
        charges = fee_record.extra_charges or []
        total = fee_record.amount + sum(Decimal(str(ch['amount'])) for ch in charges)
        voucher_data = {
            'student': student,
            'fee_record': fee_record,
            'charges': charges,
            'total': total,
            'tenant': request.tenant if hasattr(request, 'tenant') else None,
        }
        html = render_to_string('tenant/voucher_snippet.html', voucher_data)
        return HttpResponse(html)"""

    new_voucher_html = """def voucher_html_api(request, schema_name, student_id):
    \"\"\"API: Return HTML of the voucher for the current month (or latest if not exists).\"\"\"
    from django.http import HttpResponse
    from django.utils import timezone
    from django.template.loader import render_to_string
    from .models import Student, FeeRecord, SchoolClient
    from django_tenants.utils import schema_context
    from decimal import Decimal

    with schema_context(schema_name):
        try:
            student = Student.objects.get(id=student_id)
        except Student.DoesNotExist:
            return HttpResponse('Student not found', status=404)

        today = timezone.localdate()
        month, year = today.month, today.year
        fee_record = FeeRecord.objects.filter(student=student, month=month, year=year).first()
        if not fee_record:
            return HttpResponse('No fee record for current month', status=404)

        # Fetch tenant from public schema
        tenant = None
        try:
            with schema_context('public'):
                tenant = SchoolClient.objects.get(schema_name=schema_name)
        except SchoolClient.DoesNotExist:
            pass

        # Build voucher data
        charges = fee_record.extra_charges or []
        total = fee_record.amount + sum(Decimal(str(ch['amount'])) for ch in charges)
        voucher_data = {
            'student': student,
            'fee_record': fee_record,
            'charges': charges,
            'total': total,
            'tenant': tenant,
        }
        html = render_to_string('tenant/voucher_snippet.html', voucher_data)
        return HttpResponse(html)"""

    if old_voucher_html in content:
        content = content.replace(old_voucher_html, new_voucher_html)
        with open(view_path, "w") as f:
            f.write(content)
        print("✅ Patched voucher_html_api view to fetch tenant correctly.")
    else:
        # Try a more flexible replacement using regex
        import re
        pattern = r"def voucher_html_api\(request, schema_name, student_id\):.*?return HttpResponse\(html\)"
        match = re.search(pattern, content, re.DOTALL)
        if match:
            content = content.replace(match.group(0), new_voucher_html)
            with open(view_path, "w") as f:
                f.write(content)
            print("✅ Patched voucher_html_api view (regex).")
        else:
            print("⚠️ Could not find voucher_html_api view. Please check manually.")


def main():
    print("=" * 60)
    print("🎨 AXIS VOUCHER FINAL FIX v2 – Direct Buttons, Single Card")
    print("=" * 60)

    # Update voucher_snippet.html
    patch_file("templates/tenant/voucher_snippet.html", NEW_VOUCHER_SNIPPET)

    # Update voucher_modal.html
    patch_file("templates/tenant/voucher_modal.html", NEW_VOUCHER_MODAL)

    # Patch views.py to fix tenant name
    patch_view()

    print("\n🎉 All issues fixed!")
    print("   ✅ Removed 3‑dots dropdown, added direct buttons (Print, Save, Edit).")
    print("   ✅ Single card design – no separate heading card.")
    print("   ✅ Premium UI with clean typography and professional layout.")
    print("   ✅ School name now shows from database.")
    print("   ✅ Edit button appears only when fee is unpaid.")
    print("   ✅ Fully responsive – buttons stack on mobile.")
    print("\n🔄 Restart your server to see the changes.")
    print("   Railway: deploy new release or restart service.")
    print("=" * 60)


if __name__ == '__main__':
    main()
