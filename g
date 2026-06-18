#!/usr/bin/env python3
"""
Restore floating PWA install button – visible on ALL devices.
- Adds floating button HTML if missing.
- Sets it to always visible (except in standalone mode).
- Click triggers install prompt or fallback modal.
"""

import re
import os

BASE_HTML = "templates/tenant/base.html"

def patch_base_html():
    if not os.path.exists(BASE_HTML):
        print(f"❌ {BASE_HTML} not found!")
        return

    with open(BASE_HTML, "r", encoding="utf-8") as f:
        content = f.read()

    # ---- 1. Check if floating container already exists ----
    if 'id="pwaInstallContainer"' in content:
        print("⏩ Floating container already exists. We'll update its visibility.")
    else:
        # Insert floating container before </body> or before fallback modal
        floating_html = '''
    <!-- Floating Install Button (always visible) -->
    <div id="pwaInstallContainer" style="position: fixed; bottom: 24px; right: 24px; z-index: 9999; display: flex;">
        <button id="installAppBtn" style="background: var(--primary); color: white; border: none; border-radius: 2rem; padding: 0.6rem 1.2rem; font-weight: 600; box-shadow: 0 4px 12px rgba(0,0,0,0.2); cursor: pointer; display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem;">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M4 16v1a2 2 0 002 2h12a2 2 0 002-2v-1M12 4v12m-4-4l4 4 4-4"/>
            </svg>
            Install App
        </button>
    </div>
'''
        # Insert before </body>
        if '</body>' in content:
            content = content.replace('</body>', floating_html + '\n</body>')
        else:
            content += floating_html
        print("✅ Floating button HTML added.")

    # ---- 2. Ensure CSS hides it in standalone mode ----
    # Look for existing @media all and (display-mode: standalone) rule that hides #pwaInstallContainer
    # If not present, add it inside <style> block
    if '@media all and (display-mode: standalone)' not in content:
        # Find </style> and insert before it
        css_rule = '''
    /* Hide floating button when app is installed (standalone mode) */
    @media all and (display-mode: standalone) {
        #pwaInstallContainer { display: none !important; }
    }
'''
        content = content.replace('</style>', css_rule + '\n    </style>')
        print("✅ Added CSS to hide floating button in standalone mode.")
    else:
        # Ensure the rule includes #pwaInstallContainer
        if '#pwaInstallContainer' not in content:
            # Insert the rule inside the existing media query
            # Find the media query block and insert
            pattern = r'(@media all and \(display-mode: standalone\)\s*\{)([^}]*)\}'
            def replacer(match):
                prefix = match.group(1)
                inside = match.group(2)
                if '#pwaInstallContainer' not in inside:
                    inside += '\n        #pwaInstallContainer { display: none !important; }\n    '
                return prefix + inside + '}'
            content = re.sub(pattern, replacer, content, flags=re.DOTALL)
            print("✅ Updated existing standalone CSS to hide floating button.")
        else:
            print("⏩ Standalone CSS already covers floating button.")

    # ---- 3. Update JavaScript for floating button ----
    # We need to ensure the floating button's click handler works with deferredPrompt or fallback.
    # The existing script already has a handler for installAppBtn, but it's incomplete (the code is messy).
    # We'll replace the whole install-related script with a clean version.

    # Find the script block that handles install. We'll replace it entirely.
    # We'll look for the pattern that defines deferredPrompt and the event listeners.
    # Safer: remove the old install script and add a new one before </body>.

    # We'll use a marker to identify the old script block. Since we have the fallback modal already,
    # we can place the new script after the fallback modal.

    # Remove any existing script that handles install (we'll add new one)
    # We'll find the part from "let deferredPrompt;" to the end of that script block.
    # Use regex to remove it, but careful: there may be multiple script tags.
    # Simpler: we'll just add a new script that overrides the handler and remove the old one.

    # We'll insert a new script block after the fallback modal that sets up everything cleanly.
    new_js = '''
<script>
    (function() {
        let deferredPrompt;
        const floatingBtn = document.getElementById('installAppBtn');
        const sidebarBtn = document.getElementById('installAppSidebarBtn');
        const fallbackModal = document.getElementById('installFallbackModal');

        // Listen for beforeinstallprompt
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            console.log('beforeinstallprompt fired');
        });

        // Function to trigger install or fallback
        async function triggerInstall() {
            if (deferredPrompt) {
                deferredPrompt.prompt();
                const result = await deferredPrompt.userChoice;
                if (result.outcome === 'accepted') {
                    console.log('User accepted install');
                    // Hide both buttons after installation
                    if (floatingBtn) floatingBtn.closest('#pwaInstallContainer').style.display = 'none';
                    if (sidebarBtn) sidebarBtn.style.display = 'none';
                } else {
                    console.log('User dismissed install');
                }
                deferredPrompt = null;
            } else {
                // No native prompt – show fallback modal
                if (fallbackModal) fallbackModal.style.display = 'flex';
            }
        }

        // Attach to floating button
        if (floatingBtn) {
            floatingBtn.addEventListener('click', triggerInstall);
        }

        // Attach to sidebar button
        if (sidebarBtn) {
            sidebarBtn.addEventListener('click', triggerInstall);
        }

        // Hide buttons once installed (appinstalled event)
        window.addEventListener('appinstalled', () => {
            console.log('App installed');
            if (floatingBtn) floatingBtn.closest('#pwaInstallContainer').style.display = 'none';
            if (sidebarBtn) sidebarBtn.style.display = 'none';
        });

        // Also hide fallback modal when close button clicked
        const closeFallback = document.getElementById('closeFallbackModal');
        if (closeFallback) {
            closeFallback.addEventListener('click', () => {
                if (fallbackModal) fallbackModal.style.display = 'none';
            });
        }
        if (fallbackModal) {
            fallbackModal.addEventListener('click', (e) => {
                if (e.target === fallbackModal) fallbackModal.style.display = 'none';
            });
        }

    })();
</script>
'''
    # Remove old install-related scripts. We'll locate the pattern that starts with "let deferredPrompt;" and ends before the next script or before the fallback modal.
    # But easier: we can just remove the entire script block that contains "deferredPrompt" and replace with new.

    # Find the first script that defines deferredPrompt (could be multiple). We'll use regex to remove it.
    pattern = r'<script>\s*let\s+deferredPrompt;.*?</script>'
    # Use DOTALL to match across lines
    content = re.sub(pattern, '', content, flags=re.DOTALL)

    # Also remove any inline script that sets installContainer.style.display etc.
    # But we can just let the new script handle everything.

    # Insert new script before </body> (but after fallback modal if present)
    if '</body>' in content:
        content = content.replace('</body>', new_js + '\n</body>')
    else:
        content += new_js
    print("✅ Replaced install script with clean version.")

    # ---- 4. Ensure floating button is initially visible ----
    # In case there is an inline style display:none on the container, remove it.
    # We already set style="display: flex;" in the added HTML.
    # But if it existed before, we might need to force it.
    # Use regex to replace any display:none on #pwaInstallContainer with display:flex.
    content = re.sub(r'(id="pwaInstallContainer"[^>]*style="[^"]*)display\s*:\s*none\s*;?', r'\1display: flex;', content)

    # Write back
    with open(BASE_HTML, "w", encoding="utf-8") as f:
        f.write(content)

    print("✅ base.html patched successfully.")
    print("\n🎯 Floating install button is now visible on mobile AND desktop.")
    print("   Clicking it will try native install, or show fallback instructions.")
    print("   Restart server to see changes: python manage.py runserver")

if __name__ == "__main__":
    patch_base_html()
