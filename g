#!/usr/bin/env python3
"""
AXIS Voucher Enhancement Patcher
--------------------------------
- Adds premium UI to voucher (school logo, student details, fee breakdown, pending note, dates, status)
- Replaces action buttons with a three‑dot dropdown menu (Print, Save, Edit)
- Ensures voucher button exists on both desktop and mobile student profiles
- Fixes school name display from tenant database

Run: python3 voucher_enhancement_patcher.py
"""

import os
import re

# ----------------------------------------------
# 1. Updated voucher_snippet.html (premium design)
# ----------------------------------------------
NEW_VOUCHER_SNIPPET = """{% load static %}
<div class="voucher-receipt" id="voucherDisplay">
    <!-- Header: School Logo + Name -->
    <div class="voucher-header">
        <div class="school-brand">
            {% if tenant.school_logo %}
                <img src="{{ tenant.school_logo.url }}" alt="School Logo" class="school-logo">
            {% else %}
                <div class="logo-placeholder">{{ tenant.name|slice:":2"|upper }}</div>
            {% endif %}
            <div class="school-name">{{ tenant.name|default:"School" }}</div>
        </div>
        <div class="voucher-meta">
            <span class="voucher-label">Voucher #</span>
            <span class="voucher-number">{{ fee_record.id }}</span>
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
            <span class="pending-icon">⚠️</span>
            Total pending (including previous months): <strong>₹{{ pending|floatformat:2 }}</strong>
        </div>
        {% endif %}
    {% endwith %}

    <!-- Footer: Dates & Status -->
    <div class="voucher-footer">
        <div class="footer-item">
            <span class="footer-label">Generated on</span>
            <span class="footer-value">{{ fee_record.due_date|date:"d M Y" }}</span>
        </div>
        <div class="footer-item">
            <span class="footer-label">Due Date</span>
            <span class="footer-value">{{ fee_record.due_date|date:"d M Y" }}</span>
        </div>
        <div class="footer-item">
            <span class="footer-label">Status</span>
            <span class="footer-value status-badge status-{{ fee_record.status }}">{{ fee_record.get_status_display }}</span>
        </div>
    </div>
</div>

<style>
    /* --- Premium Voucher Styles --- */
    .voucher-receipt {
        background: var(--surface, #ffffff);
        border-radius: 1.25rem;
        padding: 1.5rem;
        border: 1px solid var(--border, #e2e8f0);
        box-shadow: 0 8px 30px rgba(0,0,0,0.06);
        font-family: system-ui, -apple-system, sans-serif;
        max-width: 100%;
        margin: 0 auto;
    }

    /* Header */
    .voucher-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        border-bottom: 2px solid var(--primary, #3b82f6);
        padding-bottom: 0.75rem;
        margin-bottom: 1rem;
        flex-wrap: wrap;
        gap: 0.5rem;
    }
    .school-brand {
        display: flex;
        align-items: center;
        gap: 0.75rem;
    }
    .school-logo {
        height: 48px;
        width: auto;
        border-radius: 0.5rem;
        object-fit: contain;
    }
    .logo-placeholder {
        width: 48px;
        height: 48px;
        background: linear-gradient(135deg, var(--primary), var(--primary-dark));
        border-radius: 0.75rem;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 800;
        font-size: 1.2rem;
        color: white;
        flex-shrink: 0;
    }
    .school-name {
        font-size: 1.2rem;
        font-weight: 700;
        color: var(--text, #1f2937);
        line-height: 1.2;
    }
    .voucher-meta {
        text-align: right;
    }
    .voucher-label {
        font-size: 0.7rem;
        text-transform: uppercase;
        color: var(--muted, #6b7280);
        display: block;
    }
    .voucher-number {
        font-size: 1.1rem;
        font-weight: 700;
        font-family: monospace;
        color: var(--text, #1f2937);
    }

    /* Student Section */
    .student-section {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 0.5rem 1.5rem;
        background: var(--surface-alt, #f9fafb);
        padding: 0.75rem 1rem;
        border-radius: 0.75rem;
        margin-bottom: 1rem;
        border: 1px solid var(--border, #e2e8f0);
    }
    .student-detail {
        display: flex;
        justify-content: space-between;
        border-bottom: 1px dashed var(--border, #e2e8f0);
        padding: 0.3rem 0;
    }
    .student-detail:last-child {
        border-bottom: none;
    }
    .detail-label {
        font-size: 0.75rem;
        color: var(--muted, #6b7280);
        font-weight: 500;
    }
    .detail-value {
        font-weight: 600;
        color: var(--text, #1f2937);
    }

    /* Fee Table */
    .fee-table table {
        width: 100%;
        border-collapse: collapse;
        margin: 0.5rem 0 1rem;
        font-size: 0.9rem;
    }
    .fee-table th {
        text-align: left;
        padding: 0.4rem 0.2rem;
        font-weight: 600;
        color: var(--muted, #6b7280);
        border-bottom: 1px solid var(--border, #e2e8f0);
        font-size: 0.75rem;
        text-transform: uppercase;
    }
    .fee-table td {
        padding: 0.4rem 0.2rem;
        border-bottom: 1px solid var(--border, #e2e8f0);
    }
    .fee-table td:last-child {
        text-align: right;
        font-weight: 500;
    }
    .fee-table .total-row td {
        border-top: 2px solid var(--primary, #3b82f6);
        font-weight: 700;
        padding-top: 0.6rem;
        font-size: 1rem;
    }
    .fee-table .total-row td:last-child {
        color: var(--primary, #3b82f6);
    }

    /* Pending Note */
    .pending-note {
        background: #fef3c7;
        color: #92400e;
        border-radius: 0.5rem;
        padding: 0.5rem 0.75rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        font-size: 0.85rem;
        margin: 0.5rem 0 1rem;
        border-left: 4px solid #f59e0b;
    }
    .pending-icon {
        font-size: 1.2rem;
    }

    /* Footer */
    .voucher-footer {
        display: flex;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 0.5rem;
        border-top: 1px solid var(--border, #e2e8f0);
        padding-top: 0.75rem;
        margin-top: 0.5rem;
        font-size: 0.8rem;
    }
    .footer-item {
        display: flex;
        gap: 0.3rem;
    }
    .footer-label {
        color: var(--muted, #6b7280);
        font-weight: 500;
    }
    .footer-value {
        font-weight: 600;
        color: var(--text, #1f2937);
    }
    .status-badge {
        display: inline-block;
        padding: 0.1rem 0.5rem;
        border-radius: 999px;
        font-size: 0.65rem;
        font-weight: 700;
        text-transform: uppercase;
    }
    .status-pending {
        background: #fef3c7;
        color: #92400e;
    }
    .status-partial {
        background: #dbeafe;
        color: #1e40af;
    }
    .status-paid {
        background: #d1fae5;
        color: #065f46;
    }
    .status-overdue {
        background: #fee2e2;
        color: #991b1b;
    }
    .status-waived {
        background: #e0e7ff;
        color: #3730a3;
    }

    /* Responsive */
    @media (max-width: 600px) {
        .student-section {
            grid-template-columns: 1fr;
        }
        .voucher-header {
            flex-direction: column;
            align-items: flex-start;
        }
        .voucher-meta {
            text-align: left;
            width: 100%;
        }
        .voucher-footer {
            flex-direction: column;
            align-items: flex-start;
            gap: 0.3rem;
        }
        .fee-table table {
            font-size: 0.8rem;
        }
    }
</style>"""

