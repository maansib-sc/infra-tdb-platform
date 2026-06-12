import os
import yaml
import subprocess
import tempfile
from pathlib import Path

REPOS_FILE = Path("local/repo.yaml")


def run(cmd, cwd=None):
    print(">", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def load_repos():
    data = yaml.safe_load(REPOS_FILE.read_text())
    return data["repos"]


def extract_name(url):
    return url.split("/")[-1].replace(".git", "")


def git_clone(url, path):
    run(["git", "clone", url, str(path)])
    
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
    repo_path = Path(repo_path)

    gcp_project = os.getenv("GCP_PROJECT", "smarter-codes-website")
    artifact_repo = os.getenv("ARTIFACT_REPO", "tdb")
    artifact_region = os.getenv("ARTIFACT_REGION", "us-central1")

    registry_host = f"{artifact_region}-docker.pkg.dev"
    remote_image = f"{registry_host}/{gcp_project}/{artifact_repo}/{name}"

    current_commit = subprocess.check_output(
        ["git", "rev-parse", "--short", "HEAD"],
        cwd=repo_path
    ).decode().strip()

    tags = ["latest", current_commit]

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
        for url in repos:
            name = extract_name(url)
            print(f"\n========== {name} ==========")
            
            repo_path = Path(tmp) / name
            git_clone(url, repo_path)
            set_git_auth(repo_path, url, os.environ["GH_PAT"])
    
            # ensure git identity in CI
            run(["git", "config", "user.name", "github-actions[bot]"], cwd=repo_path)
            run(["git", "config", "user.email", "github-actions[bot]@users.noreply.github.com"], cwd=repo_path)
    
            # STEP 1: sync dependencies
            try:
                run_sync_logic(repo_path)
            except:
                pass
    
            # STEP 2: commit if needed
            committed = commit_if_needed(repo_path, f"chore: sync deps ({name})")

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
