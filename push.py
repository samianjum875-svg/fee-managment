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
    print("🚀 --- AXIS SYSTEM FORCE PUSH ENGINE ---")
    if not os.path.exists(".git"):
        print("❌ Error: Yeh Git repo nahi hai!")
        return

    commit_title = input("📝 Enter Commit Title / Message: ").strip()
    if not commit_title:
        print("❌ Error: Commit message likhna zaroori hai!")
        return

    print("\nAdding changes...")
    run_cmd("git add .")

    print("Creating commit...")
    run_cmd(f'git commit -m "{commit_title}"')

    # Automatically find the current working branch name
    try:
        branch = subprocess.check_output("git branch --show-current", shell=True).decode().strip()
    except Exception:
        branch = "main"

    print(f"Force pushing directly to origin/{branch}...")
    run_cmd(f"git push origin {branch} --force")
    print(f"\n🎯 BOOM! Code forcefully GitHub par push ho gaya branch '{branch}' par!")

if __name__ == '__main__':
    main()
