# Setting up a build runner

The workflows run the build inside an `ubuntu:22.04` container, so the machine only needs
Docker plus the runner agent. Your Portable-Docker-Ubuntu image is not needed for CI.

## GitHub (the job that is currently "Waiting for a runner")

On the build machine (Linux, Docker installed, your user in the `docker` group):

1. Open https://github.com/scotthowson/build_kernel_instantnoodle/settings/actions/runners/new
   and pick Linux / x64. GitHub shows the exact download URL and a one-time registration token.
2. Run what it shows, which is essentially:

   ```bash
   mkdir -p ~/actions-runner && cd ~/actions-runner
   curl -o runner.tar.gz -L <download URL from the page>
   tar xzf runner.tar.gz
   ./config.sh --url https://github.com/scotthowson/build_kernel_instantnoodle --token <TOKEN> --unattended
   sudo ./svc.sh install && sudo ./svc.sh start
   ```

   Keep the default labels; `self-hosted` is what the workflow requests. The queued job starts
   within a minute of the runner coming online.

### Dockerised runner instead (closer to your Portable-Docker setup)

```yaml
# docker-compose.yml
services:
  runner:
    image: myoung34/github-runner:latest
    restart: unless-stopped
    environment:
      REPO_URL: https://github.com/scotthowson/build_kernel_instantnoodle
      RUNNER_NAME: buildbox
      RUNNER_TOKEN: "<registration token from the page above>"
      RUNNER_WORKDIR: /tmp/runner/work
      LABELS: self-hosted,linux,x64
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      # must be the SAME path inside and outside so the job container can mount the workspace
      - /tmp/runner:/tmp/runner
```

`docker compose up -d` and the runner registers itself. The build cache (`build/`, kernel
sources) lives in `/tmp/runner`, so put that on a disk with 30 GB free.

## Forgejo (git.howson.dev)

Forgejo Actions runs the same YAML (`.forgejo/workflows/build.yml`, already adapted: Forgejo-hosted
actions, release via `forgejo-release`).

1. In the Forgejo repo: Settings → Repository → enable "Actions". Then Settings → Actions →
   Runners → "Create new Runner" to get a registration token.
2. On the build machine:

   ```bash
   # binary from https://code.forgejo.org/forgejo/runner/releases (linux-amd64)
   sudo install -m755 forgejo-runner-*-linux-amd64 /usr/local/bin/forgejo-runner
   mkdir -p ~/forgejo-runner && cd ~/forgejo-runner
   forgejo-runner register --no-interactive \
       --instance https://git.howson.dev --token <TOKEN> \
       --name buildbox --labels docker:docker://node:20-bookworm
   forgejo-runner generate-config > config.yml
   # allow the job's "--privileged" container option (needed for losetup/mount in system-image-from-ota.sh)
   sed -i 's/^  privileged: false/  privileged: true/' config.yml
   forgejo-runner daemon --config config.yml      # or wrap it in a systemd unit
   ```

   Or as a container:

   ```yaml
   services:
     forgejo-runner:
       image: code.forgejo.org/forgejo/runner:6
       restart: unless-stopped
       user: 0:0
       volumes:
         - ./data:/data
         - /var/run/docker.sock:/var/run/docker.sock
       command: forgejo-runner daemon --config /data/config.yml
   ```
   (register once with `docker compose run --rm forgejo-runner forgejo-runner register ...` using
   the same flags as above, and edit `data/config.yml` as described.)

3. Push this branch to git.howson.dev. The workflow label `docker` matches the runner label above.
   Manual runs: Actions → "Build Ubuntu Touch images" → Run workflow, tick *flashable* and *release*,
   optionally set *kernel_branch* (e.g. `Halium-10-Test`).

Releases on Forgejo are created by the workflow with the repository's own `GITHUB_TOKEN`; no extra
secret is needed.
