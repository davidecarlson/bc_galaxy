#!/bin/sh
set -eu

export GALAXY_ROOT=/opt/galaxy
export GALAXY_ROOT_DIR="${GALAXY_ROOT_DIR:-/opt/galaxy}"
export GALAXY_PYTHON="${GALAXY_PYTHON:-/usr/bin/python3}"
export GALAXY_RUNTIME_ROOT="${GALAXY_RUNTIME_ROOT:-/tmp/galaxy}"
export GALAXY_VIRTUAL_ENV="${GALAXY_VIRTUAL_ENV:-/opt/galaxy/.venv}"
export GALAXY_CONFIG_FILE="${GALAXY_CONFIG_FILE:-$GALAXY_RUNTIME_ROOT/config/galaxy.yml}"
export GALAXY_LOG_DIR="${GALAXY_LOG_DIR:-$GALAXY_RUNTIME_ROOT/log}"
export GALAXY_PID_DIR="${GALAXY_PID_DIR:-$GALAXY_RUNTIME_ROOT/pids}"
export GALAXY_GRAVITY_STATE_DIR="${GALAXY_GRAVITY_STATE_DIR:-$GALAXY_RUNTIME_ROOT/data/gravity}"
export GALAXY_SHED_TOOL_PATH="${GALAXY_SHED_TOOL_PATH:-$GALAXY_RUNTIME_ROOT/data/shed_tools}"
export GALAXY_TOOL_CONFIG_FILE="${GALAXY_TOOL_CONFIG_FILE:-$GALAXY_RUNTIME_ROOT/config/tool_conf.xml,/opt/galaxy/config/tool_conf.xml.sample}"
export GALAXY_SHED_TOOL_CONFIG_FILE="${GALAXY_SHED_TOOL_CONFIG_FILE:-$GALAXY_RUNTIME_ROOT/config/shed_tool_conf.xml}"
export GALAXY_TOOL_DATA_PATH="${GALAXY_TOOL_DATA_PATH:-$GALAXY_RUNTIME_ROOT/data/tool_data}"
export GALAXY_FILE_SOURCES_CONFIG_FILE="${GALAXY_FILE_SOURCES_CONFIG_FILE:-$GALAXY_RUNTIME_ROOT/config/file_sources_conf.yml}"
export GALAXY_USER_LIBRARY_IMPORT_DIR="${GALAXY_USER_LIBRARY_IMPORT_DIR:-$HOME}"
export GALAXY_ALLOW_PATH_PASTE="${GALAXY_ALLOW_PATH_PASTE:-false}"
export GALAXY_TOOL_SHEDS_CONFIG_FILE="${GALAXY_TOOL_SHEDS_CONFIG_FILE:-/opt/galaxy/config/tool_sheds_conf.xml.sample}"
export GALAXY_DEPENDENCY_RESOLVERS_CONFIG_FILE="${GALAXY_DEPENDENCY_RESOLVERS_CONFIG_FILE:-}"
export GALAXY_CONDA_PREFIX="${GALAXY_CONDA_PREFIX:-$GALAXY_RUNTIME_ROOT/conda}"
export GALAXY_CONDA_AUTO_INIT="${GALAXY_CONDA_AUTO_INIT:-false}"
export GALAXY_CONDA_AUTO_INSTALL="${GALAXY_CONDA_AUTO_INSTALL:-false}"
export GALAXY_CONDA_EXEC="${GALAXY_CONDA_EXEC:-}"
export GALAXY_ENABLE_SCRATCH_FILE_SOURCE="${GALAXY_ENABLE_SCRATCH_FILE_SOURCE:-false}"
export GALAXY_ENABLE_PROJECTS_FILE_SOURCE="${GALAXY_ENABLE_PROJECTS_FILE_SOURCE:-false}"
export GALAXY_CONFIG_HOST="${GALAXY_CONFIG_HOST:-0.0.0.0}"
export GALAXY_CONFIG_PORT="${GALAXY_CONFIG_PORT:-8080}"
export GALAXY_URL_PREFIX="${GALAXY_URL_PREFIX:-/}"
export GALAXY_SKIP_CLIENT_BUILD="${GALAXY_SKIP_CLIENT_BUILD:-1}"

mkdir -p \
    "$GALAXY_RUNTIME_ROOT/config" \
    "$GALAXY_RUNTIME_ROOT/data/files" \
    "$GALAXY_RUNTIME_ROOT/data/tmp" \
    "$GALAXY_RUNTIME_ROOT/data/job_working_directory" \
    "$GALAXY_RUNTIME_ROOT/data/tool_dependencies" \
    "$GALAXY_GRAVITY_STATE_DIR" \
    "$GALAXY_GRAVITY_STATE_DIR/log" \
    "$GALAXY_RUNTIME_ROOT/log" \
    "$GALAXY_RUNTIME_ROOT/pids"

mkdir -p \
    "$GALAXY_TOOL_DATA_PATH" \
    "$GALAXY_SHED_TOOL_PATH"

# Galaxy's startup scripts query Git metadata from /opt/galaxy. On HPC systems
# the container filesystem ownership often differs from the runtime UID, which
# triggers Git's safe.directory protection. Use Git's process-level config
# injection so the exemption survives sanitized config environments.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0="$GALAXY_ROOT"

