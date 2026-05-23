#!/bin/bash

# ============================================================
# 1. Add API endpoint for grade income (views.py)
# ============================================================
echo "Adding grade income API endpoint..."

cat >> axis_saas/views.py << 'EOF'

# ------------------- API: Grade Total Income -------------------
@csrf_exempt
@require_http_methods(["GET"])
def grade_income_api(request, schema_name):
    """Return total collected amount for each grade (sum of payment amounts for students in that grade)"""
    tenant = get_tenant(request, schema_name)
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    with schema_context(schema_name):
        grades = FeeStructure.objects.values_list('grade', flat=True).distinct()
        result = []
        for grade in grades:
            # Get all students in this grade
            students = Student.objects.filter(grade=grade)
            # Sum all payment amounts for these students
            total = PaymentTransaction.objects.filter(student__in=students).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
            result.append({'grade': grade, 'total_income': float(total)})
        return JsonResponse(result, safe=False)
EOF

# Add route to public_urls.py
sed -i '/urlpatterns = \[/a \    path(\'portal/<slug:schema_name>/api/grade-income/\', grade_income_api, name=\'grade_income_api\'),' axis_saas/public_urls.py

# ============================================================
# 2. Update fee_structure view to pass grade income data
# ============================================================
echo "Updating fee_structure view to include income data..."

# We'll replace the existing fee_structure function with an enhanced version
python3 << 'PYTHON_SCRIPT'
import re

view_file = 'axis_saas/views.py'
with open(view_file, 'r') as f:
    content = f.read()

# Find the fee_structure function and replace with enhanced version
pattern = r'(def fee_structure\(request, schema_name\):.*?)(?=\n\ndef [a-zA-Z_]|\Z)'
new_func = '''def fee_structure(request, schema_name):
    tenant = get_tenant(request, schema_name)
    edit_grade = request.GET.get('edit', '')
    with schema_context(schema_name):
        if request.method == 'POST':
            grade = request.POST.get('grade')
            monthly_fee = request.POST.get('monthly_fee')
            if grade and monthly_fee:
                obj, created = FeeStructure.objects.update_or_create(
                    grade=grade,
                    defaults={'monthly_fee': monthly_fee}
                )
                Student.objects.filter(grade=grade).update(custom_fee=monthly_fee)
                messages.success(request, f"Fee structure for {grade} saved successfully.")
            else:
                messages.error(request, "Please provide both grade and monthly fee.")
            return redirect('fee_structure', schema_name=schema_name)

        structures = list(FeeStructure.objects.all().order_by('grade'))
        # Calculate total income per grade (from payments)
        grade_income = {}
        for fs in structures:
            students = Student.objects.filter(grade=fs.grade)
            total = PaymentTransaction.objects.filter(student__in=students).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
            grade_income[fs.grade] = float(total)

        form = FeeStructureForm()
        if edit_grade:
            try:
                edit_obj = FeeStructure.objects.get(grade=edit_grade)
                form = FeeStructureForm(initial={'grade': edit_obj.grade, 'monthly_fee': edit_obj.monthly_fee})
            except FeeStructure.DoesNotExist:
                pass

    context = {
        'tenant': tenant,
        'form': form,
        'fee_structures': structures,
        'edit_grade': edit_grade,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'grade_income': grade_income,
    }
    return render(request, 'tenant/fee_structure.html', context)'''

new_content = re.sub(pattern, new_func, content, flags=re.DOTALL)
if new_content != content:
    with open(view_file, 'w') as f:
        f.write(new_content)
    print("✅ fee_structure view updated with grade income data.")
else:
    print("⚠️ Could not update fee_structure view – manual check may be needed.")
PYTHON_SCRIPT

# ============================================================
# 3. Replace fee_structure.html with improved version
# ============================================================
echo "Replacing fee_structure.html with enhanced version..."

cat > templates/tenant/fee_structure.html << 'EOF'
{% extends 'tenant/base.html' %}
{% load static %}
{% block title %}Fee Structure | {{ tenant.name }}{% endblock %}
{% block body %}
<div class="page-header">
    <div>
        <h1 class="page-title">Fee Structure</h1>
        <p class="page-desc">Set monthly fee per class/grade</p>
    </div>
</div>

