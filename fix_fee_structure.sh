#!/bin/bash

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
    <h3 style="margin-bottom: 20px;">{% if edit_grade %}✏️ Edit Fee for {{ edit_grade }}{% else %}➕ Add New Fee Structure{% endif %}</h3>
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
        <div style="margin-top: 20px; display: flex; gap: 10px;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
                </svg>
                {% if edit_grade %}Update Fee{% else %}Save Fee{% endif %}
            </button>
            {% if edit_grade %}
                <a href="{% url 'fee_structure' schema_name=tenant.schema_name %}" class="btn-secondary">Cancel Edit</a>
            {% endif %}
        </div>
    </form>
</div>

<!-- Current Fee Structures Table -->
<div class="page-card">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 10px;">
        <h3 style="margin:0;">📋 Current Fee Structure</h3>
        <div style="width: 250px;">
            <input type="text" id="searchTable" placeholder="🔍 Search class..." style="width:100%; padding: 8px 12px; border-radius: 6px; border: 1px solid var(--border); background: var(--surface-alt);">
        </div>
    </div>
    <div style="overflow-x: auto;">
        <table class="data-table" id="feeTable" style="width:100%; min-width: 400px;">
            <thead>
                <tr>
                    <th>Class/Grade</th>
                    <th>Monthly Fee (₹)</th>
                    <th>Last Updated</th>
                    <th style="width: 150px;">Actions</th>
                </tr>
            </thead>
            <tbody>
                {% for fs in fee_structures %}
                <tr>
                    <td><strong>{{ fs.grade }}</strong></td>
                    <td>₹{{ fs.monthly_fee|floatformat:2 }}</td>
                    <td>{{ fs.updated_at|date:"Y-m-d H:i" }}</td>
                    <td style="display: flex; gap: 8px; flex-wrap: wrap;">
                        <a href="{% url 'fee_structure' schema_name=tenant.schema_name %}?edit={{ fs.grade }}" class="btn-small edit-btn">✏️ Edit</a>
                        <a href="{% url 'student_list' schema_name=tenant.schema_name %}?grade={{ fs.grade }}" class="btn-small view-btn" target="_blank">👥 View Students</a>
                    </td>
                </tr>
                {% empty %}
                <tr><td colspan="4" style="text-align: center; padding: 2rem; color: var(--muted);">
                    📭 No fee structures defined yet. Use the form above to add one.
                </td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
    {% if not fee_structures %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.75rem; border-radius: 0.5rem;">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 8v4m0 4h.01"/></svg>
        <span>💡 After adding a fee structure, all students in that grade will automatically get the monthly fee. You can also set a custom fee per student.</span>
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
    display: inline-block;
}
.edit-btn { background: var(--primary); color: white; }
.view-btn { background: var(--surface-alt); color: var(--text); border: 1px solid var(--border); }
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
</script>
{% endblock %}
EOF

echo "✅ Fee Structure page has been updated."
echo "👉 Refresh your browser (hard refresh) to see the changes."
