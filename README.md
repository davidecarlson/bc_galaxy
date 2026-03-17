# Galaxy Open OnDemand App

This directory now contains a SeaWulf-oriented Open OnDemand Batch Connect app
for launching Galaxy from the bundled container image.

## Files

- `manifest.yml`: app metadata for Open OnDemand
- `form.yml`: SeaWulf form fields for queue, time, cores, memory, and Galaxy
  data directory
- `submit.yml.erb`: Slurm submission settings using the `basic` web template
- `template/before.sh.erb`: reserves the OnDemand proxy port
- `template/script.sh.erb`: loads the requested module, detects
  `apptainer`/`singularity`, and launches Galaxy in the container
- `template/after.sh.erb`: waits for Galaxy to listen before marking the app
  ready
- `view.html.erb`: adds a direct "Connect to Galaxy" button in the session page

## Runtime behavior

- The app uses the image at
  `/gpfs/software/galaxy/galaxy-rockylinux-9.6.sif`.
- Galaxy listens on the port assigned by Open OnDemand.
- The launcher exports `GALAXY_SLOTS` from the OOD `Number of cores` setting so
  local Galaxy jobs can honor thread-aware tool wrappers.
- Writable Galaxy state is bound to `/tmp/galaxy` inside the container.
- If `Galaxy Data Directory` is left blank, the app uses
  `$HOME/ondemand/data/galaxy`.
- User data, histories, SQLite DB, logs, and temp files stay in the user's own
  Galaxy data directory.
- Shared tool definitions and shed-installed tools can be mounted from common
  admin-managed locations so every user's session sees the same tools.
- Conda-backed tool dependencies can also be shared across sessions.

## SeaWulf-specific notes

- The app assumes `singularity` or `apptainer` is already available on compute
  nodes without loading a module.
- The app uses the OOD `basic` template, which is the same pattern used by the
  local `jupyter`, `RStudio`, and `code-server` apps for proxied web services.
- Edit the shared-tool paths near the top of
  `template/script.sh.erb` to match the real site-wide locations:
  - `/gpfs/software/galaxy/config`
  - `/gpfs/software/galaxy/tools`
  - `/gpfs/software/galaxy/shed_tools`
  - `/gpfs/software/galaxy/tool-data`
  - `/gpfs/software/galaxy/conda`
- The OOD form includes `Additional Galaxy Data Sources`, which controls which
  SeaWulf paths appear in Galaxy's server-side file browser.
- The shared config directory should contain admin-managed files such as:
  - `tool_conf.xml`
  - `shed_tool_conf.xml`
- `tool_sheds_conf.xml`
- `dependency_resolvers_conf.xml`
- The app now loads `anaconda/3` and points Galaxy at a shared Conda prefix so
  Tool Shed-installed tools can resolve Conda dependencies across sessions.
- The launcher also sets `CONDA_ENVS_PATH` and `CONDA_PKGS_DIRS` so the shared
  `anaconda/3` installation does not fall back to `/gpfs/software/Anaconda/envs`
  for Tool Shed dependency environments.
- The shared Conda prefix also exposes `bin/`, `condabin/`, and `etc/` from
  the site Anaconda install so Galaxy can activate tool environments through
  `/srv/galaxy/conda/bin/activate` while still storing envs and packages under
  `/gpfs/software/galaxy/conda`.
- The launcher bind-mounts the user's SeaWulf home directory and `/gpfs` into
  the container and enables Galaxy server-side path imports. Browser-based
  `Choose local file` uploads still show the client machine; for SeaWulf data,
  use Galaxy's path-based upload/import flow with paths under `/gpfs/...`.
- Galaxy now generates a per-session `file_sources_conf.yml` with `Home`
  pointing at `/gpfs/home/$USER` by default, plus optional `Scratch`
  (`/gpfs/scratch/$USER`) and `Projects` (`/gpfs/projects`) sources based on
  the OOD form selection.
- The repo-local `shared_galaxy/` tree can still be used as a template for
  populating `/gpfs/software/galaxy/`.
- Recommended workflow:
  - launch one admin Galaxy session
  - install `bwa_mem` from `https://toolshed.g2.bx.psu.edu`
  - verify the tool lands in the shared shed/config/conda paths
  - then let normal users launch their own sessions and use the installed tool
- Those shared locations should be writable only by admins, not by end users.

## Install

Place this directory in an Open OnDemand app path visible to the dashboard, for
example under `~/ondemand/dev/galaxy` for a development app. Ensure the shared
Galaxy image exists at `/gpfs/software/galaxy/galaxy-rockylinux-9.6.sif`, or
update the `IMAGE` path in `template/script.sh.erb` to match your site-wide
location.
