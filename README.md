# Galaxy Open OnDemand App

Open OnDemand Batch Connect app for launching Galaxy inside an Apptainer or
Singularity container on a Slurm-managed HPC cluster.

This repository is set up for a SeaWulf-style environment, but the same pattern
works on other clusters if you adjust the shared paths, module names, and queue
settings.

## What This App Provides

- Launches Galaxy as an Open OnDemand interactive web app.
- Runs Galaxy from a shared container image.
- Stores each user's Galaxy state in a user-owned writable directory.
- Uses shared admin-managed locations for:
  - Tool panel configuration
  - Tool Shed installs
  - Tool data
  - Conda environments and packages
- Exposes cluster filesystem locations in Galaxy through file sources.
- Exports `GALAXY_SLOTS` from the OOD core count so thread-aware tools can use
  the requested CPU count.

## Repository Layout

- `manifest.yml`: Open OnDemand app metadata
- `form.yml`: user-facing OOD form fields
- `submit.yml.erb`: Slurm submission options
- `template/before.sh.erb`: reserves the OOD proxy port
- `template/script.sh.erb`: cluster-side launch script
- `template/after.sh.erb`: waits for Galaxy to become reachable
- `start-galaxy.sh`: in-container Galaxy bootstrap
- `view.html.erb`: session page button
- `galaxy-rockylinux-9.6.def`: container definition file

## Runtime Model

At launch time, Open OnDemand starts a Slurm job and runs the container with a
small writable runtime tree under `/tmp/galaxy` inside the container.

Per-user writable state lives outside the container in a user-controlled
directory:

- default: `$HOME/ondemand/data/galaxy`
- override: the `Galaxy Data Directory` form field

Shared, admin-managed resources live under `/gpfs/software/galaxy` and are
bind-mounted into the container:

- `/gpfs/software/galaxy/galaxy-rockylinux-9.6.sif`
- `/gpfs/software/galaxy/config`
- `/gpfs/software/galaxy/tools`
- `/gpfs/software/galaxy/shed_tools`
- `/gpfs/software/galaxy/tool-data`
- `/gpfs/software/galaxy/conda`

Inside the container, these appear under `/srv/galaxy/...`.

## Prerequisites

The target cluster must provide:

- Open OnDemand with Batch Connect enabled
- Slurm
- `apptainer` or `singularity` on compute nodes
- environment modules
- an Anaconda module that provides `conda`

This app currently assumes:

- module name: `anaconda/3`
- shared Anaconda root: `/gpfs/software/Anaconda`
- shared Galaxy root: `/gpfs/software/galaxy`

If your cluster uses different locations, update
[`template/script.sh.erb`](/gpfs/home/decarlson/ondemand/dev/galaxy/template/script.sh.erb).

## Required Shared Filesystem Layout

Create the shared Galaxy tree:

```text
/gpfs/software/galaxy/
├── galaxy-rockylinux-9.6.sif
├── config/
│   ├── dependency_resolvers_conf.xml
│   ├── shed_tool_conf.xml
│   ├── tool_conf.xml
│   └── tool_sheds_conf.xml
├── conda/
├── shed_tools/
├── tool-data/
└── tools/
```

Recommended ownership and permissions:

- writable by admins only
- readable by all users on compute nodes
- image file readable by all users

## Minimal Shared Config Files

Place these files under `/gpfs/software/galaxy/config`.

`tool_conf.xml`

```xml
<?xml version="1.0"?>
<toolbox tool_path="/srv/galaxy/tools" monitor="true">
</toolbox>
```

`shed_tool_conf.xml`

```xml
<?xml version="1.0"?>
<toolbox tool_path="/srv/galaxy/shed_tools">
</toolbox>
```

`tool_sheds_conf.xml`

```xml
<?xml version="1.0"?>
<tool_sheds>
    <tool_shed name="Galaxy Main Tool Shed" url="https://toolshed.g2.bx.psu.edu/" />
</tool_sheds>
```

`dependency_resolvers_conf.xml`

```xml
<?xml version="1.0"?>
<dependency_resolvers>
    <conda auto_init="true" auto_install="true" prefix="/srv/galaxy/conda" />
</dependency_resolvers>
```

## Install

1. Put this app in an OOD app directory, for example:

```text
~/ondemand/dev/galaxy
```

2. Ensure the shared container image exists at:

