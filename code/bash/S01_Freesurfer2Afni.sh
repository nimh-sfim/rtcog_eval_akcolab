set -e 

ml afni
ml freesurfer
PRJ_DIR=/data/SFIMJGC_CLARID/AKColab/


SUBJECTS_DIR=${PRJ_DIR}freesurfer/

# Bring Freesurfer output for template to SUMA/AFNI format
@SUMA_Make_Spec_FS -sid ${SBJ}  -NIFTI -fspath ${SUBJECTS_DIR}/${SBJ}