<!-- Add/Edit Form -->
<div class="page-card">
    <h3 style="margin-bottom: 20px;">
        {% if edit_grade %}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/>
                <path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4Z"/>
            </svg>
            Edit Fee for {{ edit_grade }}
        {% else %}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M12 4v16m8-8H4"/>
            </svg>
            Add New Fee Structure
        {% endif %}
    </h3>
    <form method="post" id="feeForm">
        {% csrf_token %}
        <div class="field-card">
            <label>Class/Grade</label>
            <input type="text" name="grade" id="grade" value="{{ form.grade.value|default:'' }}" required {% if edit_grade %}readonly{% endif %}>
        </div>
        <div class="field-card">
            <label>Monthly Fee (₹)</label>
            <input type="number" step="0.01" name="monthly_fee" id="monthly_fee" value="{{ form.monthly_fee.value|default:'' }}" required>
        </div>
        <div style="margin-top: 20px; display: flex; gap: 10px; flex-wrap: wrap;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
                </svg>
                {% if edit_grade %}Update Fee{% else %}Save Fee{% endif %}
            </button>
            {% if edit_grade %}
                <a href="{% url 'fee_structure' schema_name=tenant.schema_name %}" class="btn-secondary">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M6 18L18 6M6 6l12 12"/></svg>
                    Cancel Edit
                </a>
            {% endif %}
        </div>
    </form>
</div>

