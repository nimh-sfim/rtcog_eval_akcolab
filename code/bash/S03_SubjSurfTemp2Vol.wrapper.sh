set -e

PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
SCRIPTS_DIR=${PRJ_DIR}code/bash/
PRCSDATA_DIR=${PRJ_DIR}prcs_data/
SUBJECTS_DIR=${PRJ_DIR}freesurfer/
echo "++ Loading Conda Environment..."
echo "++ ============================"
source /data/SFIMJGC_HCP7T/Apps/miniconda38/etc/profile.d/conda.sh
conda activate /data/SFIMJGC_HCP7T/Apps/envs/generic_2025a

echo "++ Transforming from surface to volume..."
echo "++ ======================================"
if [[ -d "${PRCSDATA_DIR}${SBJ}/D02_Templates_${SES}" ]]; then
   echo "++ [WARNING] Removing prior output folder [${PRCSDATA_DIR}${SBJ}/${SES}/D02_Templates]"
   rm -rf ${PRCSDATA_DIR}${SBJ}/${SES}//D02_Templates
fi

sh ${SCRIPTS_DIR}S03_SubjSurfTemp2Vol/run_with_native_registration.sh \
   --dlabel ${PRJ_DIR}sw/precisionEEGfMRI/data/MSHBM_sdc/${SBJ}/${SES}/ind_parcellation/test_set/${SBJ}_fsaverage6_MSHBM_parcellation.dlabel.nii \
   --subject ${SBJ} \
   --subjects-dir  ${SUBJECTS_DIR} \
   --sswarper-dir  ${PRCSDATA_DIR}${SBJ}/D01_Anatomical/ \
   --out-dir ${PRCSDATA_DIR}${SBJ}/${SES}/D02_Templates/

cd ${PRCSDATA_DIR}${SBJ}/${SES}/D02_Templates/
ln -s ../../D01_Anatomical/anatQQ.${SBJ}.nii.gz .
ln -s ../../D01_Anatomical/${SBJ}_Anat+orig.* .

echo "++ ============================="
echo "++ Program finished successfully"
echo "++ ============================="
