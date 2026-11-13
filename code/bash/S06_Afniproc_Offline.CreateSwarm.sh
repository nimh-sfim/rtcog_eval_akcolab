# Author: Javier Gonzalez-Castillo
# Date: 10/19/2026
#
set -e
module load afni

PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
SUBJECTS_DIR=${PRJ_DIR}freesurfer/
PRCSDATA_DIR=${PRJ_DIR}prcs_data/
SCRIPTS_DIR=${PRJ_DIR}code/bash/
ORIGDATA_DIR=${PRJ_DIR}orig_data/ds007216-download/
TASK=ExperienceSampling
USERNAME=`whoami`
LOGS_DIR=`echo ${PRJ_DIR}logs.${USERNAME}/S06_Afniproc_Offline.logs`

#subjects=(sub-001 sub-002 sub-003 sub-004 sub-005 sub-006 sub-007 sub-008 sub-009 sub-010 sub-011 sub-012 sub-013 sub-014 sub-015 sub-016 sub-017 sub-018 sub-019 sub-020 sub-021 sub-023 sub-024 sub-025)
subjects=(sub-003)
sessions=(ses-001 ses-002)
runs=(run-001 run-002 run-003)
echo "++ Subjects: ${subjects[@]}"
echo "++ Orig Data Folder  : ${PRCSDATA_DIR}"
echo "++ Scripts Folder    : ${SCRIPTS_DIR}"
echo "++ Swarm Folder      : ${SWARM_PATH}"
echo "++ Logs Folder       : ${LOGS_DIR}"
echo "++ Freesurfer Folder : ${SUBJECTS_DIR}"

# Create log directory if needed (for swarm files)
# ------------------------------------------------
if [ ! -d ${LOGS_DIR} ]; then 
   mkdir -p ${LOGS_DIR}
fi

# Create directory for all fMRI data processing files per subject if needed
# -------------------------------------------------------------------------
AFNI_PROC_SCRIPTS_DIR=`echo ${SCRIPTS_DIR}/S06_Afniproc_Offline`
if [ ! -d ${AFNI_PROC_SCRIPTS_DIR} ]; then 
   mkdir ${AFNI_PROC_SCRIPTS_DIR}
fi

# Copy and process all fMRI data
# ------------------------------
echo "++ INFO: Entering loop (through subjects....)"
for SBJ in ${subjects[@]}
do
   SWARM_PATH=`echo ${PRJ_DIR}/swarm.${USERNAME}/S06_Afniproc_Offline.${SBJ}.SWARM.sh`
   echo "#swarm -f ${SWARM_PATH} -J ap${SBJ} -g 16 -t 16 --partition quick,norm --time 01:00:00 --module afni --logdir ${LOGS_DIR} --sbatch \"--export AFNI_COMPRESSOR=GZIP\"" > ${SWARM_PATH}
   for SES in ${sessions[@]}
   do
     for RUN in ${runs[@]}
     do
      ANAT_PROC_DIR=`echo ${PRCSDATA_DIR}/${SBJ}/D01_Anatomical`
      OUT_DIR=`echo ${PRCSDATA_DIR}/${SBJ}/${SES}/D05_afniproc_offline_${RUN}`
      if [[ -f ${PRCSDATA_DIR}/${SBJ}/${SES}/D03_OrigData_SlTimeCorr/${SBJ}_${SES}_task-${TASK}_${RUN}_bold.nii.gz ]]; then
        afni_proc.py                                                                                                       \
            -subj_id ${SBJ}                                                                                                \
            -uvar ses ${SES}                                                                                               \
            -uvar run ${RUN}                                                                                               \
            -blocks tshift align volreg blur mask scale regress                                                                 \
            -copy_anat ${ANAT_PROC_DIR}/anatSS.${SBJ}.nii.gz                                                               \
            -anat_has_skull no                                                                                             \
            -tshift_interp -wsinc9                                                                                         \
            -dsets ${PRCSDATA_DIR}/${SBJ}/${SES}/D03_OrigData_SlTimeCorr/${SBJ}_${SES}_task-${TASK}_${RUN}_bold.nii.gz \
            -blip_warp_dset ${PRCSDATA_DIR}/${SBJ}/${SES}/D04_BiasField_${RUN}/${SBJ}_${SES}_task-${TASK}_${RUN}_bold_WARP.nii.gz \
            -tcat_remove_first_trs    0                                                                                    \
            -align_unifize_epi        local                                                                                \
            -align_opts_aea           -cost lpc+ZZ                                                                         \
                                         -giant_move                                                                       \
            -volreg_align_to 'first'                                                                                       \
            -volreg_compute_tsnr   yes                                                                                     \
            -volreg_warp_final_interp  wsinc5                                                                              \
            -blur_size                4                                                                                    \
            -regress_apply_mot_types  demean deriv                                                                         \
            -regress_polort           3                                                                                    \
            -regress_bandpass         0.01 0.1                                                                             \
            -html_review_style        pythonic                                                                                \
            -out_dir ${OUT_DIR}                                                                                            \
            -script ${AFNI_PROC_SCRIPTS_DIR}/S06_Afniproc_Offline.${SBJ}_${SES}_${RUN}.sh                                          \
            -scr_overwrite
        
        # Add line for this subject to the Swarm file
        echo "module load afni; \
           export OMP_NUM_THREADS=32; \
           tcsh -xef ${AFNI_PROC_SCRIPTS_DIR}/S06_Afniproc_Offline.${SBJ}_${SES}_${RUN}.sh 2>&1 | tee ${AFNI_PROC_SCRIPTS_DIR}/output.S06_Afniproc_Offline.${SBJ}_${SES}_${RUN}.txt" >> ${SWARM_PATH}
    fi  
    done
  done
done

echo "============================================================================================"
echo " === SWARM FILE IN: ${SWARM_PATH}"
echo "============================================================================================"