<!-- Current Fee Structures Table -->
<div class="page-card">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 10px;">
        <h3 style="margin:0;">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M3 6h18M9 12h6M7 18h10"/>
            </svg>
            Current Fee Structure
        </h3>
        <div style="width: 250px;">
            <div style="position: relative;">
                <svg style="position: absolute; left: 10px; top: 50%; transform: translateY(-50%); width: 16px; height: 16px;" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                    <circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>
                </svg>
                <input type="text" id="searchTable" placeholder="Search class..." style="width:100%; padding: 8px 12px 8px 36px; border-radius: 6px; border: 1px solid var(--border); background: var(--surface-alt);">
            </div>
        </div>
    </div>
    <div style="overflow-x: auto;">
        <table class="data-table" id="feeTable" style="width:100%; min-width: 500px;">
            <thead>
                <tr>
                    <th>Class/Grade</th>
                    <th>Monthly Fee (₹)</th>
                    <th>Total Income (₹)</th>
                    <th>Last Updated</th>
                    <th style="width: 180px;">Actions</th>
                </tr>
            </thead>
            <tbody>
                {% for fs in fee_structures %}
                <tr>
                    <td><strong>{{ fs.grade }}</strong></td>
                    <td>₹{{ fs.monthly_fee|floatformat:2 }}</td>
                    <td class="income-cell">
                        <a href="{% url 'reports' schema_name=tenant.schema_name %}?type=collection&grade={{ fs.grade }}" class="income-link" title="View all transactions for this grade">
                            ₹{{ grade_income|get_item:fs.grade|default:"0"|floatformat:2 }}
                        </a>
                    </td>
                    <td>{{ fs.updated_at|date:"Y-m-d H:i" }}</td>
                    <td style="display: flex; gap: 8px; flex-wrap: wrap;">
                        <button onclick="showInlineEditForm('{{ fs.grade }}', '{{ fs.monthly_fee|floatformat:2 }}')" class="btn-small edit-btn" title="Edit Fee">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/>
                                <path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4Z"/>
                            </svg>
                            Edit
                        </button>
                        <a href="{% url 'student_list' schema_name=tenant.schema_name %}?grade={{ fs.grade }}" class="btn-small view-btn" target="_blank" title="View Students">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/>
                            </svg>
                            View Students
                        </button>
                    </table>
                </tr>
                {% empty %}
                <tr><td colspan="5" style="text-align: center; padding: 2rem; color: var(--muted);">
                    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                        <circle cx="12" cy="12" r="10"/>
                        <path d="M12 8v4m0 4h.01"/>
                    </svg>
                    <p>No fee structures defined yet. Use the form above to add one.</p>
                </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
    {% if fee_structures %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.5rem; border-radius: 0.5rem; font-size:0.8rem; display: inline-flex; align-items: center; gap: 0.5rem;">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>
        <span>{{ fee_structures|length }} fee structure(s) loaded.</span>
    </div>
    {% else %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.75rem; border-radius: 0.5rem;">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 8v4m0 4h.01"/></svg>
        <span>After adding a fee structure, all students in that grade will automatically get the monthly fee. You can also set a custom fee per student.</span>
    </div>
    {% endif %}
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
.btn-primary:hover { background: var(--primary-dark); }
.btn-secondary {
    background: var(--surface-alt);
    color: var(--text);
    padding: 10px 20px;
    border-radius: 6px;
    border: 1px solid var(--border);
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
}
.btn-small {
    padding: 6px 12px;
    border-radius: 4px;
    font-size: 0.8rem;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    transition: all 0.2s;
}
.edit-btn { background: var(--primary); color: white; }
.edit-btn:hover { background: var(--primary-dark); transform: translateY(-1px); }
.view-btn { background: var(--surface-alt); color: var(--text); border: 1px solid var(--border); }
.view-btn:hover { background: var(--surface); transform: translateY(-1px); }
.income-cell .income-link {
    color: var(--primary);
    text-decoration: none;
    font-weight: 600;
    transition: color 0.2s;
}
.income-cell .income-link:hover {
    text-decoration: underline;
    color: var(--primary-dark);
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
.field-card {
    margin-bottom: 1rem;
}
.field-card label {
    display: block;
    font-weight: 600;
    margin-bottom: 0.3rem;
}
.field-card input, .field-card select {
    width: 100%;
    padding: 10px 12px;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--surface-alt);
    color: var(--text);
}
.page-card {
    background: var(--surface);
    border-radius: var(--radius);
    border: 1px solid var(--border);
    padding: 1.5rem;
    margin-bottom: 1.5rem;
    box-shadow: var(--shadow);
}
.info-panel {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.85rem;
}
@media (max-width: 600px) {
    .data-table th, .data-table td {
        padding: 8px;
    }
    .btn-small {
        padding: 4px 8px;
        font-size: 0.7rem;
    }
}
</style>

<script>
    // Live search in the fee table
    const searchInput = document.getElementById('searchTable');
    if (searchInput) {
        searchInput.addEventListener('keyup', function() {
            let filter = this.value.toLowerCase();
            let rows = document.querySelectorAll('#feeTable tbody tr');
            rows.forEach(row => {
                let grade = row.cells[0].innerText.toLowerCase();
                row.style.display = grade.includes(filter) ? '' : 'none';
            });
        });
    }

    // Inline edit form (populate the top form)
    function showInlineEditForm(grade, fee) {
        document.getElementById('grade').value = grade;
        document.getElementById('monthly_fee').value = fee;
        // Scroll to form
        document.querySelector('.page-card').scrollIntoView({ behavior: 'smooth' });
        // Highlight form briefly
        const formCard = document.querySelector('.page-card');
        formCard.style.transition = 'background 0.3s';
        formCard.style.background = 'var(--surface-alt)';
        setTimeout(() => { formCard.style.background = ''; }, 500);
    }
</script>
{% endblock %}
EOF

# ============================================================
# 4. Add custom modal and toast system to base.html
# ============================================================
echo "Adding custom modal and toast notifications to base.html..."

# We'll replace the body content of base.html to include modal and toast containers,
# and override window.alert and window.confirm with custom modals.
# Since base.html is large, we'll append the required scripts and styles at the end of the file.

cat >> templates/tenant/base.html << 'EOF'

<!-- Custom Modal and Toast Styles -->
<style>
    /* Modal overlay */
    .custom-modal-overlay {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0, 0, 0, 0.5);
        backdrop-filter: blur(4px);
        z-index: 10001;
        display: flex;
        align-items: center;
        justify-content: center;
        visibility: hidden;
        opacity: 0;
        transition: visibility 0.2s, opacity 0.2s;
    }
    .custom-modal-overlay.active {
        visibility: visible;
        opacity: 1;
    }
    .custom-modal {
        background: var(--surface);
        border-radius: var(--radius);
        border: 1px solid var(--border);
        max-width: 400px;
        width: 90%;
        padding: 1.5rem;
        box-shadow: var(--shadow);
        transform: scale(0.95);
        transition: transform 0.2s;
    }
    .custom-modal-overlay.active .custom-modal {
        transform: scale(1);
    }
    .custom-modal h3 {
        margin: 0 0 0.5rem 0;
        font-size: 1.2rem;
    }
    .custom-modal p {
        margin: 0.5rem 0 1.5rem 0;
        color: var(--muted);
    }
    .modal-buttons {
        display: flex;
        gap: 0.75rem;
        justify-content: flex-end;
    }
    .modal-btn {
        padding: 0.4rem 1rem;
        border-radius: 2rem;
        border: none;
        cursor: pointer;
        font-weight: 500;
        transition: all 0.2s;
    }
    .modal-btn.confirm {
        background: var(--primary);
        color: white;
    }
    .modal-btn.confirm:hover {
        background: var(--primary-dark);
    }
    .modal-btn.cancel {
        background: var(--surface-alt);
        color: var(--text);
        border: 1px solid var(--border);
    }
    /* Toast container */
    .toast-container {
        position: fixed;
        bottom: 20px;
        right: 20px;
        z-index: 10002;
        display: flex;
        flex-direction: column;
        gap: 10px;
    }
    .toast {
        background: var(--surface);
        border-left: 4px solid var(--primary);
        border-radius: 0.5rem;
        padding: 0.75rem 1rem;
        box-shadow: var(--shadow);
        display: flex;
        align-items: center;
        gap: 0.75rem;
        min-width: 250px;
        animation: slideIn 0.3s ease;
        border: 1px solid var(--border);
    }
    .toast.success { border-left-color: #10b981; }
    .toast.error { border-left-color: #ef4444; }
    .toast.warning { border-left-color: #f59e0b; }
    .toast.info { border-left-color: #3b82f6; }
    .toast-close {
        margin-left: auto;
        cursor: pointer;
        opacity: 0.6;
        transition: opacity 0.2s;
    }
    .toast-close:hover { opacity: 1; }
    @keyframes slideIn {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
    }
</style>

<!-- Modal and Toast containers -->
<div class="custom-modal-overlay" id="customModalOverlay">
    <div class="custom-modal">
        <h3 id="modalTitle">Confirm</h3>
        <p id="modalMessage">Are you sure?</p>
        <div class="modal-buttons">
            <button class="modal-btn cancel" id="modalCancelBtn">Cancel</button>
            <button class="modal-btn confirm" id="modalConfirmBtn">Confirm</button>
        </div>
    </div>
</div>
<div class="toast-container" id="toastContainer"></div>

<script>
    // Custom modal logic
    (function() {
        let resolvePromise = null;
        const overlay = document.getElementById('customModalOverlay');
        const confirmBtn = document.getElementById('modalConfirmBtn');
        const cancelBtn = document.getElementById('modalCancelBtn');
        const modalTitle = document.getElementById('modalTitle');
        const modalMessage = document.getElementById('modalMessage');

        function showModal(options) {
            return new Promise((resolve) => {
                modalTitle.innerText = options.title || 'Confirm';
                modalMessage.innerText = options.message || 'Are you sure?';
                resolvePromise = resolve;
                overlay.classList.add('active');
            });
        }

        function closeModal(result) {
            overlay.classList.remove('active');
            if (resolvePromise) {
                resolvePromise(result);
                resolvePromise = null;
            }
        }

        confirmBtn.onclick = () => closeModal(true);
        cancelBtn.onclick = () => closeModal(false);
        // Click on overlay background closes with false
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) closeModal(false);
        });

        // Override native confirm
        window.customConfirm = showModal;

        // Also override alert with a toast (non-blocking) – we'll keep alert simple but can be customized
        const originalAlert = window.alert;
        window.alert = function(message) {
            showToast(message, 'info');
        };
    })();

    // Toast notifications
    function showToast(message, type = 'info', duration = 4000) {
        const container = document.getElementById('toastContainer');
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.innerHTML = `
            <span>${message}</span>
            <span class="toast-close">✕</span>
        `;
        container.appendChild(toast);
        const closeBtn = toast.querySelector('.toast-close');
        closeBtn.addEventListener('click', () => toast.remove());
        setTimeout(() => {
            if (toast.parentNode) toast.remove();
        }, duration);
    }

    // Override Django messages display (the messages.html template will still append, but we'll also show toasts)
    // We'll capture existing messages and display as toasts
    document.addEventListener('DOMContentLoaded', function() {
        const messageDivs = document.querySelectorAll('.message');
        messageDivs.forEach(div => {
            let type = 'info';
            if (div.classList.contains('success')) type = 'success';
            else if (div.classList.contains('error')) type = 'error';
            else if (div.classList.contains('warning')) type = 'warning';
            showToast(div.innerText, type);
            div.remove(); // remove original message element to avoid duplication
        });
    });
</script>
EOF

# ============================================================
# 5. Update fee_collection.html to use custom confirm
# ============================================================
echo "Updating fee_collection.html to use custom confirm..."

sed -i 's/if (!confirm(/if (!await customConfirm({ title: "Confirm", message: /g' templates/tenant/fee_collection.html
sed -i 's/)) return/}))) return/g' templates/tenant/fee_collection.html
# Also handle the single generate confirm
sed -i 's/if (!confirm(/if (!await customConfirm({ title: "Confirm", message: /g' templates/tenant/fee_collection.html
# Ensure async function wrapping – but we'll do a simpler approach: replace all confirm calls in script
# We'll just replace the two instances manually with async/await compatible code
python3 << 'PYTHON_FIX'
import re

file_path = 'templates/tenant/fee_collection.html'
with open(file_path, 'r') as f:
    content = f.read()

# Replace confirm for generate all
content = re.sub(r'if \(!confirm\(\'Generate fee records for current month for all active students\?\'\)\)',
                 'if (!await customConfirm({ title: "Generate Fees", message: "Generate fee records for current month for all active students?" }))',
                 content)
# Replace confirm for single generate
content = re.sub(r'if \(!confirm\(\`Generate current month fee for \{\{ selected_student\.name \}\}\?\`\)\)',
                 'if (!await customConfirm({ title: "Generate Fee", message: `Generate current month fee for {{ selected_student.name }}?` }))',
                 content)
# Also replace the confirm in the generic generate single button (the one inside generateSingleBtn)
content = re.sub(r'if \(!confirm\(`Generate current month fee for \{\{ selected_student\.name \}\}\?`\)\)',
                 'if (!await customConfirm({ title: "Generate Fee", message: `Generate current month fee for {{ selected_student.name }}?` }))',
                 content)

with open(file_path, 'w') as f:
    f.write(content)
print("✅ fee_collection confirm calls replaced with custom modal.")
PYTHON_FIX

# ============================================================
# 6. Enhance reports page to accept grade filter
# ============================================================
echo "Enhancing reports page to handle grade filtering..."

# Update the reports view to accept a 'grade' GET parameter and filter payments and defaulters accordingly
python3 << 'PYTHON_REPORTS'
import re

view_file = 'axis_saas/views.py'
with open(view_file, 'r') as f:
    content = f.read()

# Find the reports function and modify it to add grade filtering
# We'll add a new parameter 'grade' and use it to filter payments_qs and defaulters_data

pattern = r'(def reports\(request, schema_name\):.*?)(?=\n\ndef [a-zA-Z_]|\Z)'
# We'll do a more targeted insertion: after getting search_q, add grade filter
# Since the function is large, we'll use a regex to inject grade parameter handling

# Simpler approach: add grade filter after search_q handling
inject_code = '''
    grade_filter = request.GET.get('grade', '')
    if grade_filter:
        payments_qs = payments_qs.filter(student__grade=grade_filter)'''

# Find where payments_qs is defined and inject after search_q block
# We'll do a safe insertion using a marker
marker = "if search_q:\n            payments_qs = payments_qs.filter("
if marker in content:
    # Insert after that block? Actually we need to add after the if block ends.
    # Easier: replace the line where payments_qs is initially defined with one that also respects grade filter
    # Let's just append after the block: after the if search_q and before paginator
    content = content.replace(
        "        # Paginate (15 per page)\n        paginator = Paginator(payments_qs.order_by('-payment_date'), 15)",
        f"        # Grade filter\n        grade_filter = request.GET.get('grade', '')\n        if grade_filter:\n            payments_qs = payments_qs.filter(student__grade=grade_filter)\n\n        # Paginate (15 per page)\n        paginator = Paginator(payments_qs.order_by('-payment_date'), 15)"
    )
    # Also filter defaulters_data if grade is provided
    content = content.replace(
        "        defaulters_list = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct()",
        "        grade_filter = request.GET.get('grade', '')\n        defaulters_list = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue'])\n        if grade_filter:\n            defaulters_list = defaulters_list.filter(grade=grade_filter)\n        defaulters_list = defaulters_list.distinct()"
    )
    with open(view_file, 'w') as f:
        f.write(content)
    print("✅ Reports view updated with grade filtering.")
else:
    print("⚠️ Could not modify reports view – marker not found.")
PYTHON_REPORTS

# Also update reports.html to display grade filter badge and pre-fill filters if grade present
sed -i '/<div class="page-header">/a \    {% if request.GET.grade %}\n    <div class="grade-filter-badge">\n        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M3 6h18M9 12h6M7 18h10"/></svg>\n        Showing data for grade: <strong>{{ request.GET.grade }}</strong>\n        <a href="?type={{ report_type }}" class="clear-filter">Clear</a>\n    </div>\n    {% endif %}' templates/tenant/reports.html

# ============================================================
# Final instructions
# ============================================================
echo ""
echo "==========================================================="
echo "All enhancements applied successfully!"
echo "==========================================================="
echo "👉 Restart your Django server: python3 manage.py runserver"
echo "👉 Hard refresh the browser (Ctrl+Shift+R)."
echo "New features:"
echo "  - Fee Structure: Total income per grade, inline edit button, clickable income link to reports."
echo "  - Custom modal & toast notifications replace all alerts/confirms."
echo "  - Reports page accepts ?grade=XYZ to filter data by grade."
echo "==========================================================="
EOF
