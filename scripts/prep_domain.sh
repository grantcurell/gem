#!/bin/bash
printf "\n=====>  prep_domain.sh starts: $(date) ###########\n"

# Store command line arguments
arguments=$*
printf "$0 ${arguments}\n\n"

# Process command line arguments
eval `cclargs_lite -D " " $0 \
  -anal        ""          ""       "[Analysis file or archive     ]"\
  -input       ""          ""       "[Model input file path        ]"\
  -o           ""          ""       "[Domain output path           ]"\
  -work        "${TASK_WORK}" ""    "[Work directory path          ]"\
  -bin         "${TASK_BIN}"  ""    "[Binaries directory path      ]"\
  -headscript  ""          ""       "[Headscript to run            ]"\
  -check_namelist "0"      "0"      "[Check namelist validity      ]"\
  -nmlfile     ""          ""       "[Model namelist settings file ]"\
  -npex        "1"         "1"      "[# of processors along x      ]"\
  -npey        "1"         "1"      "[# of processors along y      ]"\
  -cache       ""          ""       "[GEM_cache                    ]"\
  -nthreads    "1"         "1"      "[# of simultaneous threads    ]"\
  -verbose     "0"         "1"      "[verbose mode                 ]"\
  -abort       ""          ""       "[Abort signal file prefix     ]"\
  ++ $arguments`

set -ex

echo "[prep_domain.sh] Parsed arguments:"
echo "anal: $anal"
echo "input: $input"
echo "o (output): $o"
echo "work: $work"
echo "bin: $bin"
echo "headscript: $headscript"
echo "nmlfile: $nmlfile"
echo "check_namelist: $check_namelist"
echo "npex: $npex"
echo "npey: $npey"
echo "nthreads: $nthreads"

# Abort early if no output dir
if [[ -z "${o}" ]] ; then
   echo "❌ Error: output path (-o) must be defined for $0" >&2
   exit 1
fi

mydomain=$(basename ${o})
mkdir -p ${work} ${o}

# Normalize paths
for fpath in anal input o work headscript nmlfile ; do
   target=$(eval echo \$${fpath})
   if [[ -e ${target} ]] ; then
      resolved=$(readlink -e ${target})
      echo "[prep_domain.sh] Normalized path for ${fpath}: ${resolved}"
      eval ${fpath}="${resolved}"
   else
      echo "[prep_domain.sh] WARNING: ${fpath} (${target}) does not exist"
   fi
done

# Prepare abort file
if [[ -n "${abort}" ]] ; then
   abort_file=${work}/${abort}-$$
   echo "[prep_domain.sh] Creating abort file: $abort_file"
   touch ${abort_file}
fi

# Adjust bin
[[ -n "${bin}" ]] && bin="${bin}/"

# Set up working directory
work=${work}/${mydomain}
mkdir -p ${work}
cd ${work}
echo "[prep_domain.sh] Now in working dir: $(pwd)"
date

# Handle namelist validation
if [[ -n "${nmlfile}" && -e "${nmlfile}" ]]; then
   echo "[prep_domain.sh] Found namelist: ${nmlfile}"
   if [[ ${check_namelist} -gt 0 ]]; then
      echo "[prep_domain.sh] Validating namelist..."
      ${bin}checknml --nml="convection_cfgs dyn_fisl dyn_kernel gem_cfgs grid hvdif init out physics_cfgs series step surface_cfgs vert_layers ensembles" -r -- ${nmlfile}
   fi
   if [[ ${npex} -gt 1 || ${npey} -gt 1 ]]; then
      . r.call.dot ${bin}checkdmpart.sh -gemnml ${nmlfile} -cfg ${mydomain} -cache "${cache}" -npex ${npex} -npey ${npey} -verbose $verbose
      if [[ "${_status}" != "OK" ]]; then
         echo "❌ ERROR: checkdmpart.sh failed with _status=${_status}"
         exit 1
      fi
   fi
else
   echo "[prep_domain.sh] Skipping namelist checks – file missing or empty"
fi

# Setup analysis directory
target_dir=${o}
tmp_analysis_path=tmp_analysis
mkdir -p ${tmp_analysis_path}
tmp_analysis_path=$(readlink -e ${tmp_analysis_path})
cd ${tmp_analysis_path}
local_anal_file=${tmp_analysis_path}/ANALYSIS

# Handle analysis input
if [[ ! -f "${local_anal_file}" ]] || [[ ! -e "${anal}" ]]; then
   echo "❌ Either local analysis file not found or source analysis path missing."
   echo "    local_anal_file=${local_anal_file}"
   echo "    anal=${anal}"
   exit 1
fi

if [[ -L ${anal} ]]; then
   analysis=$(readlink "${anal}")
else
   analysis=${anal}
fi

echo "[prep_domain.sh] Resolved analysis path: ${analysis}"

if [[ -d ${analysis} ]]; then
   echo "[prep_domain.sh] Analysis is a directory; copying files..."
   for item in $(ls -1 "${analysis}"); do
      if [[ -f ${analysis}/${item} ]]; then
         editfst -s "${analysis}/${item}" -d "${local_anal_file}" -i 0
      elif [[ -d ${analysis}/${item} ]]; then
         if [[ ${item} == "nudge" ]]; then
            ln -s "$(readlink -e ${analysis}/${item})" "${target_dir}/NUDGE"
         else
            ln -s "$(readlink -e ${analysis}/${item})" "${target_dir}/IAUREP"
         fi
      fi
   done
elif r.filetype "${analysis}" -t 36 37; then
   echo "[prep_domain.sh] Analysis is an archive; unpacking with cmcarc..."
   mkdir -p "${work}/unpack_archive"
   cd "${work}/unpack_archive"
   cmcarc -x -f "${analysis}"
   for item in $(ls -1 .); do
      if [[ -f ${item} ]]; then
         editfst -s "${item}" -d "${local_anal_file}" -i 0
         /bin/rm -f "${item}"
      elif [[ -d ${item} ]]; then
         if [[ ${item} == "nudge" ]]; then
            mv "${item}" "${target_dir}/NUDGE"
         else
            mv "${item}" "${target_dir}/IAUREP"
         fi
      fi
   done
else
   echo "[prep_domain.sh] Copying raw analysis file..."
   cp "${analysis}" "${local_anal_file}"
fi

echo "[prep_domain.sh] Finished analysis setup."
