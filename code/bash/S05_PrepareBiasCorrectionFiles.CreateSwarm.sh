# Author: Javier Gonzalez-Castillo
# Date: 03/27/2025
#
# Description:
# Updated script to read BIDS like data and write in BIDS like formate
#
# NOTE:
# Echo times are hard coded. Check the values still apply.
#
# April 4th, 2025
# Conseses between Javier and Cesar on afni_proc configuration

set -e

module load afni

PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/

PRCSDATA_DIR=${PRJ_DIR}prcs_data/
SCRIPTS_DIR=${PRJ_DIR}code/bash/
TASK=ExperienceSampling
USERNAME=`whoami`
SWARM_PATH=`echo ${PRJ_DIR}swarm.${USERNAME}/S05_PrepareBiasCorrectionFiles_${TASK}.SWARM.sh`
LOGS_DIR=`echo ${PRJ_DIR}logs.${USERNAME}/S05_PrepareBiasCorrectionFiles_${TASK}.logs`
#subjects=(sub-001 sub-002 sub-003 sub-004 sub-005 sub-006 sub-007 sub-008 sub-009 sub-010 sub-011 sub-012 sub-013 sub-014 sub-015 sub-016 sub-017 sub-018 sub-019 sub-020 sub-021 sub-023 sub-024 sub-025)
subjects=(sub-003)
sessions=(ses-001 ses-002)
runs=(run-001 run-002 run-003)
echo "++ Subjects: ${subjects[@]}"
echo "++ Orig Data Folder  : ${PRCSDATA_DIR}"
echo "++ Scripts Folder    : ${SCRIPTS_DIR}"
echo "++ Swarm Folder      : ${SWARM_PATH}"
echo "++ Logs Folder       : ${LOGS_DIR}"

# Initialize Swarm File
# ---------------------
echo "#swarm -f ${SWARM_PATH} -g 8 -t 8 --time 01:00:00 --partition quick,norm --module afni --logdir ${LOGS_DIR} --sbatch \"--export AFNI_COMPRESSOR=GZIP\"" > ${SWARM_PATH}

# Create log directory if needed (for swarm files)
# ------------------------------------------------
if [ ! -d ${LOGS_DIR} ]; then 
   mkdir -p ${LOGS_DIR}
fi

# Copy and process all fMRI data
# ------------------------------
for SBJ in ${subjects[@]}
do
    for SES in ${sessions[@]}
    do
       for RUN in ${runs[@]}
       do
          echo "export SBJ=${SBJ} SES=${SES} RUN=${RUN} TASK=${TASK}; sh ${SCRIPTS_DIR}/S05_PrepareBiasCorrectionFiles.sh" >> ${SWARM_PATH}
       done
   done
done
echo "++ Swarm File in: ${SWARM_PATH}"    
