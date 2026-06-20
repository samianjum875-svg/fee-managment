#!/usr/bin/env python3
"""
Recovery script for axis_school_sys.
Restores from 'backup' remote's 'daily-backup' branch.
Usage: python3 y.py
"""

import subprocess
import sys
import os

def run_cmd(cmd):
    try:
        subprocess.run(cmd, check=True, shell=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: Command failed -> {cmd}")
        sys.exit(1)

def main():
    print("🔄 --- AXIS RECOVERY ENGINE (wapsi) ---")

    if not os.path.exists(".git"):
        print("❌ Error: Yeh Git repo nahi hai!")
        return

    # Check if 'backup' remote exists
    try:
        subprocess.check_output("git remote get-url backup", shell=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        print("❌ Error: 'backup' remote nahi mila! Pehle add karo:")
        print("   git remote add backup https://github.com/samianjum/fee-managment.git")
        return

    print("📡 Fetching from backup remote...")
    run_cmd("git fetch backup")

    print("\n--- RECENT COMMITS ON BACKUP/DAILY-BACKUP ---")
    try:
        log_output = subprocess.check_output(
            "git log backup/daily-backup --oneline -n 10", shell=True
        ).decode().strip()
        print(log_output)
    except subprocess.CalledProcessError:
        print("⚠️  Could not fetch log from backup/daily-backup. Trying 'backup/main'...")
        try:
            log_output = subprocess.check_output(
                "git log backup/main --oneline -n 10", shell=True
            ).decode().strip()
            print(log_output)
        except:
            print("❌ Could not fetch log. Check your backup remote.")
            return

    print("----------------------------------------")

    target = input("\n🔙 Kis commit par restore karna hai? (Enter commit hash or 'latest'): ").strip()

    if not target:
        print("❌ Cancelled: Koi input nahi diya.")
        return

    print("\n⚠️  WARNING: Yeh operation aapki current working directory ko overwrite kar dega!")
    confirm = input("Kya aap pakka restore karna chahte hain? (y/n): ").strip().lower()

    if confirm not in ['y', 'yes']:
        print("❌ Operation cancelled.")
        return

    try:
        if target.lower() == 'latest':
            print("🔄 Restoring from latest backup (backup/daily-backup)...")
            run_cmd("git reset --hard backup/daily-backup")
        else:
            print(f"🔄 Restoring to commit {target}...")
            run_cmd(f"git reset --hard {target}")

        print("\n✅ RESTORE COMPLETE! Code successfully restored.")
        print("   Ab aap 'git push origin main' kar sakte hain agar ye final version hai.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Restore failed: {e}")
        print("   Ho sakta hai commit hash galat ho ya remote branch available nahi.")

if __name__ == '__main__':
    main()
