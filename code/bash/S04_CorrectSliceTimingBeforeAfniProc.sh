set -e
ml afni
PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
PRCSDATA_DIR=${PRJ_DIR}prcs_data/
ORIGDATA_DIR=${PRJ_DIR}orig_data/ds007216-download/

# Copy and process all fMRI data
# ------------------------------
OUT_DIR=`echo ${PRCSDATA_DIR}/${SBJ}/${SES}/D03_OrigData_SlTimeCorr`
cd ${OUT_DIR}
cp ${ORIGDATA_DIR}/${SBJ}/${SES}/func/${SBJ}_${SES}_task-${TASK}_run-???_bold.* .
for RUN in 001 002 003
do
  if [[ -f "${SBJ}_${SES}_task-${TASK}_run-${RUN}_bold.nii.gz" ]]; then
  	echo "Slice Timing before for ${SBJ}_${SES}_task-${TASK}_run-${RUN}_bold.nii.gz"
  	3dinfo -slice_timing ${SBJ}_${SES}_task-${TASK}_run-${RUN}_bold.nii.gz 
  	abids_tool.py -add_slice_times -input ${SBJ}_${SES}_task-${TASK}_run-${RUN}_bold.nii.gz     
  	echo "Slice Timing after for ${SBJ}_${SES}_task-${TASK}_run-${RUN}_bold.nii.gz"
  	3dinfo -slice_timing ${SBJ}_${SES}_task-${TASK}_run-${RUN}_bold.nii.gz 
  fi
done
