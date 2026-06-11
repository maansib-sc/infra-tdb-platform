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
    sync_script = Path(__file__).resolve().parent / "sync_git_deps.py"

    run([
        "python",
        str(sync_script),
        "--mode",
        "git"
    ], cwd=repo_path)


def process_repo(url):
    name = extract_name(url)

    print(f"\n========== {name} ==========")

    with tempfile.TemporaryDirectory() as tmp:
        repo_path = Path(tmp) / name

        git_clone(url, repo_path)

        # ensure git identity in CI
        run(["git", "config", "user.name", "github-actions[bot]"], cwd=repo_path)
        run(["git", "config", "user.email", "github-actions[bot]@users.noreply.github.com"], cwd=repo_path)

        # STEP 1: sync dependencies
        run_sync_logic(repo_path)

        # STEP 2: commit if needed
        committed = commit_if_needed(repo_path, f"chore: sync deps ({name})")

        print(f"{name}: {'updated' if committed else 'no changes'}")


def main():
    repos = load_repos()

    for url in repos:
        process_repo(url)


if __name__ == "__main__":
    main()
