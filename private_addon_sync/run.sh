#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Mirrors add-on folders from private GitHub repos into /addons (Local add-ons).
set -u

OPTIONS=/data/options.json
CACHE=/data/repos
ADDONS=/addons
MARKER=.private_addon_sync

TOKEN=$(bashio::config 'github_token')
INTERVAL=$(bashio::config 'sync_interval_minutes')

if bashio::var.is_empty "${TOKEN}"; then
    bashio::exit.nok "Set github_token in the add-on configuration."
fi

# Pass the token as an HTTP header via environment-scoped git config, so it is
# never written to .git/config, a remote URL, or the log.
AUTH=$(printf 'x-access-token:%s' "${TOKEN}" | base64 | tr -d '\n')
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="http.https://github.com/.extraHeader"
export GIT_CONFIG_VALUE_0="Authorization: Basic ${AUTH}"
export GIT_TERMINAL_PROMPT=0
unset TOKEN AUTH

mkdir -p "${CACHE}"

# Fetch one repo into the cache. Args: owner/name, branch (may be empty).
fetch_repo() {
    local repo=$1 branch=$2 dir="${CACHE}/${1//\//__}"
    if [ -d "${dir}/.git" ]; then
        git -C "${dir}" fetch --quiet --depth 1 origin "${branch:-HEAD}" \
            && git -C "${dir}" reset --quiet --hard FETCH_HEAD
    else
        rm -rf "${dir}"
        git clone --quiet --depth 1 ${branch:+--branch "${branch}"} \
            "https://github.com/${repo}.git" "${dir}"
    fi
}

# Copy every add-on folder in a fetched repo to /addons. Echoes "changed" if
# anything was updated.
install_addons() {
    local repo=$1 dir="${CACHE}/${1//\//__}" cfg src name dest owner out
    while IFS= read -r cfg; do
        src=$(dirname "${cfg}")
        if [ "${src}" = "${dir}" ]; then name=${repo#*/}; else name=$(basename "${src}"); fi
        dest="${ADDONS}/${name}"

        if [ -e "${dest}" ]; then
            if [ ! -f "${dest}/${MARKER}" ]; then
                bashio::log.warning "${dest} already exists and was not created by this add-on; skipping ${repo}:${name}. Remove it once to let this add-on manage it."
                continue
            fi
            owner=$(cat "${dest}/${MARKER}")
            if [ "${owner}" != "${repo}" ]; then
                bashio::log.warning "${dest} is managed from ${owner}; skipping duplicate ${repo}:${name}."
                continue
            fi
        fi

        mkdir -p "${dest}"
        echo "${repo}" > "${dest}/${MARKER}"
        out=$(rsync -a --delete --itemize-changes --exclude .git --exclude "${MARKER}" "${src}/" "${dest}/") || {
            bashio::log.error "Copying ${repo}:${name} failed."
            continue
        }
        if [ -n "${out}" ]; then
            bashio::log.info "Updated ${name} from ${repo}."
            echo changed
        fi
    done < <(find "${dir}" -maxdepth 2 -name .git -prune -o \
        \( -name config.yaml -o -name config.yml -o -name config.json \) -type f -print)
}

sync_all() {
    local repo branch changed=""
    while IFS=$'\t' read -r repo branch; do
        [ -n "${repo}" ] || continue
        if ! fetch_repo "${repo}" "${branch}"; then
            bashio::log.error "Could not fetch ${repo}. Check the repo name and that the token can read it."
            continue
        fi
        if install_addons "${repo}" | grep -q '^changed$'; then changed=1; fi
    done < <(jq -r '.repositories[] | [.repo, (.branch // "")] | @tsv' "${OPTIONS}")

    if [ -n "${changed}" ]; then
        bashio::log.info "Reloading the add-on store."
        bashio::api.supervisor POST /store/reload > /dev/null \
            || bashio::log.warning "Store reload failed; use Check for updates in the add-on store."
    else
        bashio::log.info "Everything is up to date."
    fi
}

while true; do
    sync_all
    if [ "${INTERVAL}" -eq 0 ]; then
        bashio::log.info "sync_interval_minutes is 0; restart this add-on to sync again."
        exit 0
    fi
    sleep $((INTERVAL * 60))
done
