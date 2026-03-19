#!/bin/sh
set -eu

export GALAXY_ROOT=/opt/galaxy
export GALAXY_ROOT_DIR="${GALAXY_ROOT_DIR:-/opt/galaxy}"
export GALAXY_PYTHON="${GALAXY_PYTHON:-/usr/bin/python3}"
export GALAXY_RUNTIME_ROOT="${GALAXY_RUNTIME_ROOT:-/tmp/galaxy}"
export GALAXY_VIRTUAL_ENV="${GALAXY_VIRTUAL_ENV:-/opt/galaxy/.venv}"
export GALAXY_CONFIG_FILE="${GALAXY_CONFIG_FILE:-$GALAXY_RUNTIME_ROOT/config/galaxy.yml}"
export GALAXY_JOB_CONFIG_FILE="${GALAXY_JOB_CONFIG_FILE:-$GALAXY_RUNTIME_ROOT/config/job_conf.xml}"
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
export GALAXY_ID_SECRET_FILE="${GALAXY_ID_SECRET_FILE:-/srv/galaxy/config/id_secret}"
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
export GALAXY_ADMIN_USERS="${GALAXY_ADMIN_USERS:-}"
export GALAXY_SMTP_SERVER="${GALAXY_SMTP_SERVER:-}"
export GALAXY_SMTP_USERNAME="${GALAXY_SMTP_USERNAME:-}"
export GALAXY_SMTP_PASSWORD="${GALAXY_SMTP_PASSWORD:-}"
export GALAXY_SMTP_SSL="${GALAXY_SMTP_SSL:-false}"
export GALAXY_EMAIL_FROM="${GALAXY_EMAIL_FROM:-}"
export GALAXY_ERROR_EMAIL_TO="${GALAXY_ERROR_EMAIL_TO:-}"
export GALAXY_SLOTS="${GALAXY_SLOTS:-1}"
export GALAXY_MEMORY_MB="${GALAXY_MEMORY_MB:-1024}"
export TMPDIR="${TMPDIR:-$GALAXY_RUNTIME_ROOT/data/tmp}"

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

cat >"$GALAXY_SHED_TOOL_CONFIG_FILE" <<EOF
<?xml version="1.0"?>
<toolbox tool_path="${GALAXY_SHED_TOOL_PATH}">
</toolbox>
EOF

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

cat >"$GALAXY_JOB_CONFIG_FILE" <<EOF
<?xml version="1.0"?>
<job_conf>
    <plugins>
        <plugin id="local" type="runner" load="galaxy.jobs.runners.local:LocalJobRunner" workers="4" />
    </plugins>
    <handlers>
        <handler id="main" />
    </handlers>
    <destinations default="local">
        <destination id="local" runner="local">
            <env id="GALAXY_SLOTS">${GALAXY_SLOTS}</env>
            <env id="GALAXY_MEMORY_MB">${GALAXY_MEMORY_MB}</env>
            <env id="TMPDIR">${TMPDIR}</env>
        </destination>
    </destinations>
</job_conf>
EOF

if [ "$GALAXY_ENABLE_PROJECTS_FILE_SOURCE" = "true" ]; then
    if [ -d /gpfs/projects ]; then
        for project_dir in /gpfs/projects/*; do
            [ -d "$project_dir" ] || continue
            [ -r "$project_dir" ] || continue
            [ -x "$project_dir" ] || continue

            project_name=$(basename "$project_dir")
            project_id=$(printf '%s' "$project_name" | tr -c '[:alnum:]' '_')

            cat >>"$GALAXY_FILE_SOURCES_CONFIG_FILE" <<EOF
- id: seawulf_project_${project_id}
  label: "Project: ${project_name}"
  doc: "SeaWulf project directory"
  type: "posix"
  root: "${project_dir}"
  writable: false
EOF
        done
    fi
fi

if [ ! -r "$GALAXY_ID_SECRET_FILE" ]; then
    echo "Galaxy id_secret file not found or not readable: $GALAXY_ID_SECRET_FILE" >&2
    exit 1
fi

GALAXY_ID_SECRET=$(tr -d '\r\n' <"$GALAXY_ID_SECRET_FILE")
if [ -z "$GALAXY_ID_SECRET" ]; then
    echo "Galaxy id_secret file is empty: $GALAXY_ID_SECRET_FILE" >&2
    exit 1
fi
GALAXY_ID_SECRET_LENGTH=$(printf '%s' "$GALAXY_ID_SECRET" | wc -c | tr -d ' ')
if [ "$GALAXY_ID_SECRET_LENGTH" -gt 56 ]; then
    echo "Galaxy id_secret is too long (${GALAXY_ID_SECRET_LENGTH} bytes). Galaxy requires 4-56 bytes." >&2
    exit 1
fi

# Rebuild the generated config on each start so OOD-assigned host/port changes
# are reflected even when the runtime directory is persistent across sessions.
cat >"$GALAXY_CONFIG_FILE" <<EOF
galaxy:
  brand: "Galaxy"
  admin_users: "${GALAXY_ADMIN_USERS}"
  allow_local_account_creation: true
  user_activation_on: false
  id_secret: "${GALAXY_ID_SECRET}"
  root: "${GALAXY_ROOT_DIR}"
  galaxy_url_prefix: "${GALAXY_URL_PREFIX}"
  data_dir: "${GALAXY_RUNTIME_ROOT}/data"
  host: "${GALAXY_CONFIG_HOST}"
  port: ${GALAXY_CONFIG_PORT}
  job_config_file: "${GALAXY_JOB_CONFIG_FILE}"
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
EOF

if [ -n "$GALAXY_SMTP_SERVER" ]; then
    cat >>"$GALAXY_CONFIG_FILE" <<EOF
  smtp_server: "${GALAXY_SMTP_SERVER}"
EOF
fi

if [ -n "$GALAXY_SMTP_USERNAME" ]; then
    cat >>"$GALAXY_CONFIG_FILE" <<EOF
  smtp_username: "${GALAXY_SMTP_USERNAME}"
EOF
fi

if [ -n "$GALAXY_SMTP_PASSWORD" ]; then
    cat >>"$GALAXY_CONFIG_FILE" <<EOF
  smtp_password: "${GALAXY_SMTP_PASSWORD}"
EOF
fi

cat >>"$GALAXY_CONFIG_FILE" <<EOF
  smtp_ssl: ${GALAXY_SMTP_SSL}
EOF

if [ -n "$GALAXY_EMAIL_FROM" ]; then
    cat >>"$GALAXY_CONFIG_FILE" <<EOF
  email_from: "${GALAXY_EMAIL_FROM}"
EOF
fi

if [ -n "$GALAXY_ERROR_EMAIL_TO" ]; then
    cat >>"$GALAXY_CONFIG_FILE" <<EOF
  error_email_to: "${GALAXY_ERROR_EMAIL_TO}"
EOF
fi

cat >>"$GALAXY_CONFIG_FILE" <<EOF
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