# Reused runtime directories can contain stale pid files from prior sessions.
rm -f "$GALAXY_RUNTIME_ROOT"/pids/*.pid

if [ ! -f "$GALAXY_SHED_TOOL_CONFIG_FILE" ]; then
    cat >"$GALAXY_SHED_TOOL_CONFIG_FILE" <<EOF
<?xml version="1.0"?>
<toolbox tool_path="${GALAXY_SHED_TOOL_PATH}">
</toolbox>
EOF
fi

GALAXY_PRIMARY_TOOL_CONFIG_FILE=$(printf '%s' "$GALAXY_TOOL_CONFIG_FILE" | cut -d, -f1)
if [ ! -f "$GALAXY_PRIMARY_TOOL_CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$GALAXY_PRIMARY_TOOL_CONFIG_FILE")"
    cat >"$GALAXY_PRIMARY_TOOL_CONFIG_FILE" <<EOF
<?xml version="1.0"?>
<toolbox monitor="true">
</toolbox>
EOF
fi

mkdir -p "$(dirname "$GALAXY_FILE_SOURCES_CONFIG_FILE")"
cat >"$GALAXY_FILE_SOURCES_CONFIG_FILE" <<EOF
- id: seawulf_home
  label: Home
  doc: SeaWulf home directory
  type: posix
  root: "$HOME"
  writable: false
EOF

if [ "$GALAXY_ENABLE_SCRATCH_FILE_SOURCE" = "true" ]; then
    cat >>"$GALAXY_FILE_SOURCES_CONFIG_FILE" <<EOF
- id: seawulf_scratch
  label: Scratch
  doc: SeaWulf scratch directory
  type: posix
  root: "/gpfs/scratch/$USER"
  writable: false
EOF
fi

if [ "$GALAXY_ENABLE_PROJECTS_FILE_SOURCE" = "true" ]; then
    cat >>"$GALAXY_FILE_SOURCES_CONFIG_FILE" <<EOF
- id: seawulf_projects
  label: Projects
  doc: SeaWulf project directories
  type: posix
  root: "/gpfs/projects"
  writable: false
EOF
fi

# Rebuild the generated config on each start so OOD-assigned host/port changes
# are reflected even when the runtime directory is persistent across sessions.
cat >"$GALAXY_CONFIG_FILE" <<EOF
galaxy:
  brand: "Galaxy"
  admin_users: "david.carlson@stonybrook.edu"
  allow_user_creation: true
  user_activation_on: false
  id_secret: "change-me-for-production"
  root: "${GALAXY_ROOT_DIR}"
  galaxy_url_prefix: "${GALAXY_URL_PREFIX}"
  data_dir: "${GALAXY_RUNTIME_ROOT}/data"
  host: "${GALAXY_CONFIG_HOST}"
  port: ${GALAXY_CONFIG_PORT}
  database_connection: "sqlite:///${GALAXY_RUNTIME_ROOT}/data/galaxy.sqlite?isolation_level=IMMEDIATE"
  file_path: "${GALAXY_RUNTIME_ROOT}/data/files"
  new_file_path: "${GALAXY_RUNTIME_ROOT}/data/tmp"
  tool_data_path: "${GALAXY_TOOL_DATA_PATH}"
  job_working_directory: "${GALAXY_RUNTIME_ROOT}/data/job_working_directory"
  tool_dependency_dir: "${GALAXY_RUNTIME_ROOT}/data/tool_dependencies"
  tool_config_file: "${GALAXY_TOOL_CONFIG_FILE}"
  shed_tool_config_file: "${GALAXY_SHED_TOOL_CONFIG_FILE}"
  shed_tool_path: "${GALAXY_SHED_TOOL_PATH}"
  tool_sheds_config_file: "${GALAXY_TOOL_SHEDS_CONFIG_FILE}"
  file_sources_config_file: "${GALAXY_FILE_SOURCES_CONFIG_FILE}"
  user_library_import_dir: "${GALAXY_USER_LIBRARY_IMPORT_DIR}"
  allow_path_paste: ${GALAXY_ALLOW_PATH_PASTE}
  dependency_resolvers_config_file: "${GALAXY_DEPENDENCY_RESOLVERS_CONFIG_FILE}"
  conda_prefix: "${GALAXY_CONDA_PREFIX}"
  conda_auto_init: ${GALAXY_CONDA_AUTO_INIT}
  conda_auto_install: ${GALAXY_CONDA_AUTO_INSTALL}
  conda_exec: "${GALAXY_CONDA_EXEC}"
gravity:
  galaxy_root: "${GALAXY_ROOT_DIR}"
  virtualenv: "${GALAXY_VIRTUAL_ENV}"
  log_dir: "${GALAXY_GRAVITY_STATE_DIR}/log"
  app_server: "gunicorn"
  gunicorn:
    bind: "${GALAXY_CONFIG_HOST}:${GALAXY_CONFIG_PORT}"
EOF

cd "$GALAXY_ROOT"
exec sh run.sh --skip-samples --skip-client-build "$@"
