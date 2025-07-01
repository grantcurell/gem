#!/bin/bash
set -x  # Print every command before executing

printf "\n=====>  runprep.sh DEBUG START: $(date) ###########\n"

# Store and print command line arguments
arguments=$*
printf "$0 ${arguments}\n\n"

# Process arguments using cclargs_lite
. r.entry.dot
eval "$(cclargs_lite -D " " $0 \
  -cfg       "0:0"         "0:0"     "[multi domains to run      ]"\
  -dircfg    "configurations/GEM_cfgs" "configurations/GEM_cfgs" "[location of config files  ]"\
  -npe       "1"           "1"       "[# of simultaneous threads ]"\
  -checkpart "1x1"         "1x1"     "[MPI topology to check     ]"\
  -verbose   "1"           "1"       "[verbose mode              ]"\
  -_status   "ABORT"       "ABORT"   "[Return status             ]"\
  ++ $arguments)"

# Print parsed variables
echo "cfg=$cfg"
echo "dircfg=$dircfg"
echo "npe=$npe"
echo "checkpart=$checkpart"
echo "verbose=$verbose"

export CMCCONST="${CMCCONST:-${ATM_MODEL_DFILES}/datafiles/constants}"

DOMAIN_start=$(echo "$cfg" | cut -d":" -f1)
DOMAIN_end=$(echo "$cfg" | cut -d":" -f2)

ici=$PWD
cd PREP || exit 1
cd "$ici" || exit 1

# Comment out cleanup so we preserve logs
# rm -fr PREP/*

work="${PWD}/PREP/work"
mkdir -p "$work"

ptopo=$(echo "$checkpart" | tr "X" "x")
npex=$(echo "$ptopo" | cut -d "x" -f1)
npey=$(echo "$ptopo" | cut -d "x" -f2)

abort_prefix=err_
domain_number=$(printf "%04d" "$DOMAIN_start")
while [ "$domain_number" -le "$DOMAIN_end" ]; do
    echo "========== Preparing domain cfg_${domain_number} =========="

    dname="cfg_${domain_number}"
    DEST="${PWD}/PREP/output/${dname}"

    # Remove only if you really want to clean each run
    # /bin/rm -rf "$DEST"
    mkdir -p "$DEST"

    # Source domain-specific config
    . "${dircfg}/${dname}/configexp.cfg" || { echo "❌ Failed to source configexp.cfg"; exit 1; }

    echo "GEM_anal=$GEM_anal"
    echo "GEM_inrep=$GEM_inrep"
    echo "GEM_headscript_E=$GEM_headscript_E"

    if [[ -n "$GEM_headscript_E" ]]; then
        headscript_E=$(which "$GEM_headscript_E")
        if [[ ! -x "${headscript_E:-__No_Such_File_-}" ]]; then
            echo "❌ ERROR: Cannot find or execute headscript $GEM_headscript_E"
            _status='ABORT'
            . r.return.dot
        fi
    else
        headscript_E=""
    fi

    GEM_check_settings=${GEM_check_settings:-0}

    echo ">> Calling prep_domain.sh..."
    . r.call.dot prep_domain.sh -anal "$GEM_anal" -input "'$GEM_inrep'" \
        -o "$DEST" -work "$work" -headscript "$headscript_E" -bin \
        -check_namelist "$GEM_check_settings" \
        -npex "$npex" -npey "$npey" -cache "$GEM_cache" \
        -nmlfile "${dircfg}/${dname}/gem_settings.nml" \
        -nthreads "$npe" -verbose "$verbose" -abort "${abort_prefix}${domain_number}"

    echo ">> Finished prep_domain.sh for $dname"

    if [[ -n "$GEM_inrep" ]]; then
        ln -s "$GEM_inrep" "${DEST}/MODEL_inrep" || true
    else
        mkdir -p "${DEST}/MODEL_inrep" || true
    fi

    domain_number=$(printf "%04d" $((domain_number + 1)))
done

# Check for error files — now preserved
echo ">> Scanning for abort markers..."
find PREP/work -name "${abort_prefix}*"

if [[ $(find PREP/work -name "${abort_prefix}*" | wc -l) -gt 0 ]]; then
    echo "❌ One or more prep_domain.sh function calls aborted"
    _status='ABORT'
else
    echo "✅ All domains processed successfully"
    _status='ED'
fi

. r.return.dot

