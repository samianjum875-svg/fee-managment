import subprocess
import os
import sys

def main():
    print("🔄 --- AXIS RECOVERY GRID ---")
    if not os.path.exists(".git"):
        print("❌ Error: Yeh Git repo nahi hai!")
        return

    try:
        log_data = subprocess.check_output("git log --oneline -n 10", shell=True).decode().strip()
    except subprocess.CalledProcessError:
        print("❌ Error: History retrieve nahi ho saki.")
        return

    print("\n--- RECENT 10 PUSHES / COMMITS ---")
    print(log_data)
    print("-----------------------------------")

    target_hash = input("\n🔙 Kis commit hash par reset karna hai? (Hash code paste karein): ").strip()
    if not target_hash:
        print("❌ Cancelled: Koi hash enter nahi kiya.")
        return

    print(f"\n⚠️ ATTENTION: System aapke code ko forcefully reset karne laga hai.")
    confirm = input(f"Kya aap pakka '{target_hash}' par wapas jaana chahte hain? (y/n): ").strip().lower()

    if confirm in ['y', 'yes']:
        try:
            subprocess.run(f"git reset --hard {target_hash}", check=True, shell=True)
            print(f"\n🎯 SUCCESS! Code forcefully '{target_hash}' par recover aur reset ho gaya hai.")
        except subprocess.CalledProcessError:
            print("❌ Reset failed. Shayed hash code galat tha ya koi permission issue hai.")
    else:
        print("❌ Operation aborted safely.")

if __name__ == '__main__':
    main()
