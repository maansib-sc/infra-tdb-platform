import json
import os
import yaml
import subprocess
import tempfile
from pathlib import Path

REPOS_FILE = Path("local/repo.yaml")

HOST = os.environ.get("HOST")
DOCKER_MODULE_TTT = os.environ.get("DOCKER_MODULE_TTT", "false") == "true"
DOCKER_ELEMENTIZER = os.environ.get("DOCKER_ELEMENTIZER", "false") == "true"

MODULE_TTT_TAG = os.environ.get("MODULE_TTT_TAG", "")
ELEMENTIZER_TAG = os.environ.get("ELEMENTIZER_TAG", "")

def run(cmd, cwd=None):
    print(">", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def load_repos():
    try:
        return json.loads(os.environ["REPOS_JSON"])
    except:
        data = yaml.safe_load(REPOS_FILE.read_text())
        return [
            {"url": d, "branch": "main"}
            for d in data.get("repos", [])
        ]


def extract_name(url):
    return url.split("/")[-1].replace(".git", "")


def git_clone(url, branch, path):
    run(["git", "clone", "-b", branch, url, str(path)])


def set_git_auth(repo_path, url, token):
    auth_url = url.replace("https://", f"https://x-access-token:{token}@")
    run(["git", "remote", "set-url", "origin", auth_url], cwd=repo_path)


def commit_if_needed(repo_path, msg):
    status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )

    if not status.stdout.strip():
        print("No changes")
        return False

    run(["git", "add", "."], cwd=repo_path)
    run(["git", "commit", "-m", msg], cwd=repo_path)
    run(["git", "push"], cwd=repo_path)

    return True


def run_sync_logic(repo_path):
    sync_script = f"{repo_path}/sync_git_deps.py"

    run([
        "python",
        str(sync_script),
        "--mode",
        "git"
    ], cwd=repo_path)


def run_docker_publish(repo_path, name):
    if not (name.startswith("module-") or name.startswith("package-")):
        return
    
    if not DOCKER_MODULE_TTT and name == "module-ttt":
        print(f"Skipping docker publish for {name} (DOCKER_MODULE_TTT is false)")
        return
    if not DOCKER_ELEMENTIZER and name == "package-content-elementizer":
        print(f"Skipping docker publish for {name} (DOCKER_ELEMENTIZER is false)")
        return

    repo_path = Path(repo_path)
    remote_image = f'talkingdb/{name.replace("module-", "").replace("package-", "")}'

    current_commit = subprocess.check_output(
        ["git", "rev-parse", "--short", "HEAD"],
        cwd=repo_path
    ).decode().strip()

    tags = ["latest", current_commit]
    
    if name == "module-ttt" and MODULE_TTT_TAG:
        tags.append(MODULE_TTT_TAG)
    if name == "package-content-elementizer" and ELEMENTIZER_TAG:
        tags.append(ELEMENTIZER_TAG)

    print(f"🐳 Building image {name}")

    run(["docker", "build", "-t", f"{name}:latest", "."], cwd=repo_path)

    for tag in tags:
        run([
            "docker",
            "tag",
            f"{name}:latest",
            f"{remote_image}:{tag}"
        ])

    for tag in tags:
        run([
            "docker",
            "push",
            f"{remote_image}:{tag}"
        ])

    print(f"✅ Pushed {name} -> {remote_image}")


def process_repos(repos):
    with tempfile.TemporaryDirectory() as tmp:
        for repo in repos:
            url = repo["url"]
            branch = repo.get("branch", "main")
            
            name = extract_name(url)
            print(f"\n========== {name} ==========")

            repo_path = Path(tmp) / name
            
            git_clone(url, branch, repo_path)
            set_git_auth(repo_path, url, os.environ["GH_PAT"])

            # ensure git identity in CI
            run(["git", "config", "user.name", "github-actions[bot]"], cwd=repo_path)
            run(["git", "config", "user.email",
                "github-actions[bot]@users.noreply.github.com"], cwd=repo_path)

            # STEP 1: sync dependencies
            try:
                run_sync_logic(repo_path)
            except:
                pass

            # STEP 2: commit if needed
            committed = commit_if_needed(
                repo_path, f"chore: sync deps ({name})")

            # STEP 3: docker publish
            try:
                run_docker_publish(repo_path, name)
            except:
                pass

            print(f"{name}: {'updated' if committed else 'no changes'}")


def main():
    repos = load_repos()
    process_repos(repos)


if __name__ == "__main__":
    main()
