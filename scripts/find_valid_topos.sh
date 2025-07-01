#!/bin/bash

printf "To find valid PE topology for GEM\n"

# Parse arguments
arguments=$*
eval `cclargs_lite -D " " $0  \
   -npex_low     "1"    "1"    "[(lower bound for npex)       ]"\
   -npex_high    "0"    "0"    "[(upper bound for npex)       ]"\
   -npey_low     "1"    "1"    "[(lower bound for npey)       ]"\
   -npey_high    "0"    "0"    "[(upper bound for npey)       ]"\
   -omp          "1"    "1"    "[(number of omp threads)      ]"\
   -smt          "1"    "2"    "[(smt levels)                 ]"\
   -corespernode "80"   "80"   "[(cores in one node)          ]"\
   -nml          "gem_settings.nml" "gem_settings.nml" "[/PATH/TO/gem_settings.nml]"\
   ++ $arguments`

# Check for namelist
if [ ! -e "${nml}" ]; then
   echo "ERROR: File ${nml} NOT found"
   exit 1
fi

# Get grid type and size
GRDTYP=$(rpy.nml_get -f ${nml} grid/Grd_typ_S | sed "s/'//g" | tr 'a-z' 'A-Z')
GNJ=$(rpy.nml_get -f ${nml} grid/Grd_nj | sed "s/'//g")
GNI=$(rpy.nml_get -f ${nml} grid/Grd_ni | sed "s/'//g")

# Compute missing dim for GY
if [[ "${GRDTYP}" == "GY" ]]; then
   export GEM_YINYANG=YES
   mult=2
   if [[ -z "${GNI}" && -n "${GNJ}" ]]; then
      GNI=$((1 + (GNJ - 1) * 3))
   elif [[ -z "${GNJ}" && -n "${GNI}" ]]; then
      GNJ=$((1 + (GNI - 1) / 3))
   fi
else
   mult=1
fi

# Abort if still missing
if [[ -z "${GNI}" || -z "${GNJ}" ]]; then
   echo "ERROR: Invalid or missing Grd_ni or Grd_nj"
   exit 1
fi

# Set default bounds if unset
[ $npex_high -lt 1 ] && npex_high=$((GNI / 20))
[ $npey_high -lt 1 ] && npey_high=$((GNJ / 10))

CORESperNODE=${corespernode}
THREADSperNODE=$((CORESperNODE * smt))

printf "\nScanning topologies for $GNI x $GNJ grid ($GRDTYP)\n"
printf "%-10s %-10s %-10s %-10s %-10s %-10s %-10s\n" "NPEX" "NPEY" "NODES" "CORES" "MPI" "SUB_X" "SUB_Y"

for ((npex=npex_low; npex<=npex_high; npex++)); do
  for ((npey=npey_low; npey<=npey_high; npey++)); do

    # Create scratch workspace
    workdir=$(mktemp -d -t checkdmpartXXXX)
    cp ${nml} ${workdir}/model_settings.nml

    # Make checkdm.nml
    cat > ${workdir}/checkdm.nml <<EOF
&cdm_cfgs
cdm_npex = ${npex}
cdm_npey = ${npey}
cdm_eigen_S=''
/
EOF

    # Determine YIN/YANG or not
    ngrids=1
    if [[ "$GRDTYP" == "GY" ]]; then
        ngrids=2
        mkdir -p ${workdir}/YIN/000-000 ${workdir}/YAN/000-000
        ln -s /dev/null ${workdir}/YIN/000-000/constantes
        ln -s /dev/null ${workdir}/YAN/000-000/constantes
        cp ${workdir}/checkdm.nml ${workdir}/YIN/000-000
        mv ${workdir}/checkdm.nml ${workdir}/YAN/000-000
    else
        mkdir -p ${workdir}/000-000
        ln -s /dev/null ${workdir}/000-000/constantes
        mv ${workdir}/checkdm.nml ${workdir}/000-000
    fi

    # Prepare and run checkdmpart (suppress all output)
    export DOMAIN_start=0
    export DOMAIN_end=0
    export DOMAIN_total=1
    export TASK_INPUT=${workdir}
    export TASK_WORK=${workdir}
    export CCARD_OPT='ABORT'
    export CCARD_ARGS="-dom_start 0 -dom_end 0 -npex 1 -npey 1 -ngrids ${ngrids} -input ${workdir}"

    TMP_OUT=$(mktemp)
    checkdmpart 1> "$TMP_OUT" 2>&1
    grep -q topo_allowed "$TMP_OUT"
    ok=$?
    rm -rf "$workdir" "$TMP_OUT"

    if [[ $ok -eq 0 ]]; then
        nthreads=$((npex * npey * omp * mult))
        nodes=$(echo "scale=3; ${nthreads} / ${THREADSperNODE}" | bc)
        cores=$(echo "scale=0; ${nodes} * ${CORESperNODE}" | bc)
        printf "%-10s %-10s %-10.2f %-10.0f %-10s %-10s %-10s\n" \
            $npex $npey $nodes $cores $((npex*npey*mult)) $((GNI/npex)) $((GNJ/npey))
    fi

  done
done