```text
/gpfs/software/galaxy/galaxy-rockylinux-9.6.sif
```

3. Populate the shared config and shared directories under
   `/gpfs/software/galaxy`.

4. Confirm compute nodes can access:
   - `/gpfs/software/galaxy/...`
   - `/gpfs/software/Anaconda`
   - the `anaconda/3` module
   - `apptainer` or `singularity`

5. Open the app in Open OnDemand and launch a session.

## First-Run Admin Workflow

Use one admin-owned Galaxy session to install shared tools from the Tool Shed.

Suggested smoke test:

1. Launch the app as an admin user.
2. Install `bwa_mem` from `https://toolshed.g2.bx.psu.edu`.
3. Verify that the install populates:
   - `/gpfs/software/galaxy/shed_tools`
   - `/gpfs/software/galaxy/conda`
4. Run a small test job.
5. Confirm a normal user can launch a separate session and use the installed
   tool without reinstalling it.

## User-Facing OOD Options

The form currently exposes:

- `Galaxy Data Directory`
  per-user writable state location
- `Additional Galaxy Data Sources`
  controls which server-side file sources appear in Galaxy
- `Number of cores`
  exported to the job allocation and to `GALAXY_SLOTS`
- `Memory`
- `Queue`
- `Extra Container Args`

## Data Access Model

Browser uploads and server-side imports are different:

- `Choose local file` always shows the filesystem of the user's local machine
  running the browser.
- Galaxy file sources expose server-side cluster paths from the compute node.

This app generates a per-session `file_sources_conf.yml` with:

- `Home` -> `/gpfs/home/$USER`
- optional `Scratch` -> `/gpfs/scratch/$USER`
- optional `Projects` -> `/gpfs/projects`

It also enables path-based imports for server-side files under `/gpfs/...`.

## Conda and Tool Shed Behavior

Galaxy is configured to use a shared Conda prefix at:

```text
/gpfs/software/galaxy/conda
```

The launcher exports:

- `GALAXY_CONDA_PREFIX=/srv/galaxy/conda`
- `GALAXY_CONDA_EXEC=/gpfs/software/Anaconda/bin/conda`
- `CONDA_ENVS_PATH=/srv/galaxy/conda/envs`
- `CONDA_PKGS_DIRS=/srv/galaxy/conda/pkgs`

It also symlinks the shared prefix's `bin`, `condabin`, and `etc` directories
to the site Anaconda install so Galaxy can activate tool environments via:

```text
/srv/galaxy/conda/bin/activate
```

This is important because Galaxy uses the configured `conda_prefix` both for
environment creation and for activation during job execution.

## Site-Specific Settings To Review

Before reusing this app on another cluster, review:

- [`form.yml`](/gpfs/home/decarlson/ondemand/dev/galaxy/form.yml)
  queue names and resource defaults
- [`template/script.sh.erb`](/gpfs/home/decarlson/ondemand/dev/galaxy/template/script.sh.erb)
  shared filesystem paths, Anaconda path, image path, and module name
- [`start-galaxy.sh`](/gpfs/home/decarlson/ondemand/dev/galaxy/start-galaxy.sh)
  `admin_users` and `id_secret`

## Security Notes

Two settings should be changed before treating this as production-ready:

- `id_secret` in
  [`start-galaxy.sh`](/gpfs/home/decarlson/ondemand/dev/galaxy/start-galaxy.sh)
  is still a placeholder and should be replaced with a persistent random secret.
- `admin_users` in
  [`start-galaxy.sh`](/gpfs/home/decarlson/ondemand/dev/galaxy/start-galaxy.sh)
  should be set for your site.

Also review whether exposing all of `/gpfs/projects` is appropriate for your
cluster. You may want to narrow that to specific project roots.

## Troubleshooting

If Tool Shed installs create Conda environments in the wrong place:

- confirm `CONDA_ENVS_PATH` and `CONDA_PKGS_DIRS` are set in the launcher
- confirm `/gpfs/software/galaxy/conda` is writable by the installing admin
- confirm the shared prefix contains `bin/activate`

If Galaxy jobs run single-threaded:

- confirm the OOD session was launched with more than one core
- confirm the tool wrapper uses `GALAXY_SLOTS`

If server-side data browsing does not show expected paths:

- confirm `/gpfs` is bind-mounted into the container
- confirm the OOD form selection includes the desired file source
- confirm the path exists and is readable by the session user
