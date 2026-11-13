# This script runs @SSwarper on each individual subjects
#
# NOTES:
#
# 1) It assumes Freesurfer was run, and uses one of its outputs as input
# 2) Input is brain.finalsurfs.nii.gz, which is already skull-stripped
#
export OMP_NUM_THREADS=32
set -e

ml afni

PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
PRCS_DATA_DIR=${PRJ_DIR}prcs_data/
SBJ_DIR=`echo ${PRCS_DATA_DIR}/${SBJ}/`
ANAT_DATA_DIR=`echo ${SBJ_DIR}/D01_Anatomical`

echo "++ Working on Subject ${SBJ}... pre-processing anatomical data"
echo "++ Output folder.... ${ANAT_DATA_DIR}"
# Create directory for outputs of anatomical pre-processing if needed
# -------------------------------------------------------------------
if [ ! -d ${ANAT_DATA_DIR} ]; then 
   echo "++ INFO: New Anatomical Preprocessing directory created [${ANAT_DATA_DIR}]"
   mkdir -p ${ANAT_DATA_DIR}
fi

# Enter destination folder
# ------------------------
cd ${ANAT_DATA_DIR}

# @SSwarper works best with BRIK/HEAD files... we need to transform the nii files
# -------------------------------------------------------------------------------
if [ ! -e ${ANAT_DATA_DIR}/${SBJ}_Anat+orig.HEAD ]; then
   echo "++INFO: Making a copy of original anatomical dataset in BRIK/HEAD format"
   echo "3dcopy -overwrite ${PRJ_DIR}/freesurfer/${SBJ}/SUMA/T1.nii.gz ${SBJ}_Anat+orig"
   3dcopy -overwrite ${PRJ_DIR}/freesurfer/${SBJ}/SUMA/T1.nii.gz ${SBJ}_Anat+orig
   echo "3dcopy -overwrite ${PRJ_DIR}/freesurfer/${SBJ}/SUMA/fs_parc_wb_mask.nii.gz ${SBJ}_Anat_FBmask+orig"
   3dcopy -overwrite ${PRJ_DIR}/freesurfer/${SBJ}/SUMA/fs_parc_wb_mask.nii.gz ${SBJ}_Anat_FBmask+orig
fi

# Run @SSwarper, which will compute transformation into MNI space
# ---------------------------------------------------------------
sswarper2 -input ${SBJ}_Anat+orig               \
          -base MNI152_2009_template_SSW.nii.gz \
          -mask_apply ${SBJ}_Anat_FBmask+orig   \
          -subid ${SBJ}.                        \
          -odir ${ANAT_DATA_DIR}

gzip *.nii
