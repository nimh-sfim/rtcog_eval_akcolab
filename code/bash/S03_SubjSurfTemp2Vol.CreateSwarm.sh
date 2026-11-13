set -e
PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
PRCSDATA_DIR=${PRJ_DIR}prcs_data/
SUBJECTS_DIR=${PRJ_DIR}freesurfer/
SCRIPTS_DIR=${PRJ_DIR}code/bash/

USERNAME=`whoami`
SWARM_DIR=`echo ${PRJ_DIR}/swarm.${USERNAME}/`
SWARM_PATH=`echo ${SWARM_DIR}S03_SubjSurfTemp2Vol.SWARM.sh`
LOGS_DIR=`echo ${PRJ_DIR}/logs.${USERNAME}/S03_SubjSurfTemp2Vol.logs`

subjects=(sub-001 sub-002 sub-003 sub-004 sub-005 sub-006 sub-007 sub-008 sub-009 sub-010 sub-011 sub-012 sub-013 sub-014 sub-015 sub-016 sub-017 sub-018 sub-019 sub-020 sub-021 sub-023 sub-024 sub-025)
sessions=(ses-001 ses-002)
echo "++ Subjects          : ${subjects[@]}"
echo "++ Swarm Folder      : ${SWARM_PATH}"
echo "++ Logs Folder       : ${LOGS_DIR}"
echo "++ Freesurfer Folder : ${SUBJECTS_DIR}"

# Create log directory if needed
# ------------------------------
if [ ! -d ${LOGS_DIR} ]; then
   mkdir -p ${LOGS_DIR}
fi

# Create log directory if needed
# ------------------------------
if [ ! -d ${SWARM_DIR} ]; then
   mkdir -p ${SWARM_DIR}
fi

# Initialize Swarm File
echo "#Creation Date: `date`" > ${SWARM_PATH}
echo "#swarm -f ${SWARM_PATH} -J sur2vol -g 24 -t 24 --time 00:30:00 --partition norm,quick --logdir ${LOGS_DIR}" >> ${SWARM_PATH}

# Write one entry per sbj,sess pair
# NOTE: We also create output folders now instead of doing that as part 
#       of the swarm to avoid crashes due to several jobs trying to create the same folder
for SBJ in ${subjects[@]}
do
  for SES in ${sessions[@]}
  do
    # Add entry to swarm file
   echo "export SBJ=${SBJ} SES=${SES}; sh ${SCRIPTS_DIR}S03_SubjSurfTemp2Vol.wrapper.sh" >> ${SWARM_PATH}       
  done
done
echo "++ Swarm file: ${SWARM_PATH}"
echo "++ INFO: Script finished correctly."