# ----------------------------------------------
# 2. Updated voucher_modal.html with dropdown
# ----------------------------------------------
NEW_VOUCHER_MODAL = """<!-- Voucher Modal -->
<div id="voucherModal" class="modal" style="display:none;">
    <div class="modal-content" style="max-width: 800px;">
        <div class="modal-header">
            <h3 id="voucherModalTitle">Fee Voucher</h3>
            <div class="voucher-actions">
                <!-- Three-dot dropdown -->
                <div class="dropdown" style="position: relative; display: inline-block;">
                    <button class="btn-secondary dropdown-toggle" id="voucherActionsToggle" style="padding: 0.25rem 0.6rem; font-size: 1.2rem; line-height: 1; background: transparent; border: none; cursor: pointer;">
                        ⋮
                    </button>
                    <div class="dropdown-menu" id="voucherActionsMenu" style="display: none; position: absolute; right: 0; top: 100%; background: var(--surface, #fff); border: 1px solid var(--border, #e2e8f0); border-radius: 0.5rem; min-width: 120px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); z-index: 100; padding: 0.3rem 0;">
                        <button class="dropdown-item" id="printVoucherBtn" style="display: block; width: 100%; text-align: left; padding: 0.3rem 0.8rem; background: none; border: none; cursor: pointer; font-size: 0.85rem;">🖨️ Print</button>
                        <button class="dropdown-item" id="downloadVoucherBtn" style="display: block; width: 100%; text-align: left; padding: 0.3rem 0.8rem; background: none; border: none; cursor: pointer; font-size: 0.85rem;">💾 Save</button>
                        <button class="dropdown-item" id="editVoucherBtn" style="display: none; width: 100%; text-align: left; padding: 0.3rem 0.8rem; background: none; border: none; cursor: pointer; font-size: 0.85rem;">✏️ Edit</button>
                    </div>
                </div>
                <button class="close-modal" onclick="closeVoucherModal()">&times;</button>
            </div>
        </div>
        <div id="voucherModalBody">
            <!-- Content loaded via JS -->
        </div>
    </div>
</div>

<style>
/* Modal overlay & content – ensures visibility */
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
    background: var(--surface, #fff);
    border-radius: 1.5rem;
    max-width: 800px;
    width: 100%;
    max-height: 90vh;
    overflow-y: auto;
    padding: 1.5rem;
    box-shadow: 0 20px 60px rgba(0,0,0,0.3);
    position: relative;
}
.modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    padding-bottom: 0.5rem;
    border-bottom: 1px solid var(--border, #e2e8f0);
}
.modal-header h3 {
    margin: 0;
    font-size: 1.25rem;
}
.close-modal {
    background: none;
    border: none;
    font-size: 1.8rem;
    cursor: pointer;
    color: var(--muted, #6b7280);
    line-height: 1;
}
.close-modal:hover {
    color: var(--text, #1f2937);
}
.voucher-actions {
    display: flex;
    align-items: center;
    gap: 0.5rem;
}
.dropdown-menu {
    display: none;
}
.dropdown-menu.show {
    display: block;
}
.dropdown-item:hover {
    background: var(--surface-alt, #f3f4f6);
}
</style>

<script>
// Voucher JS (will be included in profile pages)
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

// Toggle dropdown menu
document.addEventListener('DOMContentLoaded', function() {
    const toggle = document.getElementById('voucherActionsToggle');
    const menu = document.getElementById('voucherActionsMenu');
    if (toggle && menu) {
        toggle.addEventListener('click', function(e) {
            e.stopPropagation();
            menu.classList.toggle('show');
        });
        document.addEventListener('click', function(e) {
            if (!toggle.contains(e.target) && !menu.contains(e.target)) {
                menu.classList.remove('show');
            }
        });
    }
});

function openVoucherModal(studentId, schema) {
    currentStudentId = studentId;
    currentSchema = schema;
    const modal = document.getElementById('voucherModal');
    modal.style.display = 'flex';
    // Load status
    loadVoucherStatus(studentId, schema);
}

function closeVoucherModal() {
    document.getElementById('voucherModal').style.display = 'none';
    // Close dropdown if open
    const menu = document.getElementById('voucherActionsMenu');
    if (menu) menu.classList.remove('show');
}

function loadVoucherStatus(studentId, schema) {
    const body = document.getElementById('voucherModalBody');
    body.innerHTML = '<p>Loading...</p>';
    fetch(`/portal/${schema}/api/student/${studentId}/voucher-status/`)
        .then(res => res.json())
        .then(data => {
            if (data.error) {
                body.innerHTML = '<p>Error: ' + data.error + '</p>';
                return;
            }
            currentFeeStatus = data;
            if (data.exists && data.fee_record.paid_amount > 0) {
                // Scenario 3: paid, show voucher only
                showVoucher(data, schema, studentId);
                document.getElementById('editVoucherBtn').style.display = 'none';
            } else if (data.exists && data.fee_record.paid_amount === 0) {
                // Scenario 2: exists, unpaid => show voucher with edit button
                showVoucher(data, schema, studentId);
                document.getElementById('editVoucherBtn').style.display = 'block';
                document.getElementById('editVoucherBtn').onclick = function() {
                    showVoucherForm(data, true);
                };
            } else {
                // Scenario 1: no fee => show form
                showVoucherForm(data, false);
                document.getElementById('editVoucherBtn').style.display = 'none';
            }
        })
        .catch(err => {
            body.innerHTML = '<p>Error loading status: ' + err.message + '</p>';
        });
}

function showVoucher(data, schema, studentId) {
    // Fetch voucher HTML snippet
    const body = document.getElementById('voucherModalBody');
    fetch(`/portal/${schema}/api/student/${studentId}/voucher-html/`)
        .then(res => res.text())
        .then(html => {
            body.innerHTML = html;
            document.getElementById('voucherModalTitle').innerText = 'Fee Voucher';
            // Attach print and download (using the dropdown items)
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
                // Close dropdown
                document.getElementById('voucherActionsMenu').classList.remove('show');
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
                document.getElementById('voucherActionsMenu').classList.remove('show');
            };
        })
        .catch(err => {
            body.innerHTML = '<p>Error loading voucher: ' + err.message + '</p>';
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
    const title = document.getElementById('voucherModalTitle');
    title.innerText = isEdit ? 'Edit Fee Voucher' : 'Generate Fee Voucher';
    let html = '<div class="voucher-form">';
    html += `<p><strong>Student:</strong> ${data.student_name} (${data.student_roll})</p>`;
    html += `<p><strong>Class:</strong> ${data.grade} - ${data.section}</p>`;
    html += `<div class="form-group">
                <label>Fee Amount (₹)</label>
                <input type="number" step="0.01" id="voucherFeeAmount" value="${data.fee_record ? data.fee_record.amount : data.default_fee}" placeholder="Default: ${data.default_fee}">
            </div>`;
    html += `<div class="form-group">
                <label>Extra Charges</label>
                <div id="chargesContainer">`;
    let charges = data.fee_record ? data.fee_record.extra_charges : data.default_charges;
    if (!charges || charges.length === 0) {
        charges = [{title: '', amount: ''}];
    }
    charges.forEach((ch, idx) => {
        html += `<div class="charge-item" data-index="${idx}">
                    <input type="text" class="charge-title" value="${ch.title || ''}" placeholder="Title">
                    <input type="number" step="0.01" class="charge-amount" value="${ch.amount || ''}" placeholder="Amount">
                    <button type="button" class="remove-charge" onclick="removeCharge(this)">&times;</button>
                </div>`;
    });
    html += `<button type="button" class="btn-secondary" onclick="addCharge()">+ Add Charge</button>`;
    html += `</div></div>`;
    // Pending total
    html += `<div class="form-group"><strong>Total Pending (including this fee):</strong> ₹<span id="voucherTotalPending">${data.total_pending}</span></div>`;
    html += `<div class="form-group">
                <label><input type="checkbox" id="saveDefaultCharges"> Save these charges as defaults for future manual generations</label>
            </div>`;
    html += `<div class="form-actions">
                <button type="button" class="btn-secondary" onclick="closeVoucherModal()">Cancel</button>
                <button type="button" class="btn-primary" id="voucherSubmitBtn">${isEdit ? 'Update' : 'Generate'}</button>
            </div>`;
    html += '</div>';
    body.innerHTML = html;

    document.getElementById('voucherSubmitBtn').addEventListener('click', function() {
        submitVoucher(currentStudentId, currentSchema, isEdit);
    });
    // Update total pending when amount/charges change? Not required for now.
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
            // Optionally reload the page to update fee records
            // location.reload();
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
</script>"""

