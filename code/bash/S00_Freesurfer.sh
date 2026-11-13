set -e 

ml afni
ml ANTs
PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/
ORIGDATA_DIR=${PRJ_DIR}orig_data/ds007216-download/
PRCSDATA_DIR=${PRJ_DIR}prcs_data/

SBJ_DIR=`echo ${PRCSDATA_DIR}${SBJ}/`
ANAT_DIR=`echo ${SBJ_DIR}/D00_PreFreeSurfer`

# Create output folders if they do not exists already
if [ ! -d ${SBJ_DIR} ]; then
       mkdir -p ${SBJ_DIR}
fi

if [ ! -d ${ANAT_DIR} ]; then
       mkdir -p ${ANAT_DIR}
fi

# Enter output folder
# ===================
echo "++ Entering output folde [${ANAT_DIR}]...."
echo "++ ======================================================================="
cd ${ANAT_DIR}

# Copy anatomical from original data folder
# =========================================
echo "++ Copy anatomical from original data folder"
echo "++ ======================================================================="
### 3dcopy    -overwrite ${ORIGDATA_DIR}/${SBJ}/ses-001/anat/${SBJ}_ses-001_T1w.nii.gz ${SBJ}_Anat.orig.nii
3dcopy    -overwrite ${ORIGDATA_DIR}/${SBJ}/ses-001/anat/${SBJ}_ses-001_T1w.nii.gz ${SBJ}_Anat.nii
3drefit   -deoblique ${SBJ}_Anat.nii
3dUnifize -overwrite -input ${SBJ}_Anat.nii -prefix ${SBJ}_Anat_uni.nii 

# Skull strip anatomical
# ======================
echo "++ Skull strip anatomical"
echo "++ ======================================================================="
3dSkullStrip -overwrite -input ${SBJ}_Anat_uni.nii -prefix ${SBJ}_Anat_uni_ss.nii

# Get brain mask from skull stripped anatomical file
# ==================================================
echo "++ Get brain mask from skull stripped anatomical file"
echo "++ ======================================================================="
3dcalc -overwrite -a ${SBJ}_Anat_uni_ss.nii -expr 'step(a)' -prefix ${SBJ}_Anat_BrainMask.nii
3dmask_tool -overwrite -fill_holes -input ${SBJ}_Anat_BrainMask.nii -dilate_inputs 2 -2 -prefix ${SBJ}_Anat_BrainMask.nii

# Correct bias field in anatomical inputs
# =======================================
echo "++ Correct bias field in anatomical inputs"
echo "++ ======================================================================="
N4BiasFieldCorrection -d 3 \
                      -i ${SBJ}_Anat.nii \
                      -w ${SBJ}_Anat_BrainMask.nii \
                      -s 2 \
                      -b '[150]' \
                      -c '[100x100x100x100,1e-7]' \
                      -o '[T1w_N4.nii,T1w_bias.nii]' -v 1

### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL ${SBJ}_Anat.nii
### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL ${SBJ}_Anat_uni.nii
### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL ${SBJ}_Anat_uni_ss.nii
### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL ${SBJ}_Anat_BrainMask.nii
### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL T1w_N4.nii
### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL T1w_bias.nii
### 3drefit -atrcopy ${SBJ}_Anat.orig.nii IJK_TO_DICOM_REAL ${SBJ}_Anat_uni_ss.nii

# Run recon_all
# =============
echo "++ Running Freesurfer on session basis..."
echo "++ ======================================================================="
ml freesurfer
export FREESURFER=${FREESURFER_HOME}
export SUBJECTS_DIR=${PRJ_DIR}freesurfer/

recon-all -subject ${SBJ} -i T1w_N4.nii  -all