# ----------------------------------------------
# Helper functions
# ----------------------------------------------
def file_read(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def file_write(path, content):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

def file_exists(path):
    return os.path.exists(path)

def insert_before_closing_body(html, snippet):
    if '</body>' not in html:
        return html
    return html.replace('</body>', snippet + '\n</body>')

def ensure_voucher_button_mobile():
    """Add voucher button to mobile profile if missing."""
    path = 'templates/mobile/student_profile.html'
    if not file_exists(path):
        print(f"⚠️ {path} not found, skipping.")
        return

    content = file_read(path)

    # Check if button already exists
    if 'openVoucherModal' in content:
        print("ℹ️ Mobile profile already has voucher button.")
        return

    # Find the .profile-actions div and insert button
    pattern = r'(<div class="profile-actions">.*?)(</div>)'
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        print("⚠️ Could not find .profile-actions in mobile profile. Adding at top of hero.")
        # Fallback: add after hero content
        hero_end = content.find('</div>', content.find('profile-hero-content'))
        if hero_end != -1:
            button = '''
    <div class="profile-actions">
        <button class="btn-primary" onclick="openVoucherModal({{ student.id }}, '{{ tenant.schema_name }}')">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M4 4v16h16M8 12h8M12 8v8"/>
            </svg>
            Voucher
        </button>
    </div>'''
            content = content[:hero_end] + button + content[hero_end:]
            file_write(path, content)
            print("✅ Added voucher button to mobile profile (fallback).")
        return

    button = '''
    <button class="btn-primary" onclick="openVoucherModal({{ student.id }}, '{{ tenant.schema_name }}')">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 4v16h16M8 12h8M12 8v8"/>
        </svg>
        Voucher
    </button>'''
    new_content = content[:match.start(1)] + match.group(1) + button + match.group(2)
    file_write(path, new_content)
    print("✅ Added voucher button to mobile student profile.")

def ensure_voucher_modal_included():
    """Ensure voucher_modal.html is included in both base templates."""
    bases = ['templates/tenant/base.html', 'templates/mobile/base.html']
    for base in bases:
        if not file_exists(base):
            print(f"⚠️ {base} not found, skipping.")
            continue
        content = file_read(base)
        if 'voucher_modal.html' in content:
            print(f"ℹ️ {base} already includes voucher modal.")
            continue
        snippet = '    {% include "tenant/voucher_modal.html" %}'
        content = insert_before_closing_body(content, snippet)
        file_write(base, content)
        print(f"✅ Added voucher modal include to {base}.")

def main():
    print("=" * 60)
    print("AXIS VOUCHER ENHANCEMENT PATCHER")
    print("=" * 60)

    # 1. Overwrite voucher_snippet.html
    snippet_path = 'templates/tenant/voucher_snippet.html'
    file_write(snippet_path, NEW_VOUCHER_SNIPPET)
    print("✅ Updated voucher_snippet.html with premium design.")

    # 2. Overwrite voucher_modal.html with dropdown
    modal_path = 'templates/tenant/voucher_modal.html'
    file_write(modal_path, NEW_VOUCHER_MODAL)
    print("✅ Updated voucher_modal.html with three-dot dropdown menu.")

    # 3. Ensure voucher button on mobile profile
    ensure_voucher_button_mobile()

    # 4. Ensure modal is included in both base templates
    ensure_voucher_modal_included()

    print("\n✅ All changes applied successfully!")
    print("Restart the server and refresh to see the enhanced voucher UI.")

if __name__ == '__main__':
    main()
